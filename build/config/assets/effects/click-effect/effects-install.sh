#!/bin/sh
# FurryOS 交互动效层 —— 点击特效系统级默认配置注入脚本
#
# 目标：让「新用户首次登录后点击特效即处于启用状态」，以及「安装后无需手动开启」。
#
# 三条注入路径（按可靠性排序）：
#   A. /etc/skel/.config/kwinrc
#      —— 新用户首登生效（live-build 的 config/includes.chroot/etc/skel/ 注入）。
#      写入 [Plugins] mouseclickEnabled=true + [Effect-mouseclick] 配色段。
#      ★ 注意：/etc/skel/.config/kdeglobals 的唯一负责人是桌面视觉层（成员二），
#        本脚本只写 skel/kwinrc；kdeglobals 段由成员二合并，脚本只做
#        「缺失则补 [Effects] Click=true」的兜底，不覆盖已有内容。
#   B. 系统级默认（对所有用户，包括已存在用户）：
#      /etc/xdg/kwinrc（XDG 系统配置目录，优先级低于用户配置但高于编译默认值）。
#      KConfig 会把 /etc/xdg 当作系统级默认，当用户从未设置过该键时读取
#      /etc/xdg 的值。同时写 /etc/xdg/kdeglobals 的 [Effects] Click 作兼容层兜底。
#   C. 安装型即时生效（面向已装好的 FurryOS 或 Live 会话）：
#      用 kwriteconfig5 写入当前用户的 kwinrc，然后 qdbus 通知 KWin 重载。
#
# ★ 生效权威依据（已用 deb 反查 + kwin 源码双重验证）：
#   kwin 源码 src/effect/effectloader.cpp:56-58
#     KConfigGroup plugins(m_config, QStringLiteral("Plugins"));
#     const QString key = effectName + QStringLiteral("Enabled");
#   m_config 来自 src/main.cpp:83 → openConfig("kwinrc")；
#   effecthandler.cpp:131 → setConfig(kwinApp()->config())，仍是 kwinrc。
#   反查 libkwin.so.5.27.11 utf16 字符串：kdeglobals 只用于
#   Colors:Window / wayland / localhost 三组，**没有 [Effects] 组或 Click 键**。
#   ⇒ KWin 5.27 读 kwinrc [Plugins] mouseclickEnabled，不读 kdeglobals [Effects] Click。
#     因此本脚本把 [Effect-mouseclick] 外观段也写入 kwinrc（kwin_mouseclick_config.so
#     的 utf16 字符串同时含 "Effect-mouseclick" 和 "kwinrc"），并同时写 kdeglobals
#     作双保险。
#
# 用法：
#   chmod +x effects-install.sh
#   ./effects-install.sh            # 注入 A+B（构建期/安装期）
#   ./effects-install.sh --live     # 额外对当前用户写入并即时重载（C）
#
# 退出码：0 成功；1 参数错误；2 缺少依赖（仅 --live 模式检查）。

set -eu

PREFIX="${PREFIX:-}"

log() { printf '[furryos-effects] %s\n' "$*"; }

inject_skel() {
    skel="${PREFIX}/etc/skel/.config"
    mkdir -p "$skel"

    # --- A1: skel kwinrc ---
    if [ -f "$skel/kwinrc" ]; then
        if ! grep -q '^\[Plugins\]' "$skel/kwinrc"; then
            printf '\n[Plugins]\nmouseclickEnabled=true\n' >> "$skel/kwinrc"
        else
            # 段已存在：确保键存在且为 true
            if grep -q '^mouseclickEnabled=' "$skel/kwinrc"; then
                sed -i 's/^mouseclickEnabled=.*/mouseclickEnabled=true/' "$skel/kwinrc"
            else
                sed -i '0,/^\[Plugins\]/s//[Plugins]\nmouseclickEnabled=true/' "$skel/kwinrc"
            fi
        fi
    else
        printf '[Plugins]\nmouseclickEnabled=true\n' > "$skel/kwinrc"
    fi
    log "wrote $skel/kwinrc ([Plugins] mouseclickEnabled=true)"

    # --- A2: skel kdeglobals ---
    # 注意：kdeglobals 的唯一负责人是桌面视觉层。若该文件尚不存在，
    # 这里只创建「最小可用」的 [Effects] 段，避免与成员二的合并冲突；
    # 若已存在，则只追加缺失的 [Effects] 段，不触碰其他段。
    if [ -f "$skel/kdeglobals" ]; then
        if ! grep -q '^\[Effects\]' "$skel/kdeglobals"; then
            printf '\n[Effects]\nClick=true\n' >> "$skel/kdeglobals"
            log "appended [Effects] Click=true to existing $skel/kdeglobals"
        else
            if grep -q '^Click=' "$skel/kdeglobals"; then
                sed -i 's/^Click=.*/Click=true/' "$skel/kdeglobals"
            else
                sed -i '0,/^\[Effects\]/s//[Effects]\nClick=true/' "$skel/kdeglobals"
            fi
            log "ensured Click=true in existing $skel/kdeglobals"
        fi
    else
        printf '[Effects]\nClick=true\n' > "$skel/kdeglobals"
        log "created $skel/kdeglobals with [Effects] Click=true (minimal, for desktop-visual to extend)"
    fi

    # --- A3: skel 内特效外观（爪印蓝配色）——写入 kwinrc（外观权威位置）---
    if ! grep -q '^\[Effect-mouseclick\]' "$skel/kwinrc" 2>/dev/null; then
        printf '\n[Effect-mouseclick]\nColor1=26,111,212\nColor2=15,76,140\nColor3=10,53,104\nLineWidth=3\nRingCount=2\nRingLife=250\nRingSize=32\nShowText=false\n' >> "$skel/kwinrc"
        log "appended [Effect-mouseclick] palette to $skel/kwinrc"
    fi
    # A4: 同时在 kdeglobals 写一份外观段作双保险（kwin 的 KCM 引用两个文件）
    if [ -f "$skel/kdeglobals" ] && ! grep -q '^\[Effect-mouseclick\]' "$skel/kdeglobals" 2>/dev/null; then
        printf '\n[Effect-mouseclick]\nColor1=26,111,212\nColor2=15,76,140\nColor3=10,53,104\nLineWidth=3\nRingCount=2\nRingLife=250\nRingSize=32\nShowText=false\n' >> "$skel/kdeglobals"
        log "appended [Effect-mouseclick] palette to $skel/kdeglobals (compat)"
    fi
}

