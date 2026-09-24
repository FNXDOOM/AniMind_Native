#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickWindow>
#include <QDir>
#include <QLibraryInfo>
#include <QQuickStyle>
#include <QFile>
#include <QTextStream>
#include <QIcon>

#include "mpv_item.h"
#include "auth_manager.h"

static QFile g_logFile;
void fileMessageHandler(QtMsgType type, const QMessageLogContext &, const QString &msg) {
    if (!g_logFile.isOpen()) return;
    QTextStream ts(&g_logFile);
    switch (type) {
        case QtDebugMsg:    ts << "[D] "; break;
        case QtInfoMsg:     ts << "[I] "; break;
        case QtWarningMsg:  ts << "[W] "; break;
        case QtCriticalMsg: ts << "[C] "; break;
        case QtFatalMsg:    ts << "[F] "; break;
    }
    ts << msg << "\n";
    ts.flush();
}

int main(int argc, char *argv[])
{
    // Use OpenGL for Qt scene graph — required for QQuickFramebufferObject + libmpv
    // Disable threaded render loop to avoid deadlocks on AMD integrated graphics
    qputenv("QSG_RENDER_LOOP", "basic");
    qputenv("QSG_RHI_BACKEND", "opengl");
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

    QQuickStyle::setStyle("Material");

    QGuiApplication app(argc, argv);
    app.setApplicationName("AnimindPlayer");
    app.setOrganizationName("Animind");

    // Set window icon from the .ico shipped next to the exe
    QString iconPath = QCoreApplication::applicationDirPath() + "/animind.ico";
    if (QFile::exists(iconPath))
        app.setWindowIcon(QIcon(iconPath));
    else
        app.setWindowIcon(QIcon(":/icons/animind.ico")); // fallback to Qt resource

    QString exeDir = QCoreApplication::applicationDirPath();
    g_logFile.setFileName(exeDir + "/animind_qt.log");
    g_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
    qInstallMessageHandler(fileMessageHandler);

    qInfo() << "=== AnimindPlayer startup ===";
    qInfo() << "Render loop: basic (single-threaded)";

    qmlRegisterType<MpvItem>("Animind.Player", 1, 0, "MpvVideo");
    AuthManager authManager;

    QQmlApplicationEngine engine;

    QString qtQmlDir = QString(QT_QML_IMPORT_PATH);
    qInfo() << "Qt QML path:" << qtQmlDir;
    if (!qtQmlDir.isEmpty() && QDir(qtQmlDir).exists())
        engine.addImportPath(qtQmlDir);

    QUrl qmlUrl = QUrl::fromLocalFile(exeDir + "/qml/main.qml");
    qInfo() << "Loading QML from:" << qmlUrl.toString();

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [qmlUrl](QObject *obj, const QUrl &objUrl) {
            if (!obj && qmlUrl == objUrl) {
                qCritical() << "QML root object failed to create:" << objUrl.toString();
                QCoreApplication::exit(-1);
            }
        }, Qt::QueuedConnection);

    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
        [](const QList<QQmlError> &ws) {
            for (const auto &w : ws) qWarning() << "QML:" << w.toString();
        });

    engine.rootContext()->setContextProperty("authManager", &authManager);
    const QString supabaseUrl  = qgetenv("ANIMIND_SUPABASE_URL");
    const QString supabaseKey  = qgetenv("ANIMIND_SUPABASE_ANON_KEY");
    authManager.setSupabaseConfig(supabaseUrl, supabaseKey);
    engine.rootContext()->setContextProperty("supabaseUrl", supabaseUrl);
    engine.rootContext()->setContextProperty("supabaseKey", supabaseKey);

    engine.load(qmlUrl);
    return app.exec();
}
