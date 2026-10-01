#include "auth_manager.h"

#include "backend_config.h"

#include <QDateTime>
#include <QDesktopServices>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTcpSocket>
#include <QUrl>
#include <QUrlQuery>
#include <climits>

namespace {
constexpr quint16 kBridgePort = 27182;
constexpr int kBridgeTimeoutMs = 180000;

QString deviceId()
{
    const QString unique = QString::fromUtf8(QSysInfo::machineUniqueId());
    return unique.isEmpty() ? QSysInfo::machineHostName() : unique;
}

// The API answers with access_token; a session token under that other name is kept as a
// fallback so a renamed field cannot silently break sign-in.
QString sessionTokenFrom(const QVariantMap& payload)
{
    const QString primary = payload.value(QStringLiteral("access_token")).toString();
    return primary.isEmpty() ? payload.value(QStringLiteral("token")).toString() : primary;
}

qint64 expiryFrom(const QJsonObject& obj){
    // An explicit instant wins over a duration: the server states both, and the
    // instant is the one it actually pins to the session row.
    if (obj.value(QStringLiteral("access_token_expires_at")).isString()) {
        const QDateTime when = QDateTime::fromString(obj.value(QStringLiteral("access_token_expires_at")).toString(), Qt::ISODate);
        if (when.isValid())
            return when.toMSecsSinceEpoch();
    }
    const qint64 seconds = static_cast<qint64>(obj.value(QStringLiteral("expires_in")).toDouble(0));
    return seconds > 0 ? QDateTime::currentMSecsSinceEpoch() + seconds * 1000 : 0;
}

QString dataDir()
{
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty())
        base = QDir::homePath() + QStringLiteral("/AnimindQt");
    QDir().mkpath(base);
    return base;
}
}

AuthManager::AuthManager(BackendApi* api, QObject* parent)
    : QObject(parent)
    , api_(api)
{
    connect(&server_, &QTcpServer::newConnection, this, &AuthManager::onNewConnection);
    timeout_.setSingleShot(true);
    connect(&timeout_, &QTimer::timeout, this, &AuthManager::onAuthTimeout);
    refreshTimer_.setSingleShot(true);
    connect(&refreshTimer_, &QTimer::timeout, this, &AuthManager::onRefreshTimeout);

    if (api_) {
        connect(api_, &BackendApi::watchlistLoaded, this, [this](const QVariantList& rows) {
            setLibraryLoading(false);
            setLibrary(rows);
        });
        connect(api_, &BackendApi::watchlistSaved, this, [this](const QString& animeId, const QString& status) {
            for (int i = 0; i < libraryShows_.size(); ++i) {
                QVariantMap item = libraryShows_[i].toMap();
                if (item.value(QStringLiteral("anime_id")).toString() == animeId) {
                    item.insert(QStringLiteral("userStatus"), status);
                    item.insert(QStringLiteral("status"), status);
                    libraryShows_[i] = item;
                    emit libraryShowsChanged();
                    persistLibraryCache(libraryShows_);
                    return;
                }
            }
            refreshLibrary();
        });
        connect(api_, &BackendApi::requestFailed, this, [this](const QString& endpoint, int status, const QString& message) {
            if (endpoint != QStringLiteral("watchlist"))
                return;
            setLibraryLoading(false);
            if (status == 401)
                setError(QStringLiteral("Your session expired. Sign in again."));
            else if (!message.isEmpty())
                setError(message);
        });
    }

    // Restore touches the network, so it has to wait for the event loop to be running.
    QTimer::singleShot(0, this, [this]() { restoreSession(); });
}

bool AuthManager::authenticated() const
{
    if (accessToken_.isEmpty() || userId_.isEmpty() || expiresAtMs_ <= 0)
        return false;
    return QDateTime::currentMSecsSinceEpoch() < expiresAtMs_;
}

bool AuthManager::ensureValidToken()
{
    if (authenticated())
        return true;
    if (!refreshToken_.isEmpty()) {
        request(QNetworkAccessManager::PostOperation, QStringLiteral("/api/auth/desktop/refresh"),
                QJsonDocument(QJsonObject{{QStringLiteral("refresh_token"), refreshToken_}}).toJson(QJsonDocument::Compact),
                QByteArray(), [this](bool ok, int, const QVariantMap& payload) {
                    if (!ok) {
                        setError(QStringLiteral("Sign-in expired. Please sign in again."));
                        return;
                    }
                    applyTokens(payload);
                });
    }
    return false;
}

