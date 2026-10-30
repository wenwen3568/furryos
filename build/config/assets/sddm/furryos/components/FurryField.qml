/*
    FurryOS SDDM 主题 —— 输入框组件（用户名 / 密码共用）
    ------------------------------------------------------------
    · 白底 + 浅蓝边框，符合 brand-tokens.md 蓝白配色
    · 左侧爪印图标，纯装饰，位于输入区外框内、不遮挡光标与文字
    · 四态：normal / focus（2px 主色描边）/ error（错误红描边）/ 抖动
    · 密码错误时整体轻微抖动（320ms / ±6px / 2 次，由 shake() 触发）
    · 字号、圆角、时长全部取自 Theme.qml（禁止本文件另写数值）
*/
import QtQuick 2.15
import QtQml 2.15

Rectangle {
    id: root

    /* ---- 对外接口 ---- */
    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias readOnly: input.readOnly
    property alias inputFocus: input.focus
    property alias placeholder: placeholder.text
    property bool isPassword: false
    property bool errorState: false
    property int fontSize: Theme.bodyFontPx
    property color borderColor: Theme.furryosBlueLight

    signal accepted

    implicitWidth: 300
    implicitHeight: Theme.fieldHeight
    radius: Theme.radiusControl
    color: Theme.furryosWhite
    border.width: (input.activeFocus || errorState) ? Theme.focusBorderWidth : Theme.hairlineWidth
    border.color: errorState ? Theme.furryosNegative
                : input.activeFocus ? Theme.furryosBlue
                : root.borderColor

    Behavior on border.color {
        ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
    }
    Behavior on border.width {
        NumberAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
    }

    /* ---- 爪印图标：装饰，固定在外框左侧留白内 ----
       尺寸随控件高度等比，保证 1366x768 与 2560x1440 下留白比例一致。 */
    Image {
        id: pawIcon
        anchors.left: parent.left
        anchors.leftMargin: Math.round(14 * (root.height / Theme.fieldHeight))
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(20 * (root.height / Theme.fieldHeight))
        height: Math.round(20 * (root.height / Theme.fieldHeight))
        source: "../assets/paw.svg"
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        opacity: input.activeFocus ? 0.85 : 0.5
        Behavior on opacity {
            NumberAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
        }
    }

    /* ---- 占位提示：与输入文字同字号，只靠颜色区分，
       避免「placeholder 比输入小一档」的割裂 ---- */
    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.leftMargin: Math.round(46 * (root.height / Theme.fieldHeight))
        anchors.right: parent.right
        anchors.rightMargin: Math.round(14 * (root.height / Theme.fieldHeight))
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Theme.furryosTextMuted
        font.pixelSize: root.fontSize
        visible: input.text.length === 0
        elide: Text.ElideRight
    }

    /* ---- 实际输入 ---- */
    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: Math.round(46 * (root.height / Theme.fieldHeight))
        anchors.right: parent.right
        anchors.rightMargin: Math.round(14 * (root.height / Theme.fieldHeight))
        anchors.verticalCenter: parent.verticalCenter
        echoMode: root.isPassword ? TextInput.Password : TextInput.Normal
        color: Theme.furryosText
        font.pixelSize: root.fontSize
        selectionColor: Theme.furryosBlueLight
        selectedTextColor: Theme.furryosBlueDeep
        selectByMouse: true
        passwordCharacter: "●"
        onAccepted: root.accepted()
        Keys.onTabPressed: nextItemInFocusChain().forceActiveFocus()
        Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus()
    }

    /* ---- 抖动：走 Translate，不动 x ----
       与 FurryButton 同一套参数（Theme.shakeDuration / shakeAmplitude），
       两处抖动因此完全同步，不会一个 320ms 一个 200ms。 */
    transform: Translate { id: shakeTranslate; x: 0 }

    function shake() {
        shakeAnim.restart()
    }

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
