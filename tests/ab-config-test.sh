#!/bin/sh
#
# ab-config-test.sh - the agreements between Project 19's files.
#
# WHAT THIS TESTS IS NOT A PROGRAM. Almost nothing in Project 19 is code.
# It is a boot script, a partition table, a RAUC configuration, a handful
# of systemd units and an image recipe, and the defects available are
# almost all of one kind: two files that have to agree about a number or a
# string, and do not.
#
# Nothing in the build can catch those. BitBake does not know that the
# compatible string in system.conf has to equal the one in the bundle
# recipe; wic does not know that p2 and p3 are what the boot script calls
# slot A and slot B; systemd does not know that the watchdog cannot count
# past about 15 seconds. Each of these disagreements produces a build that
# succeeds and a board that does the wrong thing, which on a Raspberry Pi
# usually means no console output at all.
#
# So this file asserts the agreements directly, against the real files
# rather than fixtures, because the thing that can be wrong IS the real
# file's content.
#
# It needs no hardware, no Yocto, no network and no build. That is the
# point: it is the only check in this project that can run before the four
# hours the first build will take.
#
#   sh tests/ab-config-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

SYSCONF=$ROOT/meta-bench/recipes-core/rauc/files/system.conf
BUNDLE=$ROOT/meta-bench/recipes-core/bundles/bench-bundle.bb
BOOTCMD=$ROOT/meta-bench/recipes-bsp/rpi-u-boot-scr/files/boot.cmd.in
WKS=$ROOT/meta-bench/wic/bench-ab.wks
IMAGE=$ROOT/meta-bench/recipes-core/images/bench-ab-image.bb
RECIPE=$ROOT/meta-bench/recipes-bench/bench-ab/bench-ab_0.1.bb
ABFILES=$ROOT/meta-bench/recipes-bench/bench-ab/files
KASAB=$ROOT/kas/bench-rpi3-ab.yml

pass=0
fail=0

check() {
	if [ "$2" = "$3" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: wanted '$3', got '$2'"
		fail=$((fail + 1))
	fi
}

contains() {
	case $2 in
	*"$3"*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	*)
		echo "FAILED   $1: '$3' not found"
		fail=$((fail + 1))
		;;
	esac
}

# Every file this test reasons about has to exist before any assertion
# about its contents means anything. A grep against a missing file returns
# empty, and an empty string compared against an empty string passes. That
# is how a test suite reports thirty-five successes about a file that was
# deleted.
for f in "$SYSCONF" "$BUNDLE" "$BOOTCMD" "$WKS" "$IMAGE" "$RECIPE"; do
	if [ ! -r "$f" ]; then
		echo "FAILED   missing input: $f"
		echo
		echo "0 passed, 1 failed"
		exit 1
	fi
done

# ------------------------------------------- the compatible string

# The single most expensive disagreement available in this project. RAUC
# compares these two before writing anything, so a mismatch is a device
# that refuses every update it is ever offered, and the message it prints
# is about compatibility rather than about a typo.
sys_compat=$(sed -n 's/^compatible=//p' "$SYSCONF")

# Read through the indirection the recipe uses. Criterion 7 needs a bundle
# carrying the wrong string, so the value is overridable, and what has to
# match system.conf is the DEFAULT rather than whatever a variant kas file
# set. Reading the assignment itself would compare the literal characters
# "${BENCH_AB_COMPATIBLE}" against "bench-rpi3", which is how this check
# failed the moment the indirection was introduced.
bun_compat=$(sed -n 's/^BENCH_AB_COMPATIBLE ??*= "\(.*\)"/\1/p' "$BUNDLE")
check "system.conf declares a compatible string" \
	"$(test -n "$sys_compat" && echo yes || echo no)" "yes"
check "the bundle recipe declares a default one too" \
	"$(test -n "$bun_compat" && echo yes || echo no)" "yes"
check "the two compatible strings are identical" "$bun_compat" "$sys_compat"

# And the indirection is actually wired up. Without this, the default above
# could be correct while the class read something else entirely, and the
# check above would pass on a variable nothing consumes.
contains "the bundle takes its compatible from that variable" \
	"$(cat "$BUNDLE")" 'RAUC_BUNDLE_COMPATIBLE = "${BENCH_AB_COMPATIBLE}"'

# ------------------------------------------- slots, devices and bootnames