void AuthManager::request(const QNetworkAccessManager::Operation operation,
                          const QString& path,
                          const QByteArray& body,
                          const QByteArray& bearerOverride,
                          std::function<void(bool, int, const QVariantMap&)> done)
{
    QNetworkRequest req{backend::url(path)};
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "Animind-Qt/1.0");
    req.setTransferTimeout(15000);
    if (!body.isEmpty())
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    const QByteArray bearer = bearerOverride.isNull() ? accessToken_.toUtf8() : bearerOverride;
    if (!bearer.isEmpty())
        req.setRawHeader("Authorization", QByteArray("Bearer ") + bearer);

    QNetworkReply* reply = nullptr;
    switch (operation) {
    case QNetworkAccessManager::PostOperation:
        reply = net_.post(req, body);
        break;
    default:
        reply = net_.get(req);
        break;
    }

    connect(reply, &QNetworkReply::finished, this, [reply, done]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QVariantMap payload = doc.isObject() ? doc.object().toVariantMap() : QVariantMap();
        const bool ok = reply->error() == QNetworkReply::NoError;
        if (!ok && status == 0)
            qWarning() << "Auth request failed:" << reply->errorString();
        reply->deleteLater();
        done(ok, status, payload);
    });
}

void AuthManager::signInWithBrowserBridge()
{
    if (signingIn_) {
        setError(QStringLiteral("A sign-in is already in progress."));
        return;
    }
    setError(QString());

    if (!server_.listen(QHostAddress::LocalHost, kBridgePort)) {
        setError(QStringLiteral("Port %1 is already in use.").arg(kBridgePort));
        return;
    }

    signingIn_ = true;
    emit signingInChanged();
    timeout_.start(kBridgeTimeoutMs);

    if (!QDesktopServices::openUrl(QUrl(backend::desktopAuthUrl()))) {
        closeBridge();
        signingIn_ = false;
        emit signingInChanged();
        setError(QStringLiteral("Failed to open a browser for sign-in."));
    }
}

void AuthManager::beginPasswordFlow(const QString& email, const QString& password, const QString& username, bool signup)
{
    const QString trimmedEmail = email.trimmed().toLower();
    if (trimmedEmail.isEmpty() || password.isEmpty()) {
        const QString message = QStringLiteral("Email and password are required.");
        setError(message);
        emit signInFailed(message);
        return;
    }

    setError(QString());
    signingIn_ = true;
    emit signingInChanged();

    QJsonObject body;
    body.insert(QStringLiteral("email"), trimmedEmail);
    body.insert(QStringLiteral("password"), password);
    if (signup) {
        const QString chosen = username.trimmed();
        body.insert(QStringLiteral("username"), chosen.isEmpty() ? trimmedEmail.split(QLatin1Char('@')).first() : chosen);
    }

    request(QNetworkAccessManager::PostOperation,
            signup ? QStringLiteral("/api/auth/signup") : QStringLiteral("/api/auth/login"),
            QJsonDocument(body).toJson(QJsonDocument::Compact), QByteArray(),
            [this, trimmedEmail](bool ok, int status, const QVariantMap& payload) {
                // The API answers with access_token; older builds of the docs called it
                // token, so both spellings are accepted rather than trusting one.
                const QString sessionToken = sessionTokenFrom(payload);
                if (!ok || sessionToken.isEmpty()) {
                    signingIn_ = false;
                    emit signingInChanged();
                    const QString message = payload.value(QStringLiteral("message")).toString();
                    const QString failure = !message.isEmpty()
                        ? message
                        : (status == 423 ? QStringLiteral("Too many attempts. Try again shortly.")
                                         : QStringLiteral("Sign-in failed."));
                    setError(failure);
                    emit signInFailed(failure);
                    return;
                }
                const QVariantMap user = payload.value(QStringLiteral("user")).toMap();
                if (!user.isEmpty()) {
                    // The desktop exchange payload carries no user id, and authenticated()
                    // requires one: without this a password sign-in stayed "not signed in".
                    userId_ = user.value(QStringLiteral("id")).toString();
                    username_ = user.value(QStringLiteral("username")).toString();
                    avatarUrl_ = user.value(QStringLiteral("avatar_url")).toString();
                    email_ = user.value(QStringLiteral("email"), email_).toString();
                    emit sessionChanged();
                    emit profileChanged();
                }
                exchangeForDesktopSession(sessionToken, nullptr,
                                          user.value(QStringLiteral("email"), trimmedEmail).toString());
            });
}

