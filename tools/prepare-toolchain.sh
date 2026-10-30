#!/bin/bash
#
# prepare-toolchain.sh — 在仓库内准备 live-build / debootstrap / ubuntu-keyring
# 的解包副本，以及 tools/lb.sh 需要的 shim，并固化几处必须的工具链补丁。
#
# 为什么需要解包副本
# ------------------
# 受限宿主（见 docs/BUILD.md 第 5 节）上 live-build 不能装成系统包：
# /usr 与 dpkg 数据库只读。因此 live-build、debootstrap、ubuntu-keyring 都以
# `dpkg-deb -x` 解包到 tools/ 下，由 tools/lb.sh 用 PATH/LIVE_BUILD/DEBOOTSTRAP_DIR
# 指过去。这些解包产物是「可重建的构建依赖」，不入库（.gitignore 已排除
# tools/rootfs、tools/lbroot、tools/shim、tools/*.deb），所以必须有本脚本。
#
# 固化的补丁（都是「不改就构建不出来」的环境事实，不是可选项）
# ------------------------------------------------------------
#  1) debootstrap/functions：宿主 /root 挂 nodev 时 mknod 出来的设备节点存在却
#     打不开，所有 postinst 里 `> /dev/null` 都失败。让 setup_devices() 直接走
#     setup_devices_bind()，并跳过 nodev 上必然失败的 device-node 探针。
#  2) live-build/binary_grub-efi：Ubuntu 的 bootx64.efi 是指向签名 shim 的符号
#     链接，上游用 `stat -c %s` 只量到 36 字节的链接，EFI FAT 镜像过小、mcopy
#     报 Disk full。改成 `stat -L -c %s`（量目标文件）。
#  3) live-build 的 GRUB 资源映射：binary_grub_cfg 从 ${LIVE_BUILD}/share/bootloaders
#     复制资源，而 Debian 包把它们装在 /usr/share/live/build/bootloaders。
#     用符号链接把它们接起来。
#  4) chroot_install-packages：live-build 把内核元包名拼成
#     ${LB_LINUX_PACKAGES}-${LB_LINUX_FLAVOURS_WITH_ARCH}（=linux-image-generic-amd64），
#     noble 的 generic 内核元包没有 -amd64 后缀，直接装会 No such package。
#     在 apt 消费队列前改写名字（旧文档提到的「6200 钩子」，实际实现点在这里）。
#  5) chroot_{proc,sysfs,selinuxfs}：宿主 /etc/mtab 指向只读的 /proc，一次成功的
#     挂载也会以 16 退出并打断 chroot 阶段。shim/mount（mount -n）是第一道防线，
#     这三处 `|| true` 是第二道。
#
# 产物布局（默认 DEST=tools/）
# ----------------------------
#   rootfs/                    live-build 的 /usr（bin/lb、lib/live、share/live/build/*）
#                              + debootstrap（sbin/debootstrap、share/debootstrap/*）
#                              + ubuntu-keyring（share/keyrings/*）
#   lbroot/usr/lib/live/       ${LIVE_BUILD}：scripts/{build.sh,build/} + functions/share 链接
#   shim/cat, shim/mount       宿主只读 /usr 与只读 /etc/mtab 的绕法（见各文件注释）
#
# 用法：
#   bash tools/prepare-toolchain.sh                 # 准备到 tools/
#   bash tools/prepare-toolchain.sh --dest /tmp/tc  # 准备到别处（验证脚本本身）
#   DEB_DIR=/path/to/debs bash tools/prepare-toolchain.sh
#
# 依赖：dpkg-deb、python3；下载时还需要 curl / apt-get
# 退出码：0 成功；1 准备或打补丁失败；2 缺少必要命令。

set -eu

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="$(cd "${SELF_DIR}/.." && pwd)"
DEST="${WS}/tools"
DEB_DIR="${DEB_DIR:-${WS}}"
MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu}"

log () { printf '[prepare-toolchain] %s\n' "$*"; }
die () { printf '[prepare-toolchain] ERROR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
	--dest) [ $# -ge 2 ] || die "--dest 需要参数"; DEST="$2"; shift 2 ;;
	--deb-dir) [ $# -ge 2 ] || die "--deb-dir 需要参数"; DEB_DIR="$2"; shift 2 ;;
	-h|--help) sed -n '2,50p' "$0"; exit 0 ;;
	*) die "unknown option: $1" ;;
	esac
done

