#pragma once

#include "clock_estimator.h"
#include "sync_decision.h"
#include "sync_telemetry.h"

#include <QHash>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class QAbstractSocket;
class QTcpSocket;
class QSslSocket;
class QTimer;

// Socket.IO v4 / Engine.IO v4 watch-party client on raw sockets, because this Qt build has no
// WebSockets module. Owns the room's view — roster, clock, gate, broadcast order — and never the
// player; the policy that turns a broadcast into a seek lives in sync_decision.cpp.
class SyncPlayClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool connecting READ connecting NOTIFY connectingChanged)
    Q_PROPERTY(QString roomCode READ roomCode NOTIFY roomChanged)
    Q_PROPERTY(bool inRoom READ inRoom NOTIFY roomChanged)
    Q_PROPERTY(bool isHost READ isHost NOTIFY hostChanged)
    Q_PROPERTY(QString hostUserId READ hostUserId NOTIFY hostChanged)
    Q_PROPERTY(QString hostDisplayName READ hostDisplayName NOTIFY hostChanged)
    Q_PROPERTY(QString selfUserId READ selfUserId NOTIFY selfUserIdChanged)
    Q_PROPERTY(QVariantList peers READ peers NOTIFY peersChanged)
    Q_PROPERTY(int readyCount READ readyCount NOTIFY rosterChanged)
    Q_PROPERTY(int totalPeers READ totalPeers NOTIFY rosterChanged)
    Q_PROPERTY(double canonicalTime READ canonicalTime NOTIFY clockChanged)
    Q_PROPERTY(bool gateOpen READ gateOpen NOTIFY gateChanged)
    Q_PROPERTY(double clockOffsetMs READ clockOffsetMs NOTIFY clockOffsetChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // Best measured round trip; the hub builds the room's scheduled start from it.
    Q_PROPERTY(int pingMs READ pingMs NOTIFY clockOffsetChanged)
    // "unknown" | "seeded" | "trusted": how much the offset above is worth right now.
    Q_PROPERTY(QString clockConfidence READ clockConfidence NOTIFY clockOffsetChanged)
    // Display only: the decision layer measures from the anchor, never from this.
    Q_PROPERTY(double driftMs READ driftMs NOTIFY driftChanged)
    // Hub-published thresholds and features, so a redeploy can retune a shipped client.
    Q_PROPERTY(QVariantMap syncConfig READ syncConfig NOTIFY syncConfigChanged)
    Q_PROPERTY(QVariantList activity READ activity NOTIFY activityChanged)
    // Who is holding the gate, and what the room has agreed to wait until.
    Q_PROPERTY(QString waitingOn READ waitingOn NOTIFY gateChanged)
    Q_PROPERTY(qint64 gateDeadlineMs READ gateDeadlineMs NOTIFY gateChanged)
    Q_PROPERTY(double bufferGoalSeconds READ bufferGoalSeconds NOTIFY gateChanged)
    // Monotonic instant the room agreed to start at, and this client's deviation from it.
    Q_PROPERTY(qint64 scheduledStartMonoMs READ scheduledStartMonoMs NOTIFY scheduleChanged)
    Q_PROPERTY(qint64 lastStartSkewMs READ lastStartSkewMs NOTIFY scheduleChanged)
    Q_PROPERTY(bool ignoringWait READ ignoringWait NOTIFY ignoreWaitChanged)

public:
    explicit SyncPlayClient(QObject* parent = nullptr);

    bool connected() const { return connected_; }
    bool connecting() const { return connecting_; }
    QString roomCode() const { return roomCode_; }
    bool inRoom() const { return !roomCode_.isEmpty(); }
    bool isHost() const { return isHost_; }
    QString hostUserId() const { return hostUserId_; }
    QString hostDisplayName() const { return hostDisplayName_; }
    QString selfUserId() const { return selfUserId_; }
    QVariantList peers() const { return peers_; }
    int readyCount() const { return readyCount_; }
    int totalPeers() const { return totalPeers_; }
    double canonicalTime() const { return canonicalTime_; }
    bool gateOpen() const { return gateOpen_; }
    QString lastError() const { return lastError_; }
    double clockOffsetMs() const { return double(clock_.adjustedOffsetMs()); }
    int pingMs() const { return int(clock_.bestRttMs(monotonicMs())); }
    QString clockConfidence() const;
    double driftMs() const { return driftMs_; }
    QVariantMap syncConfig() const { return syncConfig_; }
    QVariantList activity() const { return activity_; }
    QString waitingOn() const { return waitingOn_; }
    qint64 gateDeadlineMs() const { return gateDeadlineMs_; }
    double bufferGoalSeconds() const { return bufferGoalSeconds_; }
    qint64 scheduledStartMonoMs() const { return scheduledStartMonoMs_; }
    qint64 lastStartSkewMs() const { return lastStartSkewMs_; }
    bool ignoringWait() const { return ignoreWait_; }

    // baseUrl is the http(s) origin; the socket derives from it. The token rides only in CONNECT.
    Q_INVOKABLE void connectToHost(const QString& baseUrl, const QString& token, const QString& userId = QString());
    // QML has no clipboard API, and dragging a selection is not "copy".
    Q_INVOKABLE bool copyRoomCodeToClipboard();
    Q_INVOKABLE void disconnectFromHost();

    // The only events the server answers.
    Q_INVOKABLE void createRoom(const QString& episodeId);
    Q_INVOKABLE void joinRoom(const QString& code);

    Q_INVOKABLE void emitPlay(double currentTime);
    Q_INVOKABLE void emitPause(double currentTime);
    Q_INVOKABLE void emitSeek(double time);
    Q_INVOKABLE void emitReady();
    Q_INVOKABLE void emitBuffering();
    Q_INVOKABLE void emitStallRecovered();
    Q_INVOKABLE void emitRequestSync();
    Q_INVOKABLE void emitBufferingProgress(double bufferedSeconds, double percent);
    Q_INVOKABLE void emitHeartbeat(double currentTime, double playbackRate, double bufferedAhead,
                                   double durationSeconds = 0.0);
    Q_INVOKABLE void emitTransferHost(const QString& targetUserId);
    Q_INVOKABLE void emitChangeEpisode(const QString& episodeId);
    Q_INVOKABLE void emitTimesyncPing();
    // The room starts without this member either way; only whether anyone waits changes.
    Q_INVOKABLE void emitIgnoreWait(bool ignore);
    // For a consistently late display: a property of the TV, not of the network.
    Q_INVOKABLE void setExtraTimeOffsetMs(double ms);

    // This clock shifted by the measured offset; compare only against other hub stamps.
    Q_INVOKABLE double serverNowMs() const;
    // Group position now, projected from the anchor on the monotonic clock.
    Q_INVOKABLE double projectedGroupPosition() const;
    // Called when the armed start fires; returns the position to start from.
    Q_INVOKABLE double acceptScheduledStart();
    // 0 when nothing is armed. QML has no monotonic clock, so the wait is computed here.
    Q_INVOKABLE qint64 msUntilScheduledStart() const;
    Q_INVOKABLE QVariantMap tuning() const;
    Q_INVOKABLE QString telemetryDump();
    // The decision layer's named outcome plus the numbers to act on; touches no player.
    Q_INVOKABLE QVariantMap evaluate(bool scrubbing, bool midSeek);
    // Call the instant the viewer acts: the room's answer must not land over its own cause.
    Q_INVOKABLE void noteLocalAction();

signals:
    void connectedChanged();
    void connectingChanged();
    void roomChanged();
    void hostChanged();
    void selfUserIdChanged();
    void peersChanged();
    void rosterChanged();
    void clockChanged();
    void gateChanged();
    void clockOffsetChanged();
    void lastErrorChanged();
    void driftChanged();
    void syncConfigChanged();
    void activityChanged();
    void scheduleChanged();
    void ignoreWaitChanged();
    // The hub publishes the cadence, so the caller's timer follows the room, not a compiled-in number.
    void heartbeatIntervalChanged(int intervalMs);

    // Room and roster state is already applied; the UI binds instead of re-deriving it.
    void eventReceived(const QString& name, const QVariantMap& payload);
    void roomAcked(const QString& event, bool ok, const QVariantMap& payload);
    void socketClosed();

private:
    void startUpgrade();
    void writeFrame(quint8 opcode, const QByteArray& payload);
    void writeText(const QByteArray& payload);
    void onReadyRead();
    void onDisconnected();
    void handleEngineFrame(const QByteArray& frame);
    void handleSocketPacket(const QByteArray& packet);
    void sendConnectPacket();
    void sendEvent(const QString& name, const QVariantMap& payload, bool wantsAck, int ackId);
    // Our measured round trip on every action; the hub's scheduled start is built from it.
    QVariantMap actionPayload(const QString& key, double value);
    void applyEvent(const QString& name, const QVariantMap& payload);
    void applyRoster(const QVariantList& entries);
    void mergePeer(const QVariantMap& entry);
    void dropPeer(const QString& userId);
    void applySyncConfig(const QVariantMap& config);
    void noteActivity(const QString& text, const QString& userId = QString());
    void updateWaitingOn();
    void updateOwnDrift();
    QString whoFor(const QString& userId) const;
    static QString formatClock(double seconds);
    void armTimeSyncProbe();
    void recordProbeReply(const QVariantMap& payload);
    bool acceptSequence(const QVariantMap& payload);
    void setError(const QString& message);
    void scheduleReconnect();
    void resetRoomState();
    // Forgotten together when the link ends, whether the user or the network ended it.
    void resetLinkState(const QString& reason);
    void setConnected(bool connected);
    void setConnecting(bool connecting);
    bool parseFrame(QByteArray& payload, quint8& opcode, bool& fin);

    QTcpSocket* plainSocket_ = nullptr;
    QSslSocket* secureSocket_ = nullptr;
    QAbstractSocket* socket_ = nullptr;
    QTimer* handshakeTimer_ = nullptr;
    QTimer* reconnectTimer_ = nullptr;
    QTimer* silenceTimer_ = nullptr;
    QTimer* timeSyncTimer_ = nullptr;

    QByteArray readBuffer_;
    QByteArray fragmentBuffer_;
    QByteArray wsKey_;
    bool inHttpHandshake_ = false;
    bool handshaked_ = false;
    bool connected_ = false;
    bool connecting_ = false;
    bool intentionalClose_ = false;
    bool pendingCreate_ = false;
    bool resumeAfterConnect_ = false;

    QString baseUrl_;
    QString token_;
    QString selfUserId_;
    QString sid_;
    QString roomCode_;
    QString pendingRoomCode_;
    QString lastEpisodeId_;
    QString hostUserId_;
    QString hostDisplayName_;
    QString lastError_;
    QString hostName_;
    quint16 hostPort_ = 80;
    bool secure_ = false;

    QVariantList peers_;
    QVariantList activity_;
    int readyCount_ = 0;
    int totalPeers_ = 0;
    double canonicalTime_ = 0.0;
    bool isHost_ = false;
    bool gateOpen_ = false;
    double driftMs_ = 0.0;
    QString waitingOn_;
    qint64 gateDeadlineMs_ = 0;
    double bufferGoalSeconds_ = 0.0;
    bool ignoreWait_ = false;

    int nextAckId_ = 1;
    int reconnectAttempt_ = 0;
    QHash<int, QString> pendingAcks_;
    // The hub's own ack deadline; without it an unanswered create/join spins the panel forever.
    QTimer* ackTimer_ = nullptr;
    QHash<int, qint64> ackSentAtMs_;
    qint64 protocolTimeoutMs_ = 12500;

    // The server pings on this schedule and drops silent peers; the client watches the same gap.
    int pingIntervalMs_ = 25000;
    int pingTimeoutMs_ = 40000;
    qint64 lastServerFrameMs_ = 0;

    // A protocol timeout is not a clean close; the panel must not claim the other.
    QString closeReason_;

    // ── Sync core ────────────────────────────────────────────────────────────
    ClockEstimator clock_;
    sync::Tuning tuning_;
    sync::State decisionState_;
    // Unapplied broadcast: signals are edge-triggered and applied once, drift is level-triggered.
    sync::RoomSignal pendingSignal_;
    SyncTelemetry telemetry_;
    QVariantMap syncConfig_;
    // Keyed by the stamp the hub echoes back, so a reply matches its send instant.
    QHash<qint64, qint64> probesInFlight_;
    qint64 lastAppliedSeq_ = 0;
    qint64 scheduledStartMonoMs_ = 0;
    double scheduledStartPosition_ = 0.0;
    qint64 lastStartSkewMs_ = 0;
    // Group position at the last broadcast, advanced on the monotonic clock.
    GroupAnchor anchor_;
    double mediaDuration_ = 0.0;
    double localPosition_ = 0.0;
    double localRate_ = 1.0;
    double bufferedAhead_ = 0.0;
    bool localPlaying_ = false;
    qint64 hostHandoverUntilMonoMs_ = 0;
    int timeSyncIntervalMs_ = 1000;

    // Refreshed per heartbeat so the decision layer needs no mpv access.
    void setLocalState(double position, double rate, double bufferedAhead, bool playing);
};
