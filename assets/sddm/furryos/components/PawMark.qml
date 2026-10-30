/*
    FurryOS SDDM 主题 —— 单个爪印装饰图样
    ------------------------------------------------------------
    以「设计坐标」定位，由 PawBackground 按屏幕比例换算到实际像素，
    保证 1600x900 设计基准在不同分辨率下装饰位置一致。
    低透明度 furryos-blue，仅作背景装饰。
*/
import QtQuick 2.15

Image {
    id: pawMark

    /* 设计基准坐标与尺寸（1600x900） */
    property real designX: 0
    property real designY: 0
    property real designSize: 100

    /* 缩放因子由 PawBackground 注入 */
    property real scaleX: 1
    property real scaleY: 1

    /* 额外旋转与不透明度，便于排布出自然散落感 */
    property real rotationDeg: 0

    x: designX * scaleX
    y: designY * scaleY
    width: designSize * scaleX
    height: designSize * scaleY
    rotation: rotationDeg
    opacity: Theme.pawOpacity

    source: "../assets/paw.svg"
    fillMode: Image.PreserveAspectFit
    smooth: true
    /* 按实际像素尺寸光栅化 SVG，而不是按设计尺寸：
       早先用 designSize 光栅化再被 scaleX/scaleY 放大，在 2560x1440 及以上
       屏幕上爪印边缘会发虚（SVG 先缩到 340px 再拉到 800px）。 */
    sourceSize.width: Math.max(1, Math.round(width))
    sourceSize.height: Math.max(1, Math.round(height))
}