for CMD in dpkg-deb python3; do
	command -v "${CMD}" >/dev/null 2>&1 || die "缺少必要命令：${CMD}"
done

log "仓库：${WS}"
log "安装到：${DEST}"
mkdir -p "${DEST}" "${DEB_DIR}"

# ---------------------------------------------------------------- 取包 ----
# find_deb <glob> — 在 DEB_DIR 里找已经下载好的 deb
find_deb () {
	set -- "${DEB_DIR}"/$1
	[ -e "$1" ] || return 1
	printf '%s\n' "$1"
}

# apt_download <package> — 用宿主 apt 源下载（Debian/Ubuntu 都有该包时最省事）
apt_download () {
	command -v apt-get >/dev/null 2>&1 || return 1
	log "apt-get download $1"
	( cd "${DEB_DIR}" && apt-get download "$1" >/dev/null 2>&1 ) || return 1
	find_deb "$1*.deb"
}

# noble_download <package> — 从 noble 的 Packages 索引里找 Filename 再 curl
noble_download () {
	command -v curl >/dev/null 2>&1 || return 1
	local idx="${DEB_DIR}/.noble-Packages"
	if [ ! -f "${idx}" ]; then
		log "下载 noble main Packages 索引"
		curl -fsS "${MIRROR}/dists/noble/main/binary-amd64/Packages.gz" -o "${idx}.gz" || return 1
		gunzip -f "${idx}.gz" || return 1
	fi
	local line fname
	line="$(grep -n "^Package: $1\$" "${idx}" | head -1 | cut -d: -f1)"
	[ -n "${line}" ] || return 1
	fname="$(sed -n "${line},/^\$/p" "${idx}" | grep -m1 '^Filename:' | cut -d' ' -f2-)"
	[ -n "${fname}" ] || return 1
	log "下载 $1（${fname}）"
	( cd "${DEB_DIR}" && curl -fsS "${MIRROR}/${fname}" -o "$(basename "${fname}")" ) || return 1
	find_deb "$(basename "${fname}")"
}

LIVE_BUILD_DEB="$(find_deb 'live-build_*.deb' || true)"
[ -n "${LIVE_BUILD_DEB}" ] || LIVE_BUILD_DEB="$(apt_download live-build || true)"
[ -n "${LIVE_BUILD_DEB}" ] || die "找不到 live-build 的 deb（放到 ${DEB_DIR} 或用 apt-get download live-build）"

DEBOOTSTRAP_DEB="$(find_deb 'debootstrap_*.deb' || true)"
[ -n "${DEBOOTSTRAP_DEB}" ] || DEBOOTSTRAP_DEB="$(apt_download debootstrap || true)"
[ -n "${DEBOOTSTRAP_DEB}" ] || die "找不到 debootstrap 的 deb（放到 ${DEB_DIR} 或用 apt-get download debootstrap）"

# Ubuntu 的 debootstrap 只为了拿 scripts/noble 等 Ubuntu 套件脚本
UBUNTU_DEBOOTSTRAP_DEB="$(find_deb 'debootstrap-ubuntu*.deb' || true)"
[ -n "${UBUNTU_DEBOOTSTRAP_DEB}" ] || UBUNTU_DEBOOTSTRAP_DEB="$(noble_download debootstrap || true)"

KEYRING_DEB="$(find_deb 'ubuntu-keyring*.deb' || true)"
[ -n "${KEYRING_DEB}" ] || KEYRING_DEB="$(noble_download ubuntu-keyring || true)"
[ -n "${KEYRING_DEB}" ] || die "找不到 ubuntu-keyring 的 deb（放到 ${DEB_DIR} 或联网重跑）"

log "live-build     : $(basename "${LIVE_BUILD_DEB}")"
log "debootstrap    : $(basename "${DEBOOTSTRAP_DEB}")"
[ -n "${UBUNTU_DEBOOTSTRAP_DEB}" ] && log "ubuntu scripts : $(basename "${UBUNTU_DEBOOTSTRAP_DEB}")"
log "keyring        : $(basename "${KEYRING_DEB}")"

# ---------------------------------------------------------------- 解包 ----
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

mkdir -p "${STAGE}/lb" "${STAGE}/dbs" "${STAGE}/keyring"
dpkg-deb -x "${LIVE_BUILD_DEB}" "${STAGE}/lb"
dpkg-deb -x "${DEBOOTSTRAP_DEB}" "${STAGE}/dbs"
dpkg-deb -x "${KEYRING_DEB}" "${STAGE}/keyring"
if [ -n "${UBUNTU_DEBOOTSTRAP_DEB}" ]; then
	mkdir -p "${STAGE}/ubdbs"
	dpkg-deb -x "${UBUNTU_DEBOOTSTRAP_DEB}" "${STAGE}/ubdbs"
