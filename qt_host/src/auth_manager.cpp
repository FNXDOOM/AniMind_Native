#include "auth_manager.h"

#include <QDesktopServices>
#include <QDateTime>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTcpSocket>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>
#include <climits>

namespace {
constexpr quint16 kBridgePort = 27182;
constexpr int kBridgeTimeoutMs = 180000;
const char* kBridgeUrl = "https://fnxdoom.in/desktop-auth";
const char* kDefaultBackendBaseUrl = "https://api.fnxdoom.in";
}

AuthManager::AuthManager(QObject* parent)
    : QObject(parent)
{
    connect(&server_, &QTcpServer::newConnection, this, &AuthManager::onNewConnection);
    timeout_.setSingleShot(true);
    connect(&timeout_, &QTimer::timeout, this, &AuthManager::onAuthTimeout);
    refreshTimer_.setSingleShot(true);
    connect(&refreshTimer_, &QTimer::timeout, this, &AuthManager::onRefreshTimeout);
    restoreSession();
}

bool AuthManager::authenticated() const
{
    if (accessToken_.isEmpty() || userId_.isEmpty() || expiresAtMs_ <= 0) {
        return false;
    }
    return QDateTime::currentMSecsSinceEpoch() < expiresAtMs_;
}

void AuthManager::signInWithBrowserBridge()
{
    if (signingIn_) {
        setError("A sign-in is already in progress.");
        return;
    }

    setError(QString());

    if (!server_.listen(QHostAddress::LocalHost, kBridgePort)) {
        setError(QString("Port %1 is already in use.").arg(kBridgePort));
        return;
    }

    signingIn_ = true;
    emit signingInChanged();
    timeout_.start(kBridgeTimeoutMs);

    if (!QDesktopServices::openUrl(QUrl(QString::fromUtf8(kBridgeUrl)))) {
        server_.close();
        timeout_.stop();
        signingIn_ = false;
        emit signingInChanged();
        setError("Failed to open browser for sign-in.");
    }
}

void AuthManager::signOut()
{
    revokeDesktopSessionBestEffort();
    timeout_.stop();
    refreshTimer_.stop();
    if (server_.isListening()) {
        server_.close();
    }
    signingIn_ = false;
    emit signingInChanged();

    userId_.clear();
    email_.clear();
    accessToken_.clear();
    refreshToken_.clear();
    sessionId_.clear();
    expiresAtMs_ = 0;
    libraryShows_.clear();
    emit sessionChanged();
    emit libraryShowsChanged();

    QFile::remove(sessionFilePath());
    QFile::remove(libraryCacheFilePath());
}

void AuthManager::onAuthTimeout()
{
    if (server_.isListening()) {
        server_.close();
    }
    if (!signingIn_) {
        return;
    }
    signingIn_ = false;
    emit signingInChanged();
    setError("Sign-in timed out. Please try again.");
}

void AuthManager::onRefreshTimeout()
{
    if (!refreshSessionToken()) {
        qWarning() << "Session refresh failed; keeping current session state until re-auth is needed.";
    }
}

