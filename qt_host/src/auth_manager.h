#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QTcpServer>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class AuthManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY sessionChanged)
    Q_PROPERTY(bool signingIn READ signingIn NOTIFY signingInChanged)
    Q_PROPERTY(QString userId READ userId NOTIFY sessionChanged)
    Q_PROPERTY(QString email READ email NOTIFY sessionChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantList libraryShows READ libraryShows NOTIFY libraryShowsChanged)

public:
    explicit AuthManager(QObject* parent = nullptr);

    bool authenticated() const;
    bool signingIn() const { return signingIn_; }
    QString userId() const { return userId_; }
    QString email() const { return email_; }
    QString lastError() const { return lastError_; }
    QVariantList libraryShows() const { return libraryShows_; }

    Q_INVOKABLE void signInWithBrowserBridge();
    Q_INVOKABLE void signOut();
    Q_INVOKABLE QVariantMap getShowDetails(const QString& showId);
    Q_INVOKABLE QVariantMap getStreamTicket(const QString& episodeId, int audioTrackIndex = -1, const QString& clientType = "native");

signals:
    void sessionChanged();
    void signingInChanged();
    void lastErrorChanged();
    void libraryShowsChanged();

private slots:
    void onNewConnection();
    void onAuthTimeout();
    void onRefreshTimeout();

private:
    bool decodeJwt(const QString& jwt, QString& outUserId, QString& outSessionId, qint64& outExpMs) const;
    QString extractJsonString(const QByteArray& json, const QString& key) const;
    qint64 extractJsonNumber(const QByteArray& json, const QString& key) const;
    QString extractLikelyEmail(const QByteArray& json) const;
    void setError(const QString& error);
    void persistSession() const;
    void restoreSession();
    QString sessionFilePath() const;
    QString libraryCacheFilePath() const;
    void syncLibraryFromServer();
    void persistLibraryCache(const QJsonArray& items) const;
    void finishSignInSuccess(const QString& userId, const QString& email, const QString& token, const QString& sessionId, qint64 expMs);
    QString deriveClerkFapiFromTokenPayload(const QByteArray& payload) const;
    QString resolveEmailFromClientResponse(const QJsonObject& root, const QString& preferredSessionId) const;
    QString resolveSessionIdFromClientResponse(const QJsonObject& root, const QString& preferredSessionId) const;
    bool hydrateSessionFromClient();
    bool refreshSessionToken();
    bool exchangeClerkTokenForDesktopSession(const QString& clerkToken, QString& outAccessToken, QString& outRefreshToken, QString& outSessionId, qint64& outExpMs);
    bool refreshDesktopSession();
    void revokeDesktopSessionBestEffort();
    void scheduleRefreshTimer();

    QTcpServer server_;
    QTimer timeout_;
    QTimer refreshTimer_;
    QNetworkAccessManager net_;

    bool signingIn_ = false;
    QString userId_;
    QString email_;
    QString accessToken_;
    QString refreshToken_;
    QString sessionId_;
    qint64 expiresAtMs_ = 0;
    bool clerkSessionTokenEndpointDisabled_ = false;
    QString lastError_;
    QVariantList libraryShows_;
};