fi

rm -rf "${DEST}/rootfs" "${DEST}/lbroot" "${DEST}/shim"
mkdir -p "${DEST}/rootfs" "${DEST}/lbroot/usr/lib"

# live-build：整个 usr/ 解到 rootfs（/usr/bin/lb、/usr/share/live/build、/usr/lib/live）
cp -a "${STAGE}/lb/usr/." "${DEST}/rootfs/usr/"

# lbroot/usr/lib/live：lb(1) 从 ${LIVE_BUILD}/scripts/{build.sh,build/} 执行子命令，
# 从 ${LIVE_BUILD}/{functions,share} 读数据；而 Debian 的 live-build 包把它们装在
# /usr/lib/live/{build.sh,build/} 与 /usr/share/live/build/。这里按 lb(1) 的期望重组。
LBROOT="${DEST}/lbroot/usr/lib/live"
mkdir -p "${LBROOT}/scripts" "${LBROOT}/share/bin"
cp -a "${DEST}/rootfs/usr/lib/live/build.sh" "${LBROOT}/scripts/build.sh"
cp -a "${DEST}/rootfs/usr/lib/live/build/." "${LBROOT}/scripts/build/"
ln -sfn ../../../../rootfs/usr/lib/live/build "${LBROOT}/build"
ln -sfn ../../../../rootfs/usr/share/live/build/functions "${LBROOT}/functions"
ln -sfn ../../../../../../rootfs/usr/share/live/build/bin/Packages "${LBROOT}/share/bin/Packages"
ln -sfn ../../../../../rootfs/usr/share/live/build/bootloaders "${LBROOT}/share/bootloaders"

# debootstrap（Debian 版：binary + functions + scripts）
cp -a "${STAGE}/dbs/usr/." "${DEST}/rootfs/usr/"

# Ubuntu 套件脚本（noble 等）覆盖进来，只加不删
if [ -d "${STAGE}/ubdbs/usr/share/debootstrap/scripts" ]; then
	cp -a "${STAGE}/ubdbs/usr/share/debootstrap/scripts/." \
		"${DEST}/rootfs/usr/share/debootstrap/scripts/"
fi

# ubuntu-keyring
mkdir -p "${DEST}/rootfs/usr/share/keyrings"
cp -a "${STAGE}/keyring/usr/share/keyrings/." "${DEST}/rootfs/usr/share/keyrings/"

# ---------------------------------------------- 补丁 1：debootstrap nodev ----
DBS="${DEST}/rootfs/usr/share/debootstrap/functions"
[ -f "${DBS}" ] || die "解包后找不到 ${DBS}"
cp -a "${DBS}" "${DEST}/rootfs/usr/share/debootstrap/functions.orig"

python3 - "${DBS}" <<'PYDBS'
import sys

path = sys.argv[1]
src = open(path).read()
orig = src

# (a) setup_devices()：nodev 挂载上 setup_devices_simple 产出的节点打不开，
#     直接改用 bind-mount 宿主可用设备。
anchor_a = "\t\tsetup_devices_simple\n"
repl_a = (
    "\t\t# FurryOS build: the workspace (/root/furryos) is mounted nodev, so\n"
    "\t\t# setup_devices_simple() creates device nodes that exist but cannot be\n"
    "\t\t# opened, which breaks every postinst that redirects to /dev/null.\n"
    "\t\t# setup_devices_bind() bind-mounts the host's working devices instead.\n"
    "\t\tsetup_devices_bind\n"
)
if src.count(anchor_a) != 1:
    sys.exit("patch(a): expected exactly 1 setup_devices_simple call, got %d"
             % src.count(anchor_a))
src = src.replace(anchor_a, repl_a)

# (b) setup_dynamic_devices()：在 HOST_OS 分支之前插入 FURRYOS_BIND_DEVICES 提前返回
#     （这是 chroot 阶段装包前的那次设备准备，宿主上验证过的补丁位置）。
anchor_head = (
    "\tif doing_variant fakechroot; then\n"
    "\t\treturn 0\n"
    "\tfi\n\n"
)
anchor_tail = "\tcase \"$HOST_OS\" in\n"
anchor_b = anchor_head + anchor_tail
if src.count(anchor_b) != 1:
    sys.exit("patch(b): expected exactly 1 setup_dynamic_devices() HOST_OS case, got %d"
             % src.count(anchor_b))
