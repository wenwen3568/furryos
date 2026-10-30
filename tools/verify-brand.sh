#!/bin/bash
#
# verify-brand.sh — 一键品牌自检。
#
# 把「不需要已构建系统就能跑」的校验脚本串起来，按层输出汇总：
#
#   1. 系统身份层   tools/verify-identity.sh       /etc/os-release、issue、motd、ssh 横幅…
#   2. 桌面视觉层   assets/desktop/.tools/verify-all.py
#                   → verify-colors.py / verify-wallpaper.py / verify-consistency.py
#   3. 启动画面     assets/effects/splash/verify-splash-pixels.py
#   4. SDDM QML     qmllint（宿主装了 Qt 才跑，缺了跳过而不是失败）
#
# 这是「改了资产/钩子后先自检一遍」的入口；针对已构建系统的验收（文件是否
# 真的进了镜像）见 docs/BUILD.md 第 6 节的验收清单。
#
# 用法：
#   bash tools/verify-brand.sh              # 需要联网取上游参考包时会自动取
#   bash tools/verify-brand.sh --no-fetch   # 只用本地缓存的参考包
#
# 退出码：0 = 全部通过；1 = 有失败项（汇总在最后）。

set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="$(cd "${SELF_DIR}/.." && pwd)"

FAIL=0
SKIP=0
FAILED_NAMES=""

run () {  # run <名称> <命令...>
	_name="$1"; shift
	printf '\n=== %s\n' "${_name}"
	if "$@"; then
		printf '[PASS] %s\n' "${_name}"
	else
		printf '[FAIL] %s\n' "${_name}"
		FAIL=$((FAIL + 1))
		FAILED_NAMES="${FAILED_NAMES}${FAILED_NAMES:+, }${_name}"
	fi
}

skip () {  # skip <名称> <原因>
	printf '\n=== %s\n[SKIP] %s（%s）\n' "$1" "$1" "$2"
	SKIP=$((SKIP + 1))
}

# 1. 系统身份层（33 项断言）
run "系统身份层 verify-identity.sh" bash "${WS}/tools/verify-identity.sh" "$@"

# 2. 桌面视觉层：配色 / 壁纸 / 一致性
if command -v python3 >/dev/null 2>&1; then
	run "桌面视觉层 verify-all.py" python3 "${WS}/assets/desktop/.tools/verify-all.py"
else
	skip "桌面视觉层 verify-all.py" "缺少 python3"
fi

# 3. 启动画面像素抽查
if command -v python3 >/dev/null 2>&1; then
	run "启动画面 verify-splash-pixels.py" \
		python3 "${WS}/assets/effects/splash/verify-splash-pixels.py"
else
	skip "启动画面 verify-splash-pixels.py" "缺少 python3"
fi

# 4. SDDM 主题的 QML 语法（qmllint 是 Qt 自带的，宿主机不一定装）
if command -v qmllint >/dev/null 2>&1; then
	run "SDDM QML 语法 qmllint" bash -c '
		set -e
		cd "$1"
		qmllint Main.qml components/*.qml
	' _ "${WS}/assets/sddm/furryos"
else
	skip "SDDM QML 语法 qmllint" "宿主未安装 qmllint（apt-get install qtdeclarative5-dev-tools）"
fi

printf '\n=== 汇总 ===\n'
if [ "${FAIL}" -eq 0 ]; then
	printf '全部通过（%d 项检查，%d 项跳过）\n' "$((4 - SKIP))" "${SKIP}"
	exit 0
fi
printf '失败 %d 项：%s（%d 项跳过）\n' "${FAIL}" "${FAILED_NAMES}" "${SKIP}"
exit 1
