#!/bin/sh
# FurryOS 交互动效层 —— 点击特效启用状态确认脚本
#
# 输出「启用了什么 / 在哪里确认 / 结果如何」。
# 退出码：0 = 已启用（含通过系统级默认对新用户生效）；1 = 未启用或显式关闭。
#
# 判定语义（KConfig 优先级：用户配置 > /etc/xdg 系统默认 > 编译默认）：
#   1. 用户 ~/.config/kwinrc [Plugins] mouseclickEnabled 存在 → 以它为准
#      （true=启用；false=用户手动关闭 → 判失败，需用户重新打开）
#      ★ 这是 KWin 5.27 唯一权威的开关键（依据见 kwinrc-effects.conf 注释）
#   2. 用户配置无该键 → 看 /etc/xdg/kwinrc（系统级默认）
#   3. 两者都无该键 → 未启用
#   4. /etc/skel/.config/kwinrc 决定「新用户首次登录」是否启用
#   5. kdeglobals [Effects] Click 是 Plasma 兼容层键；KWin 5.27 不读它，
#      此处仅作「双保险」呈现，**不作为生效判据**
#   6. 运行时（需 Plasma 会话）：qdbus 查询 KWin 已加载特效列表
#
# 手动确认命令（任选其一，第一条是权威判据）：
#   grep -A2 '^\[Plugins\]' ~/.config/kwinrc | grep mouseclickEnabled
#   grep -A2 '^\[Effects\]' ~/.config/kdeglobals | grep '^Click='   # 兼容层，非权威
#   qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects

# 用法：
#   ./effects-verify.sh                 # 检查真实系统
#   PREFIX=/path/to/root ./effects-verify.sh   # 检查构建产物/测试前缀
#
# 环境变量：
#   PREFIX  构建前缀（如 live-build 的 chroot 根）；留空则检查真实 /
#   HOME    用户主目录；留空则用当前用户

rc=0
user_override=0
PREFIX="${PREFIX:-}"

read_key() {
    # $1 = 文件路径  $2 = 段名  $3 = 键名 → stdout 输出值（无值则空）
    [ -f "$1" ] || return 0
    awk -v grp="[$2]" -v key="$3" '
        $0 == grp { in_grp = 1; next }
        /^\[/ { in_grp = 0 }
        in_grp && index($0, key"=") == 1 { sub("^"key"=", ""); print; exit }
    ' "$1"
}

report() {
    # $1 = 文件  $2 = 段  $3 = 键  $4 = 标签
    f="$1"; grp="$2"; key="$3"; label="$4"
    if [ ! -f "$f" ]; then
        printf '  [--] %-46s 文件不存在\n' "$label"
        return 2
    fi
    val=$(read_key "$f" "$grp" "$key")
    if [ -z "$val" ]; then
        printf '  [--] %-46s 键缺失\n' "$label"
        return 2
    fi
    if [ "$val" = "true" ]; then
        printf '  [OK] %-46s = true\n' "$label"
        return 0
    fi
    printf '  [XX] %-46s = %s（被显式关闭）\n' "$label" "$val"
    return 1
}

echo "=== FurryOS 点击特效启用状态检查 ==="

echo
echo "--- [1] 用户配置（最终生效值，优先级最高） ---"
UK="${HOME:-/root}/.config/kwinrc"
UD="${HOME:-/root}/.config/kdeglobals"
uv=0
if [ -f "$UK" ] && [ -n "$(read_key "$UK" Plugins mouseclickEnabled)" ]; then
    report "$UK" Plugins mouseclickEnabled "kwinrc [Plugins] mouseclickEnabled" || uv=1
    user_override=1
else
    printf '  [--] %-46s 未设置（回落到系统级默认）\n' "kwinrc [Plugins] mouseclickEnabled"
fi
if [ -f "$UD" ] && [ -n "$(read_key "$UD" Effects Click)" ]; then
    report "$UD" Effects Click "kdeglobals [Effects] Click" || uv=1
else
    printf '  [--] %-46s 未设置（回落到系统级默认）\n' "kdeglobals [Effects] Click"
fi

echo
echo "--- [2] 系统级默认 /etc/xdg（用户未设置时对新/老用户生效） ---"
xk=0
report "$PREFIX/etc/xdg/kwinrc" Plugins mouseclickEnabled "/etc/xdg/kwinrc mouseclickEnabled" || xk=1
report "$PREFIX/etc/xdg/kdeglobals" Effects Click "/etc/xdg/kdeglobals Click" || xk=1

echo
echo "--- [3] 新用户模板 /etc/skel（首次登录时复制到 ~/.config） ---"
sk=0
report "$PREFIX/etc/skel/.config/kwinrc" Plugins mouseclickEnabled "/etc/skel/.config/kwinrc mouseclickEnabled" || sk=1
report "$PREFIX/etc/skel/.config/kdeglobals" Effects Click "/etc/skel/.config/kdeglobals Click" || sk=1

echo
echo "--- [4] 运行时状态（需在 Plasma 会话中执行） ---"
if command -v qdbus >/dev/null 2>&1 && qdbus org.kde.KWin /KWin org.kde.KWin.listOfEffects >/dev/null 2>&1; then
    if qdbus org.kde.KWin /KWin org.kde.KWin.listOfEffects 2>/dev/null | tr ',' '\n' | grep -qx mouseclick; then
        echo "  [OK] KWin 已知特效包含 mouseclick"
    else
        echo "  [XX] KWin 已知特效中不含 mouseclick（kwin 未安装/版本不符）"
        rc=1
    fi
    if qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects 2>/dev/null | tr ',' '\n' | grep -qx mouseclick; then
        echo "  [OK] mouseclick 已加载 —— 桌面点击即可见涟漪反馈"
    else
        echo "  [!!] mouseclick 未加载（配置已写；需注销重登或检查 compositing 是否开启）"
    fi
else
    echo "  [--] 当前不在 Plasma 会话或无 qdbus，跳过"
    echo "       登录后执行: qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects"
fi

echo
echo "=== 结论 ==="
if [ "$user_override" -eq 1 ]; then
    if [ "$uv" -eq 0 ]; then
        echo "已启用：用户配置显式开启（最终生效值）。"
    else
        echo "未启用：用户配置显式关闭。请在 系统设置 → 工作空间行为 → 桌面特效"
        echo "        勾选 Mouse Click Animation，或执行:"
        echo "        kwriteconfig5 --file kwinrc --group Plugins --key mouseclickEnabled true"
        rc=1
    fi
else
    if [ "$xk" -eq 0 ]; then
        echo "已启用：通过 /etc/xdg 系统级默认生效（用户未覆盖）。"
    elif [ "$sk" -eq 0 ]; then
        echo "已启用（仅新用户）：/etc/skel 已预置，首次登录后生效。"
        echo "        现有用户需执行: kwriteconfig5 --file kwinrc --group Plugins --key mouseclickEnabled true"
    else
        echo "未启用：用户配置、系统级默认、新用户模板均未开启。"
        rc=1
    fi
fi
exit "$rc"
