#!/bin/sh
# FurryOS 交互动效层 —— 启动画面（Plymouth + KSplash）系统级安装脚本
#
# 安装内容：
#   1. Plymouth 主题 furryos-plymouth/ → /usr/share/plymouth/themes/furryos/
#      - 需要 plymouth 包（initramfs 阶段）
#      - plymouth-set-default-theme furryos
#      - update-initramfs -u（重建 initramfs，否则主题不生效）
#      - 内核命令行需含 splash 参数（live-build 的 --bootappend-live 或
#        config/bootloaders/isolinux 中的 append 行）
#   2. KSplash / Look and Feel 主题 furryos-ksplash/ →
#      /usr/share/plasma/look-and-feel/org.furryos.desktop/
#      - plasma-workspace-data 提供 ksplashqml，已有 kde-plasma-desktop 依赖
#      - contents/defaults 的 [KSplash] Theme=org.furryos.desktop
#        让新用户首次登录时自动使用 FurryOS 启动画面
#      - contents/defaults 的 ColorScheme=FurryOS 需要配色方案文件
#        （由桌面视觉层提供；本脚本只负责 KSplash 部分）
#
# 用法：
#   ./effects-splash-install.sh [--prefix DIR]
#     --prefix DIR  安装到 DIR（默认 /），用于构建期/测试
#     --initramfs   额外执行 update-initramfs -u（真实系统；默认不执行，
#                   因为 live-build 会自己构建 initramfs）
#
# 退出码：0 成功；1 参数错误；2 缺少必要命令。

set -eu

PREFIX=""
DO_INITRAMFS=0

log() { printf '[furryos-splash] %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { log "ERROR: --prefix 需要参数"; exit 1; }
            PREFIX="$2"; shift 2 ;;
        --initramfs)
            DO_INITRAMFS=1; shift ;;
        -h|--help )
            sed -n '2,40p' "$0"; exit 0 ;;
        * )
            log "ERROR: unknown option: $1"; exit 1 ;;
    esac
done

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------- 1. Plymouth 主题 ----------------
install_plymouth() {
    dest="${PREFIX}/usr/share/plymouth/themes/furryos"
    if [ ! -d "$SRC_DIR/furryos-plymouth" ]; then
        log "WARNING: $SRC_DIR/furryos-plymouth 不存在，跳过 Plymouth 主题"
        return 0
    fi
    mkdir -p "$dest"
    cp -a "$SRC_DIR/furryos-plymouth/." "$dest/"
    log "installed plymouth theme → $dest"

    if [ -z "$PREFIX" ]; then
        if command -v plymouth-set-default-theme >/dev/null 2>&1; then
            plymouth-set-default-theme furryos && log "plymouth-set-default-theme furryos OK"
        else
            log "WARNING: plymouth-set-default-theme 未找到（plymouth 未安装），"
            log "         Plymouth 启动画面不可用；KSplash 仍会生效。"
        fi
        if [ "$DO_INITRAMFS" -eq 1 ]; then
            if command -v update-initramfs >/dev/null 2>&1; then
                update-initramfs -u && log "update-initramfs -u OK"
            else
                log "WARNING: update-initramfs 未找到，请手动重建 initramfs"
            fi
        else
            log "NOTE: 未传 --initramfs，未重建 initramfs。"
            log "      若 plymouth 主题未生效，请执行: sudo update-initramfs -u"
        fi
    fi
}

# ---------------- 2. KSplash / Look and Feel 主题 ----------------
install_ksplash() {
    dest="${PREFIX}/usr/share/plasma/look-and-feel/org.furryos.desktop"
    if [ ! -d "$SRC_DIR/furryos-ksplash" ]; then
        log "WARNING: $SRC_DIR/furryos-ksplash 不存在，跳过 KSplash 主题"
        return 0
    fi
    mkdir -p "$dest"
    cp -a "$SRC_DIR/furryos-ksplash/." "$dest/"
    log "installed look-and-feel (KSplash) theme → $dest"
}

install_plymouth
install_ksplash

cat <<EOF

[furryos-splash] 安装完成。生效条件核对：
  1) Plymouth 启动画面（开机到显示管理器之前）
     - 主题目录: ${PREFIX}/usr/share/plymouth/themes/furryos/
     - 默认主题: ${PREFIX}/etc/plymouth/plymouthd.conf 中 DefaultTheme=furryos
       （plymouth-set-default-theme furryos 会写入此项）
     - initramfs 已包含该主题（plymouth 主题不进 initramfs 则不显示：
       执行 sudo update-initramfs -u）
     - 内核命令行含 splash（GRUB 的 linux 行 append ... splash）
  2) KSplash 启动画面（登录后到桌面就绪）
     - 主题目录: ${PREFIX}/usr/share/plasma/look-and-feel/org.furryos.desktop/
     - 用户默认值: /etc/skel/.config/... 由 contents/defaults 写入
       [KSplash] Theme=org.furryos.desktop（KPackage 会在用户首次登录时应用）
EOF