void AuthManager::signInWithPassword(const QString& email, const QString& password)
{
    beginPasswordFlow(email, password, QString(), false);
}

void AuthManager::signUpWithPassword(const QString& email, const QString& password, const QString& username)
{
    beginPasswordFlow(email, password, username, true);
}

// The browser hands over either a bridge JWT (site sign-in) or a one-time
// auth_code (Google), and the exchange turns either into the desktop pair.
void AuthManager::exchangeForDesktopSession(const QString& bearer, QTcpSocket* replySocket, const QString& handoffEmail)
{
    QJsonObject body;
    body.insert(QStringLiteral("deviceName"), QStringLiteral("Animind Qt Desktop"));
    body.insert(QStringLiteral("deviceId"), deviceId());

    request(QNetworkAccessManager::PostOperation, QStringLiteral("/api/auth/desktop/exchange"),
            QJsonDocument(body).toJson(QJsonDocument::Compact), bearer.toUtf8(),
            [this, replySocket, handoffEmail](bool ok, int, const QVariantMap& payload) {
                const QJsonObject obj = QJsonObject::fromVariantMap(payload);
                const QString access = payload.value(QStringLiteral("access_token")).toString();
                const QString refresh = payload.value(QStringLiteral("refresh_token")).toString();
                const qint64 expMs = expiryFrom(obj);
                if (!ok || access.isEmpty() || refresh.isEmpty() || expMs <= 0) {
                    if (replySocket)
                        respondToBrowser(replySocket, 500, QStringLiteral("Sign-in failed"),
                                         QStringLiteral("The desktop session could not be created."));
                    signingIn_ = false;
                    emit signingInChanged();
                    setError(QStringLiteral("Could not create a desktop session."));
                    emit signInFailed(lastError_);
                    return;
                }

                accessToken_ = access;
                refreshToken_ = refresh;
                sessionId_ = payload.value(QStringLiteral("session_id")).toString();
                expiresAtMs_ = expMs;

                const QString fromPayload = payload.value(QStringLiteral("user_id")).toString();
                finishSignIn(fromPayload.isEmpty() ? userId_ : fromPayload, handoffEmail, expMs);

                if (replySocket)
                    respondToBrowser(replySocket, 200, QStringLiteral("Sign-in complete"),
                                     QStringLiteral("You can close this tab and return to Animind."));
            });
}

void AuthManager::finishSignIn(const QString& userId, const QString& email, qint64 expMs)
{
    timeout_.stop();
    closeBridge();
    signingIn_ = false;
    emit signingInChanged();

    userId_ = userId;
    if (!email.isEmpty())
        email_ = email;
    expiresAtMs_ = expMs;
    persistSession();
    scheduleRefreshTimer();
    emit sessionChanged();
    emit signInSucceeded();

    // The desktop token identifies the device; the profile endpoint fills in the
    // avatar and display name the shell shows.
    request(QNetworkAccessManager::GetOperation, QStringLiteral("/api/auth/me"), QByteArray(), QByteArray(),
            [this](bool ok, int, const QVariantMap& payload) {
                const QVariantMap user = payload.value(QStringLiteral("user")).toMap();
                if (!ok || user.isEmpty())
                    return;
                userId_ = user.value(QStringLiteral("id"), userId_).toString();
                email_ = user.value(QStringLiteral("email"), email_).toString();
                username_ = user.value(QStringLiteral("username")).toString();
                avatarUrl_ = user.value(QStringLiteral("avatar_url")).toString();
                persistSession();
                emit sessionChanged();
                emit profileChanged();
            });

    refreshLibrary();
}

