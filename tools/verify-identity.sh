#!/bin/bash
#
# verify-identity.sh — FurryOS 系统身份层静态校验（不启动真实系统）
#
# 用法：bash tools/verify-identity.sh [--no-fetch]
#         --no-fetch  参考基线缺失时不要自动下载，直接报错退出
#
# 注意：本脚本使用了进程替换 <(...)，只能由 bash 执行。
# 用 sh（dash）运行会报 Syntax error: "(" unexpected。
#
# 原理：
#   宿主是 Debian 12，无法安装 Ubuntu 包，也不能启动 Ubuntu 内核。
#   因此这里用「上游 Ubuntu noble 包的原始文件」搭建一个最小化的 /etc 快照，
#   再把 assets/identity/ 里的资产按注入钩子同样的逻辑应用上去，
#   最后对应用后的文件系统做 grep 校验。
#
# 输入（由 tools/fetch-refs.sh 生成；参考数据不入库，脚本入库）：
#   <repo>/.verify/x/base     <- base-files 解包（/etc/os-release 等上游原值）
#   <repo>/.verify/x/ssh      <- openssh-server 解包（sshd_config.d、pam.d/sshd）
#   <repo>/.verify/x/motd     <- motd-news-config 解包（/etc/default/motd-news）
#   <repo>/assets/identity/   <- 本层资产
#
#   基线缺失时会自动调用 tools/fetch-refs.sh（可用 --no-fetch 关闭）。
#   脚本路径全部相对自身定位，因此在任意 clone 目录、任意 CWD 下都成立。
#
# 输出：PASS/FAIL 汇总；任何 FAIL 以退出码 1 结束，缺参考基线以退出码 2 结束。

set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="$(cd "${SELF_DIR}/.." && pwd)"
VERIFY="${WS}/.verify"
SIM="${VERIFY}/sim"
SRC="${WS}/assets/identity"
BRAND="${WS}/assets/brand"

AUTO_FETCH=1
for _arg in "$@"; do
	case "${_arg}" in
	--no-fetch) AUTO_FETCH=0 ;;
	-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
	*) echo "unknown option: ${_arg}" >&2; exit 2 ;;
	esac
done

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$1"; }

# --------------------------------------------------- 0. 参考基线是否就绪
echo "== 0. 检查上游参考基线 =="

refs_ready () {
	[ -e "${VERIFY}/x/base/usr/lib/os-release" ] \
		&& [ -d "${VERIFY}/x/base/etc/update-motd.d" ] \
		&& [ -e "${VERIFY}/x/ssh/usr/share/openssh/sshd_config" ] \
		&& [ -e "${VERIFY}/x/motd/etc/default/motd-news" ]
}

if ! refs_ready && [ "${AUTO_FETCH}" -eq 1 ]; then
	echo "  参考基线缺失，调用 tools/fetch-refs.sh 拉取（--no-fetch 可关闭）"
	sh "${SELF_DIR}/fetch-refs.sh" || {
		echo "  ERROR: tools/fetch-refs.sh 失败（无网络？可用 --no-fetch 并手动准备基线）" >&2
		exit 2
	}
fi

if ! refs_ready; then
	echo "缺少上游参考包解包目录：${VERIFY}/x/{base,ssh,motd}" >&2
	echo "请先运行：sh tools/fetch-refs.sh" >&2
	exit 2
fi
echo "  参考基线就绪：${VERIFY}/x/{base,ssh,motd}"

# ---------------------------------------------------------------- 1. 搭建快照
echo
echo "== 1. 用上游包原始文件搭建模拟文件系统 =="
rm -rf "${SIM}"
mkdir -p "${SIM}/etc/ssh/sshd_config.d" "${SIM}/etc/update-motd.d" \
         "${SIM}/etc/default" "${SIM}/etc/xdg" \
         "${SIM}/usr/share/about-distro" "${SIM}/usr/lib" \
         "${SIM}/var/cache" "${SIM}/etc/systemd/system"

