import QtQuick
import QtQuick.Controls
import "components"

// SideNav — the app rail. Expands to 176px and collapses to 68px; the width
// animates, labels fade and slide, icons reposition and stay legible.
// Icons are Segoe MDL2 Assets under a single family name: a comma-separated
// fallback chain makes every glyph render as tofu.
Item {
    id: sideNav

    property string currentPage: "home"
    property bool   drawerMode:  false
    property bool   collapsed:   false

    signal navigate(string page)
    // The toggle asks the shell to collapse; root owns the state so the rail
    // width and the content column can never disagree mid-animation.
    signal toggleRequested()

    readonly property int expandedW:  Theme.railExpandedW
    readonly property int collapsedW: Theme.railCollapsedW
    readonly property int railWidth:  drawerMode ? expandedW : (collapsed ? collapsedW : expandedW)

    implicitWidth: railWidth
    width: railWidth
    height: parent ? parent.height : 720

    Behavior on width {
        NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic }
    }

    readonly property color activeBg:  Theme.surfaceRaised
    readonly property color hoverBg:   Theme.card
    readonly property color label:     Theme.textSecondary
    readonly property color labelHi:   Theme.textPrimary

    Rectangle {
        anchors.fill: parent
        color: Theme.sidebar
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 1
            color: sideNav.drawerMode ? "transparent" : Theme.borderSubtle
        }
    }

    // ── Brand ────────────────────────────────────────────────────────────
    Item {
        id: brand
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.leftMargin: sideNav.collapsed && !sideNav.drawerMode ? 0 : Theme.s5
        anchors.topMargin: Theme.s5
        height: 28

        Behavior on anchors.leftMargin {
            NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic }
        }

        // The mark stays put when collapsed; only the wordmark fades.
        Text {
            id: brandMark
            anchors.verticalCenter: parent.verticalCenter
            x: sideNav.collapsed && !sideNav.drawerMode ? (sideNav.railWidth - implicitWidth) / 2 : 0
            text: "\uE768"
            color: Theme.accent
            font.family: Theme.iconFont
            font.pixelSize: 15

            Behavior on x { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: brandMark.right
            anchors.leftMargin: Theme.s3
            text: "Animind"
            color: Theme.textPrimary
            font.family: Theme.displayFont
            font.pixelSize: 19
            font.weight: Font.Bold
            font.letterSpacing: -0.2
            opacity: sideNav.collapsed && !sideNav.drawerMode ? 0 : 1
            visible: opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: Theme.dFast; easing.type: Theme.easeOutCubic } }
        }
    }

    // ── Nav ──────────────────────────────────────────────────────────────
    Column {
        id: navCol
        anchors { top: brand.bottom; left: parent.left; right: parent.right }
        anchors.topMargin: Theme.s6
        anchors.leftMargin: Theme.s3
        anchors.rightMargin: Theme.s3
        spacing: Theme.s1

        Repeater {
            model: [
                { page: "home",    icon: "\uE80F", label: "Home" },
                { page: "browse",  icon: "\uE80A", label: "Browse" },
                { page: "search",  icon: "\uE721", label: "Search" },
                { page: "mylist",  icon: "\uE71D", label: "My List" },
                { page: "history", icon: "\uE823", label: "Continue Watching" },
                { page: "simulcast", icon: "\uE7C1", label: "My Shows" }
            ]

            delegate: RailItem {
                width: navCol.width
                railIcon: modelData.icon
                railLabel: modelData.label
                isActive: sideNav.currentPage === modelData.page
                isCollapsed: sideNav.collapsed && !sideNav.drawerMode
                onActivated: sideNav.navigate(modelData.page)
            }
        }
    }

    // ── Pinned footer ────────────────────────────────────────────────────
    Column {
        id: footCol
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        anchors.bottomMargin: Theme.s4
        anchors.leftMargin: Theme.s3
        anchors.rightMargin: Theme.s3
        spacing: Theme.s1

        Repeater {
            model: [
                { page: "settings", icon: "\uE713", label: "Settings" },
                { page: "__collapse", icon: "",     label: "" }
            ]

            delegate: RailItem {
                id: footItem
                width: footCol.width
                railIcon: modelData.icon
                railLabel: modelData.label
                isCollapsed: sideNav.collapsed && !sideNav.drawerMode
                isToggle: modelData.page === "__collapse"
                isActive: !isToggle && sideNav.currentPage === modelData.page
                toggleState: sideNav.collapsed
                onActivated: isToggle ? sideNav.toggleRequested()
                                      : sideNav.navigate(modelData.page)
            }
        }
    }
}
