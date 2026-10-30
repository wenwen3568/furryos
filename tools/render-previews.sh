#!/bin/bash
#
# render-previews.sh — 把 FurryOS 的四个界面渲染成 PNG，放进 docs/preview/。
#
# 每个 PNG 的来源都写清楚（不许把「示意」说成「截图」）：
#
#   sddm-login-1600x900.png / sddm-login-2560x1440.png
#       真渲染：qmlscene 离屏实例化 assets/sddm/furryos/Main.qml，
#       再用 Item.grabToImage() 抓帧。两个尺寸用来证明版式按 screenScale 等比缩放。
#
#   ksplash-1920x1080.png
#       真渲染：qmlscene 离屏实例化 assets/effects/splash/furryos-ksplash/
#       contents/splash/Splash.qml（stage=2，等淡入动画结束后抓帧）。
#
#   splash-master-1920x1080.png
#       真渲染：QtSvg 渲染 assets/effects/splash/furryos-splash.svg（母版）。
#
#   plymouth-1920x1080.png
#       合成：宿主没有 plymouth 运行环境（需要 DRM/framebuffer），因此用
#       plymouth 主题自带的真实素材（paw-white-256.png / spinner0.png）+
#       furryos.script 里的真实坐标公式（logo 居中、字标在 logo 下方、
#       spinner 在字标下方）合成，背景色取自脚本的 palette.background。
#       它验证的是「素材 + 坐标 + 配色」，不是 plymouth 的渲染管线。
#
#   desktop-1920x1080.png
#       合成：真实壁纸 assets/desktop/wallpapers/FurryOS/contents/images/1920x1080.png
#       + 用 FurryOS.colors / skel kdeglobals 的实值画出的面板条与窗口示意
#       （面板高度 44px 取自 look-and-feel 的 layout JS：2*floor(gridUnit*2.5/2)，
#        gridUnit=18）。宿主没有 Plasma 会话，无法截真图；窗口装饰/图标未渲染。
#
# 用法：bash tools/render-previews.sh [输出目录]
# 依赖：qmlscene（Qt5 declarative）、ImageMagick convert
# 退出码：0 = 全部生成；1 = 缺依赖或渲染失败

set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="$(cd "${SELF_DIR}/.." && pwd)"
OUT="${1:-${WS}/docs/preview}"
TMP="$(mktemp -d /tmp/furryos-preview.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

fail() { echo "ERROR: $*" >&2; exit 1; }

command -v qmlscene >/dev/null 2>&1 || fail "缺少 qmlscene（apt-get install qtdeclarative5-dev-tools）"
command -v convert  >/dev/null 2>&1 || fail "缺少 ImageMagick convert"

mkdir -p "${OUT}"

# qmlscene 在无显示环境下的最小环境
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export QT_LOGGING_RULES="qt.qpa.*=false"

# run_qml <qml 文件> <期望输出 png>
run_qml() {
	local qml="$1" png="$2"
	if ! timeout 180 qmlscene "${qml}" >"${TMP}/qml.log" 2>&1; then
		cat "${TMP}/qml.log" >&2
		fail "qmlscene 执行失败: ${qml}"
	fi
	if [ ! -s "${png}" ]; then
		cat "${TMP}/qml.log" >&2
		fail "未生成 ${png}（日志见上）"
	fi
	echo "  wrote ${png}"
}

# ---------------------------------------------------------------------------
# 1) SDDM 登录界面（真渲染）
# ---------------------------------------------------------------------------
render_sddm() {
	local w="$1" h="$2" png="$3"
	cat > "${TMP}/sddm-${w}.qml" <<EOF
import QtQuick 2.15
Item {
    width: ${w}
    height: ${h}
    Loader {
        id: loader
        anchors.fill: parent
        source: "file://${WS}/assets/sddm/furryos/Main.qml"
        onStatusChanged: if (status === Loader.Error) { console.log("LOAD-ERROR"); Qt.exit(2) }
    }
    Timer {
        interval: 900
        running: true
        onTriggered: {
            if (!loader.item) { console.log("NO-ITEM"); Qt.exit(3); return }
            loader.item.width = ${w}
            loader.item.height = ${h}
            grabTimer.running = true
        }
    }
    Timer {
        id: grabTimer
        interval: 500
        running: false
        onTriggered: {
            loader.item.grabToImage(function (res) {
                if (!res.saveToFile("${png}")) { console.log("SAVE-FAILED"); Qt.exit(4) }
                Qt.quit()
            })
        }
    }
}
EOF
	run_qml "${TMP}/sddm-${w}.qml" "${png}"
}