# system.conf says which partition each slot is; boot.cmd.in says which
# partition each letter is. Two files, two representations, no shared
# source, and a disagreement boots the wrong root filesystem while
# reporting the right slot name.
a_dev=$(sed -n '/^\[slot\.rootfs\.0\]/,/^\[/p' "$SYSCONF" | sed -n 's/^device=//p')
b_dev=$(sed -n '/^\[slot\.rootfs\.1\]/,/^\[/p' "$SYSCONF" | sed -n 's/^device=//p')
a_name=$(sed -n '/^\[slot\.rootfs\.0\]/,/^\[/p' "$SYSCONF" | sed -n 's/^bootname=//p')
b_name=$(sed -n '/^\[slot\.rootfs\.1\]/,/^\[/p' "$SYSCONF" | sed -n 's/^bootname=//p')

check "slot rootfs.0 is partition 2" "$a_dev" "/dev/mmcblk0p2"
check "slot rootfs.1 is partition 3" "$b_dev" "/dev/mmcblk0p3"
check "slot rootfs.0 is bootname A" "$a_name" "A"
check "slot rootfs.1 is bootname B" "$b_name" "B"

# The boot script sets rauc_part next to the letter it matched. Reading the
# number back out of the script is what makes this a check of the script
# rather than a restatement of the configuration.
# The ranges are anchored on the branch conditions rather than on
# indentation. The first version of this ended its range at a tab, the boot
# script is indented with spaces, so the range ran to the end of the file
# and the check read both partition numbers as one answer. It reported a
# failure, which is the lucky direction; the same mistake in the B branch
# would have compared '3' against '3' and passed while reading the whole
# file.
script_a=$(awk '/= "xA"/,/= "xB"/' "$BOOTCMD" |
	sed -n 's/.*setenv rauc_part //p' | head -n 1)
script_b=$(awk '/= "xB"/,/^done/' "$BOOTCMD" |
	sed -n 's/.*setenv rauc_part //p' | head -n 1)
check "boot script sends slot A to partition 2" "$script_a" "2"
check "boot script sends slot B to partition 3" "$script_b" "3"

# ------------------------------------------- the order inside the boot script

# THE ORDERING IS THE DESIGN, and it is invisible to every other check. The
# counter must be decremented and written to disk before the kernel is
# loaded. Written the other way round, the one failure that matters most,
# a kernel that loads and then hangs, never decrements anything, and the
# board retries the broken slot forever.
dec_line=$(grep -n "setexpr BOOT_A_LEFT" "$BOOTCMD" | head -n 1 | cut -d: -f1)
save_line=$(grep -n "^saveenv" "$BOOTCMD" | head -n 1 | cut -d: -f1)
load_line=$(grep -n "ext4load" "$BOOTCMD" | head -n 1 | cut -d: -f1)

check "the boot script decrements a counter" \
	"$(test -n "$dec_line" && echo yes || echo no)" "yes"
check "it saves the environment unconditionally" \
	"$(test -n "$save_line" && echo yes || echo no)" "yes"
check "it loads a kernel" \
	"$(test -n "$load_line" && echo yes || echo no)" "yes"
check "the decrement comes before the save" \
	"$(test "$dec_line" -lt "$save_line" && echo yes || echo no)" "yes"
check "the save comes before the kernel load" \
	"$(test "$save_line" -lt "$load_line" && echo yes || echo no)" "yes"

# The kernel comes out of the slot, not off the shared FAT partition. If
# this line ever becomes a fatload from 0:1, every slot boots the same
# kernel and an update can no longer change it, silently.
contains "the kernel is loaded from the chosen slot" \
	"$(cat "$BOOTCMD")" 'ext4load @@BOOT_MEDIA@@ 0:${rauc_part}'
contains "and from /boot inside that slot" \
	"$(cat "$BOOTCMD")" '/boot/@@KERNEL_IMAGETYPE@@'

# A slot that runs out of attempts must not leave the board at a U-Boot
# prompt nobody is watching.
contains "an exhausted board resets its counters" "$(cat "$BOOTCMD")" "BOOT_A_LEFT 3"
contains "and reboots rather than stopping" "$(cat "$BOOTCMD")" "reset"

# ------------------------------------------- the card

