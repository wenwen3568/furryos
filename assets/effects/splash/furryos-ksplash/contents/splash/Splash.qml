/*
    FurryOS KSplash —— 登录完成到桌面就绪的过渡画面
    ------------------------------------------------------------------
    视觉来源：assets/effects/splash/furryos-splash.svg（同一构图、同一渐变、
    同一字标位置），因此开机 → 登录 → 桌面三段的视觉是连续的。
    色值唯一来源：assets/brand/brand-tokens.md
    结构参考：Ubuntu noble 的 plasma-workspace-data 中
      org.kde.breeze.desktop/contents/splash/Splash.qml，
    但全部替换为 FurryOS 品牌元素，不继承上游资产或文案。
    禁止项：不得出现 Ubuntu/KDE/Plasma 字样、Logo 或商标。

    t5 视觉统一的两处实质改动（都由 verify-splash-pixels.py / verify-visual.py 断言）：
      1) 字标与副标语由「白色」改为「深蓝 (#0A3568) / 深蓝 (#0F4C8C)」。
         渐变在 y=65% 处已经变到浅蓝 (159,195,240)，白字只有 1.8:1，
         实测截图同款；深蓝字在同一位置是 6.6:1 / 5.2:1。
      2) 所有元素按画面高度百分比定位（0.278 / 0.577 / 0.684 / 0.833），
         与 furryos-splash.svg 的设计坐标一一对应，任意分辨率都不跑版。

    动效参数：
      - 淡入 longDuration（200ms，InOutQuad），落在 brand-tokens 的
        200–300ms 轻快区间；早先是 veryLongDuration*2 = 1000ms，偏拖沓。
      - 进度指示 1500ms/圈，与 Plymouth spinner 的 1.5s 一致。
*/

import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore

Rectangle {
    id: root
    // 与启动画面底部同色：蓝白渐变的收尾白
    color: "#FFFFFF"

    property int stage

    /* ---- 设计基准：furryos-splash.svg 的 1920x1080 坐标，换算为比例 ---- */
    readonly property real px: height / 1080.0

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
        // SVG 母版坐标：translate(810,300) 处的 256x256 爪印
        Image {
            id: logo
            readonly property real size: Math.round(256 * root.px)

            x: Math.round(root.width / 2 - size / 2)
            y: Math.round(300 * root.px)

            asynchronous: true
            source: "images/paw-white.svg"
            sourceSize.width: size
            sourceSize.height: size
            width: size
            height: size
        }

        // 字标：SVG 基线 y=700，字号 96px → 用 0.8 的基线系数反推 y
        Text {
            id: wordmark
            text: "FurryOS"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(700 * root.px - 96 * root.px * 0.8)
            color: "#0A3568"      // furryos-blue-deep：浅蓝底上 6.6:1
            font.family: PlasmaCore.Theme.defaultFont.family
            font.pixelSize: Math.max(12, Math.round(96 * root.px))
            font.weight: Font.Bold
            font.letterSpacing: Math.round(6 * root.px)
        }

        // 副标语：SVG 基线 y=762，字号 30px
        Text {
            id: subtitle
            text: "蓝白之间，轻快回应"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(762 * root.px - 30 * root.px * 0.8)
            color: "#0F4C8C"      // furryos-blue-dark：浅蓝底上 5.2:1
            font.family: PlasmaCore.Theme.defaultFont.family
            font.pixelSize: Math.max(10, Math.round(30 * root.px))
            font.letterSpacing: Math.round(4 * root.px)
        }

        // 进度指示：furryos-blue 细圆弧，与点击特效涟漪同色
        // SVG 进度条中心 y=903 → 0.836；此处 0.833 与之对齐
        Image {
            id: busyIndicator
            readonly property real size: Math.max(16, Math.round(60 * root.px))
            width: size
            height: size
            x: Math.round(root.width / 2 - size / 2)
            y: Math.round(900 * root.px - size / 2)
            asynchronous: true
            source: "images/busywidget.svg"
            sourceSize.width: size
            sourceSize.height: size
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
        duration: PlasmaCore.Units.longDuration
        easing.type: Easing.InOutQuad
    }
}