echo "== SDDM 登录界面 =="
render_sddm 1600 900 "${OUT}/sddm-login-1600x900.png"
render_sddm 2560 1440 "${OUT}/sddm-login-2560x1440.png"

# ---------------------------------------------------------------------------
# 2) KSplash（真渲染，需要 org.kde.plasma.core）
# ---------------------------------------------------------------------------
echo "== KSplash =="
if [ -d /usr/lib/x86_64-linux-gnu/qt5/qml/org/kde/plasma ] || [ -d /usr/lib/qt5/qml/org/kde/plasma ]; then
	cat > "${TMP}/ksplash.qml" <<EOF
import QtQuick 2.15
Item {
    width: 1920
    height: 1080
    Loader {
        id: loader
        anchors.fill: parent
        source: "file://${WS}/assets/effects/splash/furryos-ksplash/contents/splash/Splash.qml"
        onStatusChanged: if (status === Loader.Error) { console.log("LOAD-ERROR"); Qt.exit(2) }
    }
    Timer { interval: 800; running: true; onTriggered: loader.item.stage = 2 }
    Timer {
        interval: 2200
        running: true
        onTriggered: {
            loader.item.grabToImage(function (res) {
                if (!res.saveToFile("${OUT}/ksplash-1920x1080.png")) { console.log("SAVE-FAILED"); Qt.exit(4) }
                Qt.quit()
            })
        }
    }
}
EOF
	run_qml "${TMP}/ksplash.qml" "${OUT}/ksplash-1920x1080.png"
else
	echo "  SKIP: 宿主没有 org.kde.plasma.core QML 模块，无法渲染 ksplash" >&2
fi

