#include "mpv_item.h"

#include <QMetaObject>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFunctions>
#include <QPointer>
#include <QQuickWindow>
#include <QVector>
#include <QByteArray>
#include <QDebug>

#include <mpv/client.h>
#include <mpv/render_gl.h>

static void* get_proc_address(void* /*ctx*/, const char* name) {
    QOpenGLContext* gl = QOpenGLContext::currentContext();
    if (!gl) return nullptr;
    return reinterpret_cast<void*>(gl->getProcAddress(QByteArray(name).constData()));
}

class MpvFboRenderer final : public QQuickFramebufferObject::Renderer, protected QOpenGLFunctions {
public:
    explicit MpvFboRenderer(MpvItem* item) : m_item(item) {
        initializeOpenGLFunctions();
    }

    ~MpvFboRenderer() override {
        if (m_mpvRenderCtx) {
            mpv_render_context_set_update_callback(m_mpvRenderCtx, nullptr, nullptr);
            mpv_render_context_free(m_mpvRenderCtx);
            m_mpvRenderCtx = nullptr;
        }
    }

    QOpenGLFramebufferObject* createFramebufferObject(const QSize& size) override {
        QOpenGLFramebufferObjectFormat fmt;
        fmt.setAttachment(QOpenGLFramebufferObject::NoAttachment);
        return new QOpenGLFramebufferObject(size, fmt);
    }

    void synchronize(QQuickFramebufferObject* item) override {
        m_item = static_cast<MpvItem*>(item);
    }

    void render() override {
        if (!m_item) {
            qWarning() << "[render] m_item is null";
            return;
        }
        if (!ensureRenderContext()) {
            qWarning() << "[render] Failed to ensure render context";
            return;
        }

        QOpenGLFramebufferObject* fbo = framebufferObject();
        if (!fbo) {
            qWarning() << "[render] framebufferObject() returned null";
            return;
        }

        mpv_opengl_fbo mpfbo{
            static_cast<int>(fbo->handle()),
            fbo->width(),
            fbo->height(),
            0
        };
        int flipY = 1;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };

        std::lock_guard<std::mutex> lock(m_item->m_mpvMutex);
        if (!m_item->m_mpv) {
            qWarning() << "[render] m_item->m_mpv is null";
            return;
        }
        mpv_render_context_render(m_mpvRenderCtx, params);
        update();
    }

private:
    static void onMpvRenderUpdate(void* ctx) {
        auto* self = static_cast<MpvFboRenderer*>(ctx);
        if (!self || !self->m_item) return;
        QQuickWindow* w = self->m_item->window();
        if (w) {
            QMetaObject::invokeMethod(w, "update", Qt::QueuedConnection);
        }
    }

    bool ensureRenderContext() {
        if (m_mpvRenderCtx) return true;
        if (!m_item) {
            qWarning() << "[MpvFboRenderer] m_item is null";
            return false;
        }

        std::lock_guard<std::mutex> lock(m_item->m_mpvMutex);
        if (!m_item->m_mpv) {
            qWarning() << "[MpvFboRenderer] m_item->m_mpv is null";
            return false;
        }

        QOpenGLContext* glCtx = QOpenGLContext::currentContext();
        if (!glCtx) {
            qCritical() << "[MpvFboRenderer] No active OpenGL context!";
            return false;
        }
        qInfo() << "[MpvFboRenderer] Active OpenGL context found";

        mpv_opengl_init_params glInit{get_proc_address, nullptr};
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
            {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };

        int err = mpv_render_context_create(&m_mpvRenderCtx, m_item->m_mpv, params);
        if (err < 0 || !m_mpvRenderCtx) {
            qCritical() << "[MpvFboRenderer] mpv_render_context_create FAILED:" << mpv_error_string(err);
            return false;
        }

        qInfo() << "[MpvFboRenderer] mpv_render_context created successfully";
        mpv_render_context_set_update_callback(m_mpvRenderCtx, onMpvRenderUpdate, this);
        return true;
    }

    QPointer<MpvItem> m_item;
    mpv_render_context* m_mpvRenderCtx = nullptr;
};

MpvItem::MpvItem(QQuickItem* parent)
    : QQuickFramebufferObject(parent) {
    if (!initializeMpv()) {
        qWarning() << "Failed to initialize libmpv";
        return;
    }
    setMirrorVertically(true);
}

MpvItem::~MpvItem() {
    std::lock_guard<std::mutex> lock(m_mpvMutex);
    if (m_mpv) {
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
    }
}

