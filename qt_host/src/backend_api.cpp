#include "backend_api.h"

#include "backend_config.h"

#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>

namespace {
constexpr int kTimeoutMs = 15000;

QByteArray jsonBody(const QJsonObject& object)
{
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

QString messageFromError(const QByteArray& payload, const QString& fallback)
{
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (doc.isObject()) {
        const QJsonObject obj = doc.object();
        const QString message = obj.value(QStringLiteral("message")).toString();
        if (!message.isEmpty())
            return message;
    }
    return fallback;
}
}

BackendApi::BackendApi(QObject* parent)
    : QObject(parent)
    , baseUrl_(backend::baseUrl())
{
}

void BackendApi::setAccessToken(const QString& token)
{
    if (accessToken_ == token)
        return;
    accessToken_ = token;
    emit accessTokenChanged();
}

void BackendApi::setPending(bool pending)
{
    const int next = pending ? pending_ + 1 : qMax(0, pending_ - 1);
    if (next == pending_)
        return;
    pending_ = next;
    emit onlineChanged();
}

QString BackendApi::resolveUrl(const QString& maybeRelative) const
{
    if (maybeRelative.isEmpty())
        return maybeRelative;
    if (maybeRelative.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)
        || maybeRelative.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive))
        return maybeRelative;
    return baseUrl_ + (maybeRelative.startsWith(QLatin1Char('/')) ? maybeRelative : QStringLiteral("/") + maybeRelative);
}

QNetworkRequest BackendApi::prepare(const QString& path, bool requiresAuth) const
{
    QNetworkRequest req{QUrl(baseUrl_ + path)};
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "Animind-Qt/1.0");
    req.setTransferTimeout(kTimeoutMs);
    if (requiresAuth && !accessToken_.isEmpty())
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken_.toUtf8());
    return req;
}

