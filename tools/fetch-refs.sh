#!/bin/sh
#
# fetch-refs.sh — 拉取上游 Ubuntu noble 参考包并解包，供 tools/verify-identity.sh 使用
#
# 为什么需要：
#   宿主是 Debian 12（或任意非 Ubuntu 系统），装不了 Ubuntu 包，但身份层校验需要
#   「注入前」的真实上游文件内容（/etc/os-release、/etc/issue、/etc/issue.net、
#   /etc/lsb-release、/etc/update-motd.d/*、/etc/default/motd-news、sshd 模板）
#   作为对照基线。直接下载 .deb 并解包即可，不需要安装，也不改动宿主。
#
# 产物目录：<repo>/.verify/（已被 .gitignore 排除，属可重建的参考数据）
#   P                 noble main 的 Packages 索引
#   *.deb             下载的参考包（已存在则复用，不重复下载）
#   x/base            base-files       解包（os-release / issue / issue.net / lsb-release /
#                                        update-motd.d/*）
#   x/ssh             openssh-server   解包（sshd_config 模板 / pam.d/sshd）
#   x/motd            motd-news-config 解包（/etc/default/motd-news）
#   x/lsb             lsb-release      解包
#
# 目录名与 tools/verify-identity.sh 的读取路径严格一致（历史上旧脚本解包到
# x/base-files / x/openssh-server，而校验器读 x/base / x/ssh，导致校验永远缺基线）。
#
# 用法：
#   sh tools/fetch-refs.sh                 # 默认 archive.ubuntu.com
#   MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu sh tools/fetch-refs.sh
#
# 退出码：0 成功；1 下载或解包失败；2 缺少必要命令。

set -eu

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="$(cd "${SELF_DIR}/.." && pwd)"
V="${WS}/.verify"
MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu}"

log () { printf '[fetch-refs] %s\n' "$*"; }

for CMD in curl dpkg-deb gzip; do
	if ! command -v "${CMD}" >/dev/null 2>&1
	then
		log "ERROR: 缺少必要命令：${CMD}"
		exit 2
	fi
done

mkdir -p "${V}/x"
cd "${V}"

if [ ! -f P ]
then
	log "下载 noble main 的 Packages 索引（${MIRROR}）"
	curl -fsS "${MIRROR}/dists/noble/main/binary-amd64/Packages.gz" -o P.gz
	gunzip -f P.gz
fi

# field <package> <field> — 取 Packages 索引里某个包的一个字段
field () {
	_l="$(grep -n "^Package: $1\$" P | head -1 | cut -d: -f1)"
	[ -n "${_l}" ] || return 0
	sed -n "${_l},/^\$/p" P | grep -m1 "^$2:" | cut -d' ' -f2-
}

# fetch <package> <target-subdir>
fetch () {
	_p="$1"
	_d="$2"
	_f="$(field "${_p}" Filename)"
	if [ -z "${_f}" ]
	then
		log "ERROR: 在 noble main 中找不到 ${_p} 的 Filename 字段"
		return 1
	fi
	_n="$(basename "${_f}")"
	if [ ! -f "${_n}" ]
	then
		log "下载 ${_p} -> ${_n}"
		curl -fsS "${MIRROR}/${_f}" -o "${_n}"
	else
		log "复用已下载的 ${_n}"
	fi
	rm -rf "x/${_d}"
	mkdir -p "x/${_d}"
	dpkg-deb -x "${_n}" "x/${_d}"
}

log "解包参考包到 ${V}/x/"
fetch base-files        base
fetch openssh-server    ssh
fetch motd-news-config  motd
fetch lsb-release       lsb

# 校验产物齐备：缺任何一个，verify-identity.sh 的对照都会失真。
missing=0
for f in \
	x/base/usr/lib/os-release \
	x/base/etc/issue \
	x/base/etc/issue.net \
	x/base/etc/update-motd.d \
	x/ssh/usr/share/openssh/sshd_config \
	x/ssh/etc/pam.d/sshd \
	x/motd/etc/default/motd-news
do
	if [ ! -e "${f}" ]
	then
		log "ERROR: 参考文件缺失：${V}/${f}"
		missing=$(( missing + 1 ))
	fi
done

if [ "${missing}" -ne 0 ]
then
	log "ERROR: ${missing} 个参考文件缺失，校验基线不可用"
	exit 1
fi

log "完成。参考文件位置："
log "  /etc/os-release 原值        : ${V}/x/base/usr/lib/os-release"
log "  /etc/issue(.net) 原值       : ${V}/x/base/etc/issue{,.net}"
log "  /etc/update-motd.d/ 原值    : ${V}/x/base/etc/update-motd.d/"
log "  sshd 配置模板               : ${V}/x/ssh/usr/share/openssh/sshd_config"
log "  /etc/default/motd-news 原值 : ${V}/x/motd/etc/default/motd-news"
log "现在可以运行：sh tools/verify-identity.sh"
