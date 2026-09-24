import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// TopBar — 64px broadcast head bar.
// Voice: Bahnschrift, uppercase, tracked. Active nav is an on-air underline,
// not a filled pill, so the bar reads as a channel strip.
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

    readonly property color clrSurface:   "#07070d"
    readonly property color clrPrimary:   "#f47521"
    readonly property color clrMuted:     "#9a9ab2"
    readonly property color clrOnSurface: "#f2f2f7"

    height: 64

    // ── Background ───────────────────────────────────────────────────────
    Rectangle {
        id: barBg
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(0.027, 0.027, 0.051, 0.98) }
            GradientStop { position: 1.0; color: Qt.rgba(0.027, 0.027, 0.051, 0.88) }
        }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }
    }

    // ── Content ──────────────────────────────────────────────────────────
    RowLayout {
        anchors { fill: parent; leftMargin: 28; rightMargin: 24 }
        spacing: 28

        // ── Brand ────────────────────────────────────────────────────────
        Item {
            implicitWidth: logoRow.implicitWidth
            implicitHeight: 40
            Layout.alignment: Qt.AlignVCenter

            Row {
                id: logoRow
                spacing: 11
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 26; height: 26
                    radius: 7
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#f47521" }
                        GradientStop { position: 1.0; color: "#b23a86" }
                    }
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        text: "\u25B6"
                        color: "white"
                        font.pixelSize: 11
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ANIMIND"
                    color: topBar.clrOnSurface
                    font.family: "Bahnschrift, Segoe UI Variable Display, Segoe UI"
                    font.pixelSize: 21
                    font.weight: Font.Bold
                    font.letterSpacing: 3.6
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: topBar.navLinkClicked("home")
            }
        }

        // ── Nav ──────────────────────────────────────────────────────────
        Row {
            spacing: 22
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: [
                    { id: "home",      label: "HOME" },
                    { id: "search",    label: "SEARCH" },
                    { id: "trending",  label: "TRENDING" },
                    { id: "simulcast", label: "MY SHOWS" },
                    { id: "mylist",    label: "MY LISTS" },
                    { id: "history",   label: "HISTORY" }
                ]

                delegate: Item {
                    id: navItem
                    width: navLabel.implicitWidth
                    height: 40
                    activeFocusOnTab: true

                    readonly property bool isActive: topBar.currentPage === modelData.id

                    Text {
                        id: navLabel
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: modelData.label
                        color: navItem.isActive ? topBar.clrOnSurface
                             : navMa.containsMouse ? "#c8c8dc"
                             : topBar.clrMuted
                        font.family: "Bahnschrift, Segoe UI Variable Display, Segoe UI"
                        font.pixelSize: 13
                        font.weight: navItem.isActive ? Font.Bold : Font.Normal
                        font.letterSpacing: 1.9
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }

                    // On-air underline
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 2; radius: 1
                        color: topBar.clrPrimary
                        visible: navItem.isActive
                        scale: navItem.isActive ? 1.0 : 0.6
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }

                    // Keyboard focus
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: -6 }
                        height: 1
                        color: "#f47521"
                        visible: navItem.activeFocus
                    }

                    Keys.onEnterPressed: topBar.navLinkClicked(modelData.id)
                    Keys.onReturnPressed: topBar.navLinkClicked(modelData.id)
                    Keys.onSpacePressed: topBar.navLinkClicked(modelData.id)

                    MouseArea {
                        id: navMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { navItem.forceActiveFocus(); topBar.navLinkClicked(modelData.id) }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // ── Right side ───────────────────────────────────────────────────
        Row {
            spacing: 14
            Layout.alignment: Qt.AlignVCenter

            Item {
                id: notifIcon
                width: 34; height: 34
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 17
                    color: notifMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    border.color: topBar.clrMuted
                    border.width: 1
                    opacity: 0.9
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "\uEA8F"   // Segoe MDL2 Assets: ringer
                    color: notifMa.containsMouse ? topBar.clrPrimary : topBar.clrMuted
                    font.family: "Segoe MDL2 Assets"
                    font.pixelSize: 15
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
            width: 34; height: 34

            Rectangle {
                anchors.fill: parent
                radius: 17
                color: "#22232e"
                border.color: Qt.rgba(0.95, 0.46, 0.13, 0.45)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: {
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
                    font.family: "Bahnschrift, Segoe UI Variable Display, Segoe UI"
                    font.pixelSize: 15
                    font.weight: Font.Bold
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
            width: btnText.implicitWidth + 26; height: 32
            radius: 4
            color: btnMa.containsMouse ? Qt.rgba(0.95, 0.46, 0.13, 0.18) : "transparent"
            border.color: Qt.rgba(0.95, 0.46, 0.13, 0.55)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                id: btnText
                anchors.centerIn: parent
                text: (authManager && authManager.signingIn) ? "SIGNING IN" : "SIGN IN"
                color: topBar.clrPrimary
                font.family: "Bahnschrift, Segoe UI Variable Display, Segoe UI"
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.8
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