void BackendApi::send(QNetworkAccessManager::Operation operation,
                      const QString& endpoint,
                      const QString& path,
                      const QByteArray& body,
                      Expect expect,
                      std::function<void(const QJsonValue&)> onValue)
{
    QNetworkRequest req = prepare(path, true);
    if (!body.isEmpty())
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    if (accessToken_.isEmpty()) {
        emit requestFailed(endpoint, 401, QStringLiteral("Sign in to reach this data."));
        return;
    }

    QNetworkReply* reply = nullptr;
    switch (operation) {
    case QNetworkAccessManager::GetOperation:
        reply = net_.get(req);
        break;
    case QNetworkAccessManager::PostOperation:
        reply = net_.post(req, body);
        break;
    case QNetworkAccessManager::PutOperation:
        reply = net_.put(req, body);
        break;
    case QNetworkAccessManager::DeleteOperation:
        reply = net_.deleteResource(req);
        break;
    case QNetworkAccessManager::CustomOperation:
        reply = net_.sendCustomRequest(req, "PATCH", body);
        break;
    default:
        reply = net_.get(req);
        break;
    }

    setPending(true);
    connect(reply, &QNetworkReply::finished, this, [this, reply, endpoint, expect, onValue]() {
        setPending(false);
        reply->deleteLater();

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray payload = reply->readAll();
        if (reply->error() != QNetworkReply::NoError) {
            emit requestFailed(endpoint, status > 0 ? status : 0,
                               messageFromError(payload, reply->errorString()));
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(payload);
        if (expect == Expect::Object && !doc.isObject()) {
            emit requestFailed(endpoint, 0, QStringLiteral("Expected a JSON object from %1.").arg(endpoint));
            return;
        }
        if (expect == Expect::Array && !doc.isArray()) {
            emit requestFailed(endpoint, 0, QStringLiteral("Expected a JSON array from %1.").arg(endpoint));
            return;
        }
        onValue(doc.isObject() ? QJsonValue(doc.object()) : QJsonValue(doc.array()));
    });
}

void BackendApi::fetchWatchlist()
{
    send(QNetworkAccessManager::GetOperation, QStringLiteral("watchlist"),
         QStringLiteral("/api/me/watchlist"), {}, Expect::Array,
         [this](const QJsonValue& value) { emit watchlistLoaded(value.toArray().toVariantList()); });
}

void BackendApi::putWatchlist(const QString& animeId, const QVariantMap& animeData, const QString& status)
{
    if (animeId.isEmpty())
        return;
    QJsonObject body;
    body.insert(QStringLiteral("anime_id"), animeId);
    body.insert(QStringLiteral("anime_data"), QJsonValue::fromVariant(animeData));
    body.insert(QStringLiteral("status"), status.isEmpty() ? QStringLiteral("Plan to Watch") : status);

    const QString path = QStringLiteral("/api/me/watchlist/") + QString::fromUtf8(QUrl::toPercentEncoding(animeId));
    send(QNetworkAccessManager::PutOperation, QStringLiteral("watchlist"), path, jsonBody(body), Expect::Object,
         [this, animeId, status](const QJsonValue&) {
             emit watchlistSaved(animeId, status.isEmpty() ? QStringLiteral("Plan to Watch") : status);
         });
}

void BackendApi::patchWatchlistStatus(const QString& animeId, const QString& status)
{
    if (animeId.isEmpty())
        return;
    QJsonObject body;
    body.insert(QStringLiteral("status"), status);
    const QString path = QStringLiteral("/api/me/watchlist/") + QString::fromUtf8(QUrl::toPercentEncoding(animeId));
    send(QNetworkAccessManager::CustomOperation, QStringLiteral("watchlist"), path, jsonBody(body), Expect::Object,
         [this, animeId, status](const QJsonValue&) { emit watchlistSaved(animeId, status); });
}

void BackendApi::deleteWatchlist(const QString& animeId)
{
    if (animeId.isEmpty())
        return;
    const QString path = QStringLiteral("/api/me/watchlist/") + QString::fromUtf8(QUrl::toPercentEncoding(animeId));
    send(QNetworkAccessManager::DeleteOperation, QStringLiteral("watchlist"), path, {}, Expect::Object,
         [this, animeId](const QJsonValue&) { emit watchlistRemoved(animeId); });
}

void BackendApi::fetchHistory(int limit)
{
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("limit"), QString::number(qBound(1, limit, 200)));
    send(QNetworkAccessManager::GetOperation, QStringLiteral("history"),
         QStringLiteral("/api/me/history?") + query.toString(QUrl::FullyEncoded), {}, Expect::Array,
         [this](const QJsonValue& value) { emit historyLoaded(value.toArray().toVariantList()); });
}

void BackendApi::putHistory(const QVariantMap& entry)
{
    // The server derives the owner from the token, so user_id is not sent: writing it
    // was how the previous client could save rows against somebody else's account.
    QJsonObject body;
    body.insert(QStringLiteral("show_title"), entry.value(QStringLiteral("show_title")).toString());
    body.insert(QStringLiteral("episode_label"), entry.value(QStringLiteral("episode_label")).toString());
    if (entry.contains(QStringLiteral("thumbnail_url")))
        body.insert(QStringLiteral("thumbnail_url"), QJsonValue::fromVariant(entry.value(QStringLiteral("thumbnail_url"))));
    if (entry.contains(QStringLiteral("anilist_id")))
        body.insert(QStringLiteral("anilist_id"), QJsonValue::fromVariant(entry.value(QStringLiteral("anilist_id"))));
    body.insert(QStringLiteral("progress_pct"), entry.value(QStringLiteral("progress_pct")).toInt());

    send(QNetworkAccessManager::PutOperation, QStringLiteral("history"),
         QStringLiteral("/api/me/history"), jsonBody(body), Expect::Object,
         [this](const QJsonValue&) { emit historySaved(); });
}

void BackendApi::fetchProgress(const QString& animeId, int episodeIndex)
{
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("anime_id"), animeId);
    query.addQueryItem(QStringLiteral("episode_index"), QString::number(episodeIndex));
    send(QNetworkAccessManager::GetOperation, QStringLiteral("progress"),
         QStringLiteral("/api/me/progress?") + query.toString(QUrl::FullyEncoded), {}, Expect::Object,
         [this, animeId, episodeIndex](const QJsonValue& value) {
             emit progressLoaded(animeId, episodeIndex, value.toObject().value(QStringLiteral("timestamp")).toDouble());
         });
}

