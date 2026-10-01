#pragma once

#include <QQuickFramebufferObject>
#include <QObject>
#include <QString>
#include <QVariant>
#include <QMetaType>
#include <atomic>
#include <mutex>
#include <thread>

struct mpv_handle;

class MpvItem : public QQuickFramebufferObject
{
    Q_OBJECT
    Q_PROPERTY(bool rendererReady READ rendererReady NOTIFY rendererReadyChanged)
    Q_PROPERTY(QString mediaUrl READ mediaUrl WRITE setMediaUrl NOTIFY mediaUrlChanged)
    // Observed from mpv rather than polled: a sync controller needs position, pause and
    // cache state the moment they change, not on a timer's schedule.
    // Named playbackPosition because QQuickItem already has a position() accessor; a
    // property called "position" would shadow it.
    Q_PROPERTY(double playbackPosition READ playbackPosition NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(bool seeking READ seeking NOTIFY seekingChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY bufferingChanged)
    Q_PROPERTY(double bufferedAhead READ bufferedAhead NOTIFY bufferedAheadChanged)
    Q_PROPERTY(double playbackRate READ playbackRate NOTIFY playbackRateChanged)
    Q_PROPERTY(bool idle READ idle NOTIFY idleChanged)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
    ~MpvItem() override;

    bool rendererReady() const { return m_ready.load(); }
    QString mediaUrl() const { return m_mediaUrl; }
    void setMediaUrl(const QString& url) { if (m_mediaUrl != url) { m_mediaUrl = url; emit mediaUrlChanged(); } }

    double playbackPosition() const { return m_position.load(); }
    double duration() const { return m_duration.load(); }
    bool paused() const { return m_paused.load(); }
    bool seeking() const { return m_seeking.load(); }
    bool buffering() const { return m_buffering.load(); }
    double bufferedAhead() const { return m_bufferedAhead.load(); }
    double playbackRate() const { return m_speed.load(); }
    bool idle() const { return m_idle.load(); }

    Q_INVOKABLE void command(const QVariantList& params);
    Q_INVOKABLE void setProperty(const QString& name, const QVariant& value);
    Q_INVOKABLE QString getPropertyString(const QString& name);
    Q_INVOKABLE double getPropertyDouble(const QString& name);
    // chapter-list and track-list are node arrays; the string and double accessors cannot
    // read them, which is why the player had no chapter support.
    Q_INVOKABLE QVariantList getPropertyList(const QString& name);
    Renderer* createRenderer() const override;

signals:
    void rendererReadyChanged();
    void mediaUrlChanged();
    void positionChanged();
    void durationChanged();
    void pausedChanged();
    void seekingChanged();
    void bufferingChanged();
    void bufferedAheadChanged();
    void playbackRateChanged();
    void idleChanged();
    void fileOpened();
    // Emitted when the demuxer reaches the end of the file; keep-open holds the frame so
    // the UI can advance to the next episode instead of sitting on a frozen picture.
    void fileFinished(const QString& reason);
    void mpvEvent(int eventId);

private:
    friend class MpvFboRenderer;
    bool initializeMpv();
    void startEventPump();
    void stopEventPump();
    void pumpEvents();
    void observeProperties();
    void handlePropertyChange(void* propertyEvent);
    void handleEndFile(void* endFileEvent);
    void reportEnd(const QString& reason);
    bool m_endReported = false;   // pump thread only
    void publishDouble(std::atomic<double>& slot, double value, void (MpvItem::*notify)());
    void publishFlag(std::atomic<bool>& slot, bool value, void (MpvItem::*notify)());

    mpv_handle* m_mpv = nullptr;
    QString m_mediaUrl;
    std::atomic<bool> m_ready{false};
    mutable std::mutex m_mpvMutex;

    std::atomic<double> m_position{0.0};
    std::atomic<double> m_duration{0.0};
    std::atomic<double> m_bufferedAhead{0.0};
    std::atomic<double> m_speed{1.0};
    std::atomic<bool> m_paused{true};
    std::atomic<bool> m_seeking{false};
    std::atomic<bool> m_buffering{false};
    std::atomic<bool> m_idle{true};

    std::thread m_eventThread;
    std::atomic<bool> m_stopPump{false};
};
