import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Effects

// SideNav — 256px glassmorphic sidebar
// Usage:
//   SideNav {
//       currentPage: root.currentPage   // "home" | "browse" | "mylist" | "history" | "settings"
//       onNavigate:  (page) => root.currentPage = page
//   }

Item {
    id: sideNav

    // ── Public API ────────────────────────────────────────────────────────
    property string currentPage: "home"
    signal navigate(string page)

    // ── Design tokens (mirrors stitch tailwind config) ────────────────────
    readonly property color clrBackground:    "#0e0e0e"   // surface-container-lowest
    readonly property color clrBorder:        "#1c1b1b"   // surface-container-low
    readonly property color clrPrimary:       "#ffb693"   // primary
    readonly property color clrPrimaryAccent: "#ff6b00"   // primary-container
    readonly property color clrSecondary:     "#ddb7ff"   // secondary
    readonly property color clrOnSurface:     "#e5e2e1"   // on-surface
    readonly property color clrMuted:         "#e2bfb0"   // on-surface-variant
    readonly property color clrSurfaceHigh:   "#2a2a2a"   // surface-container-high
    readonly property color clrSurface:       "#201f1f"   // surface-container

    width: 256
    height: parent ? parent.height : 720

    // ── Background panel ──────────────────────────────────────────────────
    Rectangle {
        id: panelBg
        anchors.fill: parent
        color: Qt.rgba(0.055, 0.055, 0.055, 0.82)   // ~surface-container-lowest/82

        // Right border
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }
    }

    // Blur source — blurs whatever is behind the sidebar
    MultiEffect {
        source: panelBg
        anchors.fill: panelBg
        blurEnabled: true
        blur: 1.0
        blurMax: 32
        z: -1
    }

    // ── Content layout ────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 0 }
        spacing: 0

        // Logo
        Item {
            Layout.fillWidth: true
            height: 80

            Text {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                text: "ANIMIND"
                color: sideNav.clrPrimary
                font {
                    family: "Montserrat"
                    pixelSize: 26
                    weight: Font.Black
                    letterSpacing: -0.5
                }
            }
        }

        // Nav items
        Column {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            spacing: 2

            Repeater {
                model: [
                    { page: "home",     icon: "\u2302", label: "Home"     },
                    { page: "mylist",   icon: "\u2605", label: "My List"  },
                    { page: "history",  icon: "\u23f2", label: "History"  },
                    { page: "settings", icon: "\u2699", label: "Settings" }
                ]

                delegate: NavItem {
                    width: parent.width
                    page:    modelData.page
                    icon:    modelData.icon
                    label:   modelData.label
                    active:  sideNav.currentPage === modelData.page
                    clrPrimary:     sideNav.clrPrimary
                    clrMuted:       sideNav.clrMuted
                    clrSurfaceHigh: sideNav.clrSurfaceHigh
                    onClicked: sideNav.navigate(modelData.page)
                }
            }
        }

        Item { Layout.fillHeight: true }   // spacer

        // ── User card ─────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 16
            height: userCardCol.implicitHeight + 24
            color: Qt.rgba(0.125, 0.122, 0.122, 0.5)   // surface-container/50
            radius: 12
            border.color: Qt.rgba(1, 1, 1, 0.05)
            border.width: 1

            ColumnLayout {
                id: userCardCol
                anchors { fill: parent; margins: 12 }
                spacing: 12

                // Avatar + name row
                RowLayout {
                    spacing: 10

                    // Avatar circle
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: "#353534"

                        Text {
                            anchors.centerIn: parent
                            text: root.computeDisplayName(
                                authManager ? authManager.email        : "",
                                authManager ? authManager.userId       : "",
                                authManager ? authManager.authenticated : false
                            ).charAt(0).toUpperCase()
                            color: sideNav.clrPrimary
                            font { pixelSize: 17; weight: Font.Bold }
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            id: userNameText
                            Layout.fillWidth: true
                            text: root.computeDisplayName(
                                authManager ? authManager.email        : "",
                                authManager ? authManager.userId       : "",
                                authManager ? authManager.authenticated : false
                            )
                            color: sideNav.clrOnSurface
                            font { family: "Inter"; pixelSize: 13; weight: Font.Medium }
                            elide: Text.ElideRight

                            ToolTip.visible: userNameMouse.containsMouse && userNameText.truncated
                            ToolTip.text: userNameText.text
                            ToolTip.delay: 250

                            MouseArea {
                                id: userNameMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                        Text {
                            text: authManager && authManager.authenticated ? "Signed In" : "Not Signed In"
                            color: sideNav.clrSecondary
                            font { family: "Inter"; pixelSize: 11 }
                        }
                    }
                }

                // Upgrade button
                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    radius: 8
                    color: Qt.rgba(1, 0.42, 0, 0.15)   // primary-container/15
                    border.color: Qt.rgba(1, 0.42, 0, 0.3)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: authManager && authManager.signingIn
                              ? "Signing In..."
                              : (authManager && authManager.authenticated ? "Sign Out" : "Sign In with Browser")
                        color: sideNav.clrPrimary
                        font { family: "Inter"; pixelSize: 12; weight: Font.DemiBold; letterSpacing: 0.7 }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !(authManager && authManager.signingIn)
                        onClicked: {
                            if (!authManager) return
                            if (authManager.authenticated) authManager.signOut()
                            else authManager.signInWithBrowserBridge()
                        }
                    }
                }
            }
        }
    }

    // ── NavItem component (inline) ────────────────────────────────────────
    component NavItem: Item {
        id: navItem
        height: 48

        property string page:  ""
        property string icon:  ""
        property string label: ""
        property bool   active: false

        property color clrPrimary:     "#ffb693"
        property color clrMuted:       "#e2bfb0"
        property color clrSurfaceHigh: "#2a2a2a"

        signal clicked()

        // Active/hover background
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: navItem.active
                   ? Qt.rgba(1, 0.714, 0.576, 0.10)   // primary/10
                   : (navMa.containsMouse
                      ? Qt.rgba(1, 1, 1, 0.06)
                      : "transparent")

            Behavior on color { ColorAnimation { duration: 150 } }

            // Active left glow strip
            Rectangle {
                visible: navItem.active
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 3; height: 20; radius: 2
                color: navItem.clrPrimary
                opacity: 0.9
            }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            spacing: 14

            Text {
                text: navItem.icon
                color: navItem.active ? navItem.clrPrimary : navItem.clrMuted
                font { family: "Inter"; pixelSize: 20; weight: Font.DemiBold }
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Text {
                Layout.fillWidth: true
                text: navItem.label
                color: navItem.active ? navItem.clrPrimary : navItem.clrMuted
                font { family: "Montserrat"; pixelSize: 15; weight: navItem.active ? Font.DemiBold : Font.Normal }
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        MouseArea {
            id: navMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: navItem.clicked()
        }

        // Subtle glow behind active item (matches stitch shadow-[0_0_15px_rgba(255,182,147,0.2)])
        layer.enabled: navItem.active
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(1, 0.714, 0.576, 0.20)
            shadowBlur: 0.8
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }
    }
}