void AuthManager::onNewConnection()
{
    auto* socket = server_.nextPendingConnection();
    if (!socket) {
        return;
    }

    connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
        const QByteArray request = socket->readAll();
        const QList<QByteArray> lines = request.split('\n');
        if (lines.isEmpty()) {
            return;
        }

        const QByteArray reqLine = lines.first().trimmed();
        const QList<QByteArray> parts = reqLine.split(' ');
        if (parts.size() < 2) {
            return;
        }

        const QByteArray path = parts.at(1);
        const QUrl url(QString::fromUtf8("http://localhost") + QString::fromUtf8(path));
        const QUrlQuery query(url);
        const QString token = query.queryItemValue("token");
        const QString sessionIdFromQuery = query.queryItemValue("sessionId");

        QByteArray responseBody;
        if (token.isEmpty()) {
            responseBody = "<html><body><h2>Sign-in failed</h2><p>No token received.</p></body></html>";
            socket->write("HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n");
            socket->write(responseBody);
            socket->disconnectFromHost();
            return;
        }

        QString parsedUserId;
        QString parsedSessionId;
        qint64 expMs = 0;
        if (!decodeJwt(token, parsedUserId, parsedSessionId, expMs)) {
            responseBody = "<html><body><h2>Sign-in failed</h2><p>Token decode failed.</p></body></html>";
            socket->write("HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n");
            socket->write(responseBody);
            socket->disconnectFromHost();
            setError("Received token but failed to decode it.");
            return;
        }

        QByteArray payloadB64 = token.split('.').value(1).toUtf8();
        payloadB64.replace('-', '+');
        payloadB64.replace('_', '/');
        while (payloadB64.size() % 4 != 0) {
            payloadB64.append('=');
        }
        const QByteArray payload = QByteArray::fromBase64(payloadB64);
        QString parsedEmail = extractJsonString(payload, "email");
        if (parsedEmail.isEmpty()) parsedEmail = extractJsonString(payload, "email_address");
        if (parsedEmail.isEmpty()) parsedEmail = extractJsonString(payload, "primary_email_address");
        if (parsedEmail.isEmpty()) parsedEmail = extractLikelyEmail(payload);

        QString finalSessionId = !sessionIdFromQuery.isEmpty() ? sessionIdFromQuery : parsedSessionId;
        const QString clerkFapi = deriveClerkFapiFromTokenPayload(payload);
        if (!clerkFapi.isEmpty() && (parsedEmail.isEmpty() || finalSessionId.isEmpty())) {
            QNetworkRequest req(QUrl(clerkFapi + "/v1/client"));
            req.setRawHeader("Accept", "application/json");
            req.setRawHeader("Authorization", QString("Bearer %1").arg(token).toUtf8());
            auto* reply = net_.get(req);
            QEventLoop loop;
            connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
            loop.exec();

            if (reply->error() == QNetworkReply::NoError) {
                const auto doc = QJsonDocument::fromJson(reply->readAll());
                if (doc.isObject()) {
                    const auto root = doc.object();
                    if (finalSessionId.isEmpty())
                        finalSessionId = resolveSessionIdFromClientResponse(root, parsedSessionId);
                    if (parsedEmail.isEmpty())
                        parsedEmail = resolveEmailFromClientResponse(root, finalSessionId.isEmpty() ? parsedSessionId : finalSessionId);
                }
            }
            reply->deleteLater();
        }

        QString desktopAccessToken;
        QString desktopRefreshToken;
        QString desktopSessionId;
        qint64 desktopExpMs = 0;
        if (!exchangeClerkTokenForDesktopSession(token, desktopAccessToken, desktopRefreshToken, desktopSessionId, desktopExpMs)) {
            responseBody = "<html><body><h2>Sign-in failed</h2><p>Desktop token exchange failed.</p></body></html>";
            socket->write("HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n");
            socket->write(responseBody);
            socket->disconnectFromHost();
            setError("Failed to exchange sign-in token with backend desktop session.");
            return;
        }

        if (!desktopSessionId.isEmpty()) finalSessionId = desktopSessionId;
        finishSignInSuccess(parsedUserId, parsedEmail, desktopAccessToken, finalSessionId, desktopExpMs);
        refreshToken_ = desktopRefreshToken;
        persistSession();

        responseBody = "<html><body><h2>Sign-in complete</h2><p>You can close this tab and return to Animind.</p></body></html>";
        socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n");
        socket->write(responseBody);
        socket->disconnectFromHost();
    });
}

