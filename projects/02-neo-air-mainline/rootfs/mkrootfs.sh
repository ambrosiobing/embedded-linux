#!/bin/sh
#
# mkrootfs.sh - a Debian armhf root filesystem for the NEO Air.
#
# RUNS ON THE HOST, needs root for debootstrap and chroot.
#
#   . projects/02-neo-air-mainline/toolchain.env
#   sudo ./go neo-air rootfs
#
# Produces $NEO_OUT/rootfs.tar, which tools/sdcard.sh extracts onto
# partition 2.
#
# THE ORDER OF TWO STEPS IN HERE IS THE WHOLE POINT.
#
# The kernel fragment builds brcmfmac as a module. If the root filesystem
# is assembled before those modules are installed into it, Wi-Fi does not
# fail on the board. It is absent: no wlan0, no message in dmesg naming a
# cause, and nothing to search for except the absence itself. The board
# looks like it has no radio.
#
# So the modules are copied in and depmod is run as part of building the
# filesystem, before it is packed, and this script refuses to run at all if
# the kernel build has not happened yet. A missing module directory is
# detectable here and almost undetectable on the board.
#
# SPDX-License-Identifier: MIT

set -eu

die() {
	echo "mkrootfs: $1" >&2
	exit 1
}

note() {
	echo "--- $1"
}

[ "${NEO_ENV:-}" = 1 ] || die "toolchain.env has not been sourced.
       sudo ./go neo-air rootfs
       That sources it inside the sudo, which is the only form that
       works. Sourcing it in your own shell does not survive sudo, and
       -E does not rescue it on a sudo that ignores -E."

HERE=$(cd "$(dirname "$0")" && pwd)
OVERLAY=$HERE/overlay
[ -d "$OVERLAY" ] || die "no overlay at $OVERLAY"

[ "$(id -u)" = 0 ] || die "debootstrap and chroot need root.
       sudo ./go neo-air rootfs"

for tool in debootstrap chroot tar depmod; do
	command -v "$tool" >/dev/null 2>&1 ||
		die "$tool is missing.
       sudo apt install debootstrap qemu-user-binfmt"
done

# The second stage runs armhf binaries on an x86 host, which only works if
# binfmt has qemu registered. Without it the failure is a chroot that
# reports "Exec format error" halfway through, leaving a half-built tree
# that looks like a disk problem.
[ -r /proc/sys/fs/binfmt_misc/qemu-arm ] ||
	die "qemu-arm is not registered with binfmt_misc, so the second stage
       of debootstrap cannot run armhf binaries on this host.

       On Ubuntu 26.04 and later, qemu-user-static is a virtual package
       and the provider is the one to install:
       sudo apt install qemu-user-binfmt
       sudo systemctl restart systemd-binfmt"

# ------------------------------------------- the refusal that matters

MODULES=$NEO_OUT/modules
VERSION_FILE=$NEO_OUT/kernel-version

[ -r "$VERSION_FILE" ] || die "no $VERSION_FILE.
       Build the kernel first: kernel/build.sh writes it.
       Assembling a root filesystem before the modules exist produces a
       board with no wireless interface and nothing in dmesg to say why."

KVER=$(cat "$VERSION_FILE")
[ -d "$MODULES/lib/modules/$KVER" ] ||
	die "no modules at $MODULES/lib/modules/$KVER
       The kernel build did not install them, or it built a different
       version. This is the one failure that is invisible on the board:
       brcmfmac is a module, and without it the radio simply is not there."

note "kernel     $KVER"
note "modules    $MODULES/lib/modules/$KVER"

# ---------------------------------------------------------- debootstrap

ROOT=${NEO_ROOTFS_DIR:-$NEO_WORK/rootfs}
rm -rf "$ROOT"
mkdir -p "$ROOT" "$NEO_OUT"

note "debootstrap $DEBIAN_SUITE $DEBIAN_ARCH from $DEBIAN_MIRROR"
debootstrap --arch="$DEBIAN_ARCH" --foreign "$DEBIAN_SUITE" "$ROOT" "$DEBIAN_MIRROR"

