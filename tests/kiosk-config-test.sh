#!/bin/sh
#
# kiosk-config-test.sh - the graphics configuration, without graphics.
#
# Project 13 has no code that can be unit tested on a laptop: the
# dashboard needs a compositor and the compositor needs a GPU. What CAN
# be checked here is the thing that actually breaks, which is agreement
# between five files that nothing forces to agree:
#
#   kas/bench-kiosk.yml            sets the rotation and the distro feature
#   weston-kiosk.ini               selects the shell and the output
#   99-bench-touch.rules           could rotate a second time
#   bench-kiosk_0.1.bb             installs the rule OUT of udev's path
#   bench-hmi_0.1.bb               pins LVGL and verifies its own config
#
# The rotation rule is the one worth a test. It is set once on the
# kernel command line, and the whole design depends on it NOT being set
# again in weston.ini or armed in udev. Both of those are one
# uncommented line away, and the symptom, touch working correctly upside
# down, is the hardest version of the bug to read.
#
#   sh tests/kiosk-config-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

KAS=$ROOT/kas/bench-kiosk.yml
INI=$ROOT/meta-bench/recipes-graphics/wayland/files/weston-kiosk.ini
RULES=$ROOT/meta-bench/recipes-bench/bench-kiosk/files/99-bench-touch.rules
KIOSK_BB=$ROOT/meta-bench/recipes-bench/bench-kiosk/bench-kiosk_0.1.bb
HMI_BB=$ROOT/meta-bench/recipes-bench/bench-hmi/bench-hmi_0.1.bb
IMAGE=$ROOT/meta-bench/recipes-core/images/bench-kiosk-image.bb
GFX=$ROOT/meta-bench/recipes-bench/bench-kiosk/files/bench-gfx

pass=0
fail=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	shift
	for line in "$@"; do
		echo "           $line"
	done
	fail=$((fail + 1))
}

# Every file this suite reasons about must exist. A test that silently
# skips a missing file reports a clean run for a question it never asked.
for f in "$KAS" "$INI" "$RULES" "$KIOSK_BB" "$HMI_BB" "$IMAGE" "$GFX"; do
	if [ ! -f "$f" ]; then
		no "input file missing: $f"
	fi
done
[ "$fail" -eq 0 ] || { echo; echo "$pass passed, $fail failed"; exit 1; }

# ------------------------------------------------ rotation, set exactly once
if grep -q 'panel_orientation=upside_down' "$KAS"; then
	ok "the rotation is set on the kernel command line"
else
	no "the rotation is not set in kas/bench-kiosk.yml" \
		"Every layer above inherits it from there."
fi

# weston.ini must NOT rotate. Comments are allowed to discuss it; an
# active transform= line is the failure.
if grep -vE '^[[:space:]]*#' "$INI" | grep -qE '^[[:space:]]*transform='; then
	no "weston-kiosk.ini has an active transform= line" \
		"The kernel command line already rotates the output." \
		"Rotating again turns the picture twice while touch" \
		"follows only the first rotation."
else
	ok "weston-kiosk.ini does not rotate a second time"
fi

# The udev rule must ship with every matrix commented out.
if grep -vE '^[[:space:]]*#' "$RULES" | grep -q 'LIBINPUT_CALIBRATION_MATRIX'; then
	no "99-bench-touch.rules has an ACTIVE calibration matrix" \
		"It ships disabled on purpose: on a correctly rotated" \
		"panel it rotates the touch surface a second time."
else
	ok "the touch calibration rule ships with every matrix disabled"
fi

# And it must not be installed where udev would read it.
if grep -qE 'install .*99-bench-touch\.rules.*(udev/rules\.d|sysconfdir}/udev)' "$KIOSK_BB"; then
	no "bench-kiosk installs the rule into udev's path" \
		"That arms a correction nobody has measured the need for."
else
	ok "the rule is installed as documentation, not into udev's path"
fi

# ------------------------------------------------------ the shell selection
if grep -qE '^[[:space:]]*shell=kiosk[[:space:]]*$' "$INI"; then
	ok "weston.ini selects the kiosk shell by its weston 13 name"
else
	no "weston.ini does not say 'shell=kiosk'" \
		"Weston 13 takes the short name. The kiosk-shell.so" \
		"spelling is from older releases and is ignored, which" \
		"leaves the desktop shell running."
fi

if grep -qE '^[[:space:]]*path=/usr/bin/bench-hmi[[:space:]]*$' "$INI"; then
	ok "weston.ini autolaunches the dashboard"
else
	no "weston.ini does not autolaunch /usr/bin/bench-hmi" \
		"Without it weston paints the kiosk background and sits" \
		"there, which looks like a compositor failure."
fi

# ------------------------------------------------ the distro feature weston needs
if grep -qE 'DISTRO_FEATURES:append.*pam' "$KAS"; then
	ok "the kas file adds pam, which weston requires under systemd"