bool AuthManager::decodeJwt(const QString& jwt, QString& outUserId, QString& outSessionId, qint64& outExpMs) const
{
    const QStringList parts = jwt.split('.');
    if (parts.size() < 2) {
        return false;
    }

    QByteArray b64 = parts.at(1).toUtf8();
    b64.replace('-', '+');
    b64.replace('_', '/');
    while (b64.size() % 4 != 0) {
        b64.append('=');
    }

    const QByteArray payload = QByteArray::fromBase64(b64);
    if (payload.isEmpty()) {
        return false;
    }

    outUserId = extractJsonString(payload, "sub");
    outSessionId = extractJsonString(payload, "sid");
    const qint64 expSec = extractJsonNumber(payload, "exp");
    outExpMs = expSec > 0 ? expSec * 1000 : (QDateTime::currentMSecsSinceEpoch() + 3600 * 1000);
    return !outUserId.isEmpty();
}

QString AuthManager::extractJsonString(const QByteArray& json, const QString& key) const
{
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (!doc.isObject()) {
        return QString();
    }
    const QJsonObject obj = doc.object();
    return obj.value(key).toString();
}

qint64 AuthManager::extractJsonNumber(const QByteArray& json, const QString& key) const
{
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (!doc.isObject()) {
        return 0;
    }
    const QJsonObject obj = doc.object();
    return static_cast<qint64>(obj.value(key).toDouble(0));
}

QString AuthManager::extractLikelyEmail(const QByteArray& json) const
{
    const QString txt = QString::fromUtf8(json);
    static const QRegularExpression re(
        R"(([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}))",
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = re.match(txt);
    return match.hasMatch() ? match.captured(1) : QString();
}

QString AuthManager::deriveClerkFapiFromTokenPayload(const QByteArray& payload) const
{
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (!doc.isObject()) return QString();
    const QJsonObject obj = doc.object();
    QString iss = obj.value("iss").toString();
    if (!iss.isEmpty()) {
        QUrl u(iss);
        if (u.isValid() && !u.scheme().isEmpty() && !u.host().isEmpty()) {
            return u.scheme() + "://" + u.host();
        }
    }
    return QStringLiteral("https://clerk.fnxdoom.in");
}

QString AuthManager::resolveSessionIdFromClientResponse(const QJsonObject& root, const QString& preferredSessionId) const
{
    QJsonArray sessions = root.value("client").toObject().value("sessions").toArray();
    if (sessions.isEmpty()) sessions = root.value("sessions").toArray();
    if (sessions.isEmpty()) return preferredSessionId;

    if (!preferredSessionId.isEmpty()) {
        for (const auto& v : sessions) {
            const auto o = v.toObject();
            if (o.value("id").toString() == preferredSessionId) return preferredSessionId;
        }
    }
    return sessions.first().toObject().value("id").toString();
}

QString AuthManager::resolveEmailFromClientResponse(const QJsonObject& root, const QString& preferredSessionId) const
{
    QJsonArray sessions = root.value("client").toObject().value("sessions").toArray();
    if (sessions.isEmpty()) sessions = root.value("sessions").toArray();
    if (sessions.isEmpty()) return QString();

    QJsonObject selected = sessions.first().toObject();
    if (!preferredSessionId.isEmpty()) {
        for (const auto& v : sessions) {
            const auto o = v.toObject();
            if (o.value("id").toString() == preferredSessionId) {
                selected = o;
                break;
            }
        }
    }

    const auto user = selected.value("user").toObject();
    const auto emails = user.value("email_addresses").toArray();
    if (!emails.isEmpty()) {
        return emails.first().toObject().value("email_address").toString();
    }
    return QString();
}

void AuthManager::setError(const QString& error)
{
    if (lastError_ == error) {
        return;
    }
    lastError_ = error;
    emit lastErrorChanged();
}

QString AuthManager::sessionFilePath() const
{
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty()) {
        base = QDir::homePath() + "/AnimindQt";
    }
    QDir().mkpath(base);
    return base + "/session.json";
}