insert_b = (
    "\t# FurryOS build: the workspace (/root/furryos) is mounted nodev, so device\n"
    "\t# nodes created on it exist but cannot be opened. Package postinst scripts\n"
    "\t# run in this stage and redirect to /dev/null, so bind-mount the host's\n"
    "\t# working devices over the unusable nodes before continuing.\n"
    "\tif [ -n \"${FURRYOS_BIND_DEVICES:-}\" ]; then\n"
    "\t\tfor _dev in null zero full random urandom tty console ptmx; do\n"
    "\t\t\tif [ -c \"/dev/$_dev\" ] && [ -e \"$TARGET/dev/$_dev\" ]; then\n"
    "\t\t\t\tmount -o bind \"/dev/$_dev\" \"$TARGET/dev/$_dev\" 2>/dev/null || true\n"
    "\t\t\tfi\n"
    "\t\tdone\n"
    "\t\treturn 0\n"
    "\tfi\n\n"
)
# 插在 fakechroot 早退之后、HOST_OS 分支之前（与宿主上已验证的补丁位置一致）
src = src.replace(anchor_b, anchor_head + insert_b + anchor_tail, 1)

# (c) 容器探测：nodev 上 mknod 探针必然失败，跳过它（chroot 可写可执行就够）。
anchor_c = (
    '\t\t  *)\n'
    '\t\t    mknod "$1/test-dev-null" c 1 3 || return 1\n'
    '\t\t    if ! echo test > "$1/test-dev-null"; then\n'
    '\t\t\trm -f "$1/test-dev-null"\n'
    '\t\t\t\treturn 1\n'
    '\t\t    fi\n'
    '\t\t    rm -f "$1/test-dev-null"\n'
)
repl_c = (
    '\t\t  *)\n'
    '\t\t    # FurryOS build: host mounts /root/furryos with nodev, so the\n'
    '\t\t    # device-node probe cannot work. The chroot target itself is\n'
    '\t\t    # writable and executable, which is what debootstrap needs.\n'
)
if anchor_c not in src:
    sys.exit("patch(c): anchor for the device-node probe not found")
src = src.replace(anchor_c, repl_c, 1)

if src == orig:
    sys.exit("patch: nothing changed")
open(path, "w").write(src)
print("patched: debootstrap functions (nodev workarounds)")
PYDBS

# ------------------------------------- 补丁 2：EFI FAT 镜像尺寸（stat -L）----
GRUBEFI="${DEST}/lbroot/usr/lib/live/scripts/build/binary_grub-efi"
[ -f "${GRUBEFI}" ] || die "解包后找不到 ${GRUBEFI}"
python3 - "${GRUBEFI}" <<'PYGRUB'
import sys

path = sys.argv[1]
src = open(path).read()
# live-build 把这段写在单引号 heredoc 里，源文件里是字面量 \\$file
needle = 'stat -c %s "\\$file"'
if needle not in src:
    if 'stat -L -c %s "\\$file"' in src:
        print("patched: binary_grub-efi already uses stat -L")
        sys.exit(0)
    sys.exit('patch: stat -c %s "\\$file" not found in binary_grub-efi')
# Ubuntu 的 bootx64.efi 是指向签名 shim 的符号链接：不带 -L 只量到 36 字节的
# 链接本身，FAT 镜像就会小到装不下 shim（mcopy: Disk full）。
src = src.replace(needle, 'stat -L -c %s "\\$file"')
open(path, "w").write(src)
print("patched: binary_grub-efi EFI size uses stat -L (follow symlinks)")
PYGRUB

# --------------------- 补丁 3：chroot 挂载阶段的 mtab 容错（第二道防线）----
for SCRIPT in chroot_proc chroot_sysfs chroot_selinuxfs; do
	F="${DEST}/rootfs/usr/lib/live/build/${SCRIPT}"
	[ -f "${F}" ] || die "解包后找不到 ${F}"
	python3 - "${F}" <<'PYMNT'
import re
import sys

path = sys.argv[1]
src = open(path).read()
pat = re.compile(r'^(\t+mount -t (?:proc|sysfs|selinuxfs)[^\n]*?)(\s*\|\|\s*true)?$', re.M)


def fix(m):
    return (m.group(1) + " || true"
            + "  # FurryOS: /etc/mtab is read-only; a successful mount still exits 16")


