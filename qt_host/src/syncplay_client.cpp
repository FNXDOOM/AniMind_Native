#include "syncplay_client.h"

#include <QClipboard>
#include <QGuiApplication>

#include <QAbstractSocket>
#include <QCryptographicHash>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QSslError>
#include <QSslSocket>
#include <QTcpSocket>
#include <QTimer>
#include <QUrl>

#include <algorithm>

namespace {
constexpr int kMaxReconnectAttempts = 5;

enum Opcode : quint8 {
    OpContinuation = 0x0,
    OpText = 0x1,
    OpBinary = 0x2,
    OpClose = 0x8,
    OpPing = 0x9,
    OpPong = 0xA,
};

QVariantMap toMap(const QJsonValue& value)
{
    return value.isObject() ? value.toObject().toVariantMap() : QVariantMap();
}

qint64 nowMs()
{
    return QDateTime::currentMSecsSinceEpoch();
}

// Zero in production; the harness uses it to simulate a peer that is slow to act.
int lateDeliveryMs()
{
    static const int value = qEnvironmentVariableIntValue("ANIMIND_SYNC_LATE_DELIVERY_MS");
    return value;
}

QByteArray randomNonce(size_t length)
{
    QByteArray bytes(int(length), Qt::Uninitialized);
    for (char& c : bytes)
        c = static_cast<char>(QRandomGenerator::global()->bounded(256));
    return bytes;
}

// Frame tracing for the UI-less socket self-test.
bool traceFrames()
{
    static const bool on = !qgetenv("ANIMIND_SYNC_TRACE").isEmpty();
    return on;
}
}

SyncPlayClient::SyncPlayClient(QObject* parent)
    : QObject(parent)
{
    handshakeTimer_ = new QTimer(this);
    handshakeTimer_->setSingleShot(true);
    handshakeTimer_->setInterval(10000);
    connect(handshakeTimer_, &QTimer::timeout, this, [this]() {
        if (handshaked_)
            return;
        setError(QStringLiteral("The watch-party server did not answer the handshake."));
        setConnecting(false);
        if (socket_)
            socket_->abort();
        scheduleReconnect();
    });

    reconnectTimer_ = new QTimer(this);
    reconnectTimer_->setSingleShot(true);
    connect(reconnectTimer_, &QTimer::timeout, this, [this]() {
        if (!token_.isEmpty())
            connectToHost(baseUrl_, token_, selfUserId_);
    });

    silenceTimer_ = new QTimer(this);
    silenceTimer_->setInterval(5000);
    connect(silenceTimer_, &QTimer::timeout, this, [this]() {
        if (!connected_)
            return;
        // The same gap the server uses to drop a peer: catches a half-open link here too.
        if (nowMs() - lastServerFrameMs_ > pingIntervalMs_ + pingTimeoutMs_ + 5000) {
            closeReason_ = QStringLiteral("The server stopped answering.");
            qWarning() << "SyncPlay: server went silent, reconnecting";
            setConnected(false);
            if (socket_)
                socket_->abort();
            scheduleReconnect();
        }
        // The only tick where a suspend or clock sync can be caught before it corrupts a start.
        clock_.noteClockDomain(nowMs(), monotonicMs());
        if (clock_.detectedStep()) {
            qWarning() << "SyncPlay: the local clock moved; the estimate is being reseeded";
            armTimeSyncProbe();
        }
    });

    ackTimer_ = new QTimer(this);
    ackTimer_->setInterval(500);
    connect(ackTimer_, &QTimer::timeout, this, [this]() {
        const qint64 now = monotonicMs();
        const qint64 limit = qMax(qint64(3000), protocolTimeoutMs_);
        QList<int> expired;
        for (auto it = ackSentAtMs_.constBegin(); it != ackSentAtMs_.constEnd(); ++it) {
            if (now - it.value() >= limit)
                expired.append(it.key());
        }
        for (const int id : expired) {
            const QString event = pendingAcks_.take(id);
            ackSentAtMs_.remove(id);
            setError(QStringLiteral("The watch-party server did not answer the %1 request.").arg(event));
        }
        if (ackSentAtMs_.isEmpty())
            ackTimer_->stop();
    });

    // Self-rescheduling, not fixed-interval: chase a young estimate, leave a settled one alone.
    timeSyncTimer_ = new QTimer(this);
    timeSyncTimer_->setSingleShot(true);
    connect(timeSyncTimer_, &QTimer::timeout, this, [this]() {
        if (!connected_)
            return;
        emitTimesyncPing();
        armTimeSyncProbe();
    });
}

void SyncPlayClient::armTimeSyncProbe()
{
    if (!connected_)
        return;
    const qint64 interval = clock_.nextIntervalMs(monotonicMs(), localPlaying_);
    if (interval != timeSyncIntervalMs_) {
        timeSyncIntervalMs_ = int(interval);
        emit clockOffsetChanged();
    }
    timeSyncTimer_->start(int(interval));
}

void SyncPlayClient::setError(const QString& message)
{
    if (lastError_ == message)
        return;
    lastError_ = message;
    emit lastErrorChanged();
}

void SyncPlayClient::setConnected(bool connected)
{
    if (connected_ == connected)
        return;
    connected_ = connected;
    emit connectedChanged();
}

void SyncPlayClient::setConnecting(bool connecting)
{
    if (connecting_ == connecting)
        return;
    connecting_ = connecting;
    emit connectingChanged();
}

void SyncPlayClient::resetRoomState()
{
    roomCode_.clear();
    lastEpisodeId_.clear();
    isHost_ = false;
    hostUserId_.clear();
    hostDisplayName_.clear();
    peers_.clear();
    readyCount_ = 0;
    totalPeers_ = 0;
    canonicalTime_ = 0.0;
    gateOpen_ = false;
    pendingCreate_ = false;
    pendingAcks_.clear();
    // A leftover seq from the previous room would reject the new room's first broadcast.
    lastAppliedSeq_ = 0;
    pendingSignal_ = sync::RoomSignal{};
    decisionState_.reset();
    scheduledStartMonoMs_ = 0;
    scheduledStartPosition_ = 0.0;
    anchor_ = GroupAnchor{};
    waitingOn_.clear();
    gateDeadlineMs_ = 0;
    bufferGoalSeconds_ = 0.0;
    ignoreWait_ = false;
    activity_.clear();
    emit roomChanged();
    emit hostChanged();
    emit peersChanged();
    emit rosterChanged();
    emit clockChanged();
    emit gateChanged();
    emit activityChanged();
    emit scheduleChanged();
    emit ignoreWaitChanged();
}

void SyncPlayClient::noteActivity(const QString& text, const QString& userId)
{
    if (text.isEmpty())
        return;
    QVariantMap entry;
    entry.insert(QStringLiteral("atMs"), double(nowMs()));
    entry.insert(QStringLiteral("text"), text);
    entry.insert(QStringLiteral("userId"), userId);
    activity_.append(entry);
    while (activity_.size() > 40)
        activity_.removeFirst();
    emit activityChanged();
}

