/*
    FurryOS SDDM 主题 —— 可复用按钮组件（含动效）
    ------------------------------------------------------------
    动效硬性要求（对应 brand-tokens.md 第 4 节）：
      · 悬停：120–160ms 可见动画，颜色 + 透明度 + 缩放变化 → 取 140ms
      · 按下：180–240ms 可见动画，缩放 0.96 + 颜色加深   → 取 200ms
      · 悬停与按下合计落在 200–300ms 区间，轻快、有回应，
        严禁夸张弹跳（一律 OutQuad / InOutQuad，禁用 Elastic/Bounce）
      · 密码错误抖动：320ms / ±6px / 2 次（由 shake() 触发）
*/
import QtQuick 2.15
import QtQml 2.15

Rectangle {
    id: root

    /* ---- 对外接口 ---- */
    property alias text: label.text
    property alias textColor: label.color
    property alias fontWeight: label.font.weight
    property real fontSize: Theme.bodyFontPx
    property color baseColor: Theme.furryosBlue
    property color hoverColor: Theme.furryosAccentHover   // 比主色亮一档
    property color pressColor: Theme.furryosBlueDark     // 加深
    property bool pawDecoration: true                    // 按钮内爪印标记
    property bool buttonEnabled: true

    signal clicked

    implicitWidth: 280
    implicitHeight: Theme.buttonHeight
    radius: Theme.radiusControl
    border.color: Theme.furryosBlueLight

    /* 悬停 = 颜色变亮 + 缩放 1.03 + 边框浮现；
       按下 = 颜色加深 + 缩放 0.96。
       颜色与缩放分别以 OutQuad 过渡，时长分别为 140ms / 200ms；
       从按下抬起回到悬停只用 hoverDuration，因此连续点按时
       手感始终维持在 200–300ms 的轻快区间，无回弹。 */
    state: !buttonEnabled ? "disabled"
         : mouseArea.pressed ? "pressed"
         : mouseArea.containsMouse ? "hover" : "normal"

    Behavior on scale {
        NumberAnimation {
            duration: root.state === "pressed" ? Theme.pressDuration : Theme.hoverDuration
            easing.type: Easing.OutQuad
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: root.state === "pressed" ? Theme.pressDuration : Theme.hoverDuration
            easing.type: Easing.OutQuad
        }
    }

    Behavior on border.width {
        NumberAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
    }

    states: [
        State {
            name: "normal"
            PropertyChanges { target: root; color: root.baseColor; scale: 1.0 }
            PropertyChanges { target: root; border.width: 0 }
        },
        State {
            name: "hover"
            PropertyChanges { target: root; color: root.hoverColor; scale: Theme.hoverScale }
            PropertyChanges { target: root; border.width: 2 }
        },
        State {
            name: "pressed"
            PropertyChanges { target: root; color: root.pressColor; scale: Theme.pressScale }
            PropertyChanges { target: root; border.width: 2 }
        },
        State {
            name: "disabled"
            PropertyChanges { target: root; color: Theme.furryosDisabledBg; scale: 1.0 }
            PropertyChanges { target: root; border.width: 1 }
        }
    ]

    /* ---- 文本 ----
       禁用态改用 furryos-text-muted (#4A637C) on furryos-blue-pale (#EAF2FF)
       = 4.98:1。早先是「浅蓝底 + 白色文字」= 1.35:1，文字等于看不见。 */
    Text {
        id: label
        anchors.centerIn: parent
        text: ""
        color: root.buttonEnabled ? Theme.furryosWhite : Theme.furryosDisabledText
        font.pixelSize: root.fontSize
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    /* ---- 按钮内爪印标记（品牌元素，小尺寸、位于文字左侧，不干扰阅读） ----
       必须用白色版：按钮底是 furryos-blue，蓝色爪印会与之同色不可见。 */
    Image {
        id: pawIcon
        visible: root.pawDecoration
        anchors.right: label.left
        anchors.rightMargin: Math.round(10 * (root.height / Theme.buttonHeight))
        anchors.verticalCenter: label.verticalCenter
        width: Math.round(18 * (root.height / Theme.buttonHeight))
        height: Math.round(18 * (root.height / Theme.buttonHeight))
        source: "../assets/paw-white.svg"
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        opacity: root.buttonEnabled ? 0.9 : 0.45
    }

    /* ---- 交互 ---- */
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.buttonEnabled
        onClicked: root.clicked()
    }

    /* 抖动位移：走 Translate 变换而不是直接动 x。
       直接给 x 做动画有两个问题：(1) x 由锚点/布局驱动时，动画会覆盖绑定，
       抖完之后按钮停在原处（布局位置）之外；(2) 早先用
       `property real restX: x` 记基准位，而 x 一动 restX 就跟着漂，
       四段的 to 值都在追当前 x，抖动会逐段累积、最后回不到 0。 */
    transform: Translate { id: shakeTranslate; x: 0 }

    function shake() {
        shakeAnim.restart()
    }

    /* ---- 密码错误抖动：320ms，±6px，2 次 ----
       分段 40 + 120 + 120 + 40 = 320ms（1/8 + 3/8 + 3/8 + 1/8），
       两次完整往复（-6 → +6 → -6 → 0），合计精确 320ms。 */
    SequentialAnimation {
        id: shakeAnim
        running: false
        NumberAnimation { target: shakeTranslate; property: "x"
            to: -Theme.shakeAmplitude
            duration: Theme.shakeDuration / 8; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"
            to: Theme.shakeAmplitude
            duration: Theme.shakeDuration * 3 / 8; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"
            to: -Theme.shakeAmplitude
            duration: Theme.shakeDuration * 3 / 8; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"
            to: 0
            duration: Theme.shakeDuration / 8; easing.type: Easing.InOutQuad }
    }
}
