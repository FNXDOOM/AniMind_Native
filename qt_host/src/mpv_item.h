#pragma once

#include <QQuickFramebufferObject>
#include <QObject>
#include <QString>
#include <QVariant>
#include <QMetaType>
#include <atomic>
#include <mutex>

struct mpv_handle;

class MpvItem : public QQuickFramebufferObject
{
    Q_OBJECT
    Q_PROPERTY(bool rendererReady READ rendererReady NOTIFY rendererReadyChanged)
    Q_PROPERTY(QString mediaUrl READ mediaUrl NOTIFY mediaUrlChanged)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
    ~MpvItem() override;

    bool rendererReady() const { return m_ready.load(); }
    QString mediaUrl() const { return m_mediaUrl; }

    Q_INVOKABLE void command(const QVariantList& params);
    Q_INVOKABLE void setProperty(const QString& name, const QVariant& value);
    Q_INVOKABLE QString getPropertyString(const QString& name);
    Q_INVOKABLE double getPropertyDouble(const QString& name);
    Renderer* createRenderer() const override;

signals:
    void rendererReadyChanged();
    void mediaUrlChanged();
    void mpvEvent(int eventId);

private:
    friend class MpvFboRenderer;
    bool initializeMpv();

    mpv_handle* m_mpv = nullptr;
    QString m_mediaUrl;
    std::atomic<bool> m_ready{false};
    mutable std::mutex m_mpvMutex;
};