bool SyncPlayClient::acceptSequence(const QVariantMap& payload)
{
    const qint64 seq = qint64(payload.value(QStringLiteral("seq")).toDouble());
    if (seq <= 0)
        return true;  // a hub that sends no ordering cannot be ordered against
    if (lastAppliedSeq_ != 0 && seq <= lastAppliedSeq_) {
        // Counted, not logged: out-of-order packets are a fact about the link.
        SyncTelemetry::Sample sample;
        sample.atMonoMs = monotonicMs();
        sample.driftMs = driftMs_;
        sample.rttMs = clock_.bestRttMs(monotonicMs());
        sample.outcome = sync::Outcome::RejectStale;
        sample.clockTrusted = clock_.confidence(monotonicMs()) == ClockEstimator::Confidence::Trusted;
        telemetry_.record(sample);
        if (traceFrames())
            qWarning() << "SyncPlay: dropping stale broadcast seq" << seq << "applied" << lastAppliedSeq_;
        return false;
    }
    lastAppliedSeq_ = seq;
    return true;
}

bool SyncPlayClient::copyRoomCodeToClipboard()
{
    QClipboard* clipboard = QGuiApplication::clipboard();
    if (clipboard == nullptr || roomCode_.isEmpty())
        return false;
    clipboard->setText(roomCode_);
    return true;
}

void SyncPlayClient::connectToHost(const QString& baseUrl, const QString& token, const QString& userId)
{
    if (token.isEmpty()) {
        setError(QStringLiteral("Sign in before joining a watch party."));
        return;
    }

    baseUrl_ = baseUrl;
    token_ = token;
    if (!userId.isEmpty() && userId != selfUserId_) {
        selfUserId_ = userId;
        emit selfUserIdChanged();
    }
    if (connected_ || connecting_)
        return;

    QUrl url(baseUrl);
    if (!url.isValid() || url.host().isEmpty()) {
        setError(QStringLiteral("The backend URL is not usable for sockets."));
        return;
    }
    hostName_ = url.host();
    secure_ = url.scheme().compare(QStringLiteral("https"), Qt::CaseInsensitive) == 0
              || url.scheme().compare(QStringLiteral("wss"), Qt::CaseInsensitive) == 0;
    hostPort_ = quint16(url.port(secure_ ? 443 : 80));

    intentionalClose_ = false;
    readBuffer_.clear();
    fragmentBuffer_.clear();
    inHttpHandshake_ = true;
    handshaked_ = false;
    setConnecting(true);

    if (secure_) {
        if (!secureSocket_) {
            secureSocket_ = new QSslSocket(this);
            connect(secureSocket_, &QSslSocket::encrypted, this, &SyncPlayClient::startUpgrade);
            connect(secureSocket_, &QSslSocket::sslErrors, this, [this](const QList<QSslError>& errors) {
                qWarning() << "SyncPlay TLS error:" << errors.value(0).errorString();
                setError(QStringLiteral("The watch-party server's TLS certificate was rejected."));
                intentionalClose_ = true;
                if (socket_)
                    socket_->abort();
            });
        }
        socket_ = secureSocket_;
    } else {
        if (!plainSocket_)
            plainSocket_ = new QTcpSocket(this);
        socket_ = plainSocket_;
    }

    // Re-wiring the same socket would stack a second handler per signal.
    disconnect(socket_, nullptr, nullptr, nullptr);
    connect(socket_, &QAbstractSocket::connected, this, [this]() {
        handshakeTimer_->start();
        if (secure_)
            secureSocket_->startClientEncryption();
        else
            startUpgrade();
    });
    connect(socket_, &QAbstractSocket::readyRead, this, &SyncPlayClient::onReadyRead);
    connect(socket_, &QAbstractSocket::disconnected, this, &SyncPlayClient::onDisconnected);

    // Aborting an idle socket still emits disconnected(), which would queue a second connect.
    if (socket_->state() != QAbstractSocket::UnconnectedState)
        socket_->abort();
    socket_->connectToHost(hostName_, hostPort_);
}

void SyncPlayClient::startUpgrade()
{
    wsKey_ = randomNonce(16).toBase64();
    const QString path = QStringLiteral("/api/socket.io?EIO=4&transport=websocket");
    const QByteArray request = QStringLiteral("GET %1 HTTP/1.1\r\n"
                                              "Host: %2:%3\r\n"
                                              "Upgrade: websocket\r\n"
                                              "Connection: Upgrade\r\n"
                                              "Sec-WebSocket-Key: %4\r\n"
                                              "Sec-WebSocket-Version: 13\r\n\r\n")
                                   .arg(path, hostName_)
                                   .arg(hostPort_)
                                   .arg(QString::fromUtf8(wsKey_))
                                   .toUtf8();
    socket_->write(request);
    socket_->flush();
}

void SyncPlayClient::disconnectFromHost()
{
    intentionalClose_ = true;
    reconnectTimer_->stop();
    silenceTimer_->stop();
    timeSyncTimer_->stop();
    ackTimer_->stop();
    ackSentAtMs_.clear();
    if (socket_ && socket_->state() != QAbstractSocket::UnconnectedState) {
        writeFrame(OpClose, QByteArray());
        socket_->disconnectFromHost();
    }
    setConnected(false);
    setConnecting(false);
    resetLinkState(QStringLiteral("Left the watch party."));
    resetRoomState();
}

void SyncPlayClient::onDisconnected()
{
    handshakeTimer_->stop();
    silenceTimer_->stop();
    timeSyncTimer_->stop();
    // No resumable socket state on the server, so a reconnect is a new peer that must re-join.
    resumeAfterConnect_ = !roomCode_.isEmpty() && !intentionalClose_;
    // Both paths forget the same state: an estimate surviving a reconnect schedules a dead path.
    resetLinkState(closeReason_.isEmpty()
        ? (intentionalClose_ ? QStringLiteral("Disconnected.") : QStringLiteral("The link dropped."))
        : closeReason_);
    setConnected(false);
    setConnecting(false);
    scheduleReconnect();
}

void SyncPlayClient::resetLinkState(const QString& reason)
{
    clock_.clear();
    probesInFlight_.clear();
    anchor_ = GroupAnchor{};
    scheduledStartMonoMs_ = 0;
    pendingSignal_ = sync::RoomSignal{};
    decisionState_.reset();
    lastAppliedSeq_ = 0;
    closeReason_ = reason;
    emit clockOffsetChanged();
    emit scheduleChanged();
}

void SyncPlayClient::scheduleReconnect()
{
    emit socketClosed();
    if (intentionalClose_ || token_.isEmpty() || connecting_)
        return;
    if (reconnectAttempt_ >= kMaxReconnectAttempts) {
        setError(QStringLiteral("The watch party connection was lost."));
        return;
    }
    const int delay = qMin(8000, 1000 * (1 << reconnectAttempt_));
    reconnectAttempt_++;
    reconnectTimer_->start(delay);
}

// ── WebSocket framing ───────────────────────────────────────────────────────

void SyncPlayClient::writeFrame(quint8 opcode, const QByteArray& payload)
{
    if (!socket_ || socket_->state() != QAbstractSocket::ConnectedState)
        return;

    QByteArray header;
    header.append(char(0x80 | opcode));
    const int size = payload.size();
    if (size <= 125) {
        header.append(char(0x80 | size));
    } else if (size <= 0xFFFF) {
        header.append(char(0x80 | 126));
        header.append(char((size >> 8) & 0xFF));
        header.append(char(size & 0xFF));
    } else {
        header.append(char(0x80 | 127));
        for (int shift = 56; shift >= 0; shift -= 8)
            header.append(char((qint64(size) >> shift) & 0xFF));
    }

    const QByteArray mask = randomNonce(4);
    header.append(mask);

    QByteArray masked = payload;
    for (int i = 0; i < masked.size(); ++i)
        masked[i] = char(masked.at(i) ^ mask.at(i % 4));

    socket_->write(header);
    socket_->write(masked);
    if (traceFrames())
        qInfo() << "TX" << opcode << payload.left(90);
}