# The second stage runs armhf binaries through the binfmt handler. How the
# interpreter reaches the chroot depends on the release, and getting this
# wrong gives "Exec format error" halfway through a half-built tree.
#
# Modern registrations carry the F flag, which opens the interpreter once
# at registration time and keeps the file descriptor, so it works inside
# any chroot and nothing has to be copied. Older ones need a statically
# linked qemu copied in, which is what qemu-user-static existed for.
#
# Ubuntu 26.04 dropped qemu-user-static as a real package: it is a virtual
# one now, provided by qemu-user-binfmt, and there is no qemu-arm-static
# binary at all, only a dynamically linked /usr/bin/qemu-arm. The first
# version of this script copied "$(command -v qemu-arm-static)" with a
# "|| true" after it, so on that release it silently copied nothing and
# would have worked or not depending on a flag it never looked at.
QEMU_COPIED=
if grep -q '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-arm 2>/dev/null; then
	note "binfmt qemu-arm is registered with the F flag, so the"
	note "           interpreter is already open and nothing is copied in"
else
	qemu=$(command -v qemu-arm-static || command -v qemu-arm || true)
	[ -n "$qemu" ] || die "the qemu-arm binfmt handler has no F flag and
       neither qemu-arm-static nor qemu-arm is on PATH, so the second
       stage of debootstrap cannot run armhf binaries here.
       sudo apt install qemu-user-binfmt"
	note "binfmt has no F flag, copying $qemu into the chroot"
	cp "$qemu" "$ROOT/usr/bin/"
	QEMU_COPIED=$ROOT/usr/bin/$(basename "$qemu")
fi

chroot "$ROOT" /debootstrap/debootstrap --second-stage

# debootstrap writes a sources.list carrying main and nothing else, and
# the firmware this board needs is not in main.
#
# Bookworm split non-free-firmware out of non-free so that firmware could
# be installed without dragging in the rest of non-free. The component is
# therefore both necessary and narrow. Without it apt says
#
#   E: Unable to locate package firmware-brcm80211
#
# which reads like a wrong package name and is really a missing component.
# That is a whole evening if the reader trusts the wording.
#
# The component name is bookworm and later. On an older suite it would be
# plain non-free, so this line is tied to DEBIAN_SUITE rather than being
# universal, and DEBIAN_SUITE is pinned in toolchain.env.
note "sources.list: main non-free-firmware"
printf 'deb %s %s main non-free-firmware\n' \
	"$DEBIAN_MIRROR" "$DEBIAN_SUITE" >"$ROOT/etc/apt/sources.list"

note "packages"
chroot "$ROOT" apt-get update
chroot "$ROOT" apt-get install -y --no-install-recommends \
	systemd-sysv udev openssh-server wpasupplicant firmware-brcm80211 \
	iproute2 iputils-ping e2fsprogs rsync fdisk iw wireless-regdb

# The regulatory database, signed with a key this kernel trusts.
#
# wireless-regdb ships two copies and update-alternatives picks
# regulatory.db-debian, which is signed with Debian's key. A mainline kernel
# trusts only the upstream keys it was built with, so it rejects that one
# and says so on every boot:
#
#   cfg80211: Loading compiled-in X.509 certificates for regulatory database
#   Loaded X.509 cert 'sforshee: 00b28ddf47aef9cea7'
#   Loaded X.509 cert 'wens: 61c038651aabdcf94bd0ac7ff06c7248db18c600'
#   cfg80211: loaded regulatory.db is malformed or signature is missing/invalid
#
# The radio still works, on the world-restrictive default domain, which
# costs channels rather than function. regulatory.db-upstream is signed by
# sforshee, which is one of the two certificates named on the line above.
#
# Guarded rather than assumed: if the alternative is not registered under
# that name the boot is no worse than it is today, and a failure here should
# not take down a root filesystem build over a channel list.
note "regulatory database"
if chroot "$ROOT" update-alternatives --set regulatory.db \
	/lib/firmware/regulatory.db-upstream >/dev/null 2>&1; then
	note "           regulatory.db-upstream selected, signed by sforshee"
