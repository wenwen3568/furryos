#!/bin/sh
# FurryOS SDDM 主题安装脚本
# ------------------------------------------------------------------
# 用途：把 assets/sddm/furryos 安装为系统 SDDM 主题，并写入 /etc/sddm.conf。
# 调用方：live-build 的 config/hooks/*.chroot（在 chroot 内以 root 执行），
#         或镜像构建完成后手动执行。
#
# 用法：install-sddm-theme.sh <主题源目录> [目标根前缀]
#   <主题源目录>   含 Main.qml / metadata.desktop / components/ 的目录
#                  （即本文件同级的 furryos/）
#   [目标根前缀]   可选，默认为 / ；用于 live-build chroot 场景传 $1
#
# 幂等：可重复执行，重复执行会先清理旧副本。
set -eu

SRC="${1:-}"
PREFIX="${2:-/}"

# sddm.conf 的唯一真源：本脚本同级的 sddm.conf（成员三维护）。
# 早期版本在这里硬编码了一份精简模板，导致
#   assets/sddm/sddm.conf        有 CursorTheme=Breeze_Snow
#   安装器写出的 /etc/sddm.conf  没有该键
# 两条路径产出的配置不一致，而构建走的正是安装器这条。现在统一为
# 「有资产文件就照抄，没有才退回内置模板」。
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_ASSET="$SELF_DIR/sddm.conf"

if [ -z "$SRC" ] || [ ! -f "$SRC/Main.qml" ]; then
    echo "用法: $0 <主题源目录(含 Main.qml)> [目标根前缀]" >&2
    exit 1
fi

THEME_NAME="furryos"
DEST="${PREFIX%/}/usr/share/sddm/themes/${THEME_NAME}"
CONF="${PREFIX%/}/etc/sddm.conf"

echo "[furryos-sddm] 安装主题到 $DEST"
mkdir -p "${PREFIX%/}/usr/share/sddm/themes"
rm -rf "$DEST"
mkdir -p "$DEST"
# 复制主题全部内容（Main.qml, metadata.desktop, theme.conf, components/, assets/）
cp -a "$SRC/." "$DEST/"

# 权限：主题文件需可被 sddm 用户读取
chmod -R a+rX "$DEST"

# ---- 写入 /etc/sddm.conf ----
echo "[furryos-sddm] 写入 $CONF (Current=${THEME_NAME})"
mkdir -p "${PREFIX%/}/etc"
if [ -f "$CONF_ASSET" ]; then
    # 照抄层资产，保证 /etc/sddm.conf 与 assets/sddm/sddm.conf 逐字节一致
    install -m 0644 "$CONF_ASSET" "$CONF"
else
    cat > "$CONF" <<'EOF'
# FurryOS SDDM 配置（由 FurryOS 登录体验层生成）
[Theme]
Current=furryos
ThemeDir=/usr/share/sddm/themes
CursorTheme=Breeze_Snow

[General]
Numlock=on
EOF
fi

echo "[furryos-sddm] 完成。生效需要重启 SDDM: systemctl restart sddm"