void SyncPlayClient::writeText(const QByteArray& payload)
{
    writeFrame(OpText, payload);
}

bool SyncPlayClient::parseFrame(QByteArray& payload, quint8& opcode, bool& fin)
{
    if (readBuffer_.size() < 2)
        return false;

    const quint8 first = quint8(readBuffer_.at(0));
    fin = first & 0x80;
    opcode = first & 0x0F;

    const quint8 second = quint8(readBuffer_.at(1));
    const bool masked = second & 0x80;
    quint64 length = second & 0x7F;
    int headerSize = 2;

    if (length == 126) {
        if (readBuffer_.size() < 4)
            return false;
        length = (quint8(readBuffer_.at(2)) << 8) | quint8(readBuffer_.at(3));
        headerSize = 4;
    } else if (length == 127) {
        if (readBuffer_.size() < 10)
            return false;
        length = 0;
        for (int i = 0; i < 8; ++i)
            length = (length << 8) | quint8(readBuffer_.at(2 + i));
        headerSize = 10;
    }

    QByteArray maskKey;
    if (masked) {
        if (readBuffer_.size() < headerSize + 4)
            return false;
        maskKey = readBuffer_.mid(headerSize, 4);
        headerSize += 4;
    }

    if (quint64(readBuffer_.size()) < quint64(headerSize) + length)
        return false;

    payload = readBuffer_.mid(headerSize, int(length));
    readBuffer_.remove(0, headerSize + int(length));

    if (masked) {
        for (int i = 0; i < payload.size(); ++i)
            payload[i] = char(payload.at(i) ^ maskKey.at(i % 4));
    }
    return true;
}

void SyncPlayClient::onReadyRead()
{
    readBuffer_.append(socket_->readAll());

    if (inHttpHandshake_) {
        const int separator = readBuffer_.indexOf("\r\n\r\n");
        if (separator < 0)
            return;
        const QByteArray head = readBuffer_.left(separator);
        readBuffer_.remove(0, separator + 4);
        handshakeTimer_->stop();

        if (!head.startsWith("HTTP/1.1 101") && !head.startsWith("HTTP/1.0 101")) {
            qWarning() << "SyncPlay: upgrade rejected:" << head.left(140);
            setError(QStringLiteral("The server refused the WebSocket upgrade."));
            inHttpHandshake_ = false;
            setConnecting(false);
            if (socket_)
                socket_->abort();
            scheduleReconnect();
            return;
        }
        inHttpHandshake_ = false;
        handshaked_ = true;
        lastServerFrameMs_ = nowMs();
        silenceTimer_->start();
    }

    QByteArray payload;
    quint8 opcode = 0;
    bool fin = false;
    while (parseFrame(payload, opcode, fin)) {
        switch (opcode) {
        case OpText:
        case OpBinary:
            if (fin) {
                handleEngineFrame(payload);
            } else {
                fragmentBuffer_ = payload;
            }
            break;
        case OpContinuation:
            fragmentBuffer_.append(payload);
            if (fin) {
                handleEngineFrame(fragmentBuffer_);
                fragmentBuffer_.clear();
            }
            break;
        case OpPing:
            writeFrame(OpPong, payload);
            break;
        case OpPong:
            lastServerFrameMs_ = nowMs();
            break;
        case OpClose:
            intentionalClose_ = true;
            setConnected(false);
            if (socket_)
                socket_->abort();
            return;
        default:
            break;
        }
    }
}

// ── Engine.IO and Socket.IO ─────────────────────────────────────────────────

void SyncPlayClient::handleEngineFrame(const QByteArray& frame)
{
    if (frame.isEmpty())
        return;
    if (traceFrames())
        qInfo() << "RX" << frame.left(90);
    lastServerFrameMs_ = nowMs();

    const char kind = frame.at(0);
    const QByteArray body = frame.mid(1);
    switch (kind) {
    case '0': { // OPEN
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            sid_ = obj.value(QStringLiteral("sid")).toString();
            pingIntervalMs_ = obj.value(QStringLiteral("pingInterval")).toInt(pingIntervalMs_);
            pingTimeoutMs_ = obj.value(QStringLiteral("pingTimeout")).toInt(pingTimeoutMs_);
        }
        sendConnectPacket();
        break;
    }
    case '1': // CLOSE
        setConnected(false);
        break;
    case '2': // server ping
        writeText(QByteArrayLiteral("3"));
        break;
    case '3': // pong
        break;
    case '4': // message
        handleSocketPacket(body);
        break;
    case '5': // upgrade confirmation
        writeText(QByteArrayLiteral("5"));
        break;
    case '6': // noop
        break;
    default:
        break;
    }
}

void SyncPlayClient::sendConnectPacket()
{
    QJsonObject auth;
    auth.insert(QStringLiteral("token"), token_);
    writeText(QByteArrayLiteral("40") + QJsonDocument(auth).toJson(QJsonDocument::Compact));
}

