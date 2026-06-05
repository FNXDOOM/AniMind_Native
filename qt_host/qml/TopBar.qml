import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Effects

// TopBar — fixed 64px glassmorphic top bar
// Usage:
//   TopBar {
//       sideNavWidth: 256          // set to 0 if sidebar is hidden
//       currentPage:  root.currentPage
//       onSearchClicked:     { ... }
//       onProfileClicked:    { ... }
//   }

Item {
    id: topBar

    // ── Public API ────────────────────────────────────────────────────────
    property int    sideNavWidth:  256
    property string currentPage:   "home"
    property string searchQuery:   ""

    signal searchClicked()
    signal notificationsClicked()
    signal profileClicked()
    signal navLinkClicked(string page)

    // Position of the notification icon centre, mapped to root/window coordinates.
    // Use this in main.qml to right-align NotificationPanel to the icon.
    readonly property point notifIconCenter: notifIcon.visible
        ? notifIcon.mapToItem(null, notifIcon.width / 2, notifIcon.height / 2)
        : Qt.point(0, 0)

    // ── Design tokens ─────────────────────────────────────────────────────
    readonly property color clrSurface:   "#131313"
    readonly property color clrPrimary:   "#ffb693"
    readonly property color clrMuted:     "#e2bfb0"
    readonly property color clrOnSurface: "#e5e2e1"
    readonly property color clrBorder:    "#1c1b1b"

    height: 64

    // ── Background ────────────────────────────────────────────────────────
    Rectangle {
        id: barBg
        anchors.fill: parent
        color: Qt.rgba(0.075, 0.075, 0.075, 0.82)

        // Bottom border line
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.06)
        }
    }

    MultiEffect {
        source: barBg
        anchors.fill: barBg
        blurEnabled: true
        blur: 1.0
        blurMax: 28
        z: -1
    }

    // ── Content ───────────────────────────────────────────────────────────
    RowLayout {
        // Inset by sideNavWidth so content starts where sidebar ends
        anchors {
            fill: parent
            leftMargin: topBar.sideNavWidth + 24
            rightMargin: 24
        }
        spacing: 32

        // Centre nav links (Browse / Trending / Simulcasts)
        Row {
            spacing: 28

            Repeater {
                model: [
                    { page: "browse",    label: "Browse"     },
                    { page: "trending",  label: "Trending"   },
                    { page: "simulcast", label: "Simulcasts" }
                ]

                delegate: Item {
                    height: topBar.height
                    width: lbl.implicitWidth + 4

                    Text {
                        id: lbl
                        anchors.centerIn: parent
                        text: modelData.label
                        color: topBar.currentPage === modelData.page
                               ? topBar.clrPrimary
                               : topBar.clrMuted
                        font {
                            family: "Inter"
                            pixelSize: 13
                            weight: topBar.currentPage === modelData.page ? Font.DemiBold : Font.Normal
                            letterSpacing: 0.7
                        }
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }

                    // Active underline
                    Rectangle {
                        visible: topBar.currentPage === modelData.page
                        anchors { bottom: parent.bottom; bottomMargin: 0; horizontalCenter: parent.horizontalCenter }
                        width: lbl.implicitWidth
                        height: 2
                        radius: 1
                        color: topBar.clrPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: topBar.navLinkClicked(modelData.page)
                        onEntered: lbl.color = topBar.clrPrimary
                        onExited:  lbl.color = topBar.currentPage === modelData.page
                                               ? topBar.clrPrimary : topBar.clrMuted
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }   // pushes icons to the right

        // ── Right-side icon buttons ───────────────────────────────────────
        Row {
            spacing: 8

            // Search
            TopBarIcon {
                glyph: "\u2315"
                tip: "Search"
                clrMuted: topBar.clrMuted
                clrPrimary: topBar.clrPrimary
                onClicked: topBar.searchClicked()
            }

            // Notifications
            TopBarIcon {
                id: notifIcon
                glyph: "\uD83D\uDD14"
                tip: "Notifications"
                clrMuted: topBar.clrMuted
                clrPrimary: topBar.clrPrimary
                onClicked: topBar.notificationsClicked()
            }

            // Profile avatar
            Item {
                width: 36; height: 36
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 18
                    color: "#353534"
                    border.color: Qt.rgba(1, 0.714, 0.576, 0.25)
                    border.width: 1.5

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (!authManager || !authManager.authenticated) return "?"
                            var dn = root.computeDisplayName(
                                authManager.email, authManager.userId, authManager.authenticated)
                            if (dn === "Guest" || dn === "User") return "?"
                            return dn.charAt(0).toUpperCase()
                        }
                        color: topBar.clrPrimary
                        font { pixelSize: 15; weight: Font.Bold }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: topBar.profileClicked()
                }
            }
        }
    }

    // ── TopBarIcon inline component ───────────────────────────────────────
    component TopBarIcon: Item {
        id: tbi
        width: 36; height: 36
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        property string glyph: ""
        property string tip:   ""
        property color clrMuted:   "#e2bfb0"
        property color clrPrimary: "#ffb693"

        signal clicked()

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: tbiMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Text {
            anchors.centerIn: parent
            text: tbi.glyph
            color: tbiMa.containsMouse ? tbi.clrPrimary : tbi.clrMuted
            font { family: "Inter"; pixelSize: 19; weight: Font.DemiBold }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        MouseArea {
            id: tbiMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tbi.clicked()
        }

        ToolTip.text: tbi.tip
        ToolTip.visible: tbiMa.containsMouse
        ToolTip.delay: 500
    }
}