void AuthManager::onNewConnection()
{
    QTcpSocket* socket = server_.nextPendingConnection();
    if (!socket)
        return;

    connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
        const QByteArray raw = socket->readAll();
        const QList<QByteArray> lines = raw.split('\n');
        if (lines.isEmpty())
            return;
        const QList<QByteArray> parts = lines.first().trimmed().split(' ');
        if (parts.size() < 2)
            return;

        const QUrl url(QStringLiteral("http://localhost") + QString::fromUtf8(parts.at(1)));
        const QUrlQuery query(url);
        const QString token = query.queryItemValue(QStringLiteral("token"));
        const QString authCode = query.queryItemValue(QStringLiteral("auth_code"));

        if (!token.isEmpty()) {
            exchangeForDesktopSession(token, socket, QString());
            return;
        }
        if (!authCode.isEmpty()) {
            // A one-time code becomes a session, then the session becomes a desktop pair.
            request(QNetworkAccessManager::PostOperation, QStringLiteral("/api/auth/consume-code"),
                    QJsonDocument(QJsonObject{{QStringLiteral("code"), authCode}}).toJson(QJsonDocument::Compact),
                    QByteArray(), [this, socket](bool ok, int, const QVariantMap& payload) {
                        const QString sessionToken = sessionTokenFrom(payload);
                        if (!ok || sessionToken.isEmpty()) {
                            respondToBrowser(socket, 400, QStringLiteral("Sign-in failed"),
                                             QStringLiteral("That sign-in link has expired."));
                            return;
                        }
                        exchangeForDesktopSession(sessionToken, socket, QString());
                    });
            return;
        }

        respondToBrowser(socket, 400, QStringLiteral("Sign-in failed"), QStringLiteral("No token was received."));
    });

    connect(socket, &QTcpSocket::disconnected, socket, &QTcpSocket::deleteLater);
}

void AuthManager::respondToBrowser(QTcpSocket* socket, int status, const QString& heading, const QString& detail)
{
    if (!socket)
        return;
    const QByteArray body = QStringLiteral(
                                "<html><body style=\"font-family:sans-serif;background:#07090C;color:#F2F4F8;text-align:center;padding-top:48px\">"
                                "<h2>%1</h2><p style=\"opacity:.75\">%2</p></body></html>")
                                .arg(heading, detail)
                                .toUtf8();
    const QByteArray head = status == 200
        ? QByteArrayLiteral("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n")
        : QStringLiteral("HTTP/1.1 %1 Bad Request\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n")
              .arg(status)
              .toUtf8();
    socket->write(head);
    socket->write(body);
    socket->disconnectFromHost();
}

void AuthManager::closeBridge()
{
    if (server_.isListening())
        server_.close();
}

void AuthManager::onAuthTimeout()
{
    closeBridge();
    if (!signingIn_)
        return;
    signingIn_ = false;
    emit signingInChanged();
    setError(QStringLiteral("Sign-in timed out. Please try again."));
}

void AuthManager::onRefreshTimeout()
{
    if (refreshToken_.isEmpty())
        return;
    request(QNetworkAccessManager::PostOperation, QStringLiteral("/api/auth/desktop/refresh"),
            QJsonDocument(QJsonObject{{QStringLiteral("refresh_token"), refreshToken_}}).toJson(QJsonDocument::Compact),
            QByteArray(), [this](bool ok, int, const QVariantMap& payload) {
                if (!ok) {
                    qWarning() << "Session refresh failed; keeping current session until re-auth.";
                    return;
                }
                applyTokens(payload);
            });
}

void AuthManager::applyTokens(const QVariantMap& payload)
{
    const QJsonObject obj = QJsonObject::fromVariantMap(payload);
    const QString access = payload.value(QStringLiteral("access_token")).toString();
    const QString refresh = payload.value(QStringLiteral("refresh_token")).toString();
    const qint64 expMs = expiryFrom(obj);
    if (access.isEmpty() || refresh.isEmpty() || expMs <= 0)
        return;

    accessToken_ = access;
    refreshToken_ = refresh;
    const QString sid = payload.value(QStringLiteral("session_id")).toString();
    if (!sid.isEmpty())
        sessionId_ = sid;
    expiresAtMs_ = expMs;

    if (api_)
        api_->setAccessToken(access);

    persistSession();
    scheduleRefreshTimer();
    emit sessionChanged();
}