out, n = pat.subn(fix, src, count=1)
if n != 1:
    sys.exit("patch: no mount -t proc/sysfs/selinuxfs line found in %s" % path)
open(path, "w").write(out)
print("patched: %s tolerates the read-only mtab exit status" % path)
PYMNT
done

# ---------------------- 补丁 4：内核元包名去掉 -amd64 后缀（noble 现实）----
CIP="${DEST}/rootfs/usr/lib/live/build/chroot_install-packages"
[ -f "${CIP}" ] || die "解包后找不到 ${CIP}"
python3 - "${CIP}" <<'PYKRN'
import sys

path = sys.argv[1]
src = open(path).read()
if "Rewrote kernel package" in src:
    print("patched: chroot_install-packages already rewrites the kernel name")
    sys.exit(0)
anchor = ("if [ -e chroot/root/packages.chroot ] && [ -s chroot/root/packages.chroot ]\n"
          "then\n")
block = (
    "\t# FurryOS build: live-build composes the kernel metapackage name as\n"
    "\t# ${LB_LINUX_PACKAGES}-${LB_LINUX_FLAVOURS_WITH_ARCH}, and\n"
    "\t# functions/configuration.sh guarantees the flavour is non-empty\n"
    "\t# (`${VAR:-amd64}` also fires when the variable is set but empty). On\n"
    "\t# Ubuntu the generic kernel metapackages carry NO arch suffix, so the\n"
    "\t# composed name does not exist in the noble archive. Rewrite the queue\n"
    "\t# here, immediately before apt consumes it - this is the only point that\n"
    "\t# is both after chroot_linux-image (which appends the name) and before\n"
    "\t# the install itself.\n"
    "\tfor _PAIR in \\\n"
    "\t\t\"linux-image-generic-amd64 linux-image-generic\" \\\n"
    "\t\t\"linux-image-amd64 linux-image-generic\" \\\n"
    "\t\t\"linux-generic-amd64 linux-generic\"\n"
    "\tdo\n"
    "\t\t_BAD=\"$(echo \"${_PAIR}\" | awk '{print $1}')\"\n"
    "\t\t_GOOD=\"$(echo \"${_PAIR}\" | awk '{print $2}')\"\n"
    "\t\tif grep -qx \"${_BAD}\" chroot/root/packages.chroot; then\n"
    "\t\t\tsed -i \"s|^${_BAD}\\$|${_GOOD}|\" chroot/root/packages.chroot\n"
    "\t\t\tEcho_message \"Rewrote kernel package ${_BAD} -> ${_GOOD}\"\n"
    "\t\tfi\n"
    "\tdone\n\n"
)
if anchor not in src:
    sys.exit("patch: anchor in chroot_install-packages not found")
src = src.replace(anchor, anchor + block, 1)
open(path, "w").write(src)
print("patched: chroot_install-packages rewrites linux-image-*-amd64 -> linux-image-generic")
PYKRN

