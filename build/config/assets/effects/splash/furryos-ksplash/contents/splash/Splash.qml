/*
    FurryOS KSplash —— 登录完成到桌面就绪的过渡画面
    ------------------------------------------------------------------
    视觉来源：assets/effects/splash/furryos-splash.svg（同一构图）
    色值唯一来源：assets/brand/brand-tokens.md
    结构参考：Ubuntu noble 的 plasma-workspace-data 中
      org.kde.breeze.desktop/contents/splash/Splash.qml，
    但全部替换为 FurryOS 品牌元素，不继承上游资产或文案。
    禁止项：不得出现 Ubuntu/KDE/Plasma 字样、Logo 或商标。

    动效参数同样来自 brand-tokens.md：
      - 淡入：veryLongDuration（500ms）量级，InOutQuad
      - 完成后淡出：与启动画面 quit_callback 衔接，保证
        「启动画面 → KSplash → 桌面」三段视觉不断裂。
*/

import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore

Rectangle {
    id: root
    // 与启动画面底部同色：蓝白渐变的收尾白
    color: "#FFFFFF"

    property int stage

    onStageChanged: {
        if (stage == 2) {
            introAnimation.running = true;
        } else if (stage == 5) {
            introAnimation.target = busyIndicator;
            introAnimation.from = 1;
            introAnimation.to = 0;
            introAnimation.running = true;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        // 背景：垂直线性渐变，与 furryos-splash.svg 的四段色标一致
        // 上 #0A3568 (furryos-blue-deep) → #1A6FD4 (furryos-blue)
        //  → #EAF2FF (furryos-blue-pale) → #FFFFFF (furryos-white)
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0;  color: "#0A3568" }
                GradientStop { position: 0.42; color: "#1A6FD4" }
                GradientStop { position: 0.78; color: "#EAF2FF" }
                GradientStop { position: 1.0;  color: "#FFFFFF" }
            }
        }

        // 品牌爪印（assets/brand/paw.svg 的白色反白版）
        Image {
            id: logo
            readonly property real size: PlasmaCore.Units.gridUnit * 10

            anchors.centerIn: parent
            anchors.verticalCenterOffset: -PlasmaCore.Units.gridUnit * 2

            asynchronous: true
            source: "images/paw-white.svg"
            sourceSize.width: size
            sourceSize.height: size
        }

        // 字标
        Text {
            id: wordmark
            text: "FurryOS"
            anchors.horizontalCenter: parent.horizontalCenter
            y: logo.y + logo.height + PlasmaCore.Units.gridUnit
            color: "#FFFFFF"
            font.pointSize: PlasmaCore.Theme.defaultFont.pointSize * 3
            font.weight: Font.Light
        }

        // 副标语：与启动画面一致
        Text {
            id: subtitle
            text: "蓝白之间，轻快回应"
            anchors.horizontalCenter: parent.horizontalCenter
            y: wordmark.y + wordmark.height + PlasmaCore.Units.smallSpacing
            color: "#EAF2FF"
            font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
        }

        // 进度指示：furryos-blue 细圆弧，与点击特效涟漪同色
        Image {
            id: busyIndicator
            y: parent.height - (parent.height - logo.y) / 2 - height / 2
            anchors.horizontalCenter: parent.horizontalCenter
            asynchronous: true
            source: "images/busywidget.svg"
            sourceSize.height: PlasmaCore.Units.gridUnit * 2
            sourceSize.width: PlasmaCore.Units.gridUnit * 2
            RotationAnimator on rotation {
                id: rotationAnimator
                from: 0
                to: 360
                // 1.5s 一圈，与 Plymouth spinner 的 duration 一致
                duration: 1500
                loops: Animation.Infinite
                running: PlasmaCore.Units.longDuration > 1
            }
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: PlasmaCore.Units.veryLongDuration * 2
        easing.type: Easing.InOutQuad
    }
}