void BackendApi::putProgress(const QString& animeId, int episodeIndex, double timestamp)
{
    if (animeId.isEmpty())
        return;
    QJsonObject body;
    body.insert(QStringLiteral("anime_id"), animeId);
    body.insert(QStringLiteral("episode_index"), episodeIndex);
    body.insert(QStringLiteral("timestamp"), timestamp);
    send(QNetworkAccessManager::PutOperation, QStringLiteral("progress"),
         QStringLiteral("/api/me/progress"), jsonBody(body), Expect::Object, [](const QJsonValue&) {});
}

void BackendApi::fetchRecentProgress()
{
    send(QNetworkAccessManager::GetOperation, QStringLiteral("progress"),
         QStringLiteral("/api/me/progress/recent"), {}, Expect::Array,
         [this](const QJsonValue& value) { emit recentProgressLoaded(value.toArray().toVariantList()); });
}

void BackendApi::fetchShow(const QString& showId)
{
    if (showId.isEmpty())
        return;
    send(QNetworkAccessManager::GetOperation, QStringLiteral("show"),
         QStringLiteral("/api/shows/") + QString::fromUtf8(QUrl::toPercentEncoding(showId)), {}, Expect::Object,
         [this, showId](const QJsonValue& value) { emit showLoaded(showId, value.toObject().toVariantMap()); });
}

void BackendApi::fetchStreamTicket(const QString& episodeId, const QString& clientType)
{
    if (episodeId.isEmpty())
        return;
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("clientType"), clientType.isEmpty() ? QStringLiteral("native") : clientType);

    const QString path = QStringLiteral("/api/episodes/") + QString::fromUtf8(QUrl::toPercentEncoding(episodeId))
                         + QStringLiteral("/stream-ticket?") + query.toString(QUrl::FullyEncoded);
    send(QNetworkAccessManager::GetOperation, QStringLiteral("stream-ticket"), path, {}, Expect::Object,
         [this, episodeId](const QJsonValue& value) {
             QVariantMap ticket = value.toObject().toVariantMap();
             // mpv receives this URL with no headers and no cookies, so it must be absolute
             // and self-authenticating before it leaves here.
             ticket.insert(QStringLiteral("url"), resolveUrl(ticket.value(QStringLiteral("url")).toString()));
             emit streamTicketLoaded(episodeId, ticket);
         });
}

void BackendApi::fetchPreferences()
{
    send(QNetworkAccessManager::GetOperation, QStringLiteral("preferences"),
         QStringLiteral("/api/me/preferences"), {}, Expect::Object,
         [this](const QJsonValue& value) { emit preferencesLoaded(value.toObject().toVariantMap()); });
}

void BackendApi::putPreferences(const QVariantMap& preferences)
{
    send(QNetworkAccessManager::PutOperation, QStringLiteral("preferences"),
         QStringLiteral("/api/me/preferences"),
         jsonBody(QJsonObject::fromVariantMap(preferences)), Expect::Object, [](const QJsonValue&) {});
}

void BackendApi::checkRoom(const QString& code)
{
    const QString upper = code.trimmed().toUpper();
    if (upper.isEmpty())
        return;
    QNetworkRequest req = prepare(QStringLiteral("/api/syncplay/rooms/") + upper, false);
    QNetworkReply* reply = net_.get(req);
    setPending(true);
    connect(reply, &QNetworkReply::finished, this, [this, reply, upper]() {
        setPending(false);
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() == QNetworkReply::NoError && status == 200) {
            emit roomChecked(upper, true, QJsonDocument::fromJson(reply->readAll()).object().toVariantMap());
            return;
        }
        QVariantMap info;
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (doc.isObject())
            info.insert(QStringLiteral("message"), doc.object().value(QStringLiteral("message")).toString());
        // 404 never existed and 410 ended are both "cannot join", but only one is worth
        // telling the user their code expired.
        info.insert(QStringLiteral("statusCode"), status);
        emit roomChecked(upper, false, info);
    });
}
