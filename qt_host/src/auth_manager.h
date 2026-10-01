#pragma once

#include "backend_api.h"

#include <QObject>
#include <QNetworkAccessManager>
#include <QTcpServer>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class QTcpSocket;

// Owns the desktop token pair (adk_/adr_) and the loopback listener that receives
// a sign-in handoff from a browser. Data calls live in BackendApi; this class only
// authenticates them.
class AuthManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY sessionChanged)
    Q_PROPERTY(bool signingIn READ signingIn NOTIFY signingInChanged)
    Q_PROPERTY(QString userId READ userId NOTIFY sessionChanged)
    Q_PROPERTY(QString email READ email NOTIFY sessionChanged)
    Q_PROPERTY(QString username READ username NOTIFY sessionChanged)
    Q_PROPERTY(QString avatarUrl READ avatarUrl NOTIFY profileChanged)
    Q_PROPERTY(QString accessToken READ accessToken NOTIFY sessionChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantList libraryShows READ libraryShows NOTIFY libraryShowsChanged)
    Q_PROPERTY(bool libraryLoading READ libraryLoading NOTIFY libraryLoadingChanged)

public:
    explicit AuthManager(BackendApi* api, QObject* parent = nullptr);

    bool authenticated() const;
    bool signingIn() const { return signingIn_; }
    QString userId() const { return userId_; }
    QString email() const { return email_; }
    QString username() const { return username_; }
    QString avatarUrl() const { return avatarUrl_; }
    QString accessToken() const { return accessToken_; }
    QString lastError() const { return lastError_; }
    QVariantList libraryShows() const { return libraryShows_; }
    bool libraryLoading() const { return libraryLoading_; }

    Q_INVOKABLE void signInWithBrowserBridge();
    Q_INVOKABLE void signInWithPassword(const QString& email, const QString& password);
    Q_INVOKABLE void signUpWithPassword(const QString& email, const QString& password, const QString& username);
    Q_INVOKABLE void signOut();

    Q_INVOKABLE void refreshLibrary();
    Q_INVOKABLE void addToLibrary(const QVariantMap& animeData);
    Q_INVOKABLE void updateShowStatus(const QString& showId, const QString& status);
    Q_INVOKABLE void removeShow(const QString& showId);

    // Called by the sync layer when the socket is rejected: an expired token is the
    // common cause, and a silent refresh is cheaper than sending the user to sign in.
    Q_INVOKABLE bool ensureValidToken();

signals:
    void sessionChanged();
    void signingInChanged();
    void lastErrorChanged();
    void libraryShowsChanged();
    void libraryLoadingChanged();
    void profileChanged();
    void signInSucceeded();
    void signInFailed(const QString& message);

private slots:
    void onNewConnection();
    void onAuthTimeout();
    void onRefreshTimeout();

private:
    void setError(const QString& error);
    void persistSession() const;
    void restoreSession();
    QString sessionFilePath() const;
    QString libraryCacheFilePath() const;
    void loadLibraryCache();
    void persistLibraryCache(const QVariantList& items) const;
    void setLibrary(const QVariantList& rows);
    void setLibraryLoading(bool loading);
    void applyTokens(const QVariantMap& payload);
    void scheduleRefreshTimer();

    void request(const QNetworkAccessManager::Operation operation,
                 const QString& path,
                 const QByteArray& body,
                 const QByteArray& bearerOverride,
                 std::function<void(bool, int, const QVariantMap&)> done);

    void beginPasswordFlow(const QString& email, const QString& password, const QString& username, bool signup);
    void exchangeForDesktopSession(const QString& bearer, QTcpSocket* replySocket, const QString& handoffEmail);
    void finishSignIn(const QString& userId, const QString& email, qint64 expMs);
    void respondToBrowser(QTcpSocket* socket, int status, const QString& heading, const QString& detail);
    void closeBridge();

    QTcpServer server_;
    QTimer timeout_;
    QTimer refreshTimer_;
    QNetworkAccessManager net_;
    BackendApi* api_ = nullptr;

    bool signingIn_ = false;
    bool libraryLoading_ = false;
    QString userId_;
    QString email_;
    QString username_;
    QString avatarUrl_;
    QString accessToken_;
    QString refreshToken_;
    QString sessionId_;
    qint64 expiresAtMs_ = 0;
    QString lastError_;
    QVariantList libraryShows_;
};
