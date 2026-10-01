import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// PartyPanel — the watch-party surface: room code, roster, and the ready gate.
// The two states are Loaders, not hidden items: a ColumnLayout sizes invisible children too, so
// hiding the in-room sections pushed the join form ~90px down.
Rectangle {
    id: panel

    required property var party
    required property string episodeId
    property bool open: false

    signal closeRequested()
    signal signInRequested()

    width: open ? 336 : 0
    height: parent ? parent.height : 0
    color: Theme.glassPanel
    border.color: Theme.glassEdge
    border.width: 1
    clip: true

    Behavior on width {
        NumberAnimation { duration: Theme.dSlow; easing.type: Theme.easeOutCubic }
    }

    function driftOf(peer) {
        // The server publishes each member's offset; deriving it locally would measure our own staleness.
        if (peer.driftMs !== undefined)
            return peer.driftMs / 1000
        return (peer.currentTime || 0) - syncplay.canonicalTime
    }

    function badgeFor(peer) {
        if (peer.stalling) return { label: "Stalled", tone: Theme.danger }
        // `ready` is the server's own verdict; readyState can lag a buffering update.
        if (peer.ready) return { label: "Ready", tone: Theme.success }
        if (peer.ignoreWait) return { label: "Not waiting", tone: Theme.textMuted }
        if (peer.readyState === "buffering") return { label: "Buffering", tone: Theme.warning }
        return { label: "Waiting", tone: Theme.textMuted }
    }

    function secondsOf(value) {
        const sign = value >= 0 ? "+" : "\u2212"
        return sign + Math.abs(value).toFixed(2) + "s"
    }

    function initialOf(name) {
        const trimmed = String(name || "").trim()
        return trimmed.length ? trimmed.charAt(0).toUpperCase() : "?"
    }

    // ── Header, present in both states ────────────────────────────────────
    RowLayout {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.s6 }
        spacing: Theme.s3

        Column {
            spacing: 2
            Layout.fillWidth: true
            Text {
                text: "Watch party"
                color: Theme.textPrimary
                font.family: Theme.displayFont
                font.pixelSize: Theme.tsSection
                font.weight: Theme.wtSemiBold
            }
            Text {
                text: panel.party.inRoom
                      ? (panel.party.connected ? "Live · " + panel.party.roomCode : "Reconnecting…")
                      : (panel.party.connected ? "Connected" : "Not connected")
                color: panel.party.inRoom && panel.party.connected ? Theme.success : Theme.textMuted
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsSmall
                font.letterSpacing: Theme.trackingWide
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: 30; height: 30
            radius: Theme.rPill
            color: closeArea.containsMouse ? Theme.hoverBg : "transparent"
            border.color: closeArea.containsMouse ? Theme.borderDefault : "transparent"
            Text {
                anchors.centerIn: parent
                text: "\u2715"
                color: Theme.textSecondary
                font.pixelSize: 14
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.closeRequested()
            }
        }
    }

    // ── In room: gate, code, roster, leave ────────────────────────────────
    Loader {
        id: roomSection
        anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.s6; topMargin: Theme.s4 }
        active: panel.party.inRoom
        sourceComponent: roomContent
    }

    Component {
        id: roomContent
        ColumnLayout {
            spacing: Theme.s4

            // Selectable because QML has no clipboard API.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 66
                radius: Theme.rMd
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                Column {
                    anchors { fill: parent; leftMargin: Theme.s4; rightMargin: Theme.s4; verticalCenter: undefined }
                    anchors.top: parent.top
                    anchors.topMargin: Theme.s3
                    spacing: 2
                    Text {
                        text: "ROOM CODE"
                        color: Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: 10
                        font.letterSpacing: Theme.trackingWide
                    }
                    TextInput {
                        width: parent.width
                        text: panel.party.roomCode
                        readOnly: true
                        selectByMouse: true
                        persistentSelection: true
                        color: Theme.textPrimary
                        font.family: Theme.displayFont
                        font.pixelSize: 26
                        font.weight: Theme.tBold
                        font.letterSpacing: 6
                    }
                }
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom; margins: Theme.s3 }
                    width: copyLabel.implicitWidth + 18
                    height: 24
                    radius: Theme.rPill
                    color: copyMa.containsMouse ? Theme.hoverBg : "transparent"
                    border.color: copyMa.containsMouse ? Theme.borderDefault : Theme.borderSubtle
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    Text {
                        id: copyLabel
                        anchors.centerIn: parent
                        text: "COPY"
                        color: Theme.textSecondary
                        font.family: Theme.bodyFont
                        font.pixelSize: 10
                        font.letterSpacing: Theme.trackingWide
                    }
                    MouseArea {
                        id: copyMa
                        anchors.fill: parent
                        anchors.margins: -5
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.party.copyRoomCode()
                    }
                }
            }

            // Ready gate
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.s2

                Text {
                    text: {
                        if (panel.party.gateOpen) {
                            if (panel.party.headline.length) return panel.party.headline
                            if (panel.party.waitingOn.length)
                                return "Waiting on " + panel.party.waitingOn
                            if (panel.party.readyLine.length) return panel.party.readyLine
                            return "Waiting for the room to buffer"
                        }
                        // Outside the gate the room still has a state, and it beats the share prompt.
                        if (panel.party.headline.length) return panel.party.headline
                        return panel.party.statusText
                    }
                    visible: text.length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsMeta
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 4
                    radius: Theme.rPill
                    visible: panel.party.gateOpen
                    color: Theme.input
                    Rectangle {
                        width: parent.width * (panel.party.totalPeers > 0
                                ? Math.min(1, panel.party.readyCount / panel.party.totalPeers) : 0)
                        height: parent.height
                        radius: parent.radius
                        color: Theme.warning
                        Behavior on width { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
                    }
                }

                // A gate that names nobody looks like the app stalling.
                Text {
                    Layout.fillWidth: true
                    visible: panel.party.gateOpen && panel.party.waitingOn.length > 0
                    text: panel.party.waitingOn
                    wrapMode: Text.WordWrap
                    color: Theme.warning
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                }

                // The one control a viewer on a bad link wants, reachable while the room is held up.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s2
                    Text {
                        text: panel.party.ignoringWait ? "Waiting for the room" : "Don't wait for me"
                        color: panel.party.ignoringWait ? Theme.textMuted : Theme.textSecondary
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsSmall
                        font.weight: Theme.wtMedium
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 44; height: 22
                        radius: Theme.rPill
                        color: panel.party.ignoringWait ? Theme.accent : Theme.input
                        border.color: panel.party.ignoringWait ? Theme.accent : Theme.borderSubtle
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.dFast } }
                        Rectangle {
                            width: 16; height: 16
                            radius: Theme.rPill
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.party.ignoringWait ? parent.width - width - 3 : 3
                            color: Theme.textPrimary
                            Behavior on x { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.party.setIgnoreWait(!panel.party.ignoringWait)
                        }
                    }
                }
            }

            // A correction the viewer cannot see is a bug in their eyes, in the decision layer's words.
            Rectangle {
                Layout.fillWidth: true
                visible: panel.party.correctionLine.length > 0
                height: panel.party.correctionLine.length > 0
                        ? correctionLabel.implicitHeight + 16 : 0
                radius: Theme.rSm
                color: Theme.warningSoft
                border.color: Theme.warning
                border.width: 1
                clip: true
                Behavior on height { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
                Text {
                    id: correctionLabel
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.s3; rightMargin: Theme.s3 }
                    text: panel.party.correctionLine
                    wrapMode: Text.WordWrap
                    color: Theme.textPrimary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                }
            }

            // A late display pipeline is the viewer's to fix; every other sync control is the room's.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s2
                visible: panel.party.inRoom
                Text {
                    text: "Display offset"
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: [-200, -100, 0, 100, 200]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 22
                        radius: Theme.rPill
                        color: Math.abs(panel.party.extraTimeOffsetMs - modelData) < 1
                                 ? Theme.accentSoft : "transparent"
                        border.color: Math.abs(panel.party.extraTimeOffsetMs - modelData) < 1
                                      ? Theme.accent : Theme.borderSubtle
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.dFast } }
                        Text {
                            anchors.centerIn: parent
                            text: (modelData > 0 ? "+" : "") + modelData
                            color: Theme.textSecondary
                            font.family: Theme.bodyFont
                            font.pixelSize: 10
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.party.applyExtraTimeOffset(modelData)
                        }
                    }
                }
            }

            // Diagnostic, quiet while the estimate is trustworthy: it explains an uneven start.
            Text {
                Layout.fillWidth: true
                visible: panel.party.clockConfidence !== "trusted" && panel.party.inRoom
                text: panel.party.clockConfidence === "unknown"
                      ? "Measuring the server clock\u2026 sync will settle in a moment"
                      : "Clock estimate is rough (" + panel.party.pingMs + " ms round trip)"
                wrapMode: Text.WordWrap
                color: Theme.textMuted
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsSmall
            }

            ListView {
                id: roster
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: panel.party.peers
                spacing: Theme.s2
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: rowItem
                    required property var modelData
                    width: roster.width
                    height: 52
                    radius: Theme.rMd
                    color: rowHover.hovered ? Theme.hoverBg : "transparent"

                    readonly property var badge: panel.badgeFor(modelData)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.s3
                        anchors.rightMargin: Theme.s3
                        spacing: Theme.s3

                        Rectangle {
                            width: 32; height: 32
                            radius: Theme.rPill
                            color: rowItem.badge.tone
                            opacity: 0.18
                            border.color: rowItem.badge.tone
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: panel.initialOf(modelData.displayName)
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.weight: Theme.wtSemiBold
                            }
                        }

                        Column {
                            spacing: 1
                            Layout.fillWidth: true
                            Text {
                                text: (modelData.displayName || "Guest")
                                      + (modelData.userId === syncplay.hostUserId ? "  · host" : "")
                                color: Theme.textPrimary
                                font.family: Theme.bodyFont
                                font.pixelSize: Theme.tsBody
                                font.weight: Theme.wtMedium
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: {
                                    const drift = panel.driftOf(modelData)
                                    const latency = modelData.pingMs ? "  ·  " + modelData.pingMs + " ms" : ""
                                    return rowItem.badge.label + "  ·  " + panel.secondsOf(drift) + latency
                                }
                                color: rowItem.badge.tone
                                font.family: Theme.bodyFont
                                font.pixelSize: Theme.tsSmall
                            }
                        }

                        // The only per-peer action the protocol offers, and only the host may use it.
                        Text {
                            visible: syncplay.isHost && modelData.userId !== syncplay.hostUserId
                                     && rowHover.hovered
                            text: "MAKE HOST"
                            color: Theme.textSecondary
                            font.pixelSize: 10
                            font.letterSpacing: Theme.trackingWide
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.party.transferHost(modelData.userId)
                            }
                        }
                    }

                    HoverHandler { id: rowHover }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            // The room's own story, newest first.
            Column {
                id: activityFeed
                Layout.fillWidth: true
                spacing: 2
                visible: panel.party.activity.length > 0

                Text {
                    text: "IN THIS ROOM"
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: 10
                    font.letterSpacing: Theme.trackingWide
                }
                Repeater {
                    // The client keeps newest last; six deep, newest first, reads as a log.
                    model: {
                        const all = panel.party.activity || []
                        const out = []
                        for (let i = all.length - 1; i >= 0 && out.length < 6; --i)
                            out.push(all[i])
                        return out
                    }
                    delegate: Text {
                        required property var modelData
                        required property int index
                        width: activityFeed.width
                        text: modelData.text
                        elide: Text.ElideRight
                        // The newest line carries the most weight.
                        color: index === 0 ? Theme.textSecondary : Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsSmall
                    }
                }
            }

            SecondaryButton {
                Layout.fillWidth: true
                text: "Leave room"
                onClicked: panel.party.leaveRoom()
            }
        }
    }

    // ── Not in a room: join or create ─────────────────────────────────────
    Loader {
        id: joinSection
        anchors { top: head.bottom; left: parent.left; right: parent.right; margins: Theme.s6; topMargin: Theme.s4 }
        active: !panel.party.inRoom
        sourceComponent: joinContent
    }

    Component {
        id: joinContent
        ColumnLayout {
            width: joinSection.width - Theme.s12
            spacing: Theme.s4

            Text {
                text: "Watch this episode in sync with friends. Share the code, or enter theirs."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                color: Theme.textSecondary
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsMeta
                lineHeight: 1.35
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: Theme.rMd
                color: Theme.input
                border.color: codeField.activeFocus ? Theme.borderStrong : Theme.borderSubtle
                Behavior on border.color { ColorAnimation { duration: Theme.dFast } }

                TextInput {
                    id: codeField
                    anchors { fill: parent; leftMargin: Theme.s4; rightMargin: Theme.s4 }
                    verticalAlignment: TextInput.AlignVCenter
                    focus: true
                    color: Theme.textPrimary
                    selectedTextColor: Theme.accent
                    selectionColor: Theme.accentSoft
                    font.family: Theme.displayFont
                    font.pixelSize: 18
                    font.letterSpacing: Theme.trackingWide
                    inputMethodHints: Qt.ImhUppercaseOnly
                    // Five characters; longer input is truncated rather than silently rejected.
                    onTextChanged: if (text.length > 5) text = text.substring(0, 5)
                    onAccepted: panel.party.joinRoom(text)

                    Text {
                        anchors.fill: parent
                        visible: !parent.text.length && !parent.activeFocus
                        verticalAlignment: Text.AlignVCenter
                        text: "ROOM CODE"
                        color: Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsMeta
                        font.letterSpacing: Theme.trackingWide
                    }
                }
            }

            PrimaryButton {
                Layout.fillWidth: true
                text: "Join room"
                enabled: codeField.text.trim().length === 5
                onClicked: panel.party.joinRoom(codeField.text)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s3
                Item { Layout.fillWidth: true; height: 1 }
                Text {
                    text: "or"
                    color: Theme.textMuted
                    font.pixelSize: Theme.tsSmall
                }
                Item { Layout.fillWidth: true; height: 1 }
            }

            SecondaryButton {
                Layout.fillWidth: true
                text: panel.episodeId.length ? "Start a party here" : "Open an episode to host"
                // Not gated on auth: the party's own connect step decides who may host, and asks.
                enabled: panel.episodeId.length > 0
                onClicked: panel.party.createRoom(panel.episodeId)
            }

            Row {
                Layout.fillWidth: true
                visible: !authManager.authenticated
                spacing: Theme.s1
                Text {
                    text: "Sign in to host or join a watch party."
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                }
                Text {
                    text: "Sign in"
                    color: signInLink.containsMouse ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                    font.weight: Theme.wtMedium
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    MouseArea {
                        id: signInLink
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.signInRequested()
                    }
                }
            }
        }
    }
}
