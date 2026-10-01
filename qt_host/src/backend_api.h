#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

class QNetworkReply;
class QNetworkRequest;

// Async transport for the Animind API. Nothing here blocks: every call returns
// immediately and reports through a signal, because the previous implementation
// ran a nested event loop inside each request and froze the UI behind it.
class BackendApi : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString accessToken READ accessToken WRITE setAccessToken NOTIFY accessTokenChanged)
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)

public:
    explicit BackendApi(QObject* parent = nullptr);

    QString accessToken() const { return accessToken_; }
    void setAccessToken(const QString& token);

    QString baseUrl() const { return baseUrl_; }
    bool online() const { return pending_ > 0; }

    // Watchlist. Rows carry anime_data verbatim, so the caller's field names survive.
    Q_INVOKABLE void fetchWatchlist();
    Q_INVOKABLE void putWatchlist(const QString& animeId, const QVariantMap& animeData, const QString& status);
    Q_INVOKABLE void patchWatchlistStatus(const QString& animeId, const QString& status);
    Q_INVOKABLE void deleteWatchlist(const QString& animeId);

    // History is the "continue watching" rail; progress is a resume position in seconds.
    Q_INVOKABLE void fetchHistory(int limit = 50);
    Q_INVOKABLE void putHistory(const QVariantMap& entry);
    Q_INVOKABLE void fetchProgress(const QString& animeId, int episodeIndex);
    Q_INVOKABLE void putProgress(const QString& animeId, int episodeIndex, double timestamp);
    Q_INVOKABLE void fetchRecentProgress();

    // Catalog and playback.
    Q_INVOKABLE void fetchShow(const QString& showId);
    Q_INVOKABLE void fetchStreamTicket(const QString& episodeId, const QString& clientType = QStringLiteral("native"));

    // Preferences replace the settings page's localStorage-only behaviour.
    Q_INVOKABLE void fetchPreferences();
    Q_INVOKABLE void putPreferences(const QVariantMap& preferences);

    // Lets a join bar validate a code before the user is asked to open the episode.
    Q_INVOKABLE void checkRoom(const QString& code);

    Q_INVOKABLE QString resolveUrl(const QString& maybeRelative) const;

signals:
    void accessTokenChanged();
    void baseUrlChanged();
    void onlineChanged();

    void watchlistLoaded(const QVariantList& rows);
    void watchlistSaved(const QString& animeId, const QString& status);
    void watchlistRemoved(const QString& animeId);
    void historyLoaded(const QVariantList& rows);
    void historySaved();
    void progressLoaded(const QString& animeId, int episodeIndex, double timestamp);
    void recentProgressLoaded(const QVariantList& entries);
    void showLoaded(const QString& showId, const QVariantMap& show);
    void streamTicketLoaded(const QString& episodeId, const QVariantMap& ticket);
    void preferencesLoaded(const QVariantMap& preferences);
    void roomChecked(const QString& code, bool found, const QVariantMap& room);

    // A failed request carries the endpoint so the caller can decide whether the
    // failure is user-visible or just a missing feature.
    void requestFailed(const QString& endpoint, int status, const QString& message);

private:
    enum class Expect { Object, Array };

    QNetworkRequest prepare(const QString& path, bool requiresAuth) const;
    void send(QNetworkAccessManager::Operation operation,
              const QString& endpoint,
              const QString& path,
              const QByteArray& body,
              Expect expect,
              std::function<void(const QJsonValue&)> onValue);
    void setPending(bool pending);

    QNetworkAccessManager net_;
    QString accessToken_;
    QString baseUrl_;
    int pending_ = 0;
};
