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
    sourceSize.width: Math.round(designSize)
    sourceSize.height: Math.round(designSize)
}
