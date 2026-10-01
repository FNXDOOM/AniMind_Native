pragma Singleton
import QtQuick

// Design tokens for the whole application. Everything here is static: values
// that depend on the window size belong in main.qml, which can call the pure
// helpers below with its own width.
QtObject {
    // ── Surfaces ──────────────────────────────────────────────────────────
    readonly property color bg:            "#07090C"
    readonly property color bgSecondary:   "#0B0F14"
    readonly property color card:          "#10151C"
    readonly property color surfaceRaised:  "#151B23"
    readonly property color sidebar:       "#080B0F"
    readonly property color input:         "#11161D"
    // Sits between card and surfaceRaised so a hovered row reads as one
    // step up, never as a jump.
    readonly property color hoverBg:       "#0F141A"

    // ── Borders ───────────────────────────────────────────────────────────
    // Three steps only, so a hairline never has to be invented per screen.
    readonly property color borderSubtle:  Qt.rgba(1, 1, 1, 0.06)
    readonly property color borderDefault: Qt.rgba(1, 1, 1, 0.08)
    readonly property color borderStrong:  Qt.rgba(1, 1, 1, 0.12)

    // ── Text ──────────────────────────────────────────────────────────────
    readonly property color textPrimary:   "#FFFFFF"
    readonly property color textSecondary: "#A8AFB9"
    readonly property color textMuted:     "#69717C"

    // ── Accent ───────────────────────────────────────────────────────────
    // Deliberately scarce: progress, the active nav marker, selected states,
    // notification badges. If a screen has more red than this, it is wrong.
    readonly property color accent:        "#E50914"
    readonly property color accentHover:   "#F6121D"
    readonly property color accentPressed: "#B20710"
    readonly property color accentSoft:    Qt.rgba(0.898, 0.035, 0.078, 0.16)

    readonly property color danger:        "#E50914"
    readonly property color success:       "#2ECC71"
    // In-progress states need their own step: accent and danger are the same red, so a
    // buffering peer would otherwise be indistinguishable from a stalled one.
    readonly property color warning:       "#F5A524"
    readonly property color warningSoft:   Qt.rgba(0.961, 0.647, 0.141, 0.16)

    // ── Player chrome ────────────────────────────────────────────────────
    // The chrome sits on top of video, so its steps are translucent whites over black
    // rather than the surface ramp the rest of the app uses. Each value is exactly what
    // the chrome hardcoded before these names existed.
    readonly property color chromeText:    "#FFFFFF"
    readonly property color chromeTextDim: "#BBBBBB"
    readonly property color chromeRest:    "#22FFFFFF"
    readonly property color chromeHover:   "#33FFFFFF"
    readonly property color chromeEdge:    "#55FFFFFF"
    readonly property color chromeButton:  "#14000000"
    readonly property color chromeRadio:   "#555555"

    // Translucent scrim behind dialogs and the player chrome.
    readonly property color veil:          Qt.rgba(0, 0, 0, 0.72)
    readonly property color veilLight:     Qt.rgba(0, 0, 0, 0.45)
    // Section 25 glass surfaces. Only the two floating layers qualify —
    // the bottom tab bar and dialogs. Cards stay opaque on purpose.
    readonly property color glassSurface: Qt.rgba(0.027, 0.035, 0.047, 0.86)
    readonly property color glassPanel:   Qt.rgba(0.031, 0.043, 0.055, 0.94)
    readonly property color glassEdge:    Qt.rgba(1, 1, 1, 0.10)

    // ── Type ──────────────────────────────────────────────────────────────
    readonly property string displayFont: "Segoe UI Variable Display, Segoe UI"
    readonly property string bodyFont:    "Segoe UI Variable Text, Segoe UI"
    readonly property string iconFont:    "Segoe MDL2 Assets"

    // Hierarchy from the brief: hero 32-52, page 28-36, section 20-26,
    // card 13-16, meta 11-13, description 13-15.
    readonly property int tsHero:      44
    readonly property int tsPage:      32
    readonly property int tsSection:   22
    readonly property int tsCardTitle: 14
    readonly property int tsBody:      14
    readonly property int tsMeta:      12
    readonly property int tsSmall:     11

    readonly property int wtRegular:  Font.Normal
    readonly property int wtMedium:   Font.Medium
    readonly property int wtSemiBold: Font.DemiBold
    readonly property int tBold:      Font.Bold

    readonly property real trackingEyebrow: 0.6
    readonly property real trackingWide:    0.4

    // ── Spacing ───────────────────────────────────────────────────────────
    readonly property int s0: 0
    readonly property int s1: 4
    readonly property int s2: 8
    readonly property int s3: 12
    readonly property int s4: 16
    readonly property int s5: 20
    readonly property int s6: 24
    readonly property int s7: 28
    readonly property int s8: 32
    readonly property int s10: 40
    readonly property int s12: 48

    // ── Radii ─────────────────────────────────────────────────────────────
    readonly property int rSm:   6
    readonly property int rMd:   8
    readonly property int rLg:   12
    readonly property int rXl:   16
    readonly property int rPill: 999

    // ── Motion ────────────────────────────────────────────────────────────
    // 180-350ms for UI; the hero's ambient zoom is deliberately far slower.
    readonly property int dFast:   180
    readonly property int dBase:   240
    readonly property int dSlow:   320
    readonly property int dHero:   600
    readonly property int dAmbient: 9000

    // Plain ints rather than an inline `property enum`: an enum block inside a
    // singleton failed to compile and took every `import "."` in the directory
    // down with it.
    readonly property int easeOutCubic:   Easing.OutCubic
    readonly property int easeInOutCubic: Easing.InOutCubic
    readonly property int easeOutQuint:   Easing.OutQuint
    readonly property int easeOutBack:    Easing.OutBack


    // ── Geometry ──────────────────────────────────────────────────────────
    readonly property int railExpandedW:  176
    readonly property int railCollapsedW: 68
    readonly property int topBarH:        64
    readonly property int tabbarH:        64

    readonly property real cardAspect: 2 / 3
    readonly property real episodeAspect: 16 / 9

    // ── Shadows ───────────────────────────────────────────────────────────
    readonly property real elevationLow:    0.10
    readonly property real elevationMedium: 0.22
    readonly property real elevationHigh:   0.38

    // ── Pure helpers ──────────────────────────────────────────────────────
    // clamp() equivalent: linear between two viewport anchors, then bounded.
    // Takes the width as an argument because a singleton has no size of its
    // own; callers pass the window or the content column as appropriate.
    function fluid(minV, maxV, fromW, toW, w) {
        if (w <= fromW) return minV
        if (w >= toW)   return maxV
        return minV + (maxV - minV) * (w - fromW) / (toW - fromW)
    }

    function gutterFor(w) {
        return w < 640 ? s4 : (w < 1024 ? s6 : s8)
    }

    function heroSizeFor(w) {
        return Math.round(fluid(32, 52, 900, 1900, w))
    }

    function cardWidthFor(w, columns, gap) {
        return Math.max(96, Math.floor((w - gap * (columns - 1)) / columns))
    }
}
