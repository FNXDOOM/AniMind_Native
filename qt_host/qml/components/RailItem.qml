import QtQuick
import QtQuick.Controls
import ".."

// One rail row: icon, label, active marker, hover, focus and keyboard.
// Used for both the nav group and the pinned footer so the two can never
// drift apart in height or spacing.
Item {
    id: rail

    property string railIcon: ""
    property string railLabel: ""
    property bool   isActive: false
    property bool   isCollapsed: false
    property bool   isToggle: false
    property bool   toggleState: false
    property string tooltip: railLabel

    signal activated()

    implicitHeight: 40
    height: 40
    activeFocusOnTab: true

    readonly property bool labelVisible: !isCollapsed
    readonly property bool iconOnly: isCollapsed
    // The toggle has no glyph in the model; it derives one from the state it
    // is about to leave, so it stays reachable once the rail is narrow.
    readonly property string shownIcon: isToggle ? (toggleState ? "\uE76C" : "\uE76B") : railIcon

    Rectangle {
        anchors.fill: parent
        radius: Theme.rMd
        color: rail.isActive ? Theme.surfaceRaised : (hover.hovered ? Theme.hoverBg : "transparent")

        Behavior on color { ColorAnimation { duration: Theme.dFast } }
    }

    // Active marker: the accent, one of the few places it is allowed.
    Rectangle {
        visible: rail.isActive
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 3
        height: 18
        radius: 2
        color: Theme.accent
    }

    Text {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        // Centred in the narrow rail, left-aligned in the wide one.
        x: rail.iconOnly ? (rail.width - implicitWidth) / 2 : Theme.s3
        text: rail.shownIcon
        color: rail.isActive ? Theme.textPrimary : Theme.textSecondary
        font.family: Theme.iconFont
        font.pixelSize: 15

        Behavior on x { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: icon.right
        anchors.leftMargin: Theme.s3
        text: rail.isToggle ? (rail.toggleState ? "Expand" : "Collapse") : rail.railLabel
        color: rail.isActive ? Theme.textPrimary : Theme.textSecondary
        font.family: Theme.bodyFont
        font.pixelSize: Theme.tsBody
        font.weight: rail.isActive ? Font.DemiBold : Font.Normal
        // No width binding: the rail itself clips, and assigning `undefined`
        // to width is an error that takes the whole delegate down with it.
        opacity: rail.labelVisible ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: Theme.dFast; easing.type: Theme.easeOutCubic } }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: Theme.s1; anchors.rightMargin: Theme.s1
        height: 2; radius: 1
        color: Theme.accent
        visible: rail.activeFocus
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: { rail.forceActiveFocus(); rail.activated() } }

    Keys.onReturnPressed: rail.activated()
    Keys.onEnterPressed:  rail.activated()
    Keys.onSpacePressed:  rail.activated()

    ToolTip.visible: hover.hovered && rail.iconOnly
    ToolTip.delay: 450
    ToolTip.timeout: 3000
    ToolTip.text: rail.tooltip

    Accessible.role: Accessible.Button
    Accessible.name: rail.isToggle ? (rail.toggleState ? "Expand sidebar" : "Collapse sidebar") : rail.railLabel
    Accessible.onPressAction: rail.activated()
}
