#!/bin/sh
#
# deploy.sh - put a freshly built image where the DUT will boot it from.
#
# Two destinations, and they must agree: the boot files go to the TFTP
# directory the boot ROM reads, and the root filesystem goes to the NFS
# export the kernel mounts. A deploy that updates one and not the other
# gives a board running last week's userspace under this week's kernel,
# which is a confusing enough state that test_boot.py checks for it
# explicitly.
#
#   sh deploy.sh                       from the default build directory
#   HIL_DEPLOY_SRC=/path sh deploy.sh  from somewhere else
#
# SPDX-License-Identifier: MIT

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

# Where the built artefacts are. On the server this is usually a directory
# rsynced from the build host; on the build host itself it is the Yocto
# deploy directory.
SRC=${HIL_DEPLOY_SRC:-$HOME/bench/build/tmp/deploy/images/raspberrypi3-64}

TFTP_ROOT=${HIL_TFTP_ROOT:-/srv/tftp}
NFS_ROOT=${HIL_NFS_ROOT:-/srv/nfs/dut3}

# The DUT's serial number, last eight hex digits of the Serial line in its
# /proc/cpuinfo, read once from a normal SD boot. The boot ROM looks in a
# directory of that name before falling back to the TFTP root.
SERIAL=${HIL_DUT_SERIAL:-}

die() {
	echo "deploy.sh: $*" >&2
	exit 1
}

note() {
	printf -- '--- %s\n' "$*"
}

[ -d "$SRC" ] || die "no build directory at $SRC.
       Set HIL_DEPLOY_SRC, or build first with: ./go netboot"

# The rootfs arrives as a tarball rather than a .wic, because an NFS export
# is a directory tree and not a disk image. bench-netboot-image sets
# IMAGE_FSTYPES accordingly; if this glob finds nothing, the image built was
# the wrong one.
tarball=$(find "$SRC" -maxdepth 1 \
	-name 'bench-netboot-image-*.rootfs.tar.bz2' \
	-printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -1)
[ -n "$tarball" ] || die "no rootfs tarball in $SRC.
       bench-netboot-image sets IMAGE_FSTYPES to include tar.bz2; a .wic
       there instead means ./go build ran rather than ./go netboot."

# --- the boot files ---------------------------------------------------

if [ -n "$SERIAL" ]; then
	target=$TFTP_ROOT/$SERIAL
else
	target=$TFTP_ROOT
	note "no HIL_DUT_SERIAL set, deploying to the TFTP root"
	note "that works for one DUT; a second one needs per-serial directories"
fi

note "boot files -> $target"
mkdir -p "$target"

# bootcode.bin is the exception and it is not optional. The boot ROM asks
# for it at the TFTP root before it knows its own serial number, so a copy
# inside the serial directory alone is never found.
for file in bootcode.bin start.elf start4.elf fixup.dat fixup4.dat \
	config.txt cmdline.txt; do
	[ -f "$SRC/$file" ] && cp -f "$SRC/$file" "$target/"
done
[ -f "$SRC/bootcode.bin" ] && cp -f "$SRC/bootcode.bin" "$TFTP_ROOT/"

# The kernel and the device tree for a 3B+.
[ -f "$SRC/Image" ] && cp -f "$SRC/Image" "$target/kernel8.img"
dtb=$SRC/bcm2710-rpi-3-b-plus.dtb
[ -f "$dtb" ] && cp -f "$dtb" "$target/"
[ -d "$SRC/bcm2710-rpi-3-b-plus" ] && true   # some layouts nest overlays
[ -d "$SRC/overlays" ] && cp -rf "$SRC/overlays" "$target/"

# --- the root filesystem ----------------------------------------------
#
# Extracted rather than rsynced, because what the build produces is a
# tarball. The export is emptied first: an rsync over an old tree leaves
# files the new image deleted, and a package that was removed still being
# present is exactly the sort of difference that makes a test pass on a
# board nobody could reproduce.

note "rootfs -> $NFS_ROOT (from $(basename "$tarball"))"
[ -d "$NFS_ROOT" ] || die "no export directory at $NFS_ROOT; run server/install.sh"

if mountpoint -q "$NFS_ROOT" 2>/dev/null; then
	die "$NFS_ROOT is a mount point; refusing to empty it"
fi

find "$NFS_ROOT" -mindepth 1 -delete
tar -xf "$tarball" -C "$NFS_ROOT"

# --- what the DUT will report -----------------------------------------
#
# Written so that test_kernel_is_the_one_we_deployed has something to
# compare against. Without it that test can only check that uname works.

mkdir -p "$HERE/build"
# Newest, not lexically first. A rootfs that has carried two kernels has
# two directories here, and text order is not version order: 6.12.93 sorts
# before 6.6.63 because "1" is less than "6". The same sort bug has been
# written five times in this repository, which is why common.sh has
# newest_path; this script runs on the HIL server without that file, so the
# ranking is spelled out rather than imported.
release=$(find "$NFS_ROOT/lib/modules" -maxdepth 1 -mindepth 1 -type d \
	-printf '%T@ %f\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -1)
if [ -n "$release" ]; then
	printf '%s\n' "$release" >"$HERE/build/kernel-release"
	note "deployed kernel release $release"
else
	rm -f "$HERE/build/kernel-release"
	note "no /lib/modules in the rootfs, so the kernel release is unknown"
fi

note "done. The DUT will pick this up at its next reset."