void SyncPlayClient::handleSocketPacket(const QByteArray& packet)
{
    if (packet.isEmpty())
        return;

    const char kind = packet.at(0);
    QByteArray body = packet.mid(1);

    int ackId = -1;
    if (kind == '2' || kind == '3') {
        int digits = 0;
        while (digits < body.size() && body.at(digits) >= '0' && body.at(digits) <= '9')
            ++digits;
        if (digits > 0) {
            ackId = body.left(digits).toInt();
            body = body.mid(digits);
            if (!body.isEmpty() && body.at(0) == '-')
                body = body.mid(1); // binary attachment placeholder, unused by this protocol
        }
    }

    switch (kind) {
    case '0': { // CONNECT ack
        setConnecting(false);
        // Re-join before notifying, or a handler woken by connectedChanged would open a second room.
        if (resumeAfterConnect_) {
            resumeAfterConnect_ = false;
            const QString code = roomCode_;
            roomCode_.clear();
            joinRoom(code);
            emitRequestSync();
        }
        setConnected(true);
        reconnectAttempt_ = 0;
        closeReason_.clear();
        // The estimate died with the link, so probe now rather than at a settled room's interval.
        armTimeSyncProbe();
        break;
    }
    case '4': { // CONNECT_ERROR
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        const QString message = doc.isObject() ? doc.object().value(QStringLiteral("message")).toString() : QString();
        setError(message.isEmpty() ? QStringLiteral("The server rejected the sign-in token.") : message);
        setConnecting(false);
        // A rejected token will not fix itself, so retrying would only loop.
        intentionalClose_ = true;
        if (socket_)
            socket_->disconnectFromHost();
        break;
    }
    case '1': // DISCONNECT
        // Room gone rather than unreachable: rejoining would be wrong, and the panel must say which.
        closeReason_ = QStringLiteral("The watch party was closed.");
        setConnected(false);
        break;
    case '2': { // EVENT
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        if (!doc.isArray() || doc.array().isEmpty())
            return;
        const QString name = doc.array().at(0).toString();
        const QVariantMap payload = doc.array().size() > 1 ? toMap(doc.array().at(1)) : QVariantMap();
        const int lateMs = lateDeliveryMs();
        if (lateMs <= 0) {
            applyEvent(name, payload);
            emit eventReceived(name, payload);
            break;
        }
        // Measurement hook, not a feature: the transport keeps answering pongs while the room logic
        // is held back. Qt fires equal-interval single-shots in submission order.
        QTimer::singleShot(lateMs, this, [this, name, payload]() {
            applyEvent(name, payload);
            emit eventReceived(name, payload);
        });
        break;
    }
    case '3': { // EVENT_ACK
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        QVariantMap payload;
        if (doc.isArray() && !doc.array().isEmpty())
            payload = toMap(doc.array().at(0));

        const bool ok = payload.value(QStringLiteral("success"), true).toBool();
        const QString event = pendingAcks_.take(ackId);
        ackSentAtMs_.remove(ackId);
        if (ackSentAtMs_.isEmpty())
            ackTimer_->stop();

        if (ok && (event == QStringLiteral("createRoom") || event == QStringLiteral("joinRoom"))) {
            const QString code = payload.value(QStringLiteral("roomCode")).toString();
            if (!code.isEmpty())
                roomCode_ = code;
            else if (event == QStringLiteral("joinRoom") && !pendingRoomCode_.isEmpty())
                roomCode_ = pendingRoomCode_;
            pendingCreate_ = false;
            lastEpisodeId_.clear();
            hostUserId_ = payload.value(QStringLiteral("hostUserId"), hostUserId_).toString();
            // The create ack carries no host id: the creator is the host, as the web client assumes.
            if (event == QStringLiteral("createRoom") && hostUserId_.isEmpty())
                hostUserId_ = selfUserId_;
            isHost_ = !hostUserId_.isEmpty() && hostUserId_ == selfUserId_;
            canonicalTime_ = payload.value(QStringLiteral("currentTime"), canonicalTime_).toDouble();
            applySyncConfig(payload.value(QStringLiteral("syncConfig")).toMap());
            bufferGoalSeconds_ = payload.value(QStringLiteral("bufferGoalSeconds")).toDouble();
            // Every join re-gates the room, so this ack is the only roster a newcomer gets; prefer
            // the full list, which carries positions and buffer readings.
            const QVariantList detailed = payload.value(QStringLiteral("peers")).toList();
            const QVariantList roster = !detailed.isEmpty()
                ? detailed : payload.value(QStringLiteral("participants")).toList();
            if (!roster.isEmpty())
                applyRoster(roster);
            noteActivity(event == QStringLiteral("createRoom")
                ? QStringLiteral("Room %1 opened").arg(roomCode_)
                : QStringLiteral("Joined room %1").arg(roomCode_));
            emit roomChanged();
            emit hostChanged();
            emit clockChanged();
        }
        if (!ok)
            setError(payload.value(QStringLiteral("error")).toString());
        emit roomAcked(event, ok, payload);
        break;
    }
    default:
        break;
    }
}

