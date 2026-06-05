import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// NotificationPanel — floating dropdown shown below the TopBar notification icon
// Usage:
//   NotificationPanel {
//       id: notifPanel
//       panelOpen: root.notifPanelOpen
//       onCloseRequested: root.notifPanelOpen = false
//   }

Rectangle {
    id: notificationPanel

    // ── Public API ────────────────────────────────────────────────────────
    property bool panelOpen: false
    property var  notifications: []

    signal closeRequested()

    // ── Design tokens ─────────────────────────────────────────────────────
    readonly property color clrPrimary:   "#ffb693"
    readonly property color clrMuted:     "#e2bfb0"
    readonly property color clrOnSurface: "#e5e2e1"
    readonly property color clrBorder:    "#1c1b1b"

    // ── Geometry ──────────────────────────────────────────────────────────
    width:  Math.max(280, contentColumn.implicitWidth + 32)
    height: contentColumn.implicitHeight + 32

    // ── Visual style ──────────────────────────────────────────────────────
    color:        Qt.rgba(0.075, 0.075, 0.075, 0.82)
    border.color: notificationPanel.clrBorder
    border.width: 1
    radius:       12

    // ── Visibility ────────────────────────────────────────────────────────
    visible: notificationPanel.panelOpen

    // ── Content ───────────────────────────────────────────────────────────
    ColumnLayout {
        id: contentColumn
        anchors {
            top:    parent.top
            left:   parent.left
            right:  parent.right
            margins: 16
        }
        spacing: 0

        // Header
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 12
            text: "Notifications"
            color: notificationPanel.clrPrimary
            font {
                family:    "Montserrat"
                pixelSize: 14
                weight:    Font.DemiBold
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 16
            height: 1
            color:  Qt.rgba(1, 1, 1, 0.06)
        }

        // Empty state — shown when notifications list is empty
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: notificationPanel.notifications.length === 0

            Text {
                Layout.fillWidth: true
                text:            "No new notifications"
                color:           notificationPanel.clrOnSurface
                horizontalAlignment: Text.AlignHCenter
                font {
                    family:    "Inter"
                    pixelSize: 13
                    weight:    Font.Normal
                }
            }

            Text {
                Layout.fillWidth: true
                text:            "You're all caught up!"
                color:           notificationPanel.clrMuted
                horizontalAlignment: Text.AlignHCenter
                font {
                    family:    "Inter"
                    pixelSize: 11
                    weight:    Font.Normal
                }
            }
        }

        // Notifications list — shown when notifications list is non-empty
        Repeater {
            model:   notificationPanel.notifications
            visible: notificationPanel.notifications.length > 0

            delegate: Text {
                Layout.fillWidth: true
                text:  modelData.message || ""
                color: notificationPanel.clrOnSurface
                font {
                    family:    "Inter"
                    pixelSize: 13
                }
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Escape key handler ────────────────────────────────────────────────
    Keys.onEscapePressed: notificationPanel.closeRequested()
}
