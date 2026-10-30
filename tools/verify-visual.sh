#!/bin/bash
#
# verify-visual.sh — FurryOS 视觉统一的一键验收。
#
# 它按「越接近真实运行时越靠后」的顺序跑六件事：
#   1. qmllint            —— QML 语法/未定义引用（登录界面 + 全部组件）
#   2. qmlscene 探针      —— 真实例化组件树，读运行时属性值（颜色/时长/尺寸）
#   3. plasma 主题真实应用 —— 在沙箱 XDG 目录里用 plasma-apply-desktoptheme /
#                            plasma-apply-lookandfeel 真跑一次，看 KDE 自己
#                            写出来的 kdedefaults 是不是 FurryOS
#   4. verify-visual.py   —— 跨四层静态一致性 + 渲染预览的像素断言
#   5. verify-splash-pixels.py —— 启动画面母版的 18 项像素校验
#   6. verify-consistency.py   —— 配色方案 / skel / 全局主题三方一致
#
# 用法：bash tools/verify-visual.sh [--render]
#   --render  先跑 tools/render-previews.sh 重新渲染 docs/preview/
# 退出码：0 = 全通过；1 = 有失败
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="$(cd "${SELF_DIR}/.." && pwd)"
TMP="$(mktemp -d /tmp/furryos-visual.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

FAILED=0
declare -a SUMMARY=()

note() { printf '%s\n' "$*"; }
ok()   { note "  [PASS] $*"; SUMMARY+=("PASS  $*"); }
bad()  { note "  [FAIL] $*"; SUMMARY+=("FAIL  $*"); FAILED=1; }

DO_RENDER=0
[ "${1:-}" = "--render" ] && DO_RENDER=1

note "=========================================================="
note " FurryOS 视觉统一验收（工作区 ${WS}）"
note "=========================================================="

# ---------------------------------------------------------------- 0. 渲染
if [ "${DO_RENDER}" = "1" ] || [ ! -f "${WS}/docs/preview/sddm-login-1600x900.png" ]; then
	note ""
	note "== [0] 渲染预览到 docs/preview/ =="
	if bash "${WS}/tools/render-previews.sh" >"${TMP}/render.log" 2>&1; then
		ok "预览渲染完成（6 张 PNG）"
	else
		tail -20 "${TMP}/render.log"
		bad "预览渲染失败"
	fi
fi

