#!/bin/bash
# FurryOS live-build wrapper.
#
# Host constraints that force this wrapper:
#
#   * /usr tree and dpkg database are read-only -> live-build and debootstrap
#     run from workspace-local extractions instead of apt install.
#
#   * /root/furryos is mounted nodev. debootstrap's default
#     setup_devices_simple() runs mknod, which *succeeds* on a nodev mount but
#     produces a character device that cannot be opened. Every package
#     postinst that redirects to /dev/null then fails with
#     "Permission denied" (base-files, dpkg, libc6, procps ...).
#
#     Fix: tools/rootfs/usr/share/debootstrap/functions has setup_devices()
#     patched so the non-container branch calls setup_devices_bind(), which
#     bind-mounts the host's working /dev devices into the chroot. That patch
#     is only reachable when debootstrap does NOT think it is inside a
#     container, so this wrapper deliberately does not export container=lxc.
#
#   * live-build's Chroot() enters the chroot with `env -i`, wiping the host
#     environment. build/config/environment.chroot re-declares
#     FURRYOS_BIND_DEVICES=1 so the bind-mount fallback also stays active for
#     every later chroot stage.
#
# Workspace-local extractions:
#   * live-build 20230502 (Debian)   -> tools/rootfs/usr/lib/live
#   * debootstrap 1.0.144ubuntu1     -> merged scripts incl. the noble suite
#   * ubuntu-keyring                 -> tools/rootfs/usr/share/keyrings
LBROOT=/root/furryos/tools
BUILD=/root/furryos/build
export DEBOOTSTRAP_DIR="$LBROOT/rootfs/usr/share/debootstrap"
export FURRYOS_BIND_DEVICES=1

BIN="$LBROOT/shim"
mkdir -p "$BIN"
cat > "$BIN/cat" <<'SHIM'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    /usr/share/live/build/*|/usr/share/keyrings/*|/usr/share/debootstrap/*)
      exec /bin/cat "${a/\/usr\/share//root/furryos/tools/rootfs/usr/share}" ;;
  esac
done
exec /bin/cat "$@"
SHIM
chmod +x "$BIN/cat"

export PATH="$BIN:$LBROOT/rootfs/usr/bin:$LBROOT/rootfs/usr/sbin:$LBROOT/rootfs/usr/share/live/build:$PATH"
export LIVE_BUILD="$LBROOT/lbroot/usr/lib/live"

# Ensure the chroot's /dev devices are usable before every invocation.
#
# Two failure modes are handled here:
#
#  1. live-build's chroot_prep/chroot_devpts stages unmount the bind mounts
#     that debootstrap created, so /dev inside the chroot reverts to the
#     unusable nodev device nodes.
#
#  2. Worse: when a device node cannot be opened, shell redirection such as
#     `> /dev/null` creates a REGULAR FILE in its place. apt-key does exactly
#     this, which then makes gpgv look "not installed". Any regular file
#     sitting at a device path must be removed and the device re-bound.
rebind_chroot_devices () {
	local devdir="$BUILD/chroot/dev"
	[ -d "$devdir" ] || return 0

	# /dev/pts must be a real devpts mount: apt writes its log through a pty
	# and fails with "Can not write log (Is /dev/pts mounted?)" otherwise.
	# live-build mounts it during chroot_devpts but unmounts it again when the
	# stage ends, so re-establish it here for the whole invocation.
	mkdir -p "$devdir/pts"
	if ! mountpoint -q "$devdir/pts" 2>/dev/null; then
		mount -t devpts -o gid=5,mode=620 devpts-live "$devdir/pts" 2>/dev/null || \
			mount -o bind /dev/pts "$devdir/pts" 2>/dev/null || true
	fi

	for dev in null zero full random urandom tty console ptmx; do
		local path="$devdir/$dev"
		if [ -f "$path" ] && [ ! -b "$path" ]; then
			# A regular file replaced the device node (redirection fallback).
			rm -f "$path"
		fi
		if [ ! -e "$path" ]; then
			mknod -m 666 "$path" c 1 3 2>/dev/null || true
		fi
		if [ -c "$path" ] && ! mountpoint -q "$path" 2>/dev/null; then
			case "$dev" in
				null)    mount -o bind /dev/null    "$path" 2>/dev/null || true ;;
				zero)    mount -o bind /dev/zero    "$path" 2>/dev/null || true ;;
				full)    mount -o bind /dev/full    "$path" 2>/dev/null || true ;;
				random)  mount -o bind /dev/random  "$path" 2>/dev/null || true ;;
				urandom) mount -o bind /dev/urandom "$path" 2>/dev/null || true ;;
				tty)     mount -o bind /dev/tty     "$path" 2>/dev/null || true ;;
				console) mount -o bind /dev/console "$path" 2>/dev/null || true ;;
				ptmx)    mount -o bind /dev/ptmx    "$path" 2>/dev/null || true ;;
			esac
		fi
	done
	return 0
}
rebind_chroot_devices

exec "$LBROOT/rootfs/usr/bin/lb" "$@"
