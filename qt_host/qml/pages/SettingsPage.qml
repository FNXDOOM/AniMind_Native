import QtQuick
import QtQuick.Controls
import ".."

// SettingsPage — only controls the shell already honours.
//
// Every row writes a property that already changes something in main.qml, and
// the shell persists it. A setting nothing reads would be a worse placeholder
// than the one this page replaced.
//
// The rows are written out rather than factored into a `component`: an inline
// component here rendered zero rows while still reporting Loader.Ready and a
// clean lint. Re-extract them into components/ as real files if they need to
// be shared.
Rectangle {
    id: page
    color: Theme.bg

    readonly property var app: Window.window
    readonly property int gutter: width < 640 ? Theme.s4 : Theme.s8
    readonly property var speedOpts: [0.75, 1, 1.25, 1.5, 2]

    function speedPicked(v) {
        return page.app ? Math.abs(page.app.speedDefault - v) < 0.001 : v === 1
    }

    Flickable {
        anchors { fill: parent; topMargin: Theme.s10; bottomMargin: page.gutter }
        contentWidth: width
        contentHeight: col.height + page.gutter
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            x: page.gutter
            width: parent.width - page.gutter * 2
            spacing: Theme.s7

            Text {
                text: "Settings"
                color: Theme.textPrimary
                font.family: Theme.displayFont
                font.pixelSize: 34
                font.weight: Font.Bold
                font.letterSpacing: -0.4
            }

            // ── Interface ──────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 0
                Text {
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: "Interface"
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.trackingWide
                }
                Rectangle {
                    width: parent.width
                    height: 128
                    radius: Theme.rLg
                    color: Theme.card
                    border.color: Theme.borderSubtle
                    border.width: 1

                    // Compact sidebar
                    Item {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 64
                        Text {
                            id: if1Lbl
                            anchors { left: parent.left; right: parent.right
                                      top: parent.top; margins: Theme.s5; rightMargin: 210 }
                            text: "Compact sidebar"
                            color: Theme.textPrimary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsBody
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right
                                      top: if1Lbl.bottom; topMargin: 2
                                      leftMargin: Theme.s5; rightMargin: 210 }
                            text: "Collapse navigation to icons only."
                            color: Theme.textMuted
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsSmall
                        }
                        // A hand-built pill: the Controls Switch rendered
                        // nothing at all in this file, so the row looked
                        // readable but did nothing.
                        Rectangle {
                            id: railSw
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter
                                      rightMargin: Theme.s5 }
                            width: 44; height: 24; radius: 12
                            readonly property bool on: page.app ? page.app.railCollapsed : false
                            color: on ? Theme.accent : Theme.surfaceRaised
                            border.color: on ? Theme.accent : Theme.borderStrong
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: railSw.on ? parent.width - width - 3 : 3
                                color: Theme.textPrimary
                                Behavior on x {
                                    NumberAnimation { duration: Theme.dFast
                                                      easing.type: Theme.easeOutCubic }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (page.app) page.app.railCollapsed = !railSw.on
                            }
                        }
                    }
                    // Reduce motion
                    Item {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 64
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 1
                            color: Theme.borderSubtle
                        }
                        Text {
                            id: if2Lbl
                            anchors { left: parent.left; right: parent.right
                                      top: parent.top; margins: Theme.s5; rightMargin: 210 }
                            text: "Reduce motion"
                            color: Theme.textPrimary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsBody
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right
                                      top: if2Lbl.bottom; topMargin: 2
                                      leftMargin: Theme.s5; rightMargin: 210 }
                            text: "Turn off the hero drift, page slides and fades."
                            color: Theme.textMuted
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsSmall
                        }
                        Rectangle {
                            id: motionSw
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter
                                      rightMargin: Theme.s5 }
                            width: 44; height: 24; radius: 12
                            readonly property bool on: page.app ? page.app.motionReduced : false
                            color: on ? Theme.accent : Theme.surfaceRaised
                            border.color: on ? Theme.accent : Theme.borderStrong
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: motionSw.on ? parent.width - width - 3 : 3
                                color: Theme.textPrimary
                                Behavior on x {
                                    NumberAnimation { duration: Theme.dFast
                                                      easing.type: Theme.easeOutCubic }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (page.app) page.app.motionReduced = !motionSw.on
                            }
                        }
                    }
                }
            }

            // ── Playback ───────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 0
                Text {
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: "Playback"
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.trackingWide
                }
                Rectangle {
                    width: parent.width
                    height: 128
                    radius: Theme.rLg
                    color: Theme.card
                    border.color: Theme.borderSubtle
                    border.width: 1

                    // Default volume
                    Item {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 64
                        Text {
                            id: pb1Lbl
                            anchors { left: parent.left; right: parent.right
                                      top: parent.top; margins: Theme.s5; rightMargin: 260 }
                            text: "Default volume"
                            color: Theme.textPrimary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsBody
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right
                                      top: pb1Lbl.bottom; topMargin: 2
                                      leftMargin: Theme.s5; rightMargin: 260 }
                            text: "Applied to the open episode and every one after."
                            color: Theme.textMuted
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsSmall
                        }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter
                                      rightMargin: Theme.s5 }
                            spacing: Theme.s1
                            Repeater {
                                model: [0.25, 0.5, 0.75, 1]
                                delegate: Rectangle {
                                    id: volChip
                                    required property var modelData
                                    property bool picked: page.app
                                            && Math.abs(page.app.volumeDefault - modelData) < 0.001
                                    width: volTxt.implicitWidth + Theme.s5
                                    height: 30
                                    radius: Theme.rPill
                                    color: picked ? Theme.accentSoft : Theme.surfaceRaised
                                    border.color: picked ? Theme.accent : Theme.borderDefault
                                    border.width: 1
                                    Text {
                                        id: volTxt
                                        anchors.centerIn: parent
                                        text: Math.round(modelData * 100) + "%"
                                        color: volChip.picked ? Theme.textPrimary : Theme.textSecondary
                                        font.family: Theme.bodyFont
                                        font.pixelSize: Theme.tsSmall
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (page.app) page.app.volumeDefault = modelData
                                    }
                                }
                            }
                        }
                    }
                    // Default speed
                    Item {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 64
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 1
                            color: Theme.borderSubtle
                        }
                        Text {
                            id: pb2Lbl
                            anchors { left: parent.left; right: parent.right
                                      top: parent.top; margins: Theme.s5; rightMargin: 300 }
                            text: "Default speed"
                            color: Theme.textPrimary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsBody
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right
                                      top: pb2Lbl.bottom; topMargin: 2
                                      leftMargin: Theme.s5; rightMargin: 300 }
                            text: "Applied to the open episode and every one after."
                            color: Theme.textMuted
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsSmall
                        }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter
                                      rightMargin: Theme.s4 }
                            spacing: Theme.s1
                            Repeater {
                                model: page.speedOpts
                                delegate: Rectangle {
                                    id: spdChip
                                    required property var modelData
                                    property bool picked: page.speedPicked(modelData)
                                    width: spdTxt.implicitWidth + Theme.s5
                                    height: 30
                                    radius: Theme.rPill
                                    color: picked ? Theme.accentSoft : Theme.surfaceRaised
                                    border.color: picked ? Theme.accent : Theme.borderDefault
                                    border.width: 1
                                    Text {
                                        id: spdTxt
                                        anchors.centerIn: parent
                                        text: modelData === 1 ? "Normal" : modelData + "x"
                                        color: spdChip.picked ? Theme.textPrimary : Theme.textSecondary
                                        font.family: Theme.bodyFont
                                        font.pixelSize: Theme.tsSmall
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (page.app) page.app.speedDefault = modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Storage ───────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 0
                Text {
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: "Storage"
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.trackingWide
                }
                Rectangle {
                    width: parent.width
                    height: 64
                    radius: Theme.rLg
                    color: Theme.card
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Text {
                        id: st1Lbl
                        anchors { left: parent.left; right: parent.right
                                  top: parent.top; margins: Theme.s5 }
                        text: "Kept on this computer"
                        color: Theme.textPrimary
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsBody
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right
                                  top: st1Lbl.bottom; topMargin: 2; leftMargin: Theme.s5 }
                        text: "Preferences are stored locally, not in your account."
                        color: Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsSmall
                    }
                }
            }
        }
    }
}