void SyncPlayClient::applyEvent(const QString& name, const QVariantMap& payload)
{
    // Ordering first: applying a stale packet is how a pause overtakes the play it followed.
    if (!acceptSequence(payload))
        return;

    const qint64 now = monotonicMs();
    const qint64 serverTime = qint64(payload.value(QStringLiteral("serverTime")).toDouble());
    const qint64 seq = qint64(payload.value(QStringLiteral("seq")).toDouble());
    auto number = [&payload](const char* key) {
        return payload.value(QLatin1String(key)).toDouble();
    };
    // Spelling varies by event because the deployed web client reads each one literally.
    double position = 0.0;
    if (payload.contains(QStringLiteral("currentTime")))
        position = number("currentTime");
    else if (payload.contains(QStringLiteral("time")))
        position = number("time");
    else if (payload.contains(QStringLiteral("targetTime")))
        position = number("targetTime");
    else if (payload.contains(QStringLiteral("canonicalTime")))
        position = number("canonicalTime");

    // Built here, not written into the pending slot directly: see the note at the end.
    sync::RoomSignal next;
    next.seq = seq;
    next.serverTimeMs = serverTime;
    next.position = position;
    next.sourceUserId = payload.value(QStringLiteral("fromUserId")).toString();
    next.episodeId = payload.value(QStringLiteral("episodeId")).toString();

    bool announceClock = false;

    if (name == QStringLiteral("participantStates")) {
        canonicalTime_ = number("canonicalTime");
        announceClock = true;
        const bool playing = payload.value(QStringLiteral("isPlaying")).toBool();
        anchor_ = GroupAnchor{canonicalTime_, now, playing ? 1.0 : 0.0, playing, serverTime, seq};
        gateOpen_ = false;
        applyRoster(payload.value(QStringLiteral("peers")).toList());
        updateOwnDrift();
        next.kind = sync::RoomSignal::Kind::StateRefresh;
        next.groupPlaying = playing;
    } else if (name == QStringLiteral("waitForBufferGoal") || name == QStringLiteral("waitForReady")) {
        gateOpen_ = true;
        canonicalTime_ = position;
        announceClock = true;
        anchor_ = GroupAnchor{position, now, 0.0, false, serverTime, seq};
        if (payload.contains(QStringLiteral("bufferGoalSeconds")))
            bufferGoalSeconds_ = number("bufferGoalSeconds");
        gateDeadlineMs_ = qint64(number("waitDeadlineMs"));
        applyRoster(payload.value(QStringLiteral("peers")).toList());
        updateWaitingOn();
        next.kind = sync::RoomSignal::Kind::GateOpened;
        next.groupPlaying = false;
        emit gateChanged();
    } else if (name == QStringLiteral("allReady")) {
        // Whether playback follows is the payload's answer, not which event arrived last.
        gateOpen_ = false;
        canonicalTime_ = position;
        announceClock = true;
        const bool willPlay = payload.value(QStringLiteral("playIntent")).toBool();
        anchor_ = GroupAnchor{position, now, willPlay ? 1.0 : 0.0, willPlay, serverTime, seq};
        next.kind = sync::RoomSignal::Kind::GateClosed;
        next.groupPlaying = willPlay;
        const qint64 scheduled = qint64(number("scheduledPlayAt"));
        if (scheduled > 0)
            scheduledStartMonoMs_ = clock_.localMonoForServerTime(scheduled, nowMs(), now);
        else
            scheduledStartMonoMs_ = 0;
        scheduledStartPosition_ = position;
        waitingOn_.clear();
        emit gateChanged();
        emit scheduleChanged();
        noteActivity(willPlay ? QStringLiteral("Everyone is ready, starting together")
                              : QStringLiteral("Everyone is ready, staying paused"));
    } else if (name == QStringLiteral("syncPlay") || name == QStringLiteral("sync")) {
        gateOpen_ = false;
        const bool playing = name == QStringLiteral("syncPlay")
            ? true : payload.value(QStringLiteral("isPlaying")).toBool();
        canonicalTime_ = position;
        announceClock = true;
        anchor_ = GroupAnchor{position, now, playing ? 1.0 : 0.0, playing, serverTime, seq};
        next.kind = playing ? sync::RoomSignal::Kind::Play : sync::RoomSignal::Kind::Pause;
        next.groupPlaying = playing;
        const qint64 scheduled = qint64(number("scheduledPlayAt"));
        if (playing && scheduled > 0) {
            scheduledStartMonoMs_ = clock_.localMonoForServerTime(scheduled, nowMs(), now);
            scheduledStartPosition_ = position;
            emit scheduleChanged();
        } else if (playing) {
            scheduledStartMonoMs_ = 0;
        }
        emit gateChanged();
    } else if (name == QStringLiteral("syncPaused") || name == QStringLiteral("pause")) {
        gateOpen_ = false;
        canonicalTime_ = position;
        announceClock = true;
        anchor_ = GroupAnchor{position, now, 0.0, false, serverTime, seq};
        scheduledStartMonoMs_ = 0;
        next.kind = sync::RoomSignal::Kind::Pause;
        next.groupPlaying = false;
        emit gateChanged();
        emit scheduleChanged();
        noteActivity(QStringLiteral("%1 paused the party").arg(whoFor(next.sourceUserId)), next.sourceUserId);
    } else if (name == QStringLiteral("seek")) {
        canonicalTime_ = position;
        announceClock = true;
        anchor_ = GroupAnchor{position, now, localPlaying_ ? 1.0 : 0.0, localPlaying_, serverTime, seq};
        next.kind = sync::RoomSignal::Kind::Seek;
        next.groupPlaying = localPlaying_;
        const qint64 scheduled = qint64(number("scheduledPlayAt"));
        if (scheduled > 0) {
            scheduledStartMonoMs_ = clock_.localMonoForServerTime(scheduled, nowMs(), now);
            scheduledStartPosition_ = position;
            emit scheduleChanged();
        }
        noteActivity(QStringLiteral("%1 moved to %2").arg(whoFor(next.sourceUserId))
            .arg(formatClock(position)), next.sourceUserId);
    } else if (name == QStringLiteral("softCorrect")) {
        canonicalTime_ = position;
        anchor_ = GroupAnchor{position, now, 1.0, true, serverTime, seq};
        announceClock = true;
        next.kind = sync::RoomSignal::Kind::ServerCorrect;
        next.groupPlaying = true;
        next.sourceUserId = payload.value(QStringLiteral("fromUserId")).toString();
    } else if (name == QStringLiteral("speedSeek")) {
        next.kind = sync::RoomSignal::Kind::ServerSpeedSeek;
        next.groupPlaying = true;
        next.rate = number("rate");
        next.holdMs = qint64(number("duration"));
        next.sourceUserId = payload.value(QStringLiteral("fromUserId")).toString();
    } else if (name == QStringLiteral("bufferingUpdate")) {
        QVariantMap entry;
        entry.insert(QStringLiteral("userId"), payload.value(QStringLiteral("userId")));
        entry.insert(QStringLiteral("displayName"), payload.value(QStringLiteral("displayName")));
        entry.insert(QStringLiteral("bufferedAhead"), number("bufferedSeconds"));
        entry.insert(QStringLiteral("bufferPercent"), number("percent"));
        if (!peers_.isEmpty())
            mergePeer(entry);
        updateWaitingOn();
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("peerReady")) {
        readyCount_ = payload.value(QStringLiteral("readyCount")).toInt();
        totalPeers_ = payload.value(QStringLiteral("totalPeers")).toInt();
        // Otherwise the row keeps "buffering" until a playing heartbeat refreshes it.
        if (!payload.value(QStringLiteral("timedOut")).toBool()) {
            QVariantMap entry;
            entry.insert(QStringLiteral("userId"), payload.value(QStringLiteral("userId")));
            entry.insert(QStringLiteral("displayName"), payload.value(QStringLiteral("displayName")));
            entry.insert(QStringLiteral("ready"), true);
            entry.insert(QStringLiteral("readyState"), QStringLiteral("ready"));
            mergePeer(entry);
        }
        updateWaitingOn();
        emit rosterChanged();
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("peerJoined")) {
        mergePeer(payload);
        updateWaitingOn();
        noteActivity(QStringLiteral("%1 joined").arg(payload.value(QStringLiteral("displayName")).toString()),
                     payload.value(QStringLiteral("userId")).toString());
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("peerLeft")) {
        dropPeer(payload.value(QStringLiteral("userId")).toString());
        updateWaitingOn();
        noteActivity(QStringLiteral("%1 left").arg(payload.value(QStringLiteral("displayName")).toString()),
                     payload.value(QStringLiteral("userId")).toString());
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("peerBuffering")) {
        QVariantMap entry;
        entry.insert(QStringLiteral("userId"), payload.value(QStringLiteral("userId")));
        entry.insert(QStringLiteral("displayName"), payload.value(QStringLiteral("displayName")));
        entry.insert(QStringLiteral("readyState"), QStringLiteral("buffering"));
        entry.insert(QStringLiteral("bufferedAhead"), number("bufferedSeconds"));
        entry.insert(QStringLiteral("bufferPercent"), number("percent"));
        mergePeer(entry);
        updateWaitingOn();
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("peerStalling")) {
        QVariantMap entry;
        entry.insert(QStringLiteral("userId"), payload.value(QStringLiteral("userId")));
        entry.insert(QStringLiteral("displayName"), payload.value(QStringLiteral("displayName")));
        entry.insert(QStringLiteral("stalling"), true);
        mergePeer(entry);
        updateWaitingOn();
        noteActivity(QStringLiteral("%1 is buffering").arg(payload.value(QStringLiteral("displayName")).toString()),
                     payload.value(QStringLiteral("userId")).toString());
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("peerStallRecovered")) {
        QVariantMap entry;
        entry.insert(QStringLiteral("userId"), payload.value(QStringLiteral("userId")));
        entry.insert(QStringLiteral("displayName"), payload.value(QStringLiteral("displayName")));
        entry.insert(QStringLiteral("stalling"), false);
        mergePeer(entry);
        updateWaitingOn();
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("peerIgnoreWait")) {
        const bool ignore = payload.value(QStringLiteral("ignore")).toBool();
        QVariantMap entry;
        entry.insert(QStringLiteral("userId"), payload.value(QStringLiteral("userId")));
        entry.insert(QStringLiteral("displayName"), payload.value(QStringLiteral("displayName")));
        entry.insert(QStringLiteral("ignoreWait"), ignore);
        if (ignore) {
            entry.insert(QStringLiteral("ready"), true);
            entry.insert(QStringLiteral("readyState"), QStringLiteral("ready"));
        }
        mergePeer(entry);
        updateWaitingOn();
        noteActivity(QStringLiteral("%1 %2 waiting for the room")
            .arg(payload.value(QStringLiteral("displayName")).toString())
            .arg(ignore ? QStringLiteral("stopped") : QStringLiteral("started")),
            payload.value(QStringLiteral("userId")).toString());
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("hostChanged")) {
        hostUserId_ = payload.value(QStringLiteral("newHostUserId")).toString();
        hostDisplayName_ = payload.value(QStringLiteral("newHostDisplayName")).toString();
        isHost_ = !hostUserId_.isEmpty() && hostUserId_ == selfUserId_;
        // Until the new host reports, the room's clock is the outgoing host's last reading.
        const qint64 resumeAt = qint64(number("correctionsResumeAt"));
        if (resumeAt > 0)
            hostHandoverUntilMonoMs_ = clock_.localMonoForServerTime(resumeAt, nowMs(), now);
        emit hostChanged();
        noteActivity(QStringLiteral("%1 is now the host").arg(hostDisplayName_), hostUserId_);
        next.kind = sync::RoomSignal::Kind::None;
    } else if (name == QStringLiteral("episodeChanged")) {
        canonicalTime_ = 0.0;
        announceClock = true;
        anchor_ = GroupAnchor{};
        scheduledStartMonoMs_ = 0;
        lastEpisodeId_ = payload.value(QStringLiteral("episodeId")).toString();
        next.kind = sync::RoomSignal::Kind::EpisodeChanged;
        next.episodeId = lastEpisodeId_;
        emit scheduleChanged();
        noteActivity(QStringLiteral("The room moved to another episode"));
    } else if (name == QStringLiteral("timesync_pong")) {
        recordProbeReply(payload);
        return;
    } else if (name == QStringLiteral("syncDenied")) {
        setError(payload.value(QStringLiteral("reason")).toString());
        noteActivity(payload.value(QStringLiteral("reason")).toString());
        next.kind = sync::RoomSignal::Kind::None;
    } else {
        // Unknown events still reach eventReceived(); they are never treated as a sync signal.
        next.kind = sync::RoomSignal::Kind::None;
    }

    if (announceClock)
        emit clockChanged();

    // Only an instruction replaces the pending signal: roster traffic overwriting one loses a start.
    if (next.kind != sync::RoomSignal::Kind::None)
        pendingSignal_ = next;
}