# RAUC writes a filesystem image into a partition. If the two slots differ
# in size, a bundle that fits one will not fit the other, and the failure
# appears on a device rather than on a desk.
fixed=$(grep -c -- "--fixed-size 1024M" "$WKS")
check "exactly two slots are fixed at 1024M" "$fixed" "2"

for label in boot rootA rootB data; do
	contains "the card has a $label partition" "$(cat "$WKS")" "--label $label"
done

contains "the boot partition is active" "$(cat "$WKS")" "--active"
contains "the partition table is msdos" "$(cat "$WKS")" "--ptable msdos"

# Slot B has no --source, so a freshly flashed card has an empty second
# slot. If it ever gains one, every card ships with two copies of the same
# rootfs and the first update has nothing to prove.
rootb_line=$(grep -- "--label rootB" "$WKS")
check "slot B is empty on a fresh card" \
	"$(echo "$rootb_line" | grep -c -- "--source" || true)" "0"

# ------------------------------------------- who mounts p4

# overlayfs-etc mounts the data partition in a preinit, before systemd
# exists. A mount unit for the same device would be a second owner of it.
# This assertion is here because such a unit was written, installed and
# only then found to be a duplicate.
check "there is no data.mount unit" \
	"$(test -e "$ABFILES/data.mount" && echo present || echo absent)" "absent"
check "and the recipe installs no data.mount" \
	"$(grep -c "install.*data\.mount" "$RECIPE" || true)" "0"

ovl_dev=$(sed -n 's/^OVERLAYFS_ETC_DEVICE = "\(.*\)"/\1/p' "$IMAGE")
check "the overlay device is the data partition" "$ovl_dev" "/dev/mmcblk0p4"

# ------------------------------------------- the FAT partition

contains "boot.mount mounts p1" "$(cat "$ABFILES/boot.mount")" "What=/dev/mmcblk0p1"
contains "at /boot" "$(cat "$ABFILES/boot.mount")" "Where=/boot"

# The remedy for the two-writer hazard on uboot.env. Without sync, the
# partition can hold dirty pages when the board reboots, which is the one
# way to lose the boot counters.
contains "and mounts it with sync" "$(cat "$ABFILES/boot.mount")" "sync"

# fw_setenv has to write the same file U-Boot reads, on the partition
# boot.mount just mounted.
contains "fw_setenv is pointed at the mounted environment" \
	"$(cat "$ABFILES/fw_env.config")" "/boot/uboot.env"

# ------------------------------------------- the health verdict

# bench-health writes a marker and bench-failsafe reads it. Two files, one
# path, and a typo in either means the failsafe reboots every healthy slot
# at 120 seconds forever.
health_marker=$(sed -n 's/^GOOD=//p' "$ABFILES/bench-health")
failsafe_marker=$(sed -n 's/^GOOD=//p' "$ABFILES/bench-failsafe")
check "bench-health names a marker path" "$health_marker" "/run/slot-good"
check "bench-failsafe reads the same path" "$failsafe_marker" "$health_marker"

# The gate. meta-rauc's own mark-good service Requires boot-complete.target,
# so making the health check RequiredBy that target is what connects a
# failed check to a slot that is never confirmed. WantedBy would let the
# target be reached with the check failed, which defeats the project.
contains "the health check gates boot-complete.target" \
	"$(cat "$ABFILES/bench-health.service")" "RequiredBy=boot-complete.target"
contains "and is ordered before it" \
	"$(cat "$ABFILES/bench-health.service")" "Before=boot-complete.target"

# It must not call mark-good itself: that is meta-rauc's service's job, and
# two callers would be two owners of the one decision this project makes.
#
# The property is that the script never INVOKES rauc, so the check looks
# for a command at the start of a line rather than for the words anywhere.
# Two earlier versions got this wrong in the same direction: the first
# counted the long comment explaining why mark-good is not called here,
# the second still counted the closing message that names
# rauc-mark-good.service while explaining what happens next. Both reported
# the opposite of the truth, and both were a check reading prose as code,
# which is the fault this whole suite exists to catch one level up.
check "the health check never invokes rauc" \
	"$(grep -v '^[[:space:]]*#' "$ABFILES/bench-health" |
		grep -c '^[[:space:]]*rauc ' || true)" "0"

# ------------------------------------------- the watchdog

