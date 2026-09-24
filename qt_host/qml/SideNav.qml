import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// SideNav — the app rail. 208px on desktop; also instantiated inside a
// Drawer at compact widths. Icons are Segoe MDL2 Assets, single family name:
// a comma-separated fallback chain makes every glyph render as tofu.
Item {
    id: sideNav

    property string currentPage: "home"
    property bool   drawerMode:  false
    signal navigate(string page)

    width:  drawerMode ? 240 : 208
    height: parent ? parent.height : 720

    readonly property color bg:       "#0a0a0a"
    readonly property color activeBg: "#1e1e1e"
    readonly property color hoverBg:  "#161616"
    readonly property color hairline: "#1f1f1f"
    readonly property color label:    "#b3b3b3"
    readonly property color labelHi:  "#ffffff"
    readonly property string font:  "Segoe UI Variable Text, Segoe UI"
    readonly property string icons: "Segoe MDL2 Assets"

    Rectangle {
        anchors.fill: parent
        color: sideNav.bg
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 1
            color: sideNav.drawerMode ? "transparent" : sideNav.hairline
        }
    }

    // ── Brand ────────────────────────────────────────────────────────────
    Item {
        id: brand
        anchors { top: parent.top; left: parent.left; right: parent.right
                  leftMargin: 20; topMargin: 18 }
        height: 28
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Animind"
            color: "#ffffff"
            font.family: sideNav.font
            font.pixelSize: 19
            font.weight: Font.Bold
            font.letterSpacing: -0.2
        }
    }

    // ── Nav ──────────────────────────────────────────────────────────────
    Column {
        id: navCol
        anchors { top: brand.bottom; left: parent.left; right: parent.right
                  topMargin: 22; leftMargin: 12; rightMargin: 12 }
        spacing: 2

        Repeater {
            model: [
                { page: "home",      icon: "\uE80F", label: "Home" },
                { page: "browse",    icon: "\uE80A", label: "Browse" },
                { page: "mylist",    icon: "\uE71D", label: "My List" },
                { page: "history",   icon: "\uE823", label: "Continue Watching" },
                { page: "simulcast", icon: "\uE7C1", label: "My Shows" }
            ]

            delegate: Item {
                id: row
                width: navCol.width
                height: 40
                activeFocusOnTab: true
                readonly property bool isActive: sideNav.currentPage === modelData.page

                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.onPressAction: sideNav.navigate(modelData.page)

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: row.isActive ? sideNav.activeBg
                         : (rowMa.containsMouse ? sideNav.hoverBg : "transparent")
                    Behavior on color { ColorAnimation { duration: 130 } }
                }

                Rectangle {
                    visible: row.isActive
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 3; height: 18; radius: 2
                    color: "#ffffff"
                }

                Row {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Text {
                        text: modelData.icon
                        color: row.isActive ? sideNav.labelHi : sideNav.label
                        font.family: sideNav.icons
                        font.pixelSize: 15
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: modelData.label
                        color: row.isActive ? sideNav.labelHi : sideNav.label
                        font.family: sideNav.font
                        font.pixelSize: 14
                        font.weight: row.isActive ? Font.DemiBold : Font.Normal
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 2 }
                    height: 2; radius: 1; color: "#ffffff"
                    visible: row.activeFocus
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { row.forceActiveFocus(); sideNav.navigate(modelData.page) }
                }
                Keys.onEnterPressed:  sideNav.navigate(modelData.page)
                Keys.onReturnPressed: sideNav.navigate(modelData.page)
            }
        }
    }

    // ── Settings, pinned to the bottom ───────────────────────────────────
    Item {
        id: settingsRow
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                  bottomMargin: 16; leftMargin: 12; rightMargin: 12 }
        height: 40
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: setMa.containsMouse ? sideNav.hoverBg : "transparent"
            Behavior on color { ColorAnimation { duration: 130 } }
        }

        Row {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 12
            Text {
                text: "\uE713"
                color: sideNav.label
                font.family: sideNav.icons
                font.pixelSize: 15
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "Settings"
                color: sideNav.label
                font.family: sideNav.font
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: setMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sideNav.navigate("settings")
        }
    }
}
