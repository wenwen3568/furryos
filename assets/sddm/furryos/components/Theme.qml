/*
    FurryOS SDDM 主题 —— 品牌令牌单例
    ------------------------------------------------------------
    色值与动效时长的唯一来源：assets/brand/brand-tokens.md
    所有组件统一引用本文件，禁止在各组件内另写色值/字号/圆角。
    （t5 视觉统一：Main.qml 里原先散落的 380/560/16/42/18 等魔法数字
      全部收敛到本文件的版式令牌，改一处即可整体生效。）
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

    /* ---- 语义色（非品牌色；同样只允许在本文件出现） ---- */
    // 登录失败提示文字。取比 KDE 的 ForegroundNegative (#DA4453) 更深一档的
    // 品牌红，因为在 furryosBluePale (#EAF2FF) 上 #DA4453 只有 3.78:1（低于
    // WCAG AA 4.5:1），而本值有 5.80:1。语义色的唯一来源仍是 brand-tokens.md。
    readonly property color furryosNegative:   "#B3261E"   // 错误/失败提示

    // 禁用态：浅蓝底 + 次要文字色。早先按钮禁用态是
    // 「furryosBlueLight 底 + 白色文字」= 1.35:1，文字等于看不见；
    // 这里给出可读的配对（4.98:1），并由 verify-visual.py 断言。
    readonly property color furryosDisabledBg:   "#EAF2FF"   // 禁用底（furryos-blue-pale）
    readonly property color furryosDisabledText: "#4A637C"   // 禁用文字（furryos-text-muted）

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

    /* ---- 版式：字号层级（4 档，全局统一） ---- */
    readonly property int displayFontPx: 44   // 品牌面板大字标
    readonly property int titleFontPx: 26     // 卡片标题
    readonly property int bodyFontPx: 15      // 输入文字 / 按钮
    readonly property int labelFontPx: 13     // 字段标签 / 提示
    readonly property int captionFontPx: 12   // 会话选择等小控件

    /* ---- 版式：圆角层级（3 档，全局统一） ---- */
    readonly property int radiusCard: 18      // 登录卡片等大容器
    readonly property int radiusControl: 10   // 按钮 / 输入框
    readonly property int radiusChip: 8       // 会话选择等小控件

    /* ---- 版式：控件尺寸（设计基准 1600x900） ---- */
    readonly property int cardWidth: 380
    readonly property int cardHeight: 560
    readonly property int cardMargin: 130     // 卡片左外边距
    readonly property int cardPadding: 34     // 卡片内边距
    readonly property int columnSpacing: 18   // 卡片内垂直节奏
    readonly property int fieldHeight: 46
    readonly property int buttonHeight: 48
    readonly property int chipHeight: 34
    readonly property int brandPawPx: 40      // 卡片内品牌爪印
    readonly property int panelPawPx: 180     // 品牌面板大爪印

    /* ---- 版式：焦点描边 ---- */
    readonly property int focusBorderWidth: 2
    readonly property int hairlineWidth: 1
}