bool MpvItem::initializeMpv() {
    std::lock_guard<std::mutex> lock(m_mpvMutex);
    if (m_mpv) return true;

    m_mpv = mpv_create();
    if (!m_mpv) {
        qCritical() << "mpv_create() failed";
        return false;
    }

    auto setOpt = [this](const char* name, const char* value) -> bool {
        int rc = mpv_set_option_string(m_mpv, name, value);
        if (rc < 0) {
            qCritical() << "mpv_set_option_string FATAL for" << name << "=" << value << ":" << mpv_error_string(rc);
            return false;
        }
        qInfo() << "mpv option set:" << name << "=" << value;
        return true;
    };

    // CRITICAL: these options MUST succeed for rendering to work
    if (!setOpt("vo", "libmpv")) {
        qCritical() << "FATAL: vo=libmpv is required for Qt/QML rendering";
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
        return false;
    }
    if (!setOpt("gpu-api", "opengl")) {
        qCritical() << "FATAL: gpu-api=opengl is required for libmpv rendering";
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
        return false;
    }

    // These are optional but log if they fail
    setOpt("keep-open", "yes");
    setOpt("osc", "no");
    setOpt("input-default-bindings", "no");
    setOpt("ytdl", "no");
#if defined(Q_OS_WIN)
    // Safer hardware decode path for OpenGL rendering on Windows.
    // copy-back avoids many black-screen issues seen with zero-copy interop.
    setOpt("hwdec", "auto-copy");
#else
    setOpt("hwdec", "auto-copy");
#endif

    int err = mpv_initialize(m_mpv);
    if (err < 0) {
        qCritical() << "mpv_initialize failed:" << mpv_error_string(err);
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
        return false;
    }

    qInfo() << "libmpv initialized successfully";
    m_ready.store(true);
    emit rendererReadyChanged();
    return true;
}

QQuickFramebufferObject::Renderer* MpvItem::createRenderer() const {
    return new MpvFboRenderer(const_cast<MpvItem*>(this));
}

void MpvItem::command(const QVariantList& params) {
    if (params.isEmpty()) return;
    if (!m_ready.load()) return;

    QVector<QByteArray> utf8Args;
    utf8Args.reserve(params.size());
    for (const QVariant& v : params) {
        if (v.canConvert<double>() && v.typeId() != QMetaType::QString) {
            utf8Args.push_back(QString::number(v.toDouble(), 'g', 15).toUtf8());
        } else {
            utf8Args.push_back(v.toString().toUtf8());
        }
    }

    QVector<const char*> argv;
    argv.reserve(utf8Args.size() + 1);
    for (const QByteArray& a : utf8Args) {
        argv.push_back(a.constData());
    }
    argv.push_back(nullptr);

    std::lock_guard<std::mutex> lock(m_mpvMutex);
    if (!m_mpv) return;
    int err = mpv_command(m_mpv, argv.data());
    if (err < 0) {
        qWarning() << "mpv_command failed:" << mpv_error_string(err);
    }
}

void MpvItem::setProperty(const QString& name, const QVariant& value) {
    if (!m_ready.load()) return;

    std::lock_guard<std::mutex> lock(m_mpvMutex);
    if (!m_mpv) return;

    int err = 0;
    if (value.typeId() == QMetaType::Bool) {
        int flag = value.toBool() ? 1 : 0;
        err = mpv_set_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_FLAG, &flag);
    } else if (value.canConvert<double>() && value.typeId() != QMetaType::QString) {
        double d = value.toDouble();
        err = mpv_set_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_DOUBLE, &d);
    } else {
        QByteArray s = value.toString().toUtf8();
        err = mpv_set_property_string(m_mpv, name.toUtf8().constData(), s.constData());
    }
    if (err < 0) {
        qWarning() << "mpv_set_property failed for" << name << ":" << mpv_error_string(err);
    }
}

QString MpvItem::getPropertyString(const QString& name) {
    if (!m_ready.load()) return {};

    std::lock_guard<std::mutex> lock(m_mpvMutex);
    if (!m_mpv) return {};

    char* value = mpv_get_property_string(m_mpv, name.toUtf8().constData());
    if (!value) return {};

    QString out = QString::fromUtf8(value);
    mpv_free(value);
    return out;
}

double MpvItem::getPropertyDouble(const QString& name) {
    if (!m_ready.load()) return 0.0;

    std::lock_guard<std::mutex> lock(m_mpvMutex);
    if (!m_mpv) return 0.0;

    double value = 0.0;
    int err = mpv_get_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_DOUBLE, &value);
    if (err < 0) {
        int64_t ivalue = 0;
        err = mpv_get_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_INT64, &ivalue);
        if (err < 0) return 0.0;
        return static_cast<double>(ivalue);
    }
    return value;
}
