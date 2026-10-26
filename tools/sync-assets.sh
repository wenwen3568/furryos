#!/bin/sh

# FurryOS asset synchronisation.
#
# Copies the four layers' output (assets/identity, assets/desktop,
# assets/sddm, assets/effects) plus the captain's brand tokens (assets/brand)
# into build/config/assets/, which is what the FurryOS live-build hooks read.
#
# Why a copy instead of a symlink or an absolute path?
#   * lb chroot_hooks bind-mounts `config` into the chroot at
#     /live-build/config read-only. Only what is inside config/ is visible to
#     the hooks, so the assets must live under config/.
#   * Symlinking config/assets -> ../../../assets would place a dangling
#     symlink in the ISO's config tree and would break the read-only remount
#     (the remount,ro applies to the resolved target).
#
# Usage:
#   tools/sync-assets.sh          copy assets (idempotent)
#   tools/sync-assets.sh --check  report status without copying

set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${WORKSPACE}/assets"
DST="${WORKSPACE}/build/config/assets"

CHECK_ONLY="false"
[ "${1}" = "--check" ] && CHECK_ONLY="true"

echo "[sync-assets] workspace: ${WORKSPACE}"

STATUS=0

for LAYER in identity desktop sddm effects brand; do
	if [ ! -d "${SRC}/${LAYER}" ]
	then
		echo "[sync-assets] MISSING  assets/${LAYER}"
		STATUS=1
		continue
	fi

	COUNT="$(find "${SRC}/${LAYER}" -type f | wc -l)"
	if [ "${COUNT}" -eq 0 ]
	then
		echo "[sync-assets] EMPTY    assets/${LAYER} (no files yet)"
		STATUS=1
		continue
	fi

	if [ "${CHECK_ONLY}" = "true" ]
	then
		echo "[sync-assets] PRESENT  assets/${LAYER} (${COUNT} files)"
		continue
	fi

	rm -rf "${DST}/${LAYER}"
	install -d -m 0755 "${DST}"
	cp -a "${SRC}/${LAYER}" "${DST}/${LAYER}"
	echo "[sync-assets] COPIED   assets/${LAYER} -> ${DST}/${LAYER} (${COUNT} files)"
done

if [ "${CHECK_ONLY}" = "true" ]
then
	if [ "${STATUS}" -eq 0 ]
	then
		echo "[sync-assets] all layers present"
	else
		echo "[sync-assets] one or more layers missing/empty (downstream hooks will degrade)"
	fi
	exit "${STATUS}"
fi

# Remove stale layers that no longer exist upstream.
for LAYER in identity desktop sddm effects brand; do
	if [ -d "${DST}/${LAYER}" ] && [ ! -d "${SRC}/${LAYER}" ]
	then
		rm -rf "${DST}/${LAYER}"
		echo "[sync-assets] PRUNED   ${DST}/${LAYER}"
	fi
done

echo "[sync-assets] done -> ${DST}"
exit 0
