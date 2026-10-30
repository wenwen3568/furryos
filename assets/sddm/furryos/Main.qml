/*
    FurryOS SDDM 主题 —— 主界面
    ------------------------------------------------------------
    完整登录界面布局（非仅替换背景图）：
      · 品牌区：爪印 logo + FurryOS 字标 + 副标语
      · 用户名输入框、密码输入框（含爪印图标、密码遮蔽）
      · 登录按钮（悬停 140ms / 按下 200ms / 错误抖动 320ms）
      · 关机入口、重启入口
      · 会话选择（右上角）
      · 爪印背景装饰（不遮挡输入区域）
    色值/字号/圆角/动效参数唯一来源：components/Theme.qml
      （其上游唯一权威是 assets/brand/brand-tokens.md）

    缩放：SDDM 以 SizeRootObjectToView 把根 Item 拉伸到实际分辨率，
    因此所有版式尺寸都乘以 screenScale（= min(w/1600, h/900)），
    1600x900 设计基准在 1366x768 / 1920x1080 / 2560x1440 上等比呈现。
    t5 之前卡片是固定 380x560 像素，在 4K 屏上只剩一小块。
*/
import QtQuick 2.15
import QtQml 2.15
import QtQuick.Layouts 1.15

import "components"

Rectangle {
    id: root

    /* 设计基准：按 1600x900 布局，实际屏幕等比适配 */
    width: 1600
    height: 900

    /* 蓝白配色：极浅蓝页面底（furryos-blue-pale） */
    color: Theme.furryosBluePale

    /* ---- 屏幕适配：SDDM 会把此 Item 拉伸到实际分辨率 ---- */
    readonly property real screenScale: Math.min(width / 1600, height / 900)
    /* 版式缩放别名：所有尺寸令牌乘以它 */
    readonly property real s: screenScale

    /* ---- 全局状态 ---- */
    property string notificationMessage: ""
    property bool loginFailed: false

    /* ---- 登录卡片（安全区）---- */
    property rect loginCardRect: Qt.rect(0, 0, 0, 0)

    /* ================= 背景层 ================= */
    /* 登录卡片矩形由 loginCard 的 Component.onCompleted 写入 root.loginCardRect，
       再绑定到 PawBackground.safeRect，使装饰层知道必须避让的区域。 */
    PawBackground {
        id: pawBackground
        anchors.fill: parent
        safeRect: root.loginCardRect
        z: 0
    }

    /* 右侧品牌竖带：蓝白配色的「蓝」侧，强化可辨认度 */
    Rectangle {
        id: brandBand
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.round(320 * root.s)
        color: Theme.furryosBlue
        opacity: 0.10
        z: 0
    }

    /* ================= 主内容 ================= */
    Item {
        id: mainArea
        anchors.fill: parent
        z: 1

        /* ---- 登录卡片：白底，圆角，浅蓝描边 ---- */
        Rectangle {
            id: loginCard
            objectName: "loginCard"
            width: Math.round(Theme.cardWidth * root.s)
            height: Math.round(Theme.cardHeight * root.s)
            anchors.left: parent.left
            anchors.leftMargin: Math.round(Theme.cardMargin * root.s)
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.furryosWhite
            radius: Math.round(Theme.radiusCard * root.s)
            border.width: Theme.hairlineWidth
            border.color: Theme.furryosBlueLight

            /* 记录安全区，供背景装饰避让与外部校验 */
            Component.onCompleted: root.loginCardRect = Qt.rect(loginCard.x, loginCard.y, loginCard.width, loginCard.height)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Math.round(Theme.cardPadding * root.s)
                spacing: Math.round(Theme.columnSpacing * root.s)

                /* ---- 品牌标题：爪印 + FurryOS ---- */
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Math.round(12 * root.s)

                    Image {
                        id: brandPaw
                        width: Math.round(Theme.brandPawPx * root.s)
                        height: Math.round(Theme.brandPawPx * root.s)
                        source: "assets/paw.svg"
                        sourceSize.width: Math.round(Theme.brandPawPx * root.s)
                        sourceSize.height: Math.round(Theme.brandPawPx * root.s)
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        text: "FurryOS"
                        color: Theme.furryosBlueDeep
                        font.pixelSize: Math.round(Theme.titleFontPx * root.s)
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                }

                /* ---- 副标题 ---- */
                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: "欢迎回来，请登录"
                    color: Theme.furryosTextMuted
                    font.pixelSize: Math.round(Theme.labelFontPx * root.s)
                    horizontalAlignment: Text.AlignHCenter
                }

                /* 分隔 */
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Math.round(6 * root.s)
                    height: Theme.hairlineWidth
                    color: Theme.furryosBlueLight
                }

                /* ---- 用户名：标签与输入框成组，组内 6px、组间用 columnSpacing ---- */
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Math.round(6 * root.s)

                    Text {
                        text: "用户名"
                        color: Theme.furryosText
                        font.pixelSize: Math.round(Theme.labelFontPx * root.s)
                        font.weight: Font.DemiBold
                    }

                    FurryField {
                        id: userField
                        Layout.fillWidth: true
                        implicitHeight: Math.round(Theme.fieldHeight * root.s)
                        fontSize: Math.round(Theme.bodyFontPx * root.s)
                        radius: Math.round(Theme.radiusControl * root.s)
                        placeholder: "请输入用户名"
                        errorState: root.loginFailed
                        KeyNavigation.tab: passwordField
                        Component.onCompleted: forceActiveFocus()
                    }
                }

                /* ---- 密码 ---- */
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Math.round(6 * root.s)

                    Text {
                        text: "密码"
                        color: Theme.furryosText
                        font.pixelSize: Math.round(Theme.labelFontPx * root.s)
                        font.weight: Font.DemiBold
                    }

                    FurryField {
                        id: passwordField
                        Layout.fillWidth: true
                        implicitHeight: Math.round(Theme.fieldHeight * root.s)
                        fontSize: Math.round(Theme.bodyFontPx * root.s)
                        radius: Math.round(Theme.radiusControl * root.s)
                        isPassword: true
                        placeholder: "请输入密码"
                        errorState: root.loginFailed
                        KeyNavigation.tab: loginButton
                        onAccepted: loginButton.clicked()
                    }
                }

                /* ---- 提示信息（含密码错误） ---- */
                Text {
                    id: messageLabel
                    Layout.fillWidth: true
                    Layout.topMargin: Math.round(4 * root.s)
                    text: root.notificationMessage
                    color: root.loginFailed ? Theme.furryosNegative : Theme.furryosTextMuted
                    font.pixelSize: Math.round(Theme.labelFontPx * root.s)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                }

                /* 弹性空间 */
                Item { Layout.fillHeight: true; Layout.minimumHeight: Math.round(8 * root.s) }

                /* ---- 登录按钮（主动效） ---- */
                FurryButton {
                    id: loginButton
                    Layout.fillWidth: true
                    implicitHeight: Math.round(Theme.buttonHeight * root.s)
                    fontSize: Math.round(Theme.bodyFontPx * root.s)
                    radius: Math.round(Theme.radiusControl * root.s)
                    text: "登  录"
                    baseColor: Theme.furryosBlue
                    hoverColor: Theme.furryosAccentHover
                    pressColor: Theme.furryosBlueDark
                    pawDecoration: true
                    onClicked: doLogin()
                }

                /* ---- 关机 / 重启 ---- */
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Math.round(6 * root.s)
                    spacing: Math.round(12 * root.s)

                    FurryButton {
                        id: shutdownButton
                        Layout.fillWidth: true
                        implicitHeight: Math.round(44 * root.s)
                        radius: Math.round(Theme.radiusControl * root.s)
                        text: "关机"
                        fontSize: Math.round(Theme.labelFontPx * root.s)
                        baseColor: Theme.furryosBlueDark
                        hoverColor: Theme.furryosBlue
                        pressColor: Theme.furryosBlueDeep
                        pawDecoration: true
                        onClicked: root.sddmReady ? sddmApi.powerOff() : (root.notificationMessage = "（非 SDDM 环境）")
                    }

                    FurryButton {
                        id: restartButton
                        Layout.fillWidth: true
                        implicitHeight: Math.round(44 * root.s)
                        radius: Math.round(Theme.radiusControl * root.s)
                        text: "重启"
                        fontSize: Math.round(Theme.labelFontPx * root.s)
                        baseColor: Theme.furryosBlueDark
                        hoverColor: Theme.furryosBlue
                        pressColor: Theme.furryosBlueDeep
                        pawDecoration: true
                        onClicked: root.sddmReady ? sddmApi.reboot() : (root.notificationMessage = "（非 SDDM 环境）")
                    }
                }
            }
        }

        /* ---- 右侧品牌面板：爪印 + 字标 + 标语（输入区之外） ---- */
        Item {
            id: brandPanel
            anchors.left: loginCard.right
            anchors.leftMargin: Math.round(60 * root.s)
            anchors.right: parent.right
            anchors.rightMargin: Math.round(60 * root.s)
            anchors.verticalCenter: parent.verticalCenter

            ColumnLayout {
                anchors.fill: parent
                spacing: Math.round(24 * root.s)

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    width: Math.round(Theme.panelPawPx * root.s)
                    height: Math.round(Theme.panelPawPx * root.s)
                    source: "assets/paw.svg"
                    sourceSize.width: Math.round(Theme.panelPawPx * root.s)
                    sourceSize.height: Math.round(Theme.panelPawPx * root.s)
                    fillMode: Image.PreserveAspectFit
                    opacity: 0.55
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "FurryOS"
                    color: Theme.furryosBlueDeep
                    font.pixelSize: Math.round(Theme.displayFontPx * root.s)
                    font.weight: Font.Bold
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "蓝白之间，轻快回应"
                    color: Theme.furryosTextMuted
                    font.pixelSize: Math.round(Theme.labelFontPx * root.s * 1.4)
                }
            }
        }

        /* ---- 右上角工具条：会话选择 ----
           使用自绘控件而非 SddmComponents.ComboBox，
           避免主题对发行版 SddmComponents 安装路径的依赖。
           键盘布局/虚拟键盘入口不在本主题内实现：SDDM 的 keyboard
           对象只在部分 greeter 构建里暴露，强行调用会在缺对象时抛
           ReferenceError，故此处只保留会话选择这一项。 */
        RowLayout {
            id: topBar
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Math.round(20 * root.s)
            spacing: Math.round(10 * root.s)
            z: 2

            Rectangle {
                id: sessionBox
                objectName: "sessionBox"
                width: Math.round(200 * root.s)
                height: Math.round(Theme.chipHeight * root.s)
                radius: Math.round(Theme.radiusChip * root.s)
                color: sessionHover.containsMouse ? Theme.furryosBluePale : Theme.furryosWhite
                border.width: Theme.hairlineWidth
                border.color: sessionHover.containsMouse ? Theme.furryosBlue : Theme.furryosBlueLight

                Behavior on color {
                    ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
                }

                property int currentIndex: (typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
                readonly property string currentName: {
                    if (typeof sessionModel === "undefined" || sessionModel.count === 0) return "默认会话"
                    var n = sessionModel.get(currentIndex)
                    return (n && n.name) ? n.name : "默认会话"
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Math.round(12 * root.s)
                    anchors.right: sessionArrow.left
                    anchors.rightMargin: Math.round(6 * root.s)
                    anchors.verticalCenter: parent.verticalCenter
                    text: sessionBox.currentName
                    color: Theme.furryosText
                    font.pixelSize: Math.round(Theme.captionFontPx * root.s)
                    elide: Text.ElideRight
                }

                Text {
                    id: sessionArrow
                    anchors.right: parent.right
                    anchors.rightMargin: Math.round(12 * root.s)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▾"
                    color: sessionBox.currentIndex >= 0 && sessionHover.containsMouse ? Theme.furryosAccentHover : Theme.furryosBlue
                    font.pixelSize: Math.round(Theme.captionFontPx * root.s)
                }

                MouseArea {
                    id: sessionHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof sessionModel !== "undefined" && sessionModel.count > 0) {
                            sessionBox.currentIndex = (sessionBox.currentIndex + 1) % sessionModel.count
                        }
                    }
                }
            }
        }
    }

    /* ================= 交互逻辑 ================= */

    /* SDDM 运行时会注入全局 `sddm` 对象；在非 SDDM 环境（静态审查、
       单元测试、qmlscene 预览）中该对象不存在，裸调用会抛 ReferenceError。
       故在组件完成时探测一次并缓存：取到即 SDDM 环境，取不到走降级提示。
       注意：sddm 由 SDDM greeter 注入，Qt 的类型系统不知道它，
       qmllint 的 --check-unqualified 会对 `sddm` 提未限定访问警告，
       属预期（官方 breeze 主题同样裸用 sddm.* 且警告更多）。 */
    property var sddmApi: null
    readonly property bool sddmReady: sddmApi !== null

    Component.onCompleted: {
        sddmApi = (typeof sddm !== "undefined") ? sddm : null
    }

    function doLogin() {
        if (userField.text.length === 0) {
            root.notificationMessage = "请输入用户名"
            root.loginFailed = false
            userField.forceActiveFocus()
            return
        }
        if (passwordField.text.length === 0) {
            root.notificationMessage = "请输入密码"
            root.loginFailed = false
            passwordField.forceActiveFocus()
            return
        }

        root.notificationMessage = "正在登录…"
        root.loginFailed = false
        var sessionIndex = sessionBox.currentIndex
        if (root.sddmReady) {
            sddmApi.login(userField.text, passwordField.text, sessionIndex)
        } else {
            // 非 SDDM 环境：仅演示动效，不执行真实登录
            root.notificationMessage = "（非 SDDM 环境：跳过真实登录）"
        }
    }

    /* SDDM 登录失败回调：抖动 + 提示（sddm 存在时才连接） */
    Connections {
        target: root.sddmApi
        function onLoginFailed() {
            root.notificationMessage = "用户名或密码错误"
            root.loginFailed = true
            loginButton.shake()
            passwordField.shake()
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            root.notificationMessage = ""
        }
    }

    /* 键盘可达性：Esc 关机由系统处理；Enter 登录由密码框 onAccepted 处理 */
    focus: true
    Keys.onPressed: {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (passwordField.inputFocus || userField.inputFocus) {
                doLogin()
            }
        }
    }
}
