#pragma once

#include <QByteArray>
#include <QString>
#include <QUrl>

// The backend origin used to be a compiled-in constant, which made a build
// impossible to point anywhere else. Both the API and the site that hands over
// a sign-in are environment now, with local development defaults.
namespace backend {

inline QString trimTrailingSlash(QString value)
{
    while (value.endsWith(QLatin1Char('/')))
        value.chop(1);
    return value;
}

inline QString baseUrl()
{
    QString value = QString::fromLocal8Bit(qgetenv("ANIMIND_BACKEND_URL")).trimmed();
    if (value.isEmpty())
        value = QStringLiteral("http://127.0.0.1:3001");
    return trimTrailingSlash(value);
}

inline QString siteUrl()
{
    QString value = QString::fromLocal8Bit(qgetenv("ANIMIND_SITE_URL")).trimmed();
    if (value.isEmpty())
        value = QStringLiteral("http://localhost:3000");
    return trimTrailingSlash(value);
}

// The page that mints a bridge token and redirects it to the loopback listener.
inline QString desktopAuthUrl()
{
    return siteUrl() + QStringLiteral("/desktop-auth");
}

inline QUrl url(const QString& path)
{
    return QUrl(baseUrl() + (path.startsWith(QLatin1Char('/')) ? path : QStringLiteral("/") + path));
}

}
