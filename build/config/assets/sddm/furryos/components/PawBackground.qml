/*
    FurryOS SDDM 主题 —— 爪印背景装饰层
    ------------------------------------------------------------
    设计约束（CONTRACTS.md 成员三 + brand-tokens.md 第 2 节）：
      · 爪印仅作背景装饰，浅色底上使用低透明度 furryos-blue
      · 严禁遮挡用户名 / 密码输入区域与登录按钮
      · 本组件不接受锚点填充，只接受显式设计坐标，
        并对外暴露 `safeRect`（登录卡片矩形），装饰全部排布在其外。
      · z:-1 + enabled:false，保证装饰永远在底层且不拦截鼠标。

    坐标以 1600x900 设计基准给出，Main.qml 会按实际屏幕等比缩放。
    爪印分布区域（设计坐标）：
      · 右侧 x∈[1060,1540]：主装饰群，登录卡片（x∈[130,510]）之外
      · 左上 x∈[90,320], y∈[70,230]：标题上方留白，安全区外
      · 底部 y∈[780,870]：屏幕下缘细长带，安全区下方
*/
import QtQuick 2.15

Item {
    id: root

    /* 登录卡片矩形（安全区）。由 Main.qml 注入，装饰必须避开它。 */
    property rect safeRect

    /* 设计基准尺寸，Main.qml 负责等比缩放 */
    property real designWidth: 1600
    property real designHeight: 900

    /* 缩放因子 */
    readonly property real sx: width / designWidth
    readonly property real sy: height / designHeight

    /* 装饰不接收鼠标事件，永远在底层 */
    z: -1
    enabled: false

    /* ---- 右侧大爪印（登录卡片右侧，绝不进入安全区） ---- */
    PawMark { designX: 1120; designY: 150; designSize: 340; scaleX: root.sx; scaleY: root.sy; rotationDeg: -14; opacity: 0.26 }
    PawMark { designX: 1290; designY: 470; designSize: 250; scaleX: root.sx; scaleY: root.sy; rotationDeg: 22;  opacity: 0.20 }
    PawMark { designX: 1060; designY: 620; designSize: 190; scaleX: root.sx; scaleY: root.sy; rotationDeg: -32; opacity: 0.18 }

    /* ---- 左上角爪印（登录卡片上方留白区，y+size 必须 < 170） ---- */
    PawMark { designX: 60;  designY: 30;  designSize: 110; scaleX: root.sx; scaleY: root.sy; rotationDeg: 18;  opacity: 0.16 }
    PawMark { designX: 200; designY: 60;  designSize: 70;  scaleX: root.sx; scaleY: root.sy; rotationDeg: -20; opacity: 0.14 }

    /* ---- 底部边缘爪印（细长留白带，安全区下方） ---- */
    PawMark { designX: 330;  designY: 780; designSize: 90; scaleX: root.sx; scaleY: root.sy; rotationDeg: 8;   opacity: 0.12 }
    PawMark { designX: 640;  designY: 800; designSize: 70; scaleX: root.sx; scaleY: root.sy; rotationDeg: -12; opacity: 0.10 }
    PawMark { designX: 1450; designY: 800; designSize: 80; scaleX: root.sx; scaleY: root.sy; rotationDeg: 24;  opacity: 0.11 }
}