inject_xdg() {
    xdg="${PREFIX}/etc/xdg"
    mkdir -p "$xdg"

    # B1: /etc/xdg/kwinrc —— 系统级默认，用户未设置时生效
    if [ -f "$xdg/kwinrc" ]; then
        if ! grep -q '^\[Plugins\]' "$xdg/kwinrc"; then
            printf '\n[Plugins]\nmouseclickEnabled=true\n' >> "$xdg/kwinrc"
        else
            if grep -q '^mouseclickEnabled=' "$xdg/kwinrc"; then
                sed -i 's/^mouseclickEnabled=.*/mouseclickEnabled=true/' "$xdg/kwinrc"
            else
                sed -i '0,/^\[Plugins\]/s//[Plugins]\nmouseclickEnabled=true/' "$xdg/kwinrc"
            fi
        fi
    else
        printf '[Plugins]\nmouseclickEnabled=true\n' > "$xdg/kwinrc"
    fi
    log "wrote $xdg/kwinrc ([Plugins] mouseclickEnabled=true)"

    # B2: /etc/xdg/kdeglobals —— 系统级默认的 [Effects] Click（兼容层兜底）
    if [ -f "$xdg/kdeglobals" ]; then
        if ! grep -q '^\[Effects\]' "$xdg/kdeglobals"; then
            printf '\n[Effects]\nClick=true\n' >> "$xdg/kdeglobals"
        else
            if grep -q '^Click=' "$xdg/kdeglobals"; then
                sed -i 's/^Click=.*/Click=true/' "$xdg/kdeglobals"
            else
                sed -i '0,/^\[Effects\]/s//[Effects]\nClick=true/' "$xdg/kdeglobals"
            fi
        fi
    else
        printf '[Effects]\nClick=true\n' > "$xdg/kdeglobals"
    fi
    log "wrote $xdg/kdeglobals ([Effects] Click=true, compat layer)"

    # B3: /etc/xdg/kwinrc 外观配色（权威位置）
    if ! grep -q '^\[Effect-mouseclick\]' "$xdg/kwinrc" 2>/dev/null; then
        printf '\n[Effect-mouseclick]\nColor1=26,111,212\nColor2=15,76,140\nColor3=10,53,104\nLineWidth=3\nRingCount=2\nRingLife=250\nRingSize=32\nShowText=false\n' >> "$xdg/kwinrc"
        log "appended [Effect-mouseclick] palette to $xdg/kwinrc"
    fi
}

apply_live() {
    # C: 对当前用户即时写入并重载（需要 Plasma 会话）
    if ! command -v kwriteconfig5 >/dev/null 2>&1; then
        log "WARNING: kwriteconfig5 未找到，跳过 --live 即时生效（降级：重启后由 skel/xdg 生效）"
        return 0
    fi
    if ! command -v qdbus >/dev/null 2>&1; then
        log "WARNING: qdbus 未找到，跳过 KWin 重载（重启后生效）"
        return 0
    fi
    kwriteconfig5 --file kwinrc --group Plugins --key mouseclickEnabled true
    kwriteconfig5 --file kdeglobals --group Effects --key Click true
    # 外观配色写入 kwinrc（权威位置）；kdeglobals 同时写一份作兼容
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key Color1 "26,111,212"
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key Color2 "15,76,140"
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key Color3 "10,53,104"
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key LineWidth 3
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key RingCount 2
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key RingLife 250
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key RingSize 32
    kwriteconfig5 --file kwinrc --group Effect-mouseclick --key ShowText false
    kwriteconfig5 --file kdeglobals --group Effect-mouseclick --key Color1 "26,111,212"
    kwriteconfig5 --file kdeglobals --group Effect-mouseclick --key Color2 "15,76,140"
    kwriteconfig5 --file kdeglobals --group Effect-mouseclick --key Color3 "10,53,104"
    kwriteconfig5 --file kdeglobals --group Effect-mouseclick --key LineWidth 3
    kwriteconfig5 --file kdeglobals --group Effect-mouseclick --key RingCount 2
    kwriteconfig5 --file kdeglobals --group Effect-mouseclick --key RingLife 250
    kwriteconfig5 --file kdeglobals --group Effect-mouseclick --key RingSize 32
    log "live config written for user $(id -un)"

    # 通知 KWin 重载配置
    if qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1; then
        log "KWin reconfigure signal sent"
    else
        log "NOTE: KWin reconfigure 失败（可能不在 Plasma 会话中），注销重登即可生效"
    fi
}

MODE="${1:-}"
case "$MODE" in
    "" )
        inject_skel
        inject_xdg
        ;;
    --live )
        inject_skel
        inject_xdg
        apply_live
        ;;
    -h|--help )
        sed -n '2,40p' "$0"
        exit 0
        ;;
    * )
        log "ERROR: unknown option: $MODE"
        exit 1
        ;;
esac

log "done"
