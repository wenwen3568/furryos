/*
    FurryOS 视觉校验探针 —— SDDM 主题令牌与组件属性
    ------------------------------------------------------------------
    被 tools/verify-visual.sh 用 qmlscene 离屏执行，向 stdout 打印一行
    `PROBE-JSON:{...}`，再由 tools/verify-visual.py 逐项断言。

    为什么用 QML 实例化而不是正则读文件：
      色值在 Theme.qml 里是 `readonly property color`，正则只能看到字面量，
      看不到 Qt 解析后的实际值（例如 #1A6FD4 会被 Qt 归一化、颜色别名会被
      展开）。这里真的创建对象树并读属性，断言的是运行时值。
*/
import QtQuick 2.15
import "../../assets/sddm/furryos/components" as C

Item {
    id: root
    width: 200
    height: 200

    /* 按钮：正常态与禁用态的实际颜色/尺寸 */
    C.FurryButton {
        id: normalButton
        text: "登录"
        buttonEnabled: true
    }
    C.FurryButton {
        id: disabledButton
        text: "登录"
        buttonEnabled: false
    }

    /* 输入框：错误态描边色 */
    C.FurryField {
        id: errorField
        errorState: true
    }

    Timer {
        interval: 60
        running: true
        onTriggered: {
            var t = C.Theme
            var probe = {
                theme: {
                    furryosBlue:        String(t.furryosBlue),
                    furryosBlueDark:    String(t.furryosBlueDark),
                    furryosBlueDeep:    String(t.furryosBlueDeep),
                    furryosBlueLight:   String(t.furryosBlueLight),
                    furryosBluePale:    String(t.furryosBluePale),
                    furryosWhite:       String(t.furryosWhite),
                    furryosText:        String(t.furryosText),
                    furryosTextMuted:   String(t.furryosTextMuted),
                    furryosAccentHover: String(t.furryosAccentHover),
                    furryosNegative:    String(t.furryosNegative),
                    furryosDisabledBg:   String(t.furryosDisabledBg),
                    furryosDisabledText: String(t.furryosDisabledText),
                    hoverDuration: t.hoverDuration,
                    pressDuration: t.pressDuration,
                    shakeDuration: t.shakeDuration,
                    shakeAmplitude: t.shakeAmplitude,
                    hoverScale: t.hoverScale,
                    pressScale: t.pressScale,
                    titleFontPx: t.titleFontPx,
                    bodyFontPx: t.bodyFontPx,
                    labelFontPx: t.labelFontPx,
                    captionFontPx: t.captionFontPx,
                    displayFontPx: t.displayFontPx,
                    radiusCard: t.radiusCard,
                    radiusControl: t.radiusControl,
                    radiusChip: t.radiusChip,
                    fieldHeight: t.fieldHeight,
                    buttonHeight: t.buttonHeight,
                    cardWidth: t.cardWidth,
                    cardHeight: t.cardHeight,
                    pawOpacity: t.pawOpacity
                },
                button: {
                    implicitHeight: normalButton.implicitHeight,
                    radius: normalButton.radius,
                    normalColor: String(normalButton.color),
                    normalTextColor: String(normalButton.textColor),
                    disabledColor: String(disabledButton.color),
                    disabledTextColor: String(disabledButton.textColor),
                    pawSource: String(normalButton.children.length)
                },
                field: {
                    implicitHeight: errorField.implicitHeight,
                    radius: errorField.radius,
                    errorBorderColor: String(errorField.border.color),
                    errorBorderWidth: errorField.border.width,
                    fontSize: errorField.fontSize
                }
            }
            console.log("PROBE-JSON:" + JSON.stringify(probe))
            Qt.quit()
        }
    }
}