# THE HARDWARE CANNOT COUNT PAST ABOUT 15 SECONDS. A larger request is not
# refused, it is silently reduced, so a configuration file asking for 30
# would describe a watchdog that does not exist and every timing written
# against it would be wrong.
wdog=$(sed -n 's/^RuntimeWatchdogSec=//p' "$ABFILES/bench-watchdog.conf")
check "systemd is given a watchdog timeout" \
	"$(test -n "$wdog" && echo yes || echo no)" "yes"
check "and it is within what the SoC can count" \
	"$(test "$wdog" -le 15 && echo yes || echo no)" "yes"

# The application's own watchdog has to be slower than its beat, or systemd
# kills a healthy application between beats.
appwdog=$(sed -n 's/^WatchdogSec=//p' "$ABFILES/bench-app.service")
interval=$(sed -n 's/^INTERVAL=.*:-\([0-9]*\)}.*/\1/p' "$ABFILES/bench-app")
check "the application has a systemd watchdog" \
	"$(test -n "$appwdog" && echo yes || echo no)" "yes"
check "it is longer than two heartbeats" \
	"$(test "$appwdog" -gt "$((interval * 2))" && echo yes || echo no)" "yes"

# The failsafe must be slower than the health check can possibly be, or it
# reboots boards that were about to pass.
onboot=$(sed -n 's/^OnBootSec=//p' "$ABFILES/bench-failsafe.timer")
check "the failsafe is well after the health check" \
	"$(test "$onboot" -gt "$((appwdog * 2))" && echo yes || echo no)" "yes"

# Enabling the failsafe service as well as its timer would run it once at
# boot, immediately, before any marker could exist, and reboot every slot
# forever.
#
# The question is what SYSTEMD_SERVICE lists, not how often the file says
# the words. The first version counted every mention in the recipe, which
# includes the fetch list, the install line and the comment explaining the
# omission, and reported 4 against an expected 1.
enabled=$(sed -n '/^SYSTEMD_SERVICE/,/^"/p' "$RECIPE")
check "the failsafe timer is enabled" \
	"$(echo "$enabled" | grep -c "bench-failsafe.timer")" "1"
check "the failsafe service is not enabled beside it" \
	"$(echo "$enabled" | grep -c "bench-failsafe.service" || true)" "0"

# ------------------------------------------- the journal

# A read-only root gives a volatile journal, and every event worth reading
# here is followed by a reboot that would erase it.
contains "the image keeps /var/log off tmpfs" \
	"$(cat "$IMAGE")" 'VOLATILE_LOG_DIR = "no"'
contains "the journal is persistent" \
	"$(cat "$ABFILES/journald-persistent.conf")" "Storage=persistent"
contains "and capped so it cannot fill the data partition" \
	"$(cat "$ABFILES/journald-persistent.conf")" "SystemMaxUse="

# The symlink and the directory behind it have to name the same path.
tmpfiles_dir=$(sed -n 's/^d \([^ ]*\) .*/\1/p' "$ABFILES/bench-ab.tmpfiles.conf")
contains "the journal symlink points at the tmpfiles directory" \
	"$(cat "$RECIPE")" "ln -sf $tmpfiles_dir"

# ------------------------------------------- the per-slot kernel

# The line most easily deleted as redundant, and the one whose absence
# produces a reboot loop with a correct-looking boot log.
#
# Read out of the assignments rather than out of the file. Both of these
# names appear in long comments a few lines below explaining why they
# matter, so a whole-file search passes even when the line itself has been
# deleted. That was found by deleting the line and watching this check stay
# green, which is the only way such a check ever gets found.
installed=$(sed -n '/^IMAGE_INSTALL:append/,/^"/p' "$IMAGE")
features=$(sed -n 's/^IMAGE_FEATURES += "\(.*\)"/\1/p' "$IMAGE")

check "the image installs a kernel into the rootfs" \
	"$(echo "$installed" | grep -c "kernel-image-image")" "1"
check "and RAUC itself" \
	"$(echo "$installed" | grep -c "^ *rauc *\\\\*$")" "1"
check "the root filesystem is read-only" \
	"$(echo "$features" | grep -c "read-only-rootfs")" "1"
check "and /etc is an overlay" \
	"$(echo "$features" | grep -c "overlayfs-etc")" "1"

