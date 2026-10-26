#!/bin/sh
# FurryOS Plymouth 主题 —— 生成 spinner 帧图
#
# furryos.script 引用 images/spinner/spinner{0,10,...,360}.png（37 帧）。
# 上游 breeze 主题用等离子色弧线；FurryOS 用 furryos-blue #1A6FD4 的
# 细圆弧（与点击特效涟漪同色，视觉统一）。16bit 降级目录用 64px 小图。
#
# 用法：./gen-spinner.sh    （在 furryos-plymouth/ 目录下执行）

set -eu

cd "$(dirname "$0")"

SIZE=${SIZE:-96}
OUT="images/spinner"
OUT16="images/spinner-16"
mkdir -p "$OUT" "$OUT16"

# furryos-blue #1A6FD4
BLUE="#1A6FD4"

for i in $(seq 0 10 360); do
    # 用 ImageMagick 画一段随角度旋转的圆弧（-36° 弧长，形成「彗星尾」感）
    M=$(( SIZE / 6 ))
    E=$(( SIZE * 5 / 6 ))
    SW=$(( SIZE / 12 ))
    convert -size "${SIZE}x${SIZE}" xc:none \
        -stroke "$BLUE" -strokewidth "$SW" -fill none \
        -draw "stroke-linecap round arc ${M},${M} ${E},${E} 0,360" \
        -rotate "$i" \
        "png32:$OUT/spinner${i}.png"

    convert "$OUT/spinner${i}.png" -resize 64x64 "png32:$OUT16/spinner${i}.png"
done

echo "generated $(ls "$OUT" | wc -l) frames in $OUT and $OUT16"