void AuthManager::signOut()
{
    if (!refreshToken_.isEmpty() || !accessToken_.isEmpty()) {
        QJsonObject body;
        if (!refreshToken_.isEmpty())
            body.insert(QStringLiteral("refresh_token"), refreshToken_);
        request(QNetworkAccessManager::PostOperation, QStringLiteral("/api/auth/desktop/revoke"),
                QJsonDocument(body).toJson(QJsonDocument::Compact), QByteArray(),
                [](bool ok, int, const QVariantMap&) {
                    if (!ok)
                        qWarning() << "Revoke was not confirmed; the local session is still cleared.";
                });
    }

    timeout_.stop();
    refreshTimer_.stop();
    closeBridge();
    signingIn_ = false;
    emit signingInChanged();

    userId_.clear();
    email_.clear();
    username_.clear();
    avatarUrl_.clear();
    accessToken_.clear();
    refreshToken_.clear();
    sessionId_.clear();
    expiresAtMs_ = 0;
    libraryShows_.clear();
    if (api_)
        api_->setAccessToken(QString());
    emit libraryShowsChanged();
    emit sessionChanged();
    emit profileChanged();

    QFile::remove(sessionFilePath());
    QFile::remove(libraryCacheFilePath());
}

void AuthManager::scheduleRefreshTimer()
{
    refreshTimer_.stop();
    if (expiresAtMs_ <= 0)
        return;
    qint64 msUntil = expiresAtMs_ - QDateTime::currentMSecsSinceEpoch() - 30000;
    if (msUntil < 15000)
        msUntil = 15000;
    if (msUntil > INT_MAX)
        msUntil = INT_MAX;
    refreshTimer_.start(static_cast<int>(msUntil));
}

void AuthManager::setError(const QString& error)
{
    if (lastError_ == error)
        return;
    lastError_ = error;
    emit lastErrorChanged();
}

QString AuthManager::sessionFilePath() const
{
    return dataDir() + QStringLiteral("/session.json");
}