# base-files 的上游原值（这是「注入前」的真实状态）
# 注意：base-files 里 /etc/os-release 是指向 ../usr/lib/os-release 的符号链接，
#      直接 cp -a 会把悬空符号链接拷过来，因此这里先把链接目标复制过来，
#      再按「符号链接」的形态重建，完全还原上游状态。
cp -a "${VERIFY}/x/base/usr/lib/os-release" "${SIM}/usr/lib/os-release"
ln -sf ../usr/lib/os-release "${SIM}/etc/os-release"
cp -a "${VERIFY}/x/base/etc/issue"      "${SIM}/etc/issue"
cp -a "${VERIFY}/x/base/etc/issue.net"  "${SIM}/etc/issue.net"
cp -a "${VERIFY}/x/base/etc/lsb-release" "${SIM}/etc/lsb-release"
cp -a "${VERIFY}/x/base/etc/legal"      "${SIM}/etc/legal"
cp -a "${VERIFY}/x/base/etc/update-motd.d/." "${SIM}/etc/update-motd.d/"
cp -a "${VERIFY}/x/motd/etc/default/motd-news" "${SIM}/etc/default/motd-news"
cp -a "${VERIFY}/x/ssh/etc/ssh/sshd_config.d/." "${SIM}/etc/ssh/sshd_config.d/" 2>/dev/null || true
cp -a "${VERIFY}/x/ssh/etc/pam.d/sshd" "${SIM}/etc/pam.d-sshd.reference"
: > "${SIM}/etc/motd"   # 上游默认 /etc/motd 是空文件
printf 'Welcome to Ubuntu\n' > "${SIM}/var/cache/motd-news"

echo "  快照目录：${SIM}"
echo "  注入前 /etc/os-release : $(grep -m1 PRETTY_NAME "${SIM}/etc/os-release")"
echo "  注入前 /etc/issue      : $(cat "${SIM}/etc/issue")"
echo "  注入前 /etc/issue.net  : $(cat "${SIM}/etc/issue.net")"

# ---------------------------------------------------------------- 2. 应用资产
echo
echo "== 2. 按注入钩子逻辑应用 assets/identity/ =="

install_into() {  # install_into <src> <dst> <mode>
	install -D -m "$3" "$1" "$2"
}

# os-release：按 6010 的真实行为模拟。
# 6010 的做法是：把真实文件写到 /usr/lib/os-release，然后重建
# /etc/os-release -> ../usr/lib/os-release 符号链接（保留 dpkg 归属）。
# 这样 /etc/os-release 是符号链接，读它等于读 /usr/lib/os-release。
install_into "${SRC}/os-release" "${SIM}/usr/lib/os-release" 0644
rm -f "${SIM}/etc/os-release"
ln -sf ../usr/lib/os-release "${SIM}/etc/os-release"
install_into "${SRC}/issue"      "${SIM}/etc/issue"      0644
install_into "${SRC}/issue.net"  "${SIM}/etc/issue.net"  0644
install_into "${SRC}/motd"       "${SIM}/etc/motd"       0644
install_into "${SRC}/legal"      "${SIM}/etc/legal"      0644
install_into "${SRC}/lsb-release" "${SIM}/etc/lsb-release" 0644
install_into "${SRC}/motd-news"  "${SIM}/etc/default/motd-news" 0644
install_into "${SRC}/sshd_banner.conf" "${SIM}/etc/ssh/sshd_config.d/010-furryos-banner.conf" 0644
install_into "${SRC}/about-distro/kcm-about-distrorc" "${SIM}/etc/xdg/kcm-about-distrorc" 0644
install_into "${SRC}/about-distro/furryos-logo.svg" "${SIM}/usr/share/about-distro/furryos-logo.svg" 0644
# 6010 把 assets/identity/furryos-logo.svg 装成 /usr/share/about-distro/logo.svg，
# 缺 svg 时退回 brand/paw.svg。这里严格照抄 6010 的分支顺序：
# 早期版本额外装了一个 6010 根本不会产生的 furryos-logo.png，使 LOGO= 解析
# 断言可以在「真实产物不存在该文件」的情况下通过（假 PASS）。
if [ -r "${SRC}/furryos-logo.svg" ]; then
	install_into "${SRC}/furryos-logo.svg" "${SIM}/usr/share/about-distro/logo.svg" 0644
elif [ -r "${BRAND}/paw.svg" ]; then
	install_into "${BRAND}/paw.svg" "${SIM}/usr/share/about-distro/logo.svg" 0644