# The bundle has to be able to fit the slot the card gives it.
maxsize=$(sed -n 's/^IMAGE_ROOTFS_MAXSIZE = "\([0-9]*\)"/\1/p' "$IMAGE")
check "the image is capped below the slot size" \
	"$(test "$maxsize" -lt 1048576 && echo yes || echo no)" "yes"

# ------------------------------------------- the signing material

# Nothing in this repository may contain a private key, and every recipe
# that needs one must refuse rather than fall back to meta-rauc's example.
check "the bundle recipe ships no key path of its own" \
	"$(sed -n 's/^BENCH_RAUC_KEY ??= "\(.*\)"/\1/p' "$BUNDLE")" ""
check "nor a certificate path" \
	"$(sed -n 's/^BENCH_RAUC_CERT ??= "\(.*\)"/\1/p' "$BUNDLE")" ""
contains "and it refuses to build without them" \
	"$(cat "$BUNDLE")" "bb.fatal"

check "no private key is committed anywhere in the layer" \
	"$(find "$ROOT/meta-bench" -name '*.key.pem' -o -name '*.pem' | wc -l | tr -d ' ')" "0"

# ------------------------------------------- the two bundles meant to fail

# Criteria 5 and 7 are demonstrations, not assertions, and each needs a
# bundle that nothing else in the project would ever produce. The risk in
# both is the same: a variant that differs from the good bundle in more
# than one way proves nothing, because the failure becomes unattributable.
BROKEN=$ROOT/kas/bench-ab-bundle-broken.yml
WRONG=$ROOT/kas/bench-ab-bundle-wrong.yml

for f in "$BROKEN" "$WRONG"; do
	check "$(basename "$f") exists" \
		"$(test -r "$f" && echo yes || echo no)" "yes"
	check "and inherits the good bundle's configuration" \
		"$(grep -c "bench-ab-bundle.yml" "$f" || true)" "1"
done

# The broken bundle differs by one switch. Anything else in that file would
# make a rollback attributable to something other than the application.
check "the broken bundle sets exactly one behaviour switch" \
	"$(grep -c 'BENCH_AB_BREAK_APP = "1"' "$BROKEN" || true)" "1"
check "and the default everywhere else is off" \
	"$(sed -n 's/^BENCH_AB_BREAK_APP ??*= "\(.*\)"/\1/p' "$RECIPE")" "0"
check "the wrong bundle overrides only the compatible string" \
	"$(grep -c "BENCH_AB_COMPATIBLE = " "$WRONG" || true)" "1"
check "and it really is a different string" \
	"$(sed -n 's/.*BENCH_AB_COMPATIBLE = "\(.*\)"/\1/p' "$WRONG" |
		grep -c "^$sys_compat$" || true)" "0"

# A broken application in the card image would roll a fresh card back to an
# empty slot B on its very first boot.
check "the card image does not carry the broken application" \
	"$(grep -c "BENCH_AB_BREAK_APP" "$KASAB" || true)" "0"

# Both units are always fetched; the switch chooses which is installed
# under the name systemd looks for. Shipping only one and editing it would
# mean the two builds differed by a sed rather than by a file.
check "both application units are fetched" \
	"$(grep -c "file://bench-app.*\.service" "$RECIPE")" "2"
contains "the broken one is installed under the real name" \
	"$(cat "$RECIPE")" 'install -Dm0644 ${S}/bench-app-broken.service'
contains "and it runs /bin/false" \
	"$(cat "$ABFILES/bench-app-broken.service")" "ExecStart=/bin/false"

# THE SWITCH MUST BE IN THE TASK SIGNATURE. Without it, flipping it is
# served the previous package out of sstate: the build reports success, the
# bundle carries a working application, and criterion 5 fails to fail.
contains "the switch is in do_install's signature" \
	"$(cat "$RECIPE")" 'do_install[vardeps] += "BENCH_AB_BREAK_APP"'

# Three bundles land in one deploy directory and two are meant to fail.
# Distinguishing them by timestamp is how the wrong one gets installed
# during a demonstration.
for f in "$BROKEN" "$WRONG"; do
	check "$(basename "$f") names its output" \
		"$(grep -c "BENCH_AB_BUNDLE_NAME" "$f" || true)" "1"
done

# ------------------------------------------- the LEDs

LEDSCONF=$ROOT/meta-bench/recipes-bench/bench-status/files/leds.conf

