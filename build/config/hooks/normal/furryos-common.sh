#!/bin/sh

# FurryOS live-build hooks - shared library.
#
# This file is sourced by every FurryOS .chroot hook (it is bind-mounted
# read-only into the chroot at /live-build/config by lb chroot_hooks, so it
# is reachable from inside the chroot as /live-build/config/hooks/normal/
# furryos-common.sh).
#
# It provides:
#   * strict mode (set -e) for every hook
#   * a small logging helper
#   * FURRYOS_ASSETS: the in-chroot staging directory where the asset
#     integration hooks read the four layers' output from.
#
# IMPORTANT: hooks run inside the chroot via `Chroot chroot "/root/<hook>"`,
# so all paths below are CHROOT-ABSOLUTE paths (i.e. they refer to the target
# system's filesystem, not to the host workspace).
#
# WHERE THE ASSETS ARE REACHABLE FROM INSIDE THE CHROOT
# ----------------------------------------------------
# lb chroot_hooks bind-mounts ONLY `config/` into the chroot, at
# /live-build/config. It does NOT create /live-build/assets - there is no
# second bind mount, so any path under /live-build/ other than
# /live-build/config/ simply does not exist inside the chroot.
#
# The asset layers therefore live under /live-build/config/assets/ (that is
# where tools/sync-assets.sh copies them), and hook 6000 copies them to
# /opt/furryos/assets so that the per-layer hooks can read them from a path
# that also survives the cleanup hook. FURRYOS_ASSETS below points at that
# staging directory - NOT at a /live-build/assets path, which was the
# original bug: every layer hook then silently found nothing and degraded to
# "no branding" without failing the build.

set -e

FURRYOS_LOG_TAG="[furryos]"
FURRYOS_ASSETS="/opt/furryos/assets"

# furryos_log <message...>
furryos_log ()
{
	echo "${FURRYOS_LOG_TAG} $*"
}

# furryos_warn <message...>
furryos_warn ()
{
	echo "${FURRYOS_LOG_TAG} WARNING: $*" >&2
}

# furryos_need_file <path> <description>
# Abort with a clear message when a contract-mandated asset is missing.
furryos_need_file ()
{
	if [ ! -e "${1}" ]
	then
		echo "${FURRYOS_LOG_TAG} ERROR: required asset missing: ${1} (${2})" >&2
		exit 1
	fi
}

# furryos_install_file <src> <dest> <mode>
# Copy an asset into the target filesystem with an explicit mode.
furryos_install_file ()
{
	install -D -m "${3}" "${1}" "${2}"
}

# furryos_install_dir <src> <dest>
# Recursively copy an asset directory into the target filesystem.
furryos_install_dir ()
{
	install -d "${2}"
	cp -a "${1}/." "${2}/"
}
