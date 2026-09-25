import QtQuick
import QtQuick.Controls
import ".."

// Profile menu. One of the few surfaces allowed to read as glass: it floats
// over content, so a translucent surface with a hairline is the honest
// affordance for "this is a layer above the page".
Rectangle {
    id: menu

    property bool   authenticated: false
    property string displayName:   "Guest"
    property string detail:        ""

    signal settingsRequested()
    signal myListRequested()
    signal signInOutRequested(bool signingIn)
    signal dismissed()

    width: 248
    height: col.implicitHeight + Theme.s4
    radius: Theme.rLg
    color: Qt.rgba(0.082, 0.106, 0.137, 0.97)
    border.color: Theme.borderDefault
    border.width: 1

    // Section 24's entrance, applied to a menu: fade with a small scale lift.
    scale: 0.96
    opacity: 0
    Component.onCompleted: { lift.running = true }
    ParallelAnimation {
        id: lift
        NumberAnimation { target: menu; property: "scale"; from: 0.96; to: 1.0; duration: Theme.dFast; easing.type: Theme.easeOutCubic }
        NumberAnimation { target: menu; property: "opacity"; from: 0; to: 1; duration: Theme.dFast; easing.type: Theme.easeOutCubic }
    }

    Column {
        id: col
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.s2 }
        spacing: 1

        // ── Account header ───────────────────────────────────────────────
        Item {
            width: parent.width
            height: 56

            Row {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: Theme.s3

                Rectangle {
                    width: 34; height: 34; radius: 17
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceRaised
                    border.color: menu.authenticated ? Theme.accent : Theme.borderDefault
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: menu.displayName.charAt(0).toUpperCase()
                        color: Theme.textPrimary
                        font.family: Theme.bodyFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 34 - Theme.s3
                    spacing: 1

                    Text {
                        width: parent.width
                        text: menu.displayName
                        color: Theme.textPrimary
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsBody
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: text.length > 0
                        width: parent.width
                        text: menu.detail
                        color: Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsSmall
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle { width: parent.width - Theme.s4; height: 1; anchors.horizontalCenter: parent.horizontalCenter; color: Theme.borderSubtle }

        MenuItemRow { label: "Settings";  glyph: "\uE713"; onPicked: menu.settingsRequested() }
        MenuItemRow { label: "My List";   glyph: "\uE8FD"; onPicked: menu.myListRequested() }
        MenuItemRow { label: menu.authenticated ? "Sign out" : "Sign in"
                      glyph: menu.authenticated ? "\uE77B" : "\uE77B"
                      onPicked: menu.signInOutRequested(!menu.authenticated) }
    }
}