fi

# update-motd.d：删除上游脚本，装 FurryOS 脚本
rm -f "${SIM}/etc/update-motd.d/00-header" \
      "${SIM}/etc/update-motd.d/10-help-text" \
      "${SIM}/etc/update-motd.d/50-motd-news"
for _s in "${SRC}"/update-motd.d/*; do
	[ -e "${_s}" ] || continue
	install -D -m 0755 "${_s}" "${SIM}/etc/update-motd.d/$(basename "${_s}")"
done
# 兜底删除任何残留的「非注释行」含 Ubuntu 的脚本
for _f in "${SIM}"/etc/update-motd.d/*; do
	[ -f "${_f}" ] || continue
	if grep -vE '^[[:space:]]*#' "${_f}" | grep -qi "ubuntu"; then
		rm -f "${_f}"
	fi
done

# motd-news systemd 单元 mask
ln -sf /dev/null "${SIM}/etc/systemd/system/motd-news.timer"
ln -sf /dev/null "${SIM}/etc/systemd/system/motd-news.service"
rm -f "${SIM}/var/cache/motd-news"

echo "  注入后 /etc/os-release : $(grep -m1 PRETTY_NAME "${SIM}/etc/os-release")"
echo "  注入后 /etc/issue      : $(cat "${SIM}/etc/issue")"
echo "  注入后 /etc/issue.net  : $(cat "${SIM}/etc/issue.net")"
echo "  update-motd.d 内容    : $(ls "${SIM}/etc/update-motd.d/" | tr '\n' ' ')"

# ---------------------------------------------------------------- 3. 逐项校验
echo
echo "== 3. 硬性验收校验 =="

# --- A. /etc/issue.net 绝不可含 Ubuntu ---
# 只看非注释行：注释是给维护者看的说明，不会显示给登录用户；
# 但为了绝对保险，issue.net / issue / motd 这三个「会被原样打印」的文件
# 我们连注释行都不允许出现 Ubuntu（写入前已确认）。
if grep -i "ubuntu" "${SIM}/etc/issue.net"; then
	bad "/etc/issue.net 含 Ubuntu 字样（硬性要求违反，含注释行）"
else
	ok "/etc/issue.net 不含 Ubuntu（含注释行）"
fi
grep -q "FurryOS" "${SIM}/etc/issue.net" \
	&& ok "/etc/issue.net 含 FurryOS 横幅" \
	|| bad "/etc/issue.net 未见 FurryOS"

# --- B. os-release ---
grep -q '^NAME="FurryOS"$' "${SIM}/etc/os-release" \
	&& ok '/etc/os-release NAME="FurryOS"' \
	|| bad '/etc/os-release NAME 不是 FurryOS'
grep -q '^PRETTY_NAME="FurryOS 24.04 LTS"$' "${SIM}/etc/os-release" \
	&& ok '/etc/os-release PRETTY_NAME="FurryOS 24.04 LTS"' \
	|| bad '/etc/os-release PRETTY_NAME 不符合契约'
grep -q '^ID=ubuntu$' "${SIM}/etc/os-release" \
	&& ok '/etc/os-release 保留 ID=ubuntu（包管理兼容链）' \
	|| bad '/etc/os-release 丢失 ID=ubuntu（会影响 apt/ppa 兼容）'
if grep -qiE 'ubuntu' <(grep -vE '^(ID|ID_LIKE|HOME_URL|SUPPORT_URL|BUG_REPORT_URL)=' "${SIM}/etc/os-release"); then
	bad '/etc/os-release 除兼容字段外仍出现 ubuntu'
else
	ok '/etc/os-release 用户可见字段无 ubuntu'
fi
# 6010 的结构：/etc/os-release 是指向 ../usr/lib/os-release 的符号链接，
# 两份内容必须一致，否则 KOSRelease 回退路径会读到上游值。
# 6010 的契约是「真实文件写在 /usr/lib/os-release，/etc/os-release 保持符号链接」，
# 这样 dpkg 归属与升级行为正常。所以这里断言的就是符号链接形态本身：
# 早期版本在 else 分支也调用 ok，等于这条检查永远不可能失败。
if [ -L "${SIM}/etc/os-release" ]; then
	ok '/etc/os-release 是指向 ../usr/lib/os-release 的符号链接（保留 dpkg 归属）'
	[ "$(readlink "${SIM}/etc/os-release")" = "../usr/lib/os-release" ] \
		&& ok '符号链接目标正确：../usr/lib/os-release' \
		|| bad "符号链接目标错误：$(readlink "${SIM}/etc/os-release")"
	cmp -s "${SIM}/etc/os-release" "${SIM}/usr/lib/os-release" \
		&& ok '/etc/os-release 与 /usr/lib/os-release 内容一致（回退路径不会暴露上游）' \
		|| bad '/etc/os-release 与 /usr/lib/os-release 内容不一致'
else
	bad "/etc/os-release 不是符号链接（6010 应重建 -> ../usr/lib/os-release，否则 dpkg -S 失效）"
fi
# 上面的形态检查是对「模拟」的断言；再断言一次真实钩子确实做了同样的事，
# 避免模拟与 6010 实现漂移后校验继续自证。
if grep -q 'ln -sf ../usr/lib/os-release /etc/os-release' \
	"${WS}/build/config/hooks/normal/6010-integrate-identity-assets.chroot" 2>/dev/null
then
	:
else
	bad "6010 未重建 /etc/os-release 符号链接（校验模拟已与真实钩子漂移）"
fi

# --- C. issue / motd ---
# 同样只看「会被打印给用户」的内容，即非注释、非空行。
issue_usertext() { grep -vE '^\s*(#|$)' "$1"; }
if issue_usertext "${SIM}/etc/issue" | grep -qi "ubuntu"; then
	bad "/etc/issue 用户可见内容含 Ubuntu"
else
	ok "/etc/issue 用户可见内容不含 Ubuntu"
fi
if issue_usertext "${SIM}/etc/motd" | grep -qi "ubuntu"; then
	bad "/etc/motd 用户可见内容含 Ubuntu"
else
	ok "/etc/motd 用户可见内容不含 Ubuntu"
fi
grep -q "FurryOS" "${SIM}/etc/motd" \
	&& ok "/etc/motd 含 FurryOS 欢迎信息" \
	|| bad "/etc/motd 未见 FurryOS"
# /etc/legal：pam_motd 会一次性展示，必须同样检查
if issue_usertext "${SIM}/etc/legal" | grep -qi "ubuntu"; then
	bad "/etc/legal 用户可见内容含 Ubuntu（pam_motd 会展示它）"
else
	ok "/etc/legal 用户可见内容不含 Ubuntu"
fi

# --- D. SSH Banner 显式开启 ---
grep -qE '^Banner[[:space:]]+/etc/issue\.net$' "${SIM}/etc/ssh/sshd_config.d/010-furryos-banner.conf" \
	&& ok "sshd drop-in 显式设置 Banner /etc/issue.net" \
	|| bad "sshd drop-in 未显式设置 Banner"
grep -q "sshd_config.d/\*.conf" "${VERIFY}/x/ssh/usr/share/openssh/sshd_config" \
	&& ok "openssh-server 模板含 Include /etc/ssh/sshd_config.d/*.conf（drop-in 会被加载）" \
	|| bad "openssh-server 模板不含 Include，drop-in 不会生效"

# --- E. 动态 MOTD 不再暴露 Ubuntu ---
if [ -e "${SIM}/etc/update-motd.d/50-motd-news" ]; then
	bad "50-motd-news 仍存在（会拉取 motd.ubuntu.com）"
else
	ok "50-motd-news 已移除"
fi
# 只看会被执行/打印的非注释行：注释是维护说明，不会显示给用户。
# 先断言文件存在：早期版本把「文件不存在」也判为 PASS（两条 grep 都失败
# 时 if 为假），于是删掉 assets/identity/update-motd.d/00-header 后校验仍然全绿。
for _motd in 00-header 10-help-text; do
	_motd_path="${SIM}/etc/update-motd.d/${_motd}"
	if [ ! -f "${_motd_path}" ]; then
		bad "${_motd} 缺失（6010 应安装 FurryOS 版；系统会退回 Ubuntu 默认 MOTD）"
	elif grep -vE '^[[:space:]]*#' "${_motd_path}" 2>/dev/null | grep -qi "ubuntu\|landscape"; then
		bad "${_motd} 可执行内容仍含 Ubuntu/landscape"
	else
		ok "${_motd} 已替换为 FurryOS 版且可执行内容不含 Ubuntu"
	fi
done
# 动态 MOTD 输出模拟：跑一遍 FurryOS 版 00-header
_OUT=$(cd "${SIM}" && sh ./etc/update-motd.d/00-header 2>/dev/null | head -1)
echo "${_OUT}" | grep -q "FurryOS" \
	&& ok "00-header 实际输出：${_OUT}" \
	|| bad "00-header 实际输出不含 FurryOS：${_OUT}"
echo "${_OUT}" | grep -qi "ubuntu" \
	&& bad "00-header 实际输出含 Ubuntu" \
	|| ok "00-header 实际输出不含 Ubuntu"
# motd-news 关闭
grep -q '^ENABLED=0$' "${SIM}/etc/default/motd-news" \
	&& ok "/etc/default/motd-news ENABLED=0" \
	|| bad "/etc/default/motd-news 未关闭"
[ "$(readlink "${SIM}/etc/systemd/system/motd-news.timer")" = "/dev/null" ] \
	&& ok "motd-news.timer 已 mask（/dev/null）" \
	|| bad "motd-news.timer 未 mask"

# --- F. KDE 关于本机 ---
grep -q '^Name=FurryOS$' "${SIM}/etc/xdg/kcm-about-distrorc" \
	&& ok "kcm-about-distrorc Name=FurryOS" \
	|| bad "kcm-about-distrorc Name 不是 FurryOS"
grep -q '^LogoPath=/usr/share/about-distro/furryos-logo.svg$' "${SIM}/etc/xdg/kcm-about-distrorc" \
	&& ok "kcm-about-distrorc LogoPath 指向 FurryOS logo" \
	|| bad "kcm-about-distrorc LogoPath 未指向 FurryOS logo"
[ -r "${SIM}/usr/share/about-distro/furryos-logo.svg" ] \
	&& ok "/usr/share/about-distro/furryos-logo.svg 存在" \
	|| bad "/usr/share/about-distro/furryos-logo.svg 缺失"
# 6010 的现有逻辑安装路径
[ -r "${SIM}/usr/share/about-distro/logo.svg" ] \
	&& ok "/usr/share/about-distro/logo.svg 存在（6010 现有逻辑路径）" \
	|| bad "/usr/share/about-distro/logo.svg 缺失"
# LOGO= 字段必须能被图标主题解析：要么指向 /usr/share/about-distro 下的文件名，
# 要么有 kcm-about-distrorc 的 LogoPath 绝对路径兜底
LOGO_VAL="$(grep -m1 '^LOGO=' "${SIM}/etc/os-release" | cut -d= -f2)"
if [ -n "${LOGO_VAL}" ]; then
	ok "/etc/os-release LOGO=${LOGO_VAL}"
	if [ -r "${SIM}/usr/share/about-distro/${LOGO_VAL}.svg" ] \
		|| [ -r "${SIM}/usr/share/about-distro/${LOGO_VAL}.png" ]; then
		ok "LOGO 指向的 ${LOGO_VAL} 在 /usr/share/about-distro 中可解析"
	else
		bad "LOGO=${LOGO_VAL} 在 /usr/share/about-distro 中无法解析（有 kcm-about-distrorc 的 LogoPath 绝对路径兜底）"
	fi
else
	bad "/etc/os-release 缺 LOGO 字段"
fi
if grep -qi "ubuntu\|kubuntu" <(grep -vE '^\s*#' "${SIM}/etc/xdg/kcm-about-distrorc"); then
	bad "kcm-about-distrorc 用户可见字段含 ubuntu/kubuntu"
else
	ok "kcm-about-distrorc 用户可见字段不含 ubuntu/kubuntu"
fi

# --- G. 品牌合规：不得使用上游商标/Logo ---
# 只在「会被用户看到」的内容里查上游商标；README / 钩子注释里的说明文字不算。
if grep -rIi "ubuntu-logo\|ubuntu_logo\|Canonical" "${SRC}" \
	--include="os-release" --include="issue" --include="issue.net" \
	--include="motd" --include="legal" --include="lsb-release" \
	--include="motd-news" --include="sshd_banner.conf" 2>/dev/null; then
	bad "assets/identity 的用户可见文件引用上游 logo/商标"
else
	ok "assets/identity 的用户可见文件未引用上游 logo/商标"
fi

# --- H. lsb-release 兼容层 ---
grep -q '^DISTRIB_ID=FurryOS$' "${SIM}/etc/lsb-release" \
	&& ok "lsb-release DISTRIB_ID=FurryOS" \
	|| bad "lsb-release DISTRIB_ID 不是 FurryOS"
grep -q '^DISTRIB_NAME=FurryOS$' "${SIM}/etc/lsb-release" \
	&& ok "lsb-release 提供 DISTRIB_NAME（供 00-header 读取）" \
	|| bad "lsb-release 缺 DISTRIB_NAME"

# --- I. 全文件系统扫描：登录后任何位置都不出现 Ubuntu ---
echo
echo "== 4. 注入后全文件系统扫描（登录后用户可见内容） =="
# 说明：
#   - 只看会被打印/展示给用户的文件（issue, issue.net, motd, legal,
#     update-motd.d/*, motd-news, lsb-release, sshd drop-in, kcm-about-distrorc, os-release）。
#   - 这些文件里的注释行、说明文字不会显示给用户，但 issue/issue.net/motd/legal
#     这四个「原样打印」的文件已在上面按含注释行的标准单独校验过。
#   - os-release 允许保留 ID=ubuntu / ID_LIKE 等包管理兼容字段。
# SCAN_FILES=$(find "${SIM}" -type f \
# 	! -name "pam.d-sshd.reference" 2>/dev/null)
SCAN_FILES=$(find "${SIM}" -type f \
	! -name "pam.d-sshd.reference" \
	! -name "*.png" ! -name "*.svg" ! -name "*.gz" 2>/dev/null)

# 打印给用户看的内容 = 去掉注释行后的非空行
UBUNTU_HITS=""
for _f in ${SCAN_FILES}; do
	case "${_f}" in
	*/os-release)
		# os-release：排除 ID / ID_LIKE / *_URL 这些兼容字段
		_h=$(grep -vE '^(ID|ID_LIKE|HOME_URL|SUPPORT_URL|BUG_REPORT_URL|PRIVACY_POLICY_URL)=' "${_f}" \
			| grep -vE '^\s*(#|$)' | grep -i "ubuntu")
		;;
	*/lsb-release)
		# lsb-release：允许「基于 Ubuntu」的表述（brand-tokens.md 明确允许）
		_h=$(grep -vE '^\s*(#|$)' "${_f}" | grep -i "ubuntu" | grep -vi "based on ubuntu")
		;;
	*)
		_h=$(grep -vE '^\s*(#|$)' "${_f}" | grep -i "ubuntu")
		;;
	esac
	if [ -n "${_h}" ]; then
		UBUNTU_HITS="${UBUNTU_HITS}${_f}:
${_h}
"
	fi
done

if [ -n "${UBUNTU_HITS}" ]; then
	bad "注入后用户可见内容仍存在 Ubuntu 字样："
	printf '%s' "${UBUNTU_HITS}" | sed 's/^/        /'
else
	ok "注入后用户可见内容无 Ubuntu 字样（os-release 仅保留 ID=ubuntu 兼容字段）"
fi

# ---------------------------------------------------------------- 汇总
# 断言总数必须与 README/BUILD.md 承诺的一致：某个条件分支不再执行（文件消失、
# 循环体跳过）时 PASS 会悄悄变小而退出码仍是 0，这一条把它变成 FAIL。
EXPECTED_PASS=33
if [ "${PASS}" -ne "${EXPECTED_PASS}" ]; then
	bad "断言数 ${PASS} != ${EXPECTED_PASS}（有检查被跳过或新增；确认后同步更新 README/BUILD.md 与本行）"
fi

echo
echo "=========================================="
printf '结果：PASS=%d FAIL=%d\n' "${PASS}" "${FAIL}"
echo "=========================================="
[ "${FAIL}" -eq 0 ] || exit 1
exit 0
