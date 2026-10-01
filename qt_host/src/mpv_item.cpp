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
    // The pump thread calls mpv_wait_event on the handle, so it has to be joined before
    // the handle is destroyed or termination races with a blocking read.
    stopEventPump();
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
    startEventPump();
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

namespace {
QVariant mpvNodeToVariant(mpv_node* node)
{
    switch (node->format) {
    case MPV_FORMAT_STRING: return QString::fromUtf8(node->u.string);
    case MPV_FORMAT_FLAG:   return node->u.flag != 0;
    case MPV_FORMAT_INT64:  return static_cast<double>(node->u.int64);
    case MPV_FORMAT_DOUBLE: return node->u.double_;
    case MPV_FORMAT_NODE_ARRAY: {
        QVariantList list;
        for (int i = 0; i < node->u.list->num; ++i)
            list.append(mpvNodeToVariant(&node->u.list->values[i]));
        return list;
    }
    case MPV_FORMAT_NODE_MAP: {
        QVariantMap map;
        for (int i = 0; i < node->u.list->num; ++i)
            map.insert(QString::fromUtf8(node->u.list->keys[i]),
                       mpvNodeToVariant(&node->u.list->values[i]));
        return map;
    }
    default: return QVariant();
    }
}
}

QVariantList MpvItem::getPropertyList(const QString& name)
{
    QVariantList empty;
    if (!m_ready.load()) return empty;

    std::lock_guard<std::mutex> lock(m_mpvMutex);
    if (!m_mpv) return empty;

    mpv_node node;
    if (mpv_get_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_NODE, &node) < 0)
        return empty;

    const QVariant value = mpvNodeToVariant(&node);
    mpv_free_node_contents(&node);
    if (value.typeId() == QMetaType::QVariantList)
        return value.toList();
    return empty;
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

// ── Event pump ──────────────────────────────────────────────────────────────
// mpv only delivers property notifications while someone drains its queue, so a worker
// thread waits on events and republishes them on the GUI thread. QML never touches mpv
// state from this thread directly.

void MpvItem::observeProperties() {
    if (!m_mpv) return;
    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "demuxer-cache-duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "seeking", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "idle-active", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "eof-reason", MPV_FORMAT_STRING);
}

void MpvItem::startEventPump() {
    if (m_eventThread.joinable()) return;
    observeProperties();
    m_stopPump.store(false);
    m_eventThread = std::thread([this]() { pumpEvents(); });
}

void MpvItem::stopEventPump() {
    m_stopPump.store(true);
    if (m_eventThread.joinable())
        m_eventThread.join();
}

void MpvItem::pumpEvents() {
    while (!m_stopPump.load()) {
        mpv_event* event = mpv_wait_event(m_mpv, 0.05);
        if (!event || event->event_id == MPV_EVENT_NONE)
            continue;
        switch (event->event_id) {
        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event->data);
            break;
        case MPV_EVENT_FILE_LOADED: {
            QPointer<MpvItem> guard(this);
            QMetaObject::invokeMethod(this, [guard]() {
                if (guard) emit guard->fileOpened();
            }, Qt::QueuedConnection);
            break;
        }
        case MPV_EVENT_END_FILE:
            handleEndFile(event->data);
            break;
        case MPV_EVENT_SHUTDOWN:
            m_stopPump.store(true);
            break;
        default:
            break;
        }
    }
}

void MpvItem::publishDouble(std::atomic<double>& slot, double value, void (MpvItem::*notify)()) {
    if (qAbs(slot.load() - value) < 0.0005)
        return;
    slot.store(value);
    QPointer<MpvItem> guard(this);
    QMetaObject::invokeMethod(this, [guard, notify]() {
        if (guard) (guard->*notify)();
    }, Qt::QueuedConnection);
}

void MpvItem::publishFlag(std::atomic<bool>& slot, bool value, void (MpvItem::*notify)()) {
    if (slot.load() == value)
        return;
    slot.store(value);
    QPointer<MpvItem> guard(this);
    QMetaObject::invokeMethod(this, [guard, notify]() {
        if (guard) (guard->*notify)();
    }, Qt::QueuedConnection);
}

void MpvItem::handlePropertyChange(void* raw) {
    auto* prop = static_cast<mpv_event_property*>(raw);
    if (!prop || prop->format == MPV_FORMAT_NONE || !prop->data)
        return;

    const QByteArray name(prop->name);
    if (prop->format == MPV_FORMAT_DOUBLE) {
        const double value = *static_cast<double*>(prop->data);
        if (name == "time-pos")
            publishDouble(m_position, value, &MpvItem::positionChanged);
        else if (name == "duration")
            publishDouble(m_duration, value, &MpvItem::durationChanged);
        else if (name == "demuxer-cache-duration")
            publishDouble(m_bufferedAhead, value, &MpvItem::bufferedAheadChanged);
        else if (name == "speed")
            publishDouble(m_speed, value, &MpvItem::playbackRateChanged);
    } else if (prop->format == MPV_FORMAT_STRING) {
        // keep-open leaves the file loaded at the end, so END_FILE never arrives during
        // playback; eof-reason is the only signal that a file actually finished.
        // For MPV_FORMAT_STRING the event carries a char**, not a char*.
        const QString value = prop->data ? QString::fromUtf8(*static_cast<char**>(prop->data)) : QString();
        if (name == "eof-reason") {
            if (value.isEmpty())
                m_endReported = false;
            else if (!m_endReported) {
                m_endReported = true;
                reportEnd(value);
            }
        }
    } else if (prop->format == MPV_FORMAT_FLAG) {
        const bool value = *static_cast<int*>(prop->data) != 0;
        if (name == "pause")
            publishFlag(m_paused, value, &MpvItem::pausedChanged);
        else if (name == "seeking")
            publishFlag(m_seeking, value, &MpvItem::seekingChanged);
        else if (name == "paused-for-cache")
            publishFlag(m_buffering, value, &MpvItem::bufferingChanged);
        else if (name == "idle-active")
            publishFlag(m_idle, value, &MpvItem::idleChanged);
    }
}

void MpvItem::handleEndFile(void* raw) {
    auto* end = static_cast<mpv_event_end_file*>(raw);
    if (!end)
        return;
    // A clean END_FILE is a load or a stop, not an ending: reporting it as eof made the
    // player advance on teardown. Only a real failure belongs here.
    if (end->error != 0) {
        m_endReported = true;
        reportEnd(QString::fromUtf8(mpv_error_string(end->error)));
    }
}

void MpvItem::reportEnd(const QString& reason)
{
    QPointer<MpvItem> guard(this);
    QMetaObject::invokeMethod(this, [guard, reason]() {
        if (guard) emit guard->fileFinished(reason);
    }, Qt::QueuedConnection);
}
