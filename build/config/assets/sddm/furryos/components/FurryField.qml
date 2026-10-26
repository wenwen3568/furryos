/*
    FurryOS SDDM 主题 —— 输入框组件（用户名 / 密码共用）
    ------------------------------------------------------------
    · 白底 + 浅蓝边框，符合 brand-tokens.md 蓝白配色
    · 左侧爪印图标，纯装饰，位于输入区外框内、不遮挡光标与文字
    · 密码错误时整体轻微抖动（320ms / ±6px / 2 次）
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
    property color borderColor: Theme.furryosBlueLight

    signal accepted

    implicitWidth: 300
    implicitHeight: Theme.fieldHeight
    radius: Theme.cornerRadius
    color: Theme.furryosWhite
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? Theme.furryosBlue : root.borderColor

    Behavior on border.color {
        ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
    }

    /* 抖动基准位 */
    property real restX: x

    /* ---- 爪印图标：装饰，固定在外框左侧留白内 ---- */
    Image {
        id: pawIcon
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        source: "../assets/paw.svg"
        sourceSize.width: 20
        sourceSize.height: 20
        fillMode: Image.PreserveAspectFit
        opacity: input.activeFocus ? 0.85 : 0.5
        Behavior on opacity {
            NumberAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
        }
    }

    /* ---- 占位提示 ---- */
    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.leftMargin: 46
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Theme.furryosTextMuted
        font.pixelSize: Theme.labelFontPx
        visible: input.text.length === 0
        elide: Text.ElideRight
    }

    /* ---- 实际输入 ---- */
    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: 46
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        echoMode: root.isPassword ? TextInput.Password : TextInput.Normal
        color: Theme.furryosText
        font.pixelSize: Theme.bodyFontPx
        selectionColor: Theme.furryosBlueLight
        selectedTextColor: Theme.furryosBlueDeep
        selectByMouse: true
        passwordCharacter: "●"
        onAccepted: root.accepted()
        Keys.onTabPressed: nextItemInFocusChain().forceActiveFocus()
        Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus()
    }
}