else
	note "           could not select regulatory.db-upstream; the kernel will"
	note "           reject Debian's copy and fall back to the world domain"
fi

# The NVRAM, under the name the driver will actually ask for.
#
# brcmfmac needs two files. The .bin is unambiguous. The NVRAM is not: the
# driver builds its filename from the board type, which it takes from the
# device tree's root compatible string, and falls back to a generic name:
#
#   brcmfmac43430-sdio.friendlyarm,nanopi-neo-air.txt   asked for first
#   brcmfmac43430-sdio.txt                              tried next
#
# firmware-brcm80211 ships neither of those names. It does ship
# brcmfmac43430-sdio.AP6212.txt, and the AP6212 is the module on this
# board: a BCM43430 with Bluetooth on one SDIO bus. NVRAM is a property of
# the module, its crystal and its antenna path, rather than of the carrier
# it is soldered to, which is why the vendor name is the useful one and why
# Debian ships it that way.
#
# So the file this project was going to fetch by hand from a vendor image
# has been in the archive the whole time, under a name the driver will
# never request. Installing it under the name the driver does request
# removes the only unpinned input in Project 2.
#
# The first version of this check asked whether any .txt existed in that
# directory. Fourteen do, for Raspberry Pis and Banana Pis and two
# tablets, and none of them is the one this board needs. It reported
# success. Same failure as the config checks: a narrower question than the
# claim above it.
FWDIR=$ROOT/lib/firmware/brcm
FWBIN=$FWDIR/brcmfmac43430-sdio.bin
NVWANT=$FWDIR/brcmfmac43430-sdio.$BOARD_COMPATIBLE.txt
NVFALLBACK=$FWDIR/brcmfmac43430-sdio.txt
NVSRC=$FWDIR/brcmfmac43430-sdio.AP6212.txt

note "brcm firmware:"
[ -f "$FWBIN" ] || die "firmware-brcm80211 installed and $FWBIN is not there.
       The package moved its contents or the install did not do what it
       said. Without the firmware there is no radio at all."
note "           brcmfmac43430-sdio.bin"

if [ -f "$NVWANT" ] || [ -f "$NVFALLBACK" ]; then
	note "           nvram already present under a name the driver asks for"
elif [ -f "$NVSRC" ]; then
	cp "$NVSRC" "$NVWANT"
	note "           nvram installed from brcmfmac43430-sdio.AP6212.txt as"
	note "           brcmfmac43430-sdio.$BOARD_COMPATIBLE.txt"
	note "           sha256 $(sha256sum "$NVWANT" | cut -d' ' -f1)"
else
	note "           NO NVRAM under any name this driver asks for."
	note "           brcmfmac will load the firmware and then time out"
	note "           bringing the SDIO clock up, which reads exactly like"
	note "           broken hardware. See docs/BRINGUP.md section 5."
fi

# ------------------------------------------------- the modules, then depmod

note "installing modules and running depmod"
mkdir -p "$ROOT/lib/modules"
cp -a "$MODULES/lib/modules/$KVER" "$ROOT/lib/modules/"
chroot "$ROOT" depmod -a "$KVER"

# Assert rather than assume. depmod writing no modules.dep for this
# version means the copy landed somewhere else, and the board would boot
# with a radio that never appears.
[ -s "$ROOT/lib/modules/$KVER/modules.dep" ] ||
	die "depmod produced no modules.dep for $KVER."
grep -q 'brcmfmac' "$ROOT/lib/modules/$KVER/modules.dep" ||
	die "brcmfmac is not in modules.dep after depmod.
       The kernel fragment asks for it as a module and it is not in the
       root filesystem. Wi-Fi would be absent with no message."
note "           brcmfmac is in modules.dep"

# ---------------------------------------------------------- the overlay

note "overlay"
# -a preserves modes, and the example file stays an example: the real
# wpa_supplicant configuration holds a passphrase and is written on the
# card, never in this repository. See .gitignore.
cp -a "$OVERLAY/." "$ROOT/"

printf 'neo-air\n' >"$ROOT/etc/hostname"
printf '127.0.1.1\tneo-air\n' >>"$ROOT/etc/hosts"

