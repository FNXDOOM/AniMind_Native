import QtQuick
import QtQuick.Layouts
import ".."

// AuthSheet — email/password sign-in and account creation against the Go backend.
//
// The browser handoff stays offered below the form: it is the only route to the Google
// provider. This sheet covers the account someone already made on the site, which until
// now had no path at all from the desktop app.
Rectangle {
    id: sheet

    property bool open: false
    property bool signup: false
    // ANIMIND_UI_AUTH_PROBE=autofill drives this form: a wrong password first, so the
    // failure path renders, then a real signup, so the success signal is observable. Without
    // it the submit wiring and the handle field behind its Loader are never executed.
    property bool probeFill: false

    signal dismissed()

    Timer {
        interval: 700
        running: sheet.probeFill
        onTriggered: {
            emailField.text = "probe+" + Date.now() + "@example.test"
            passwordField.text = "wrong-on-purpose"
            sheet.submit()
        }
    }

    Timer {
        interval: 2600
        running: sheet.probeFill
        onTriggered: {
            // Read the failure before submit() clears it: beginPasswordFlow resets
            // lastError, so logging afterwards would always show an empty string.
            console.log("AUTHPROBE priorError=\"" + authManager.lastError
                        + "\" signingIn=" + authManager.signingIn
                        + " authenticated=" + authManager.authenticated)
            passwordField.text = "Verify12345!"
            if (handleLoader.item)
                handleLoader.item.text = "probehandle"
            sheet.submit()
        }
    }

    anchors.fill: parent
    visible: opacity > 0.0
    color: Theme.veil
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

    function submit() {
        const mail = emailField.text.trim()
        const pass = passwordField.text
        if (mail.length === 0 || pass.length === 0)
            return
        if (sheet.signup)
            authManager.signUpWithPassword(mail, pass, handleLoader.item ? handleLoader.item.text.trim() : "")
        else
            authManager.signInWithPassword(mail, pass)
    }

    function focusNext() {
        if (sheet.signup && handleLoader.item)
            handleLoader.item.fieldInput.forceActiveFocus()
        else
            passwordField.fieldInput.forceActiveFocus()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: sheet.dismissed()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(388, parent.width - Theme.s8)
        height: content.implicitHeight + Theme.s12
        radius: Theme.rLg
        color: Theme.glassPanel
        border.color: Theme.glassEdge
        border.width: 1
        scale: sheet.open ? 1.0 : 0.96
        Behavior on scale { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

        Keys.onEscapePressed: sheet.dismissed()

        ColumnLayout {
            id: content
            x: Theme.s6
            y: Theme.s6
            width: parent.width - Theme.s12
            spacing: 0

            Column {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.s4
                spacing: 4
                Text {
                    text: sheet.signup ? "Create your account" : "Sign in"
                    color: Theme.textPrimary
                    font.family: Theme.displayFont
                    font.pixelSize: Theme.tsSection
                    font.weight: Theme.wtSemiBold
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: sheet.signup
                         ? "Your list, progress and watch parties follow the account."
                         : "Pick up your list, history and watch parties on this machine."
                    color: Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsMeta
                    lineHeight: 1.3
                }
            }

            FormField {
                id: emailField
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.s4
                label: "Email"
                placeholder: "you@example.com"
                onAccepted: sheet.focusNext()
            }

            // A Loader, not a hidden field: a ColumnLayout applies spacing to invisible
            // children too, so a hidden handle left a gap in the middle of the form.
            Loader {
                id: handleLoader
                Layout.fillWidth: true
                Layout.bottomMargin: sheet.signup ? Theme.s4 : 0
                active: sheet.signup
                sourceComponent: handleComponent
            }

            Component {
                id: handleComponent
                FormField {
                    width: parent ? parent.width : 260
                    label: "Handle"
                    placeholder: "how the room sees you"
                    onAccepted: passwordField.fieldInput.forceActiveFocus()
                }
            }

            FormField {
                id: passwordField
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.s4
                label: "Password"
                placeholder: "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022"
                echoMode: TextInput.Password
                onAccepted: sheet.submit()
            }

            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.s4
                wrapMode: Text.WordWrap
                visible: text.length > 0
                // beginPasswordFlow clears lastError before each attempt, so anything here is
                // fresh. Gating on authenticated instead hid every failure from a machine
                // that had a restored session.
                text: authManager.signingIn ? "" : authManager.lastError
                color: Theme.danger
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsSmall
            }

            PrimaryButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.bottomMargin: Theme.s4
                text: authManager.signingIn ? "Working\u2026"
                                            : (sheet.signup ? "Create account" : "Sign in")
                enabled: !authManager.signingIn
                         && emailField.text.trim().length > 0
                         && passwordField.text.length > 0
                onClicked: sheet.submit()
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.s3
                spacing: Theme.s2

                Text {
                    text: sheet.signup ? "Already watching with us?" : "New here?"
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                }
                Text {
                    text: sheet.signup ? "Sign in" : "Create an account"
                    color: linkHover.containsMouse ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                    font.weight: Theme.wtMedium
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    MouseArea {
                        id: linkHover
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.signup = !sheet.signup
                    }
                }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.s4
                spacing: Theme.s3
                visible: !authManager.signingIn
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
                Layout.preferredHeight: 40
                text: "Continue in a browser"
                onClicked: {
                    // The loopback handoff owns its own window; the sheet would only be in
                    // the way while the browser is up.
                    sheet.dismissed()
                    authManager.signInWithBrowserBridge()
                }
            }
        }
    }
}