# ---------------------------------------------------------------- 1. qmllint
note ""
note "== [1] qmllint（登录界面 + 组件） =="
SDDM_DIR="${WS}/assets/sddm/furryos"
if command -v qmllint >/dev/null 2>&1; then
	QML_FILES=("${SDDM_DIR}/Main.qml")
	while IFS= read -r f; do QML_FILES+=("$f"); done < <(ls "${SDDM_DIR}"/components/*.qml)
	if qmllint -I "${SDDM_DIR}/components" "${QML_FILES[@]}" >"${TMP}/qmllint.log" 2>&1; then
		if [ -s "${TMP}/qmllint.log" ]; then
			cat "${TMP}/qmllint.log"
			bad "qmllint 有输出（应为空）"
		else
			ok "qmllint ${#QML_FILES[@]} 个文件无任何输出"
		fi
	else
		cat "${TMP}/qmllint.log"
		bad "qmllint 执行失败"
	fi
else
	note "  SKIP: 宿主没有 qmllint"
fi

# ---------------------------------------------------------------- 2. 探针
note ""
note "== [2] qmlscene 探针：实例化组件树读运行时属性 =="
if command -v qmlscene >/dev/null 2>&1; then
	export XDG_RUNTIME_DIR="${TMP}/runtime"
	mkdir -p "${XDG_RUNTIME_DIR}"
	chmod 700 "${XDG_RUNTIME_DIR}"
	QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
		timeout 120 qmlscene "${WS}/tools/preview/probe-sddm.qml" \
		>"${TMP}/probe.log" 2>&1
	if grep -q "PROBE-JSON:" "${TMP}/probe.log"; then
		grep -m1 "PROBE-JSON:" "${TMP}/probe.log" \
			| sed 's/^.*PROBE-JSON://' > "${TMP}/probe.json"
		ok "探针输出解析成功（$(wc -c < "${TMP}/probe.json") 字节 JSON）"
	else
		tail -20 "${TMP}/probe.log"
		bad "探针未输出 PROBE-JSON"
	fi
else
	note "  SKIP: 宿主没有 qmlscene"
fi

# ---------------------------------------------------------------- 3. plasma 真应用
note ""
note "== [3] 在沙箱里真跑 plasma-apply-*，看 KDE 写出的 kdedefaults =="
SANDBOX="${TMP}/sandbox"
mkdir -p "${SANDBOX}/share/plasma/look-and-feel" "${SANDBOX}/share/plasma/desktoptheme" \
	"${SANDBOX}/share/color-schemes" "${SANDBOX}/share/wallpapers" "${SANDBOX}/share/icons" \
	"${SANDBOX}/config"
cp -a "${WS}/assets/desktop/look-and-feel/com.furryos.lookandfeel" \
	"${SANDBOX}/share/plasma/look-and-feel/"
cp -a "${WS}/assets/desktop/plasma-theme/furryos" "${SANDBOX}/share/plasma/desktoptheme/"
cp -a "${WS}/assets/desktop/wallpapers/FurryOS" "${SANDBOX}/share/wallpapers/"
cp -a "${WS}/assets/desktop/icons/FurryOS" "${SANDBOX}/share/icons/"
cp "${WS}/assets/desktop/FurryOS.colors" "${SANDBOX}/share/color-schemes/"

export QT_QPA_PLATFORM=offscreen
export XDG_DATA_HOME="${SANDBOX}/share"
export XDG_CONFIG_HOME="${SANDBOX}/config"

if command -v plasma-apply-desktoptheme >/dev/null 2>&1; then
	if timeout 120 plasma-apply-desktoptheme furryos >"${TMP}/dt.log" 2>&1; then
		ok "plasma-apply-desktoptheme furryos 成功（主题是合法的 Plasma 主题）"
	else
		cat "${TMP}/dt.log"
		bad "plasma-apply-desktoptheme furryos 失败"
	fi
	if timeout 120 plasma-apply-desktoptheme breeze >"${TMP}/dt-breeze.log" 2>&1; then
		bad "plasma-apply-desktoptheme breeze 竟然成功（说明 breeze 是合法主题名，"
		bad "  与先前「name=breeze 会静默回落」的结论矛盾，需重新核对）"
	else
		ok "plasma-apply-desktoptheme breeze 报错（证明 'breeze' 不是 Plasma 5.27 主题名，"
		ok "  这正是旧配置 name=breeze 导致面板停在 Breeze 的根因）"
	fi
else
	note "  SKIP: 宿主没有 plasma-apply-desktoptheme"
fi

if command -v plasma-apply-lookandfeel >/dev/null 2>&1; then
	if timeout 180 plasma-apply-lookandfeel --apply com.furryos.lookandfeel \
			>"${TMP}/lnf.log" 2>&1; then
		KD="${SANDBOX}/config/kdedefaults"
		check_kd() { # file key value label
			local got
			got=$(grep -E "^${2}=" "${KD}/${1}" 2>/dev/null | head -1 | cut -d= -f2-)
			if [ "${got}" = "${3}" ]; then
				ok "全局主题应用后 ${4} = ${3}"
			else
				bad "全局主题应用后 ${4} = '${got}'（期望 ${3}）"
			fi
		}
		check_kd kdeglobals ColorScheme FurryOS "配色方案"
		check_kd kdeglobals font "Noto Sans,10,-1,5,50,0,0,0,0,0" "正文字体"
		check_kd kdeglobals fixed "Hack,10,-1,5,50,0,0,0,0,0" "等宽字体"
		check_kd plasmarc name furryos "Plasma 桌面主题"
		check_kd kcminputrc cursorTheme breeze_cursors "光标主题"
		if grep -q "^Theme=FurryOS$" "${KD}/kdeglobals" 2>/dev/null; then
			ok "全局主题应用后图标主题 = FurryOS"
		else
			bad "全局主题应用后图标主题不是 FurryOS"
		fi
		if [ -f "${KD}/package" ] && grep -q "com.furryos.lookandfeel" "${KD}/package"; then
			ok "全局主题包已登记为 com.furryos.lookandfeel"
		else
			bad "kdedefaults/package 未登记全局主题包"
		fi
	else
		cat "${TMP}/lnf.log"
		bad "plasma-apply-lookandfeel --apply 失败"
	fi
else
	note "  SKIP: 宿主没有 plasma-apply-lookandfeel"
fi
unset XDG_DATA_HOME XDG_CONFIG_HOME

# ---------------------------------------------------------------- 4/5/6
note ""
note "== [4] 跨四层静态一致性 + 渲染像素断言 =="
if python3 "${WS}/tools/verify-visual.py" --probe-json "${TMP}/probe.json" \
		>"${TMP}/visual.log" 2>&1; then
	grep -E "^\s+\[FAIL\]" "${TMP}/visual.log" && FAILED=1
	ok "verify-visual.py 通过（$(grep -c '\[PASS\]' "${TMP}/visual.log") 项）"
else
	grep -E "^\s+\[FAIL\]" "${TMP}/visual.log"
	tail -3 "${TMP}/visual.log"
	bad "verify-visual.py 有失败项"
fi

note ""
note "== [5] 启动画面母版像素校验 =="
if python3 "${WS}/assets/effects/splash/verify-splash-pixels.py" \
		"${WS}/docs/preview/splash-master-1920x1080.png" >"${TMP}/splash.log" 2>&1; then
	ok "verify-splash-pixels.py 通过（$(grep -c '\[PASS\]' "${TMP}/splash.log") 项）"
else
	grep -E "\[FAIL\]" "${TMP}/splash.log"
	bad "verify-splash-pixels.py 有失败项"
fi

note ""
note "== [6] 配色方案 / skel / 全局主题三方一致 =="
if python3 "${WS}/assets/desktop/.tools/verify-consistency.py" >"${TMP}/cons.log" 2>&1; then
	ok "verify-consistency.py 通过"
else
	grep -E "^\s+- " "${TMP}/cons.log"
	bad "verify-consistency.py 有失败项"
fi

# ---------------------------------------------------------------- 汇总
note ""
note "=========================================================="
note " 汇总：${#SUMMARY[@]} 项，失败 $([ "${FAILED}" = "0" ] && echo 0 || grep -c '^FAIL' <<<"$(printf '%s\n' "${SUMMARY[@]}")")"
note "=========================================================="
printf '%s\n' "${SUMMARY[@]}" | sed 's/^/  /'
if [ "${FAILED}" = "0" ]; then
	note ""
	note "视觉统一验收通过：登录界面 / 桌面 / 动效 / 系统设置共用同一套"
	note "FurryOS 色板、动效参数与爪印母题；预览见 docs/preview/。"
	exit 0
fi
note ""
note "存在失败项，见上。"
exit 1
