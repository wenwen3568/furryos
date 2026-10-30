#!/bin/sh
# FurryOS 交互动效层 —— 启动画面预览光栅化（宿主验证用）
#
# 为什么需要这个脚本：
#   宿主（Debian 12）的 ImageMagick 6.9 内部 SVG 渲染器（MSVG）不支持
#   <linearGradient> 填充；且本机 ImageMagick 安全策略禁用了 `-draw @file`，
#   MVG 的 `gradient` 图元也不可用。
#   直接 `convert furryos-splash.svg` 会丢掉渐变背景，导致「渲染结果像素抽查」
#   看不到蓝白底。真实运行环境（Plasma 的 QtSvg、Plymouth 的 cairo、
#   KSplash 的 QtQuick）都完整支持渐变，所以资产本身没有问题，
#   只是宿主预览需要走一条等价的光栅化路径。
#
# 做法（两阶段，均用 ImageMagick 原生能力）：
#   阶段 1 用 `gradient:` 伪图像格式生成四段垂直渐变底图（等价于 SVG 的
#          linearGradient，色值/端点完全一致）。
#   阶段 2 用内联 -draw 叠加爪印、字标、副标语、进度条。
#   furryos-splash.svg 仍是唯一源资产，本脚本只产预览图。
#
# 用法：
#   ./render-preview.sh [宽度]     # 默认 640
#   ./render-preview.sh 1920      # 1:1 设计基准
#
# 输出：furryos-splash-preview.png（蓝白渐变 + 白爪印 + FurryOS 字标 + 底部进度条）

set -eu

W="${1:-640}"
H=$(( W * 1080 / 1920 ))
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SRC_DIR/furryos-splash-preview.png"
TMP="$SRC_DIR/.preview-bg.png"

BOLD=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
CJK=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc

trap 'rm -f "$TMP" "$TMP".1 "$TMP".2 "$TMP".3' EXIT

# ---- 阶段 1：渐变底图 ----
# ImageMagick 的 gradient: 只支持两端线性渐变，故用 4 段拼接后垂直堆叠，
# 每段高度按 SVG 的 stop 偏移（0% / 42% / 78% / 100%）计算。
S1=$(( H * 42 / 100 ))
S2=$(( H * 78 / 100 ))
S3=$(( H ))
convert -size "${W}x${S1}" gradient:'#0A3568-#1A6FD4' png24:"$TMP.1"
convert -size "${W}x$(( S2 - S1 ))" gradient:'#1A6FD4-#EAF2FF' png24:"$TMP.2"
convert -size "${W}x$(( S3 - S2 ))" gradient:'#EAF2FF-#FFFFFF' png24:"$TMP.3"
convert "$TMP.1" "$TMP.2" "$TMP.3" -append +repage png24:"$TMP"
rm -f "$TMP.1" "$TMP.2" "$TMP.3"

# ---- 阶段 2：叠加元素 ----
DRAW=$(python3 - "$W" "$H" "$BOLD" "$CJK" <<'PY'
import sys
W, H, BOLD, CJK = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
W, H = int(W), int(H)
S = W / 1920.0

parts = []

def paw(fill, opacity, tx, ty, scale):
    cmds = ["push graphic-context"]
    cmds.append("fill %s fill-opacity %s" % (fill, opacity))
    cmds.append("translate %.2f,%.2f scale %.5f,%.5f" % (tx*S, ty*S, scale*S, scale*S))
    cmds.append('path "M 128 150 c 32 0 58 21 58 45 c 0 16 -15 27 -33 27 h -50 '
                'c -18 0 -33 -11 -33 -27 c 0 -24 26 -45 58 -45 z"')
    for (cx, cy, rx, ry) in [(50,108,25,32),(97,62,24,32),(159,62,24,32),(206,108,25,32)]:
        cmds.append("ellipse %d,%d %d,%d 0,360" % (cx, cy, rx, ry))
    cmds.append("pop graphic-context")
    return " ".join(cmds)

parts.append(paw('#1A6FD4', 0.07, 1500, 700, 2.2))
parts.append(paw('#1A6FD4', 0.05, 120, 120, 1.6))
parts.append(paw('#FFFFFF', 0.96, 810, 300, 1.0))

# 字标/副标语/进度条的颜色必须与 furryos-splash.svg 同步：
#   y=700 处渐变已是浅蓝 (157,193,239)，白字只有 1.8:1 → 用 furryos-blue-deep
#   副标语 #0F4C8C（5.2:1）
#   进度条 #1A6FD4（y=903 处背景 ≈ (239,245,255)，4.5:1）
parts.append(
    "push graphic-context fill #0A3568 font \"%s\" font-size %.2f gravity center "
    "text 0,%.2f \"FurryOS\" pop graphic-context"
    % (BOLD, 96*S, (700-540)*S)
)
parts.append(
    "push graphic-context fill #0F4C8C font \"%s\" font-size %.2f gravity center "
    "text 0,%.2f \"蓝白之间，轻快回应\" pop graphic-context"
    % (CJK, 30*S, (762-540)*S)
)
parts.append(
    "push graphic-context fill #1A6FD4 fill-opacity 0.18 "
    "rectangle %.2f,%.2f %.2f,%.2f "
    "fill #1A6FD4 fill-opacity 1.0 "
    "rectangle %.2f,%.2f %.2f,%.2f "
    "pop graphic-context"
    % (660*S, 900*S, 1260*S, 906*S, 660*S, 900*S, 900*S, 906*S)
)

print(" ".join(parts))
PY
)

convert "$TMP" -draw "$DRAW" "png24:$OUT"
echo "wrote $OUT (${W}x${H})"
