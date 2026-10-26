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
    radius: Theme.cornerRadius
    border.color: Theme.furryosBlueLight

    /* 抖动基准位：记录布局给定的原始 x，避免动画中重复求值漂移 */
    property real restX: x

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
            PropertyChanges { target: root; color: Theme.furryosBlueLight; scale: 1.0 }
            PropertyChanges { target: root; border.width: 0 }
        }
    ]

    /* ---- 文本 ---- */
    Text {
        id: label
        anchors.centerIn: parent
        text: ""
        color: Theme.furryosWhite
        font.pixelSize: root.fontSize
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    /* ---- 按钮内爪印标记（品牌元素，小尺寸、位于文字左侧，不干扰阅读） ---- */
    Image {
        id: pawIcon
        visible: root.pawDecoration
        anchors.right: label.left
        anchors.rightMargin: 10
        anchors.verticalCenter: label.verticalCenter
        width: 18
        height: 18
        source: "../assets/paw.svg"
        sourceSize.width: 18
        sourceSize.height: 18
        fillMode: Image.PreserveAspectFit
        opacity: 0.9
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

    /* ---- 密码错误抖动：320ms，±6px，2 次 ---- */
    function shake() {
        shakeAnim.restart()
    }

    /* ---- 密码错误抖动：320ms，±6px，2 次 ----
       分段 40 + 120 + 120 + 40 = 320ms（1/8 + 3/8 + 3/8 + 1/8），
       两次完整往复（-6 → +6 → -6 → 0），合计精确 320ms。 */
    SequentialAnimation {
        id: shakeAnim
        running: false
        NumberAnimation { target: root; property: "x"
            to: root.restX - Theme.shakeAmplitude
            duration: Theme.shakeDuration / 8; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "x"
            to: root.restX + Theme.shakeAmplitude
            duration: Theme.shakeDuration * 3 / 8; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "x"
            to: root.restX - Theme.shakeAmplitude
            duration: Theme.shakeDuration * 3 / 8; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "x"
            to: root.restX
            duration: Theme.shakeDuration / 8; easing.type: Easing.InOutQuad }
    }
}
