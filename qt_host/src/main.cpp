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
#include <QJsonDocument>
#include <QSet>
#include <QTimer>

#include "mpv_item.h"
#include "auth_manager.h"
#include "backend_api.h"
#include "backend_config.h"
#include "syncplay_client.h"

// A GUI exe owns no console; ANIMIND_UI_LOG=<file> mirrors messages where a script can read them.
static QFile g_uiLog;

static void uiLogHandler(QtMsgType, const QMessageLogContext&, const QString& message)
{
    g_uiLog.write(message.toUtf8() + '\n');
    g_uiLog.flush();
}

// Parses .env, searched from the exe directory upward.
static void loadDotEnv(const QString& startDir)
{
    QDir dir(startDir);
    for (int depth = 0; depth < 5; ++depth) {
        const QFile file(dir.filePath(QStringLiteral(".env")));
        if (file.exists()) {
            QFile readable(dir.filePath(QStringLiteral(".env")));
            if (readable.open(QIODevice::ReadOnly | QIODevice::Text)) {
                const QStringList lines = QString::fromUtf8(readable.readAll()).split(QLatin1Char('\n'));
                for (const QString& line : lines) {
                    const QString trimmed = line.trimmed();
                    if (trimmed.isEmpty() || trimmed.startsWith(QLatin1Char('#')))
                        continue;
                    const int equals = trimmed.indexOf(QLatin1Char('='));
                    if (equals <= 0)
                        continue;
                    const QString key = trimmed.left(equals).trimmed();
                    const QString value = trimmed.mid(equals + 1).trimmed();
                    if (key.isEmpty() || value.isEmpty())
                        continue;
                    // A real environment variable always wins over the file.
                    if (qEnvironmentVariableIsEmpty(key.toLatin1().constData()))
                        qputenv(key.toLatin1().constData(), value.toUtf8());
                }
            }
            return;
        }
        if (!dir.cdUp())
            return;
    }
}

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

    const QStringList args = app.arguments();

    // --player-probe <file> drives mpv with no window, so observed state can be read by a script.
    // Known limitation: libmpv can fault on exit without a window; this is not a shutdown test.
    const int probeAt = args.indexOf(QStringLiteral("--player-probe"));
    if (probeAt >= 0 && probeAt + 1 < args.size()) {
        QTextStream pout(stdout);
        MpvItem probe;
        QObject::connect(&probe, &MpvItem::positionChanged, [&]() {
            pout << "pos=" << probe.playbackPosition() << " dur=" << probe.duration()
                 << " paused=" << probe.paused() << " buffering=" << probe.buffering()
                 << " ahead=" << probe.bufferedAhead() << Qt::endl;
        });
        QObject::connect(&probe, &MpvItem::idleChanged, [&]() {
            pout << "idle=" << probe.idle() << " paused=" << probe.paused() << Qt::endl;
        });
        QObject::connect(&probe, &MpvItem::fileFinished, [&](const QString& reason) {
            pout << "file-finished " << reason << Qt::endl;
            QCoreApplication::exit(0);
        });
        if (!probe.rendererReady()) {
            pout << "mpv did not initialise" << Qt::endl;
            return 2;
        }
        probe.command(QVariantList{QVariant(QStringLiteral("loadfile")), args.at(probeAt + 1)});
        probe.command(QVariantList{QVariant(QStringLiteral("set")), QStringLiteral("pause"), QStringLiteral("no")});
        QTimer::singleShot(8000, &app, [&]() {
            pout << "direct-read eof-reason=" << probe.getPropertyString("eof-reason")
                 << " idle-observed=" << probe.idle() << " pos-observed=" << probe.playbackPosition() << Qt::endl;
        });
        QTimer::singleShot(12000, &app, [&]() { pout << "probe timeout" << Qt::endl; QCoreApplication::exit(0); });
        return app.exec();
    }

    // --sync-selftest drives the watch-party socket with no UI, so a script can verify the transport.
    if (app.arguments().contains(QStringLiteral("--sync-selftest"))) {
        QTextStream out(stdout);
        const QString base = QString::fromLocal8Bit(qgetenv("ANIMIND_SELFTEST_BASE"));
        const QString token = QString::fromLocal8Bit(qgetenv("ANIMIND_SELFTEST_TOKEN"));
        const QString user = QString::fromLocal8Bit(qgetenv("ANIMIND_SELFTEST_USER"));
        // Lag this peer's decisions: with one peer impaired by N ms both must still move together.
        const int impairMs = qEnvironmentVariableIntValue("ANIMIND_SELFTEST_IMPAIR_MS");
        const QString label = impairMs > 0 ? QStringLiteral("slow") : QStringLiteral("fast");
        out << "selftest base=" << base << " token=" << token.left(6) << " label=" << label
            << " impair=" << impairMs << Qt::endl;

        SyncPlayClient client;
        int evaluated = 0;

        auto report = [&](const QString& name, const QVariantMap& payload) {
            const QVariantMap decision = client.evaluate(false, false);
            ++evaluated;
            out << "SYNC event=" << name
                << " seq=" << qint64(payload.value(QStringLiteral("seq")).toDouble())
                << " serverTime=" << qint64(payload.value(QStringLiteral("serverTime")).toDouble())
                << " scheduledPlayAt=" << qint64(payload.value(QStringLiteral("scheduledPlayAt")).toDouble())
                << " outcome=" << decision.value(QStringLiteral("outcome")).toString()
                << " reason=" << decision.value(QStringLiteral("reason")).toString()
                << " clock=" << client.clockConfidence()
                << " ping=" << client.pingMs()
                << Qt::endl;
            if (decision.value(QStringLiteral("outcome")).toString() == QLatin1String("await-schedule")) {
                const qint64 wait = client.msUntilScheduledStart();
                const qint64 armedAt = monotonicMs() + wait;
                const double armedPosition = decision.value(QStringLiteral("targetPosition")).toDouble();
                QTimer::singleShot(int(wait), &app, [&out, &client, label, armedAt, armedPosition]() {
                    const double position = client.acceptScheduledStart();
                    // atServerMs is the only shared timeline: armedFor is monotonic per process.
                    out << "STARTFIRE label=" << label << " skewMs=" << (monotonicMs() - armedAt)
                        << " armedFor=" << armedAt << " atServerMs=" << qint64(client.serverNowMs())
                        << " position=" << position << " intended=" << armedPosition << Qt::endl;
                });
            }
        };

        QObject::connect(&client, &SyncPlayClient::eventReceived,
                         [&out, &client, &app, report, impairMs](const QString& name, const QVariantMap& payload) {
            out << "event " << name << ' '
                << QString::fromUtf8(QJsonDocument::fromVariant(payload).toJson(QJsonDocument::Compact)).left(200)
                << Qt::endl;
            // Without a self-reported buffer the gate waits on a ready that never arrives.
            if (name == QStringLiteral("waitForReady") || name == QStringLiteral("waitForBufferGoal")) {
                client.emitBufferingProgress(240.0, 100.0);
                client.emitReady();
            }
            // The gate releases to "paused"; only the unimpaired peer presses, or a joiner would
            // open a second gate and measure two starts instead of one.
            if (name == QStringLiteral("syncPaused") && impairMs <= 0)
                client.emitPlay(payload.value(QStringLiteral("currentTime")).toDouble());
            static const QSet<QString> decidable = {
                QStringLiteral("allReady"), QStringLiteral("syncPlay"), QStringLiteral("syncPaused"),
                QStringLiteral("sync"), QStringLiteral("seek"), QStringLiteral("pause"),
                QStringLiteral("softCorrect"), QStringLiteral("speedSeek"), QStringLiteral("participantStates"),
            };
            // The delay belongs to the socket layer (ANIMIND_SYNC_LATE_DELIVERY_MS); delaying this
            // call would reorder the peer's own view of the room.
            if (!decidable.contains(name))
                return;
            if (impairMs <= 0) {
                report(name, payload);
                return;
            }
            QTimer::singleShot(impairMs, &app, [&, name, payload]() {
                report(name, payload);
            });
        });
        QObject::connect(&client, &SyncPlayClient::clockOffsetChanged, [&out, &client]() {
            out << "CLOCK offsetMs=" << client.clockOffsetMs() << " confidence=" << client.clockConfidence()
                << " ping=" << client.pingMs() << Qt::endl;
        });
        QObject::connect(&client, &SyncPlayClient::connectedChanged, [&out, &client]() {
            out << "connected=" << client.connected() << " room=" << client.roomCode()
                << " host=" << client.isHost() << Qt::endl;
            if (!client.connected())
                return;
            const QString join = QString::fromLocal8Bit(qgetenv("ANIMIND_SELFTEST_JOIN"));
            if (!join.isEmpty())
                client.joinRoom(join);
            else
                client.createRoom(QString::fromLocal8Bit(qgetenv("ANIMIND_SELFTEST_EPISODE")));
        });
        QObject::connect(&client, &SyncPlayClient::roomAcked,
                         [&out, &client, &app, impairMs](const QString& event, bool ok, const QVariantMap& payload) {
            out << "ack " << event << " ok=" << ok
                << " code=" << payload.value(QStringLiteral("roomCode")).toString()
                << " groupState=" << payload.value(QStringLiteral("groupState")).toString()
                << " features=" << payload.value(QStringLiteral("syncConfig")).toMap()
                                      .value(QStringLiteral("features")).toStringList().count()
                << Qt::endl;
            if (ok && event == QStringLiteral("createRoom")) {
                client.emitReady();
                client.emitHeartbeat(10.0, 1.0, 240.0, 1400.0);
                client.emitTimesyncPing();
                // Exactly one peer originates the play, and the joiner must be in the room before it.
                const int playDelay = qEnvironmentVariableIntValue("ANIMIND_SELFTEST_PLAY_DELAY_MS");
                if (impairMs <= 0) {
                    QTimer::singleShot(playDelay > 0 ? playDelay : 1500, &app, [&client]() {
                        client.emitPlay(10.0);
                    });
                }
            }
        });
        QObject::connect(&client, &SyncPlayClient::roomChanged, [&out, &client]() {
            out << "room changed connected=" << client.connected() << " code=" << client.roomCode()
                << " inRoom=" << client.inRoom() << " host=" << client.isHost()
                << " peers=" << client.totalPeers() << " waitingOn=" << client.waitingOn() << Qt::endl;
        });
        QObject::connect(&client, &SyncPlayClient::activityChanged, [&out, &client]() {
            const QVariantList feed = client.activity();
            if (!feed.isEmpty())
                out << "ACTIVITY " << feed.last().toMap().value(QStringLiteral("text")).toString() << Qt::endl;
        });
        QObject::connect(&client, &SyncPlayClient::lastErrorChanged, [&out, &client]() {
            out << "error " << client.lastError() << Qt::endl;
        });

        client.connectToHost(base, token, user);
        const int windowMs = qEnvironmentVariableIntValue("ANIMIND_SELFTEST_MS");
        QTimer::singleShot(windowMs > 0 ? windowMs : 10000, &app,
                           [&out, &client, &evaluated, label]() {
            // Drive a heartbeat so a drift reading exists across the whole window.
            client.emitHeartbeat(12.0, 1.0, 240.0, 1400.0);
            out << "DECISIONS evaluated=" << evaluated << " label=" << label << Qt::endl;
            out << client.telemetryDump() << Qt::endl;
            QCoreApplication::exit(0);
        });
        return app.exec();
    }

    // Set window icon from the .ico shipped next to the exe
    QString iconPath = QCoreApplication::applicationDirPath() + "/animind.ico";
    if (QFile::exists(iconPath))
        app.setWindowIcon(QIcon(iconPath));
    else
        app.setWindowIcon(QIcon(":/icons/animind.ico")); // fallback to Qt resource

    QString exeDir = QCoreApplication::applicationDirPath();
    loadDotEnv(exeDir);
    g_logFile.setFileName(exeDir + "/animind_qt.log");
    g_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
    qInstallMessageHandler(fileMessageHandler);

    qInfo() << "=== AnimindPlayer startup ===";
    qInfo() << "Render loop: basic (single-threaded)";

    qmlRegisterType<MpvItem>("Animind.Player", 1, 0, "MpvVideo");
    BackendApi api;
    AuthManager authManager(&api);
    SyncPlayClient syncplay;
    qInfo() << "Backend origin:" << backend::baseUrl();
    qInfo() << "Site origin:" << backend::siteUrl();

    QQmlApplicationEngine engine;

    QString qtQmlDir = QString(QT_QML_IMPORT_PATH);
    qInfo() << "Qt QML path:" << qtQmlDir;
    if (!qtQmlDir.isEmpty() && QDir(qtQmlDir).exists())
        engine.addImportPath(qtQmlDir);

    QUrl qmlUrl = QUrl::fromLocalFile(exeDir + "/qml/main.qml");
    const QString uiLogPath = QString::fromLocal8Bit(qgetenv("ANIMIND_UI_LOG"));
    if (!uiLogPath.isEmpty()) {
        g_uiLog.setFileName(uiLogPath);
        if (g_uiLog.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
            qInstallMessageHandler(uiLogHandler);
    }

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
    engine.rootContext()->setContextProperty("api", &api);
    engine.rootContext()->setContextProperty("syncplay", &syncplay);
    engine.rootContext()->setContextProperty("backendBaseUrl", backend::baseUrl());
    engine.rootContext()->setContextProperty("siteBaseUrl", backend::siteUrl());
    // Opt-in harness: the party panel is otherwise only reachable through a click.
    engine.rootContext()->setContextProperty(
        "uiPanelProbe", qEnvironmentVariableIsSet("ANIMIND_UI_PANEL_PROBE"));
    engine.rootContext()->setContextProperty(
        "uiAuthMode", QString::fromLocal8Bit(qgetenv("ANIMIND_UI_AUTH_PROBE")));
    engine.rootContext()->setContextProperty(
        "uiShotPath", QString::fromLocal8Bit(qgetenv("ANIMIND_UI_SHOT")));
    // Host a real party through the UI's own socket, to inspect in-room surfaces against live traffic.
    engine.rootContext()->setContextProperty(
        "uiRoomToken", QString::fromLocal8Bit(qgetenv("ANIMIND_UI_ROOM_TOKEN")));
    engine.rootContext()->setContextProperty(
        "uiRoomEpisode", QString::fromLocal8Bit(qgetenv("ANIMIND_UI_ROOM_EPISODE")));
    engine.rootContext()->setContextProperty(
        "uiRoomUser", QString::fromLocal8Bit(qgetenv("ANIMIND_UI_ROOM_USER")));
    // ANIMIND_UI_MEDIA loads a real file so the controller is observed driving mpv, not just reacting.
    engine.rootContext()->setContextProperty(
        "uiMediaPath", QString::fromLocal8Bit(qgetenv("ANIMIND_UI_MEDIA")));

    engine.load(qmlUrl);

    // --exit-after <ms> lets a script smoke-test UI startup and player teardown.
    const int exitAt = args.indexOf(QStringLiteral("--exit-after"));
    if (exitAt >= 0 && exitAt + 1 < args.size()) {
        const int ms = qMax(500, args.at(exitAt + 1).toInt());
        QTimer::singleShot(ms, &app, []() { QCoreApplication::exit(0); });
    }

    return app.exec();
}