void AuthManager::persistSession() const
{
    QJsonObject obj;
    obj.insert(QStringLiteral("userId"), userId_);
    obj.insert(QStringLiteral("email"), email_);
    obj.insert(QStringLiteral("username"), username_);
    obj.insert(QStringLiteral("avatarUrl"), avatarUrl_);
    obj.insert(QStringLiteral("accessToken"), accessToken_);
    obj.insert(QStringLiteral("refreshToken"), refreshToken_);
    obj.insert(QStringLiteral("sessionId"), sessionId_);
    obj.insert(QStringLiteral("expiresAt"), static_cast<double>(expiresAtMs_));

    QFile f(sessionFilePath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    // Tokens stay in the per-user profile directory, never world-readable.
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

void AuthManager::restoreSession()
{
    QFile f(sessionFilePath());
    if (!f.exists() || !f.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return;
    const QJsonObject obj = doc.object();

    userId_ = obj.value(QStringLiteral("userId")).toString();
    email_ = obj.value(QStringLiteral("email")).toString();
    username_ = obj.value(QStringLiteral("username")).toString();
    avatarUrl_ = obj.value(QStringLiteral("avatarUrl")).toString();
    accessToken_ = obj.value(QStringLiteral("accessToken")).toString();
    refreshToken_ = obj.value(QStringLiteral("refreshToken")).toString();
    sessionId_ = obj.value(QStringLiteral("sessionId")).toString();
    expiresAtMs_ = static_cast<qint64>(obj.value(QStringLiteral("expiresAt")).toDouble(0));
    if (api_)
        api_->setAccessToken(accessToken_);

    loadLibraryCache();
    emit sessionChanged();
    emit profileChanged();

    if (!authenticated()) {
        if (refreshToken_.isEmpty()) {
            signOut();
            return;
        }
        request(QNetworkAccessManager::PostOperation, QStringLiteral("/api/auth/desktop/refresh"),
                QJsonDocument(QJsonObject{{QStringLiteral("refresh_token"), refreshToken_}}).toJson(QJsonDocument::Compact),
                QByteArray(), [this](bool ok, int, const QVariantMap& payload) {
                    if (!ok) {
                        signOut();
                        return;
                    }
                    applyTokens(payload);
                    refreshLibrary();
                });
        return;
    }

    if (expiresAtMs_ - QDateTime::currentMSecsSinceEpoch() < 120000)
        onRefreshTimeout();
    else
        scheduleRefreshTimer();
    refreshLibrary();
}

QString AuthManager::libraryCacheFilePath() const
{
    return dataDir() + QStringLiteral("/library_cache.json");
}

void AuthManager::loadLibraryCache()
{
    QFile f(libraryCacheFilePath());
    if (!f.exists() || !f.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return;
    const QJsonArray items = doc.object().value(QStringLiteral("items")).toArray();
    QVariantList rows;
    rows.reserve(items.size());
    for (const auto& item : items) {
        if (item.isObject())
            rows.push_back(item.toObject().toVariantMap());
    }
    libraryShows_ = rows;
    emit libraryShowsChanged();
}

void AuthManager::persistLibraryCache(const QVariantList& items) const
{
    QJsonArray array;
    for (const auto& item : items)
        array.append(QJsonValue::fromVariant(item));

    QJsonObject root;
    root.insert(QStringLiteral("fetchedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    root.insert(QStringLiteral("count"), array.size());
    root.insert(QStringLiteral("items"), array);

    QFile f(libraryCacheFilePath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

void AuthManager::setLibrary(const QVariantList& rows)
{
    // Pages bind the flattened anime_data shape the old direct-database reads produced,
    // so the row envelope is folded into the show object here and not in every page.
    QVariantList flattened;
    flattened.reserve(rows.size());
    for (const auto& value : rows) {
        const QVariantMap row = value.toMap();
        QVariantMap item = row.value(QStringLiteral("anime_data")).toMap();
        if (item.isEmpty())
            item = row;
        const QString status = row.value(QStringLiteral("status")).toString();
        item.insert(QStringLiteral("userStatus"), status);
        item.insert(QStringLiteral("status"), status);
        if (!item.contains(QStringLiteral("anime_id")))
            item.insert(QStringLiteral("anime_id"), row.value(QStringLiteral("anime_id")));
        flattened.push_back(item);
    }
    libraryShows_ = flattened;
    persistLibraryCache(flattened);
    emit libraryShowsChanged();
}

void AuthManager::setLibraryLoading(bool loading)
{
    if (libraryLoading_ == loading)
        return;
    libraryLoading_ = loading;
    emit libraryLoadingChanged();
}

void AuthManager::refreshLibrary()
{
    if (!authenticated() || !api_)
        return;
    api_->setAccessToken(accessToken_);
    setLibraryLoading(true);
    api_->fetchWatchlist();
}

void AuthManager::addToLibrary(const QVariantMap& animeData)
{
    if (!authenticated()) {
        setError(QStringLiteral("Sign in to keep a list."));
        return;
    }
    QString animeId = animeData.value(QStringLiteral("anilist_id")).toString();
    if (animeId.isEmpty())
        animeId = animeData.value(QStringLiteral("id")).toString();
    if (animeId.isEmpty())
        return;

    for (const auto& value : libraryShows_) {
        if (value.toMap().value(QStringLiteral("anime_id")).toString() == animeId)
            return;
    }

    QVariantMap optimistic = animeData;
    optimistic.insert(QStringLiteral("anime_id"), animeId);
    optimistic.insert(QStringLiteral("userStatus"), QStringLiteral("Plan to Watch"));
    optimistic.insert(QStringLiteral("status"), QStringLiteral("Plan to Watch"));
    libraryShows_.prepend(optimistic);
    emit libraryShowsChanged();

    QVariantMap payload = animeData;
    payload.remove(QStringLiteral("userStatus"));
    payload.remove(QStringLiteral("status"));
    api_->setAccessToken(accessToken_);
    api_->putWatchlist(animeId, payload, QStringLiteral("Plan to Watch"));
}

void AuthManager::updateShowStatus(const QString& showId, const QString& status)
{
    if (!authenticated() || showId.isEmpty() || !api_)
        return;

    for (int i = 0; i < libraryShows_.size(); ++i) {
        QVariantMap item = libraryShows_[i].toMap();
        if (item.value(QStringLiteral("anime_id")).toString() == showId) {
            item.insert(QStringLiteral("userStatus"), status);
            item.insert(QStringLiteral("status"), status);
            libraryShows_[i] = item;
            emit libraryShowsChanged();
            break;
        }
    }

    api_->setAccessToken(accessToken_);
    api_->patchWatchlistStatus(showId, status);
}

void AuthManager::removeShow(const QString& showId)
{
    if (!authenticated() || showId.isEmpty() || !api_)
        return;

    for (int i = 0; i < libraryShows_.size(); ++i) {
        if (libraryShows_[i].toMap().value(QStringLiteral("anime_id")).toString() == showId) {
            libraryShows_.removeAt(i);
            emit libraryShowsChanged();
            break;
        }
    }

    api_->setAccessToken(accessToken_);
    api_->deleteWatchlist(showId);
}