void SyncPlayClient::applyRoster(const QVariantList& entries)
{
    int ready = 0;
    for (const auto& value : entries) {
        if (value.toMap().value(QStringLiteral("ready")).toBool())
            ready++;
    }
    peers_ = entries;
    readyCount_ = ready;
    if (!entries.isEmpty())
        totalPeers_ = entries.size();
    emit peersChanged();
    emit rosterChanged();
}

void SyncPlayClient::mergePeer(const QVariantMap& entry)
{
    const QString userId = entry.value(QStringLiteral("userId")).toString();
    if (userId.isEmpty())
        return;

    QVariantList updated;
    bool found = false;
    for (const auto& value : peers_) {
        QVariantMap existing = value.toMap();
        if (existing.value(QStringLiteral("userId")).toString() == userId) {
            // Merge, not replace: a name-only event must not erase the row's position and buffer.
            for (auto it = entry.constBegin(); it != entry.constEnd(); ++it)
                existing.insert(it.key(), it.value());
            found = true;
        }
        updated.append(existing);
    }

    if (!found) {
        QVariantMap fresh = entry;
        // A join notice only names the peer; fill the fields the roster row reads.
        if (!fresh.contains(QStringLiteral("ready")))
            fresh.insert(QStringLiteral("ready"), false);
        if (!fresh.contains(QStringLiteral("readyState")))
            fresh.insert(QStringLiteral("readyState"), QStringLiteral("buffering"));
        if (!fresh.contains(QStringLiteral("currentTime")))
            fresh.insert(QStringLiteral("currentTime"), canonicalTime_);
        if (!fresh.contains(QStringLiteral("stalling")))
            fresh.insert(QStringLiteral("stalling"), false);
        updated.append(fresh);
    }

    peers_ = updated;
    totalPeers_ = updated.size();
    emit peersChanged();
    emit rosterChanged();
}

void SyncPlayClient::dropPeer(const QString& userId)
{
    if (userId.isEmpty() || peers_.isEmpty())
        return;
    QVariantList updated;
    for (const auto& value : peers_) {
        if (value.toMap().value(QStringLiteral("userId")).toString() != userId)
            updated.append(value);
    }
    if (updated.size() == peers_.size())
        return;
    peers_ = updated;
    totalPeers_ = updated.size();
    emit peersChanged();
    emit rosterChanged();
}

double SyncPlayClient::serverNowMs() const
{
    // Hub absolutes compare only against other hub stamps; use localMonoForServerTime to wait.
    return double(clock_.serverWallMs(nowMs()));
}

// ── Outbound events ─────────────────────────────────────────────────────────

void SyncPlayClient::sendEvent(const QString& name, const QVariantMap& payload, bool wantsAck, int ackId)
{
    if (!connected_) {
        setError(QStringLiteral("Not connected to the watch-party server."));
        return;
    }
    QJsonArray args;
    args.append(name);
    args.append(QJsonValue::fromVariant(payload));

    QByteArray packet = QByteArrayLiteral("2");
    if (wantsAck) {
        packet += QByteArray::number(ackId);
        // The hub's own protocol timeout, not a guessed one.
        ackSentAtMs_.insert(ackId, monotonicMs());
        ackTimer_->start();
    }
    packet += QJsonDocument(args).toJson(QJsonDocument::Compact);
    writeText(QByteArrayLiteral("4") + packet);
}

void SyncPlayClient::createRoom(const QString& episodeId)
{
    // One peer holds one room: a second create makes the server close the first.
    if (episodeId.isEmpty() || !roomCode_.isEmpty())
        return;
    lastEpisodeId_ = episodeId;
    pendingCreate_ = true;
    const int id = nextAckId_++;
    pendingAcks_.insert(id, QStringLiteral("createRoom"));
    sendEvent(QStringLiteral("createRoom"), {{QStringLiteral("episodeId"), episodeId}}, true, id);
}

void SyncPlayClient::joinRoom(const QString& code)
{
    const QString upper = code.trimmed().toUpper();
    if (upper.isEmpty())
        return;
    const int id = nextAckId_++;
    pendingAcks_.insert(id, QStringLiteral("joinRoom"));
    // The join ack carries no room code, so the code asked for has to be kept.
    pendingRoomCode_ = upper;
    sendEvent(QStringLiteral("joinRoom"), {{QStringLiteral("roomCode"), upper}}, true, id);
}

// The hub schedules from the slowest round trip it has heard of; unreported peers get left behind.
QVariantMap SyncPlayClient::actionPayload(const QString& key, double value)
{
    QVariantMap payload;
    payload.insert(key, value);
    const qint64 rtt = clock_.bestRttMs(monotonicMs());
    if (rtt >= 0)
        payload.insert(QStringLiteral("pingMs"), double(rtt));
    return payload;
}

void SyncPlayClient::emitPlay(double currentTime)
{
    noteLocalAction();
    sendEvent(QStringLiteral("play"), actionPayload(QStringLiteral("currentTime"), currentTime), false, 0);
}

void SyncPlayClient::emitPause(double currentTime)
{
    noteLocalAction();
    sendEvent(QStringLiteral("pause"), actionPayload(QStringLiteral("currentTime"), currentTime), false, 0);
}

void SyncPlayClient::emitSeek(double time)
{
    // "time" not "currentTime": the deployed clients read each spelling literally.
    noteLocalAction();
    sendEvent(QStringLiteral("seek"), actionPayload(QStringLiteral("time"), time), false, 0);
}

void SyncPlayClient::emitIgnoreWait(bool ignore)
{
    ignoreWait_ = ignore;
    sendEvent(QStringLiteral("ignoreWait"), {{QStringLiteral("ignore"), ignore}}, false, 0);
    emit ignoreWaitChanged();
    noteActivity(ignore ? QStringLiteral("You stopped holding the room")
                        : QStringLiteral("You are waiting for the room again"));
    if (ignore)
        emitRequestSync();
}

void SyncPlayClient::emitReady()
{
    sendEvent(QStringLiteral("ready"), {}, false, 0);
}

void SyncPlayClient::emitBuffering()
{
    sendEvent(QStringLiteral("buffering"), {}, false, 0);
}