# --------------------------------- 补丁 5：Ubuntu 套件脚本的 keyring 路径 ----
# debootstrap 的 noble 脚本里 keyring 是绝对路径，宿主的 /usr/share/keyrings
# 没有 ubuntu-archive-keyring.gpg。改成刚解包进来的那份。
KEYRING_DIR="${DEST}/rootfs/usr/share/keyrings"
for SCRIPT in "${DEST}"/rootfs/usr/share/debootstrap/scripts/*; do
	[ -f "${SCRIPT}" ] || continue
	grep -q '/usr/share/keyrings/ubuntu-' "${SCRIPT}" || continue
	python3 - "${SCRIPT}" "${KEYRING_DIR}" <<'PYKEY'
import sys

path, keyring_dir = sys.argv[1], sys.argv[2]
src = open(path).read()
out = src.replace('/usr/share/keyrings/ubuntu-', keyring_dir + '/ubuntu-')
if out != src:
    open(path, "w").write(out)
PYKEY
done

# ---------------------------------------------------------------- shim ----
mkdir -p "${DEST}/shim"

cat > "${DEST}/shim/cat" <<SHIM
#!/bin/bash
# FurryOS cat(1) shim.
#
# live-build 的脚本会读取 /usr/share/live/build/VERSION 之类的路径，而受限宿主上
# live-build 没有装成系统包，这些文件只存在于解包目录
# ${DEST}/rootfs/usr/share/ 下。本 shim 只改写这几类只读读取，其它一律透传。
for a in "\$@"; do
  case "\$a" in
    /usr/share/live/build/*|/usr/share/keyrings/*|/usr/share/debootstrap/*)
      exec /bin/cat "\${a/\\/usr\\/share/${DEST}/rootfs/usr/share}" ;;
  esac
done
exec /bin/cat "\$@"
SHIM
chmod 0755 "${DEST}/shim/cat"

cat > "${DEST}/shim/mount" <<'SHIM'
#!/bin/bash
# FurryOS mount(8) shim.
#
# WHY THIS EXISTS
# ---------------
# The host's /etc is a read-only filesystem, and /etc/mtab is a symlink to
# ../proc/self/mounts. Every successful mount(2) therefore makes mount(8)
# try to update /etc/mtab, fail, and exit with status 16 while printing:
#
#     mount: <target>: filesystem was mounted, but failed to update
#            userspace mount table.
#
# The kernel mount SUCCEEDS (the filesystem is really there and usable), but
# the non-zero exit status makes live-build's `set -e` abort the whole
# build at the first chroot_prep helper:
#
#     lb chroot_devpts install
#     mount: /root/furryos/build/chroot/dev/pts: filesystem was mounted,
#            but failed to update userspace mount table.
#     E: An unexpected failure occurred, exiting...   (exit code 16)
#
# THE FIX
# -------
# `mount -n` ("don't write to /etc/mtab") performs the identical mount(2)
# call and returns 0. The mount table is already maintained by the kernel in
# /proc/mounts, which is exactly what live-build itself reads to decide what
# to unmount (see functions/exit.sh, which greps /proc/mounts). So skipping
# the /etc/mtab write loses nothing.
#
# This shim is placed first in PATH by tools/lb.sh, so every live-build mount
# call transparently becomes `mount -n ...`.
#
# It is deliberately NOT installed as /bin/mount and does not touch the host.

# Do not rewrite an explicit -n/--no-mtab (idempotent).
for a in "$@"; do
  case "$a" in
    -n|--no-mtab|--version|--help|-h|-V)
      exec /bin/mount "$@" ;;
  esac
done

exec /bin/mount -n "$@"
SHIM
chmod 0755 "${DEST}/shim/mount"

# ---------------------------------------------------------------- 自检 ----
log "自检："
FAIL=0
check () {  # check <描述> <命令...>
	_desc="$1"; shift
	if "$@" >/dev/null 2>&1; then
		printf '  [OK]   %s\n' "${_desc}"
	else
		printf '  [FAIL] %s\n' "${_desc}"
		FAIL=$(( FAIL + 1 ))
	fi
}
check "live-build lb 可执行" test -x "${DEST}/rootfs/usr/bin/lb"
check "lbroot scripts/build 就位" test -d "${LBROOT}/scripts/build"
check "lbroot scripts/build.sh 就位" test -f "${LBROOT}/scripts/build.sh"
check "lbroot functions 链接可解析" test -d "${LBROOT}/functions"
check "GRUB 资源映射可解析" test -d "${LBROOT}/share/bootloaders/grub-pc"
check "debootstrap 可执行" test -x "${DEST}/rootfs/usr/sbin/debootstrap"
check "debootstrap noble 套件脚本" test -f "${DEST}/rootfs/usr/share/debootstrap/scripts/noble"
check "ubuntu-keyring 就位" test -f "${DEST}/rootfs/usr/share/keyrings/ubuntu-archive-keyring.gpg"
check "debootstrap nodev 补丁" grep -q 'FURRYOS_BIND_DEVICES' "${DBS}"
check "EFI stat -L 补丁" grep -qF 'stat -L -c %s "\$file"' "${GRUBEFI}"
check "内核包名改写补丁" grep -q 'Rewrote kernel package' "${CIP}"
check "shim/cat" test -x "${DEST}/shim/cat"
check "shim/mount" test -x "${DEST}/shim/mount"

if [ "${FAIL}" -ne 0 ]; then
	die "${FAIL} 项自检失败"
fi

# lb --version 需要 shim/cat 与 LIVE_BUILD 同时生效
if ! PATH="${DEST}/shim:${DEST}/rootfs/usr/bin:${PATH}" \
	LIVE_BUILD="${LBROOT}" \
	"${DEST}/rootfs/usr/bin/lb" --version >/dev/null 2>&1
then
	die "lb --version 运行失败（shim/PATH 配置不对）"
fi

log "完成。接下来：cd build && sh ../tools/lb.sh build"
