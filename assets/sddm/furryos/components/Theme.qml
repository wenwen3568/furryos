/*
    FurryOS SDDM 主题 —— 品牌令牌单例
    ------------------------------------------------------------
    色值与动效时长的唯一来源：assets/brand/brand-tokens.md
    所有组件统一引用本文件，禁止在各组件内另写色值。
*/
pragma Singleton

import QtQuick 2.15
import QtQml 2.15

QtObject {
    /* ---- 调色板（brand-tokens.md 第 1 节） ---- */
    readonly property color furryosBlue:        "#1A6FD4"   // 主强调色
    readonly property color furryosBlueDark:    "#0F4C8C"   // 深蓝：正文/按下态
    readonly property color furryosBlueDeep:    "#0A3568"   // 最深蓝：标题/投影
    readonly property color furryosBlueLight:   "#D6E6F7"   // 浅蓝：边框/分区
    readonly property color furryosBluePale:    "#EAF2FF"   // 极浅蓝：页面/输入底
    readonly property color furryosWhite:       "#FFFFFF"   // 白：卡片/输入区
    readonly property color furryosText:        "#12283F"   // 主文字
    readonly property color furryosTextMuted:   "#4A637C"   // 次要文字
    readonly property color furryosAccentHover: "#2C85EC"   // 悬停态

    /* ---- 动效参数（brand-tokens.md 第 4 节） ---- */
    // 悬停 120–160ms → 取 140ms（即时回应）
    readonly property int hoverDuration: 140
    // 按下 180–240ms → 取 200ms（按下确认感）
    readonly property int pressDuration: 200
    // 密码错误抖动 320ms / ±6px / 2 次
    readonly property int shakeDuration: 320
    readonly property real shakeAmplitude: 6
    // 悬停与按下整体落在 200–300ms 的「轻快、有回应」区间
    readonly property real hoverScale: 1.03
    readonly property real pressScale: 0.96

    /* ---- 爪印装饰 ---- */
    readonly property real pawOpacity: 0.22

    /* ---- 版式 ---- */
    readonly property int titleFontPx: 26
    readonly property int bodyFontPx: 15
    readonly property int labelFontPx: 13
    readonly property int fieldHeight: 46
    readonly property int buttonHeight: 48
    readonly property int cornerRadius: 10
}