void SyncPlayClient::emitStallRecovered()
{
    sendEvent(QStringLiteral("stallRecovered"), {}, false, 0);
}

void SyncPlayClient::emitRequestSync()
{
    sendEvent(QStringLiteral("requestSync"), {}, false, 0);
}

void SyncPlayClient::emitBufferingProgress(double bufferedSeconds, double percent)
{
    sendEvent(QStringLiteral("bufferingProgress"),
              {{QStringLiteral("bufferedSeconds"), bufferedSeconds}, {QStringLiteral("percent"), percent}},
              false, 0);
}

void SyncPlayClient::emitHeartbeat(double currentTime, double playbackRate, double bufferedAhead,
                                   double durationSeconds)
{
    setLocalState(currentTime, playbackRate, bufferedAhead, true);
    if (durationSeconds > 0)
        mediaDuration_ = durationSeconds;

    QVariantMap payload = actionPayload(QStringLiteral("currentTime"), currentTime);
    payload.insert(QStringLiteral("playbackRate"), playbackRate);
    payload.insert(QStringLiteral("bufferedAhead"), bufferedAhead);
    if (mediaDuration_ > 0)
        payload.insert(QStringLiteral("durationSeconds"), mediaDuration_);
    sendEvent(QStringLiteral("heartbeat"), payload, false, 0);

    // The heartbeat is where drift is sampled: one number per beat.
    SyncTelemetry::Sample sample;
    sample.atMonoMs = monotonicMs();
    sample.driftMs = anchor_.valid() ? (currentTime - anchor_.projected(sample.atMonoMs)) * 1000.0 : 0.0;
    sample.rttMs = clock_.bestRttMs(sample.atMonoMs);
    sample.rate = playbackRate;
    sample.buffering = bufferGoalSeconds_ > 0 && bufferedAhead < bufferGoalSeconds_;
    sample.gateOpen = gateOpen_;
    sample.clockTrusted = clock_.confidence(sample.atMonoMs) == ClockEstimator::Confidence::Trusted;
    telemetry_.record(sample);
    driftMs_ = sample.driftMs;
    emit driftChanged();
}

void SyncPlayClient::emitTransferHost(const QString& targetUserId)
{
    sendEvent(QStringLiteral("transferHost"), {{QStringLiteral("targetUserId"), targetUserId}}, false, 0);
}

void SyncPlayClient::emitChangeEpisode(const QString& episodeId)
{
    sendEvent(QStringLiteral("changeEpisode"), {{QStringLiteral("episodeId"), episodeId}}, false, 0);
}

void SyncPlayClient::emitTimesyncPing()
{
    const qint64 sent = nowMs();
    probesInFlight_.insert(sent, monotonicMs());
    sendEvent(QStringLiteral("timesync_ping"), {{QStringLiteral("clientSendTime"), double(sent)}}, false, 0);
    // How the room tells one member's clock is the outlier rather than everyone else's playback.
    if (clock_.hasEstimate()) {
        sendEvent(QStringLiteral("timesync_offset"),
                  {{QStringLiteral("offsetMs"), double(clock_.adjustedOffsetMs())},
                   {QStringLiteral("pingMs"), double(qMax(qint64(0), clock_.bestRttMs(monotonicMs())))}},
                  false, 0);
    }
}

// ── Sync core wiring ──────────────────────────────────────────────────────

QString SyncPlayClient::clockConfidence() const
{
    switch (clock_.confidence(monotonicMs())) {
    case ClockEstimator::Confidence::Trusted: return QStringLiteral("trusted");
    case ClockEstimator::Confidence::Seeded:  return QStringLiteral("seeded");
    case ClockEstimator::Confidence::Unknown: break;
    }
    return QStringLiteral("unknown");
}

void SyncPlayClient::applySyncConfig(const QVariantMap& config)
{
    if (config.isEmpty())
        return;
    syncConfig_ = config;
    auto ms = [&config](const char* section, const char* key, qint64 fallback) {
        const QVariantMap part = config.value(QLatin1String(section)).toMap();
        return part.contains(QLatin1String(key)) ? qint64(part.value(QLatin1String(key)).toDouble()) : fallback;
    };
    auto seconds = [&config](const char* section, const char* key, double fallback) {
        const QVariantMap part = config.value(QLatin1String(section)).toMap();
        return part.contains(QLatin1String(key)) ? part.value(QLatin1String(key)).toDouble() : fallback;
    };

    tuning_.maxPlaybackOffsetMs = ms("drift", "maxPlaybackOffsetMs", tuning_.maxPlaybackOffsetMs);
    tuning_.engageDriftMs = ms("correction", "engageDriftMs", tuning_.engageDriftMs);
    tuning_.releaseDriftMs = ms("correction", "releaseDriftMs", tuning_.releaseDriftMs);
    tuning_.fastForwardDriftMs = ms("correction", "fastForwardDriftMs", tuning_.fastForwardDriftMs);
    tuning_.maxCatchUpOffsetMs = ms("drift", "maxCatchUpOffsetMs", tuning_.maxCatchUpOffsetMs);
    tuning_.slowdownRate = seconds("correction", "slowdownRate", tuning_.slowdownRate);
    tuning_.speedupRate = seconds("correction", "speedupRate", tuning_.speedupRate);

    ClockEstimator::Options options;
    bool windowOk = false;
    const int window = config.value(QStringLiteral("timeSync")).toMap()
                            .value(QStringLiteral("window")).toInt(&windowOk);
    if (windowOk && window > 0)
        options.window = window;
    options.deadbandMs = ms("timeSync", "deadbandMs", options.deadbandMs);
    options.maxAgeMs = ms("timeSync", "maxAgeMs", options.maxAgeMs);
    clock_.setOptions(options);

    protocolTimeoutMs_ = ms("limits", "protocolTimeoutMs", protocolTimeoutMs_);
    bufferGoalSeconds_ = seconds("gate", "bufferGoalSeconds", bufferGoalSeconds_);
    const qint64 heartbeat = ms("limits", "heartbeatIntervalMs", 0);
    if (heartbeat > 0)
        emit heartbeatIntervalChanged(int(heartbeat));
    emit syncConfigChanged();
}

QVariantMap SyncPlayClient::tuning() const
{
    QVariantMap out;
    out.insert(QStringLiteral("maxPlaybackOffsetMs"), double(tuning_.maxPlaybackOffsetMs));
    out.insert(QStringLiteral("engageDriftMs"), double(tuning_.engageDriftMs));
    out.insert(QStringLiteral("releaseDriftMs"), double(tuning_.releaseDriftMs));
    out.insert(QStringLiteral("fastForwardDriftMs"), double(tuning_.fastForwardDriftMs));
    out.insert(QStringLiteral("maxCatchUpOffsetMs"), double(tuning_.maxCatchUpOffsetMs));
    out.insert(QStringLiteral("slowdownRate"), tuning_.slowdownRate);
    out.insert(QStringLiteral("speedupRate"), tuning_.speedupRate);
    out.insert(QStringLiteral("localIntentGuardMs"), double(tuning_.localIntentGuardMs));
    out.insert(QStringLiteral("remotePauseDebounceMs"), double(tuning_.remotePauseDebounceMs));
    out.insert(QStringLiteral("protocolVersion"), syncConfig_.value(QStringLiteral("version")));
    out.insert(QStringLiteral("features"), syncConfig_.value(QStringLiteral("features")));
    return out;
}

