import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// TopBar — fixed 64px glassmorphic top bar matching React UI
Item {
    id: topBar

    property string currentPage: "home"

    signal searchClicked()
    signal notificationsClicked()
    signal profileClicked()
    signal navLinkClicked(string page)

    readonly property point notifIconCenter: notifIcon.visible
        ? notifIcon.mapToItem(null, notifIcon.width / 2, notifIcon.height / 2)
        : Qt.point(0, 0)

    readonly property color clrSurface:   "#0a0a0f"
    readonly property color clrPrimary:   "#f47521"
    readonly property color clrMuted:     "#8888a0"
    readonly property color clrOnSurface: "#f0f0f5"

    height: 64

    // ── Background ────────────────────────────────────────────────────────
    Rectangle {
        id: barBg
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(0.039, 0.039, 0.059, 0.98) }
            GradientStop { position: 1.0; color: Qt.rgba(0.039, 0.039, 0.059, 0.92) }
        }

        // Bottom border line
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }
    }

    // ── Content ───────────────────────────────────────────────────────────
    RowLayout {
        anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
        spacing: 32

        // ── Logo ─────────────────────────────────────────────────────────
        Item {
            implicitWidth: logoRow.implicitWidth
            implicitHeight: 40
            Layout.alignment: Qt.AlignVCenter

            Row {
                id: logoRow
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 32; height: 32
                    radius: 8
                    color: topBar.clrPrimary

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        text: "\u25B6" // Play icon
                        color: "white"
                        font.pixelSize: 16
                    }
                }

                Text {
                    text: "ANISTREAM"
                    color: topBar.clrPrimary
                    font { family: "Montserrat"; pixelSize: 22; weight: Font.Bold; letterSpacing: 1.1 }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: topBar.navLinkClicked("home")
            }
        }

        Item { width: 16 } // Spacing

        // ── Centre Nav Links ─────────────────────────────────────────────
        Row {
            spacing: 4
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: [
                    { id: "home",      label: "Home",     icon: "\u2302" },
                    { id: "search",    label: "Search",   icon: "\u2315" },
                    { id: "trending",  label: "Trending", icon: "\u2197" },
                    { id: "simulcast", label: "My Shows", icon: "\uD83D\uDCFA" },
                    { id: "mylist",    label: "My Lists", icon: "\u2630" }
                ]

                delegate: Item {
                    width: navRow.implicitWidth + 32
                    height: 40

                    property bool isActive: topBar.currentPage === modelData.id

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: isActive ? Qt.rgba(0.95, 0.46, 0.13, 0.1) : (navMa.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                        border.color: isActive ? Qt.rgba(0.95, 0.46, 0.13, 0.2) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Row {
                        id: navRow
                        anchors.centerIn: parent
                        spacing: 8
                        
                        Text {
                            text: modelData.icon
                            color: isActive ? topBar.clrPrimary : topBar.clrMuted
                            font { family: "Inter"; pixelSize: 16 }
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.label
                            color: isActive ? topBar.clrPrimary : topBar.clrMuted
                            font { family: "Inter"; pixelSize: 14; weight: Font.Medium }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: navMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: topBar.navLinkClicked(modelData.id)
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }   // pushes icons to the right

        // ── Right Side ───────────────────────────────────────────────────
        Row {
            spacing: 16
            Layout.alignment: Qt.AlignVCenter

            // Notifications
            Item {
                id: notifIcon
                width: 36; height: 36
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 18
                    color: notifMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "\uD83D\uDD14"
                    color: notifMa.containsMouse ? topBar.clrPrimary : topBar.clrMuted
                    font { family: "Inter"; pixelSize: 19 }
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: notifMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: topBar.notificationsClicked()
                }
            }

            // Profile / Sign In
            Loader {
                anchors.verticalCenter: parent.verticalCenter
                active: true
                sourceComponent: (authManager && authManager.authenticated) ? profileAvatar : signInBtn
            }
        }
    }

    Component {
        id: profileAvatar
        Item {
            width: 36; height: 36

            Rectangle {
                anchors.fill: parent
                radius: 18
                color: "#353534"
                border.color: Qt.rgba(0.95, 0.46, 0.13, 0.25)
                border.width: 1.5

                Text {
                    anchors.centerIn: parent
                    text: {
                        // Inline display name logic — avoids cross-file root reference
                        if (!authManager || !authManager.authenticated) return "?"
                        var em = authManager.email || ""
                        if (em.indexOf("@") !== -1) {
                            var local = em.substring(0, em.indexOf("@"))
                            if (local.length > 0) return local.charAt(0).toUpperCase()
                        }
                        var uid = authManager.userId || ""
                        if (uid.length > 0) {
                            var s = uid.startsWith("user_") ? uid.substring(5) : uid
                            return s.charAt(0).toUpperCase()
                        }
                        return "U"
                    }
                    color: topBar.clrPrimary
                    font { pixelSize: 15; weight: Font.Bold }
                }
            }

            MouseArea {
                id: profMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (authManager) authManager.signOut() }
            }

            ToolTip {
                visible: profMa.containsMouse
                text: "Sign Out"
                delay: 500
            }
        }
    }

    Component {
        id: signInBtn
        Rectangle {
            width: btnText.implicitWidth + 32; height: 36
            radius: 8
            color: btnMa.containsMouse ? Qt.rgba(0.95, 0.46, 0.13, 0.2) : Qt.rgba(0.95, 0.46, 0.13, 0.1)
            border.color: Qt.rgba(0.95, 0.46, 0.13, 0.3)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                id: btnText
                anchors.centerIn: parent
                text: (authManager && authManager.signingIn) ? "Signing In..." : "Sign In"
                color: topBar.clrPrimary
                font { family: "Inter"; pixelSize: 14; weight: Font.DemiBold }
            }

            MouseArea {
                id: btnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !(authManager && authManager.signingIn)
                onClicked: {
                    if (authManager) authManager.signInWithBrowserBridge()
                }
            }
        }
    }
}