void AuthManager::persistSession() const
{
    QJsonObject obj;
    obj.insert("userId", userId_);
    obj.insert("email", email_);
    obj.insert("accessToken", accessToken_);
    obj.insert("refreshToken", refreshToken_);
    obj.insert("sessionId", sessionId_);
    obj.insert("expiresAt", static_cast<double>(expiresAtMs_));

    QFile f(sessionFilePath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void AuthManager::restoreSession()
{
    QFile f(sessionFilePath());
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject()) {
        return;
    }
    const QJsonObject obj = doc.object();
    userId_ = obj.value("userId").toString();
    email_ = obj.value("email").toString();
    accessToken_ = obj.value("accessToken").toString();
    refreshToken_ = obj.value("refreshToken").toString();
    sessionId_ = obj.value("sessionId").toString();
    expiresAtMs_ = static_cast<qint64>(obj.value("expiresAt").toDouble(0));

    if (!authenticated() && !refreshToken_.isEmpty()) {
        refreshDesktopSession();
    }

    if (!authenticated()) {
        userId_.clear();
        email_.clear();
        accessToken_.clear();
        refreshToken_.clear();
        sessionId_.clear();
        expiresAtMs_ = 0;
        libraryShows_.clear();
        QFile::remove(sessionFilePath());
        QFile::remove(libraryCacheFilePath());
        emit libraryShowsChanged();
    } else {
        // If token is close to expiry, refresh eagerly on restore.
        if (expiresAtMs_ - QDateTime::currentMSecsSinceEpoch() < 120000) {
            refreshSessionToken();
        } else {
            scheduleRefreshTimer();
        }
        QFile lf(libraryCacheFilePath());
        if (lf.exists() && lf.open(QIODevice::ReadOnly)) {
            const QJsonDocument ldoc = QJsonDocument::fromJson(lf.readAll());
            if (ldoc.isObject()) {
                const QJsonArray items = ldoc.object().value("items").toArray();
                libraryShows_.clear();
                libraryShows_.reserve(items.size());
                for (const auto& item : items) {
                    if (item.isObject()) {
                        libraryShows_.push_back(item.toObject().toVariantMap());
                    }
                }
                emit libraryShowsChanged();
            }
        }
        syncLibraryFromServer();
    }
}

void AuthManager::finishSignInSuccess(const QString& userId, const QString& email, const QString& token, const QString& sessionId, qint64 expMs)
{
    timeout_.stop();
    server_.close();
    signingIn_ = false;
    emit signingInChanged();

    userId_ = userId;
    email_ = email;
    accessToken_ = token;
    sessionId_ = sessionId;
    expiresAtMs_ = expMs;
    persistSession();
    scheduleRefreshTimer();
    syncLibraryFromServer();
    emit sessionChanged();
}

QString AuthManager::libraryCacheFilePath() const
{
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty()) {
        base = QDir::homePath() + "/AnimindQt";
    }
    QDir().mkpath(base);
    return base + "/library_cache.json";
}

void AuthManager::persistLibraryCache(const QJsonArray& items) const
{
    QJsonObject root;
    root.insert("fetchedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    root.insert("count", items.size());
    root.insert("items", items);

    QFile f(libraryCacheFilePath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

void AuthManager::syncLibraryFromServer()
{
    if (!authenticated() || accessToken_.isEmpty()) {
        return;
    }

    QUrl url(QString::fromUtf8(kDefaultBackendBaseUrl) + "/api/shows");
    QUrlQuery query;
    query.addQueryItem("limit", "200");
    query.addQueryItem("offset", "0");
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "Animind-Qt/1.0");
    req.setRawHeader("Authorization", QString("Bearer %1").arg(accessToken_).toUtf8());

    auto* reply = net_.get(req);
    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Library sync failed:" << reply->errorString();
        reply->deleteLater();
        return;
    }

    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) {
        qWarning() << "Library sync failed: invalid JSON payload";
        return;
    }

    const QJsonArray items = doc.object().value("data").toArray();
    libraryShows_.clear();
    libraryShows_.reserve(items.size());
    for (const auto& item : items) {
        if (item.isObject()) {
            libraryShows_.push_back(item.toObject().toVariantMap());
        }
    }
    persistLibraryCache(items);
    emit libraryShowsChanged();
    qInfo() << "Library sync complete. Items:" << items.size();
}