void SyncPlayClient::recordProbeReply(const QVariantMap& payload)
{
    const qint64 clientSend = qint64(payload.value(QStringLiteral("clientSendTime")).toDouble());
    const qint64 serverReceive = qint64(payload.value(QStringLiteral("serverReceiveTime")).toDouble());
    const qint64 serverSend = qint64(payload.value(QStringLiteral("serverTime")).toDouble());
    if (clientSend <= 0 || serverSend <= 0)
        return;
    if (serverReceive <= 0) {
        // Three stamps cannot support a four-timestamp estimate: keep running and say so once.
        if (syncConfig_.value(QStringLiteral("version")).toDouble() < 2)
            setError(QStringLiteral("This server predates clock sync v2: sync will be looser."));
        return;
    }
    const qint64 clientReceive = nowMs();

    ClockEstimator::Sample sample;
    sample.clientSendMs = clientSend;
    sample.serverReceiveMs = serverReceive;
    sample.serverSendMs = serverSend;
    sample.clientReceiveMs = clientReceive;
    clock_.addSample(sample, monotonicMs());

    // Each reply is republished so the hub can show per-member latency.
    probesInFlight_.remove(clientSend);
    emit clockOffsetChanged();
    armTimeSyncProbe();
}

void SyncPlayClient::updateOwnDrift()
{
    for (const auto& value : peers_) {
        const QVariantMap peer = value.toMap();
        if (peer.value(QStringLiteral("userId")).toString() != selfUserId_)
            continue;
        driftMs_ = peer.value(QStringLiteral("driftMs")).toDouble();
        emit driftChanged();
        return;
    }
}

QString SyncPlayClient::whoFor(const QString& userId) const
{
    if (userId.isEmpty())
        return QStringLiteral("The room");
    if (userId == selfUserId_)
        return QStringLiteral("You");
    for (const auto& value : peers_) {
        const QVariantMap peer = value.toMap();
        if (peer.value(QStringLiteral("userId")).toString() == userId) {
            const QString name = peer.value(QStringLiteral("displayName")).toString();
            if (!name.isEmpty())
                return name;
        }
    }
    return userId.left(6);
}

QString SyncPlayClient::formatClock(double seconds)
{
    const int total = qMax(0, int(seconds));
    return QStringLiteral("%1:%2").arg(total / 60).arg(total % 60, 2, 10, QLatin1Char('0'));
}

// A gate that names nobody reads as the app's problem rather than the network's.
void SyncPlayClient::updateWaitingOn()
{
    QStringList held;
    for (const auto& value : peers_) {
        const QVariantMap peer = value.toMap();
        if (peer.value(QStringLiteral("ready")).toBool() || peer.value(QStringLiteral("ignoreWait")).toBool())
            continue;
        const QString name = peer.value(QStringLiteral("displayName")).toString();
        if (name.isEmpty())
            continue;
        const double percent = peer.value(QStringLiteral("bufferPercent")).toDouble();
        held << QStringLiteral("%1 (%2%)").arg(name).arg(int(percent));
    }
    const QString next = held.join(QStringLiteral(", "));
    if (next == waitingOn_)
        return;
    waitingOn_ = next;
    emit gateChanged();
}

double SyncPlayClient::projectedGroupPosition() const
{
    return anchor_.projected(monotonicMs());
}

qint64 SyncPlayClient::msUntilScheduledStart() const
{
    if (scheduledStartMonoMs_ <= 0)
        return 0;
    return qMax(qint64(0), scheduledStartMonoMs_ - monotonicMs());
}

double SyncPlayClient::acceptScheduledStart()
{
    const double position = scheduledStartPosition_;
    const qint64 armed = scheduledStartMonoMs_;
    scheduledStartMonoMs_ = 0;
    decisionState_.scheduledStartMonoMs = 0;
    if (armed > 0) {
        const qint64 skew = monotonicMs() - armed;
        lastStartSkewMs_ = skew;
        telemetry_.recordStart(armed, armed + skew);
    }
    emit scheduleChanged();
    return position;
}

void SyncPlayClient::setExtraTimeOffsetMs(double ms)
{
    clock_.setExtraOffsetMs(qint64(ms));
    emit clockOffsetChanged();
}

void SyncPlayClient::noteLocalAction()
{
    sync::noteLocalIntent(decisionState_, monotonicMs(), tuning_);
}

QVariantMap SyncPlayClient::evaluate(bool scrubbing, bool midSeek)
{
    const qint64 now = monotonicMs();
    const bool trusted = clock_.confidence(now) == ClockEstimator::Confidence::Trusted;

    sync::Observation observation;
    observation.nowMonoMs = now;
    observation.anchor = anchor_;
    observation.groupPosition = anchor_.valid() ? anchor_.projected(now) : canonicalTime_;
    observation.groupPlaying = anchor_.playing;
    observation.gateOpen = gateOpen_;
    observation.localPosition = localPosition_;
    observation.localRate = localRate_;
    observation.localPlaying = localPlaying_;
    observation.scrubbing = scrubbing;
    observation.midSeek = midSeek;
    observation.bufferedAhead = bufferedAhead_;
    observation.isHost = isHost_;
    observation.ignoreWait = ignoreWait_;
    observation.clockTrusted = trusted;
    observation.rttMs = clock_.bestRttMs(now);
    observation.selfUserId = selfUserId_;
    observation.localEpisodeId = lastEpisodeId_;
    observation.tuning = tuning_;
    observation.scheduledStartMonoMs = scheduledStartMonoMs_;
    // Correction is frozen while the room's clock is changing hands.
    observation.clockHandoverPending = now < hostHandoverUntilMonoMs_;
    observation.signal = pendingSignal_;
    pendingSignal_ = sync::RoomSignal{};

    const sync::Decision decision = sync::decide(observation, decisionState_);

    SyncTelemetry::Sample sample;
    sample.atMonoMs = now;
    sample.driftMs = sync::driftMs(observation);
    sample.rttMs = observation.rttMs;
    sample.outcome = decision.outcome;
    sample.rate = decision.rate;
    sample.buffering = bufferedAhead_ > 0 && bufferedAhead_ < bufferGoalSeconds_;
    sample.gateOpen = gateOpen_;
    sample.clockTrusted = trusted;
    telemetry_.record(sample);

    QVariantMap out;
    out.insert(QStringLiteral("outcome"), sync::outcomeName(decision.outcome));
    out.insert(QStringLiteral("acts"), decision.acts());
    out.insert(QStringLiteral("targetPosition"), decision.targetPosition);
    out.insert(QStringLiteral("rate"), decision.rate);
    out.insert(QStringLiteral("holdMs"), double(decision.holdMs));
    out.insert(QStringLiteral("reason"), decision.reason);
    out.insert(QStringLiteral("driftMs"), sample.driftMs);
    out.insert(QStringLiteral("groupPosition"), observation.groupPosition);
    out.insert(QStringLiteral("scheduledStartMonoMs"), double(decisionState_.scheduledStartMonoMs));
    out.insert(QStringLiteral("clockConfidence"), clockConfidence());
    return out;
}

QString SyncPlayClient::telemetryDump()
{
    return telemetry_.dump();
}

void SyncPlayClient::setLocalState(double position, double rate, double bufferedAhead, bool playing)
{
    localPosition_ = position;
    localRate_ = rate;
    bufferedAhead_ = bufferedAhead;
    localPlaying_ = playing;
}