else
	no "kas/bench-kiosk.yml does not add pam to DISTRO_FEATURES" \
		"weston's required-distro-features.inc demands it when" \
		"the init manager is systemd, and poky does not supply" \
		"it. The build stops in features_check naming weston."
fi

# ----------------------------------------------------- the LVGL version pin
# The whole reason bench-hmi vendors LVGL is that meta-oe pins 9.1.0,
# which has no wayland driver at all. Pinning it back to that commit
# would build cleanly and produce a binary with no Wayland support.
if grep -q 'e1c0b21b2723d391b885de4b2ee5cc997eccca91' "$HMI_BB"; then
	no "bench-hmi pins LVGL 9.1.0, which HAS NO WAYLAND DRIVER" \
		"src/drivers/ at that revision holds display, evdev," \
		"libinput, nuttx, sdl, windows and x11. The wayland" \
		"driver arrives in 9.2.0."
else
	ok "bench-hmi does not pin the wayland-less LVGL 9.1.0"
fi

if grep -qE 'SRCREV_lvgl = "[0-9a-f]{40}"' "$HMI_BB"; then
	ok "the LVGL pin is a full commit hash"
else
	no "SRCREV_lvgl is not a 40 character hash" \
		"A branch name or a short hash makes the build" \
		"unreproducible, which for a vendored toolkit means the" \
		"binary changes without the recipe changing."
fi

# The recipe must verify its own generated lv_conf.h, because every
# option there is set by a sed and a sed that matches nothing succeeds.
if grep -q 'check_conf LV_USE_WAYLAND 1' "$HMI_BB"; then
	ok "bench-hmi verifies that LV_USE_WAYLAND actually took"
else
	no "bench-hmi does not verify its generated lv_conf.h" \
		"Every option there is set with sed, and a sed whose" \
		"pattern matches nothing changes nothing and reports" \
		"success. That is how a build produces an HMI with no" \
		"Wayland support and no complaint."
fi

# ------------------------------------------ the image carries the drivers
#
# The sharpest assertion in this suite. Every driver this project needs
# is =m in bcm2711_defconfig, and core-image-minimal installs no kernel
# modules, so without this line the image has no /dev/dri, no panel and
# no touch device. The symptom is a black screen, which is also the
# symptom of four other things.
if grep -qE '^[[:space:]]*kernel-modules[[:space:]]*\\?[[:space:]]*$' "$IMAGE"; then
	ok "the image installs kernel-modules"
else
	no "the image does not install kernel-modules" \
		"CONFIG_DRM, DRM_VC4, DRM_V3D, the panel driver and" \
		"edt_ft5x06 are all =m in the Pi 4 defconfig, and" \
		"core-image-minimal installs no modules. Without them" \
		"there is no /dev/dri at all and weston reports no" \
		"outputs on a board whose panel is perfectly fine."
fi

# And the =y route must NOT be attempted in a fragment, because
# DRM_VC4 depends on SND && SND_SOC, which are themselves =m. A
# tristate depending on a module can be at most a module, so the line
# would be dropped in silence.
if [ -f "$ROOT/meta-bench/recipes-kernel/linux/files/kiosk.cfg" ]; then
	if grep -qE '^CONFIG_DRM_VC4=y' \
			"$ROOT/meta-bench/recipes-kernel/linux/files/kiosk.cfg"; then
		no "a kernel fragment asks for CONFIG_DRM_VC4=y" \
			"DRM_VC4 depends on SND && SND_SOC, both =m in the" \
			"Pi 4 defconfig. A tristate that depends on a module" \
			"cannot be y, so this line is silently dropped."
	else
		ok "the kiosk fragment does not ask for the unreachable DRM_VC4=y"
	fi
else
	ok "no kiosk kernel fragment exists, so the unreachable =y is not attempted"
fi

# --------------------------------------------- the image carries the tools
for pkg in libinput wayland-utils bench-hmi bench-kiosk weston-init; do
	if grep -q "$pkg" "$IMAGE"; then
		ok "the image installs $pkg"
	else
		no "the image does not install $pkg"
	fi
done

# ------------------------------------------------- bench-gfx says what it skipped
# The rule this repository keeps relearning: a check that silently skips
# reports a clean run for a question it never asked.
if grep -q 'unasked()' "$GFX"; then
	ok "bench-gfx has a channel for questions it could not ask"
else
	no "bench-gfx has no way to report an unasked question" \
		"Every check in it can be unanswerable: a missing tool," \
		"an unmounted debugfs, a rotated journal."
fi

if sh -n "$GFX"; then
	ok "bench-gfx parses"
else
	no "bench-gfx does not parse"
fi

# BusyBox on the board has no 'head -1'; the layer's own linter enforces
# this repository wide, and it is asserted here too because bench-gfx is
# the one script in this project that runs on the board.
if grep -qE 'head -[0-9]' "$GFX"; then
	no "bench-gfx uses 'head -N', a GNU extension" \
		"BusyBox on the board needs 'head -n N'."
else
	ok "bench-gfx uses BusyBox-compatible head"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