# fstab with the same placeholder discipline as extlinux.conf: visibly
# impossible rather than plausibly wrong. flash-emmc.sh rewrites both.
cat >"$ROOT/etc/fstab" <<'EOF'
# Rewritten by tools/flash-emmc.sh with the real PARTUUID when the eMMC is
# provisioned, and by tools/sdcard.sh for the card itself. A device name
# here would be wrong half the time: names are assigned in probe order.
#
# The boot partition is mounted at /boot on purpose. U-Boot reads the
# kernel and extlinux.conf from it directly at boot time, but Linux needs
# it mounted too, because flash-emmc.sh reads the bootloader image from
# /boot and copies /boot to the new eMMC boot partition. Without this line
# /boot is an empty directory on the root filesystem and provisioning the
# eMMC cannot work. Two distinct placeholders so each line is patched with
# its own partition's PARTUUID.
PARTUUID=FILLED-BY-FLASH-EMMC / ext4 defaults,noatime 0 1
PARTUUID=FILLED-BY-FLASH-BOOT /boot ext4 defaults,noatime 0 2
EOF

chroot "$ROOT" systemctl enable systemd-networkd
chroot "$ROOT" systemctl enable wpa_supplicant@wlan0 || true

# Mask the generic wpa_supplicant.service. Two units ship: the templated
# wpa_supplicant@wlan0, which reads our per-interface config and is the one
# enabled above, and a generic wpa_supplicant.service that wants D-Bus.
# --no-install-recommends leaves dbus out, so the generic unit fails on
# every boot with a red line, while the interface unit it has nothing to do
# with works. Masking it says "this one is not used here" rather than
# leaving a failure that invites someone to install dbus chasing it.
chroot "$ROOT" systemctl mask wpa_supplicant.service

# The ssh host keys openssh-server's postinst generated a moment ago are
# this build machine's keys, made inside the chroot. Left in the tar they
# become the keys of every board ever written from it, and the private
# half travels with the image. A private key everything shares is not a
# key, and the comment field carries the build host's name as well.
#
# Deleted here, regenerated on the board at first boot by a unit in the
# overlay. ssh-keygen -A writes only what is missing, so it is idempotent
# and a reflashed board does it once.
# The overlay drops a file into /etc/ssh/sshd_config.d so that the root
# password this script asks for is usable over ssh as well as on the
# console. That only works if Debian's sshd_config still carries its
# Include line, so it is checked rather than assumed: a silent failure
# here gives a board that accepts the password on the console and refuses
# it over the network, which reads as a wrong password rather than as a
# policy, and this board's console is the thing most likely to be
# unavailable when it matters.
SSHD=$ROOT/etc/ssh/sshd_config
if grep -q '^Include /etc/ssh/sshd_config.d/' "$SSHD"; then
	note "sshd reads its drop-in directory, the overlay's policy applies"
else
	note "sshd_config has no Include line, appending the policy directly"
	sed -i 's/^#*PermitRootLogin .*/PermitRootLogin yes/' "$SSHD"
	grep -q '^PermitRootLogin yes' "$SSHD" ||
		printf '\nPermitRootLogin yes\n' >>"$SSHD"
fi

note "removing the build host's ssh host keys"
rm -f "$ROOT"/etc/ssh/ssh_host_*
chroot "$ROOT" systemctl enable regenerate-ssh-host-keys

# Root has no password and no console login is possible without one. This
# is a bench board on an isolated network, and the console is a cable
# somebody has to be holding. Stated rather than left implicit.
note "setting the root password"
chroot "$ROOT" passwd

# ------------------------------------------------------------- pack

# Only if one was copied in. Removing a name that was never there is
# harmless; removing the wrong name leaves an interpreter in the tar.
[ -z "$QEMU_COPIED" ] || rm -f "$QEMU_COPIED"
note "packing"
tar --numeric-owner -C "$ROOT" -cf "$NEO_OUT/rootfs.tar" .
size=$(du -h "$NEO_OUT/rootfs.tar" | cut -f1)
note "wrote      $NEO_OUT/rootfs.tar, $size"