# The overlays live in the kas file because rpi-config_git.bb is what
# writes config.txt. Set in the image recipe instead they would be scoped
# to that recipe, read by nobody, and the card would have no LED devices
# and no error anywhere. That is where they were written first.
overlays=$(grep -c "dtoverlay=gpio-led" "$KASAB" || true)
check "the LED overlays are declared in the kas file" "$overlays" "1"
check "and there are three of them on that one line" \
	"$(grep -o "dtoverlay=gpio-led" "$KASAB" | wc -l | tr -d ' ')" "3"
check "the image recipe declares none" \
	"$(grep -c '^RPI_EXTRA_CONFIG' "$IMAGE" || true)" "0"

# rpi-config writes the value with printf, so the escapes become real
# newlines. Written without them the second and third overlays are parsed
# as arguments to the first and nothing reports it.
check "the overlays are separated by escapes printf will expand" \
	"$(grep -c 'label=slot-a.ndtoverlay' "$KASAB" || true)" "1"

# The offsets and the wiring file have no connection but this assertion.
# leds.conf is where this bench records which line each LED module is on,
# and it is Project 12's file: if the breadboard is rewired, that is what
# gets edited, and these overlays would silently keep the old pins.
for pair in green:17 yellow:27 red:22; do
	name=${pair%:*}
	want=${pair#*:}
	got=$(sed -n "s/^$name=//p" "$LEDSCONF")
	check "leds.conf still puts $name on GPIO $want" "$got" "$want"
	check "and an overlay claims GPIO $want" \
		"$(grep -c "gpio=$want," "$KASAB" || true)" "1"
done

# The labels are the filenames under /sys/class/leds. The script and the
# overlays are the only two places they appear, so a rename in one is
# invisible until a board lights nothing.
for label in slot-a slot-b ab-busy; do
	check "the overlay labels an LED $label" \
		"$(grep -c "label=$label" "$KASAB" || true)" "1"
	check "and bench-slot-leds drives $label" \
		"$(grep -c "LEDS/$label" "$ABFILES/bench-slot-leds" || true)" "1"
done

# Two claimants for three GPIO lines. The overlays take them in the device
# tree, so libgpiod cannot open them and Project 12's daemon would fail at
# start on a board where nothing is actually wrong.
contains "Project 12's LED daemon is taken out of this image" \
	"$(cat "$IMAGE")" 'IMAGE_INSTALL:remove = "bench-status"'

# THE GUARD THAT STOPS AN UNPLUGGED LED ROLLING BACK A HEALTHY SLOT.
# bench-health runs under set -e and its exit status is the rollback
# decision, so an LED write that fails must not propagate. Without the
# guard a board whose overlays were left out of config.txt fails its health
# check, is never marked good, and rolls back after three boots, with the
# console blaming the application.
contains "the health check cannot be failed by an LED" \
	"$(grep "bench-slot-leds" "$ABFILES/bench-health")" "|| true"

# ------------------------------------------- the RAUC handlers

# Handlers are pathnames RAUC executes. A path that does not exist disables
# that handler, and RAUC says so once in a log nobody is reading during an
# install.
pre=$(sed -n 's/^pre-install=//p' "$SYSCONF")
post=$(sed -n 's/^post-install=//p' "$SYSCONF")
check "system.conf names a pre-install handler" "$pre" "/usr/bin/bench-rauc-pre-install"
check "and a post-install handler" "$post" "/usr/bin/bench-rauc-post-install"

for h in "$pre" "$post"; do
	base=${h##*/}
	check "$base is shipped by the recipe" \
		"$(grep -c "install -Dm0755 .*$base" "$RECIPE" || true)" "1"
	check "$base exists in files/" \
		"$(test -r "$ABFILES/$base" && echo yes || echo no)" "yes"
done

# The asymmetry is the error handling: post-install runs only after a
# successful install, so a failure leaves the red LED on by doing nothing.
contains "pre-install lights the busy LED" \
	"$(cat "$ABFILES/bench-rauc-pre-install")" "bench-slot-leds busy"
contains "post-install clears it" \
	"$(cat "$ABFILES/bench-rauc-post-install")" "bench-slot-leds good"

# An indicator must never fail an update either.
contains "a failing LED cannot fail an install" \
	"$(grep "bench-slot-leds" "$ABFILES/bench-rauc-pre-install")" "|| true"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