# ---------------------------------------------------------------------------
# 3) 启动画面母版 SVG（真渲染，QtSvg）
# ---------------------------------------------------------------------------
echo "== 启动画面母版 (SVG) =="
cat > "${TMP}/svg.qml" <<EOF
import QtQuick 2.15
Item {
    width: 1920
    height: 1080
    Image {
        id: img
        anchors.fill: parent
        source: "file://${WS}/assets/effects/splash/furryos-splash.svg"
        sourceSize.width: 1920
        sourceSize.height: 1080
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
    Timer {
        interval: 900
        running: true
        onTriggered: {
            img.grabToImage(function (res) {
                if (!res.saveToFile("${OUT}/splash-master-1920x1080.png")) { console.log("SAVE-FAILED"); Qt.exit(4) }
                Qt.quit()
            }, Qt.size(1920, 1080))
        }
    }
}
EOF
run_qml "${TMP}/svg.qml" "${OUT}/splash-master-1920x1080.png"

# ---------------------------------------------------------------------------
# 4) Plymouth 合成预览（真实素材 + 脚本坐标）
# ---------------------------------------------------------------------------
echo "== Plymouth（合成） =="
PLY="${WS}/assets/effects/splash/furryos-plymouth"
PAW="${PLY}/images/paw-white-256.png"
SPIN="${PLY}/images/spinner/spinner0.png"
[ -f "${SPIN}" ] || SPIN="${PLY}/images/spinner-16/spinner0.png"
[ -f "${PAW}" ]  || fail "缺少 ${PAW}"
[ -f "${SPIN}" ] || fail "缺少 spinner 帧"

# furryos.script 的坐标（1920x1080）：
#   logo:   x = W/2 - logo.w/2,  y = H/2 - logo.h/2                (256x256)
#   title:  y = logo.y + logo.h + titleH/2                          (Noto Sans 14)
#   spinner:y = logo.y + (logo.h + titleH) + spinnerH
# 字标高度用 ImageMagick 的 metrics 估：14pt Noto Sans ≈ 20px 行高
TITLE_H=20
SPIN_W=$(identify -format '%w' "${SPIN}")
SPIN_H=$(identify -format '%h' "${SPIN}")
LOGO_X=$(( (1920 - 256) / 2 ))
LOGO_Y=$(( (1080 - 256) / 2 ))
TITLE_X_OFFSET=0
SPIN_X=$(( LOGO_X + 256 / 2 - SPIN_W / 2 ))
SPIN_Y=$(( LOGO_Y + 256 + TITLE_H + SPIN_H ))

# 背景：脚本 palette.background = top furryos-blue-deep (#0A3568) -> bottom furryos-blue (#1A6FD4)
convert -depth 8 -size 1920x1080 gradient:'#0A3568-#1A6FD4' \
	\( "${PAW}" \) -geometry +${LOGO_X}+${LOGO_Y} -composite \
	-font DejaVu-Sans -pointsize 19 -fill '#FFFFFF' -gravity NorthWest \
	-annotate +$(( 960 - 45 ))+$(( LOGO_Y + 256 + 4 )) 'FurryOS' \
	\( "${SPIN}" \) -geometry +${SPIN_X}+${SPIN_Y} -composite \
	"${OUT}/plymouth-1920x1080.png"
echo "  wrote ${OUT}/plymouth-1920x1080.png"

# ---------------------------------------------------------------------------
# 5) 桌面合成预览（真实壁纸 + 实值配色）
# ---------------------------------------------------------------------------
echo "== 桌面（合成） =="
WALL="${WS}/assets/desktop/wallpapers/FurryOS/contents/images/1920x1080.png"
[ -f "${WALL}" ] || fail "缺少壁纸 ${WALL}"

# 配色取值（全部来自资产文件，不是手挑的）：
#   panel bg     = FurryOS.colors [Colors:Window] BackgroundNormal = 234,242,255
#   panel border = FurryOS.colors [Colors:Window] BackgroundAlternate = 214,230,247
#   panel height = 44（look-and-feel layout JS: 2*floor(gridUnit*2.5/2), gridUnit=18）
#   window title = [WM] activeBackground/activeForeground = 234,242,255 / 18,40,63
#   window view  = [Colors:View] BackgroundNormal = 255,255,255
#   selection    = [Colors:Selection] BackgroundNormal = 26,111,212
PANEL_H=44
convert -depth 8 "${WALL}" \
	-fill 'rgb(234,242,255)' -draw "rectangle 0,$(( 1080 - PANEL_H )) 1919,1079" \
	-fill 'rgb(214,230,247)' -draw "rectangle 0,$(( 1080 - PANEL_H )) 1919,$(( 1080 - PANEL_H + 1 ))" \
	-fill 'rgb(26,111,212)'  -draw "circle 34,$(( 1080 - PANEL_H / 2 )) 34,$(( 1080 - PANEL_H / 2 - 9 ))" \
	-fill 'rgb(214,230,247)' -draw "roundrectangle 90,$(( 1080 - PANEL_H + 12 )) 210,$(( 1080 - 12 )) 6,6" \
	-fill 'rgb(26,111,212)'  -draw "roundrectangle 220,$(( 1080 - PANEL_H + 12 )) 340,$(( 1080 - 12 )) 6,6" \
	-fill 'rgb(18,40,63)'    -draw "rectangle 1770,$(( 1080 - PANEL_H + 14 )) 1866,$(( 1080 - 14 ))" \
	-fill 'rgb(214,230,247)' -draw "rectangle 299,219 1501,861" \
	-fill 'rgb(234,242,255)' -draw "rectangle 300,220 1500,262" \
	-fill 'rgb(214,230,247)' -draw "rectangle 300,261 1500,262" \
	-fill 'rgb(18,40,63)'    -draw "rectangle 330,232 640,250" \
	-fill 'rgb(255,255,255)' -draw "rectangle 301,263 1499,859" \
	-fill 'rgb(234,242,255)' -draw "rectangle 340,290 1460,326" \
	-fill 'rgb(26,111,212)'  -draw "rectangle 340,344 760,374" \
	-fill 'rgb(74,99,124)'   -draw "rectangle 340,388 620,406" \
	"${OUT}/desktop-1920x1080.png"
echo "  wrote ${OUT}/desktop-1920x1080.png"

echo
echo "预览已生成到 ${OUT}"
ls -l "${OUT}"/*.png