QVariantMap AuthManager::getShowDetails(const QString& showId)
{
    QVariantMap out;
    if (showId.isEmpty()) {
        return out;
    }
    if (!authenticated() && !refreshSessionToken()) {
        return out;
    }
    if (accessToken_.isEmpty()) {
        return out;
    }

    const QString encShowId = QString::fromUtf8(QUrl::toPercentEncoding(showId));
    QUrl url(QString::fromUtf8(kDefaultBackendBaseUrl) + "/api/shows/" + encShowId);
    QNetworkRequest req(url);
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "Animind-Qt/1.0");
    req.setRawHeader("Authorization", QString("Bearer %1").arg(accessToken_).toUtf8());

    auto* reply = net_.get(req);
    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Get show details failed:" << reply->errorString();
        reply->deleteLater();
        return out;
    }

    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) {
        return out;
    }
    out = doc.object().toVariantMap();
    return out;
}

QVariantMap AuthManager::getStreamTicket(const QString& episodeId, int audioTrackIndex, const QString& clientType)
{
    QVariantMap out;
    if (episodeId.isEmpty()) {
        return out;
    }
    if (!authenticated() && !refreshSessionToken()) {
        return out;
    }
    if (accessToken_.isEmpty()) {
        return out;
    }

    const QString encEpisodeId = QString::fromUtf8(QUrl::toPercentEncoding(episodeId));
    QUrl url(QString::fromUtf8(kDefaultBackendBaseUrl) + "/api/episodes/" + encEpisodeId + "/stream-ticket");
    QUrlQuery query;
    query.addQueryItem("clientType", clientType.isEmpty() ? "native" : clientType);
    if (audioTrackIndex >= 0) {
        query.addQueryItem("at", QString::number(audioTrackIndex));
    }
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "Animind-Qt/1.0");
    req.setRawHeader("Authorization", QString("Bearer %1").arg(accessToken_).toUtf8());

    auto* reply = net_.get(req);
    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Get stream ticket failed:" << reply->errorString();
        reply->deleteLater();
        return out;
    }

    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) {
        return out;
    }

    out = doc.object().toVariantMap();
    const QString rawUrl = out.value("url").toString();
    if (!rawUrl.isEmpty() && !rawUrl.startsWith("http", Qt::CaseInsensitive)) {
        const QString base = QString::fromUtf8(kDefaultBackendBaseUrl);
        out.insert("url", rawUrl.startsWith("/") ? (base + rawUrl) : (base + "/" + rawUrl));
    }
    return out;
}

bool AuthManager::refreshSessionToken()
{
    return refreshDesktopSession();
}

bool AuthManager::hydrateSessionFromClient()
{
    return false;
}

