import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

// TopBar — the content header. Desktop: global search pill, bell, avatar.
// Compact: hamburger, brand, search icon, avatar. Primary navigation lives in
// SideNav (or the bottom tab bar on phones).
Item {
    id: bar

    property string currentPage: "home"
    property bool   compact:     false
    property alias  query:       searchInput.text
    readonly property bool searching: searchInput.text.length > 0

    signal navLinkClicked(string page)
    signal searchClicked()
    signal notificationsClicked()
    signal profileClicked()
    signal menuClicked()
    signal querySubmitted(string text)

    readonly property point notifIconCenter: notifBtn.visible
        ? notifBtn.mapToItem(null, notifBtn.width / 2, notifBtn.height / 2)
        : Qt.point(0, 0)

    height: compact ? 56 : 64

    readonly property color field:    Theme.input
    readonly property color hairline: Theme.borderDefault
    readonly property color muted:    Theme.textMuted
    readonly property string font:    Theme.bodyFont
    readonly property string icons:   Theme.iconFont

    // ── Hamburger, compact only ──────────────────────────────────────────
    Item {
        id: menuBtn
        visible: bar.compact
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
        width: 40; height: 40
        activeFocusOnTab: true

        // Three drawn bars instead of a font glyph: no icon-font dependency.
        Column {
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: 3
                delegate: Rectangle { width: 18; height: 2; radius: 1; color: "#ffffff" }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 8
            color: menuMa.containsMouse ? "#161616" : "transparent"
            border.color: menuBtn.activeFocus ? "#ffffff" : "transparent"
            border.width: menuBtn.activeFocus ? 2 : 0
        }
        MouseArea {
            id: menuMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bar.menuClicked()
        }
    }

    Text {
        id: brandMini
        visible: bar.compact
        anchors { left: menuBtn.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
        text: "Animind"
        color: "#ffffff"
        font.family: bar.font
        font.pixelSize: 17
        font.weight: Font.Bold
    }

    // ── Search field ─────────────────────────────────────────────────────
    Rectangle {
        id: searchPill
        visible: !bar.compact
        anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
        readonly property int baseWidth: Math.min(560, Math.max(220, parent.width - 220))
        width: baseWidth + (searchInput.activeFocus ? Theme.s6 : 0)
        height: 40
        radius: 20
        color: searchInput.activeFocus ? Theme.surfaceRaised : bar.field
        border.color: searchInput.activeFocus ? Theme.borderStrong : bar.hairline
        border.width: 1

        Behavior on width { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.dBase } }
        Behavior on border.color { ColorAnimation { duration: Theme.dBase } }

        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
            spacing: 10

            Text {
                text: "\uE721"
                color: bar.muted
                font.family: bar.icons
                font.pixelSize: 13
                Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: "#ffffff"
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                font.family: bar.font
                font.pixelSize: 14
                cursorVisible: true
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length === 0 && !searchInput.activeFocus
                    text: "Search anime, genres, or characters"
                    color: bar.muted
                    font.family: bar.font
                    font.pixelSize: 14
                }
                onAccepted: bar.querySubmitted(text)
                Keys.onEscapePressed: { searchInput.text = ""; searchInput.focus = false }
            }

            Item {
                Layout.alignment: Qt.AlignVCenter
                width: 20; height: 20
                visible: searchInput.text.length > 0
                Text {
                    anchors.centerIn: parent
                    text: "\uE711"
                    color: bar.muted
                    font.family: bar.icons
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                }
            }
        }
    }

    Item {
        id: searchBtn
        visible: bar.compact
        anchors { right: avatarBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
        width: 40; height: 40
        Text {
            anchors.centerIn: parent
            text: "\uE721"
            color: "#ffffff"
            font.family: bar.icons
            font.pixelSize: 15
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: bar.searchClicked()
        }
    }

    // ── Bell ─────────────────────────────────────────────────────────────
    Item {
        id: notifBtn
        visible: !bar.compact
        anchors { right: avatarBtn.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        width: 36; height: 36

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: notifMa.containsMouse ? "#1a1a1a" : "transparent"
            border.color: bar.hairline
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text {
            anchors.centerIn: parent
            text: "\uEA8F"
            color: "#d4d4d4"
            font.family: bar.icons
            font.pixelSize: 14
        }
        MouseArea {
            id: notifMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bar.notificationsClicked()
        }
    }

    // ── Avatar ───────────────────────────────────────────────────────────
    Item {
        id: avatarBtn
        anchors { right: parent.right; rightMargin: bar.compact ? 12 : 24; verticalCenter: parent.verticalCenter }
        width: 34; height: 34
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: parent
            radius: 17
            color: avatarHover.hovered ? Theme.surfaceRaised : Theme.card
            border.color: (authManager && authManager.authenticated)
                          ? Theme.accent : bar.hairline
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.dFast } }
        }

        HoverHandler { id: avatarHover }

        Text {
            anchors.centerIn: parent
            visible: text.length > 0
            text: {
                if (!authManager || !authManager.authenticated) return ""
                var em = authManager.email || ""
                if (em.indexOf("@") !== -1) {
                    var local = em.substring(0, em.indexOf("@"))
                    if (local.length > 0) return local.charAt(0).toUpperCase()
                }
                var uid = authManager.userId || ""
                return uid.length > 0 ? uid.replace("user_", "").charAt(0).toUpperCase() : "U"
            }
            color: "#ffffff"
            font.family: bar.font
            font.pixelSize: 14
            font.weight: Font.Bold
        }

        Text {
            anchors.centerIn: parent
            visible: authManager ? !authManager.authenticated : true
            text: "\uE77B"
            color: "#d4d4d4"
            font.family: bar.icons
            font.pixelSize: 15
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                avatarBtn.forceActiveFocus()
                bar.profileClicked()
            }
        }
    }
}