bool AuthManager::exchangeClerkTokenForDesktopSession(const QString& clerkToken, QString& outAccessToken, QString& outRefreshToken, QString& outSessionId, qint64& outExpMs)
{
    QNetworkRequest req(QUrl(QString::fromUtf8(kDefaultBackendBaseUrl) + "/api/auth/desktop/exchange"));
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("Content-Type", "application/json");
    req.setRawHeader("Authorization", QString("Bearer %1").arg(clerkToken).toUtf8());
    const QByteArray body = QJsonDocument(QJsonObject{
        {"deviceName", "Animind Qt Desktop"},
        {"deviceId", QSysInfo::machineHostName()}
    }).toJson(QJsonDocument::Compact);
    auto* reply = net_.post(req, body);
    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Desktop exchange failed:" << reply->errorString();
        reply->deleteLater();
        return false;
    }
    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) return false;
    const auto obj = doc.object();
    outAccessToken = obj.value("access_token").toString();
    outRefreshToken = obj.value("refresh_token").toString();
    outSessionId = obj.value("session_id").toString();
    if (obj.value("access_token_expires_at").isString()) {
        outExpMs = QDateTime::fromString(obj.value("access_token_expires_at").toString(), Qt::ISODate).toMSecsSinceEpoch();
    } else {
        const qint64 expSec = static_cast<qint64>(obj.value("expires_in").toDouble(0));
        outExpMs = expSec > 0 ? (QDateTime::currentMSecsSinceEpoch() + expSec * 1000) : 0;
    }
    return !outAccessToken.isEmpty() && !outRefreshToken.isEmpty() && outExpMs > 0;
}

bool AuthManager::refreshDesktopSession()
{
    if (refreshToken_.isEmpty()) return false;
    QNetworkRequest req(QUrl(QString::fromUtf8(kDefaultBackendBaseUrl) + "/api/auth/desktop/refresh"));
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("Content-Type", "application/json");
    const QByteArray body = QJsonDocument(QJsonObject{
        {"refresh_token", refreshToken_}
    }).toJson(QJsonDocument::Compact);
    auto* reply = net_.post(req, body);
    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Desktop refresh failed:" << reply->errorString();
        reply->deleteLater();
        return false;
    }
    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) return false;
    const auto obj = doc.object();
    const QString newAccess = obj.value("access_token").toString();
    const QString newRefresh = obj.value("refresh_token").toString();
    const QString sid = obj.value("session_id").toString();
    qint64 newExpMs = 0;
    if (obj.value("access_token_expires_at").isString()) {
        newExpMs = QDateTime::fromString(obj.value("access_token_expires_at").toString(), Qt::ISODate).toMSecsSinceEpoch();
    } else {
        const qint64 expSec = static_cast<qint64>(obj.value("expires_in").toDouble(0));
        newExpMs = expSec > 0 ? (QDateTime::currentMSecsSinceEpoch() + expSec * 1000) : 0;
    }
    if (newAccess.isEmpty() || newRefresh.isEmpty() || newExpMs <= 0) return false;
    accessToken_ = newAccess;
    refreshToken_ = newRefresh;
    if (!sid.isEmpty()) sessionId_ = sid;
    expiresAtMs_ = newExpMs;
    persistSession();
    scheduleRefreshTimer();
    emit sessionChanged();
    return true;
}

void AuthManager::revokeDesktopSessionBestEffort()
{
    if (refreshToken_.isEmpty() && accessToken_.isEmpty()) return;
    QNetworkRequest req(QUrl(QString::fromUtf8(kDefaultBackendBaseUrl) + "/api/auth/desktop/revoke"));
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("Content-Type", "application/json");
    if (!accessToken_.isEmpty()) {
        req.setRawHeader("Authorization", QString("Bearer %1").arg(accessToken_).toUtf8());
    }
    QJsonObject bodyObj;
    if (!refreshToken_.isEmpty()) bodyObj.insert("refresh_token", refreshToken_);
    auto* reply = net_.post(req, QJsonDocument(bodyObj).toJson(QJsonDocument::Compact));
    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    reply->deleteLater();
}

void AuthManager::scheduleRefreshTimer()
{
    refreshTimer_.stop();
    if (expiresAtMs_ <= 0) return;

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    // Refresh early to support very short-lived JWTs (e.g. ~60s).
    qint64 msUntilRefresh = expiresAtMs_ - now - 30000;
    if (msUntilRefresh < 15000) msUntilRefresh = 15000;
    if (msUntilRefresh > INT_MAX) msUntilRefresh = INT_MAX;
    refreshTimer_.start(static_cast<int>(msUntilRefresh));
}
