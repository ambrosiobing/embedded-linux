#!/bin/sh
#
# rt-kernel-install-test.sh - the script that writes a boot partition.
#
# Its failure mode is a board that does not come up, with no console output
# to say why, from a card that has to be carried back to a laptop. That is
# the most expensive kind of mistake this repository can make, and until
# now the script had no tests at all.
#
# None of it needs hardware. A boot partition is a directory with a
# config.txt in it, a rootfs is a directory, and a deploy tree is a handful
# of empty files with the right names. What the script does with them is
# pure text.
#
# Three defects are pinned here, all found by reading rather than by
# running, and all of which would have cost a flash and a boot:
#
#   the overlays were copied only "if [ -d $deploy/overlays ]" with a
#   "|| true" after it, and this BSP writes .dtbo files flat, so none were
#   installed while config.txt announced overlay_prefix=rt/overlays/;
#
#   device_tree= was the literal string bcm2711-rpi-4-b.dtb whatever the
#   card was for, which on a Pi 3 names another board's device tree;
#
#   the deploy directory defaulted to a hardcoded raspberrypi4-64, which
#   was right while only one board had been built and silently wrong once
#   two had.
#
#   sh tests/rt-kernel-install-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/rt-kernel-install.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
}

check() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		no "$1"
		echo "         want: $3"
		echo "         got:  $2"
	fi
}

contains() {
	case $2 in
	*"$3"*) ok "$1" ;;
	*)
		no "$1: '$3' not in output"
		printf '%s\n' "$2" | sed 's/^/         /'
		;;
	esac
}

absent() {
	case $2 in
	*"$3"*)
		no "$1: '$3' unexpectedly present"
		;;
	*) ok "$1" ;;
	esac
}

# A deploy tree shaped like meta-raspberrypi scarthgap's: .dtbo files flat
# rather than under overlays/, each appearing three times, and the kernel
# under both of the names the recipe uses.
make_deploy() {
	_dir=$1
	_machine=$2
	_soc=$3
	mkdir -p "$_dir"
	: >"$_dir/Image"
	# A real tarball, because the script untars it. An empty file here
	# made tar fail under set -e and aborted install after the overlays
	# were copied and before config.txt was written, which looked like a
	# bug in the script and was a bug in this fixture.
	_stage=$(mktemp -d)
	mkdir -p "$_stage/lib/modules/6.12.93-rt"
	: >"$_stage/lib/modules/6.12.93-rt/spidev.ko"
	tar -czf "$_dir/modules-$_machine.tgz" -C "$_stage" lib
	rm -rf "$_stage"
	for _board in b b-plus; do
		: >"$_dir/$_soc-rpi-3-$_board.dtb"
	done
	: >"$_dir/bcm2711-rpi-4-b.dtb"
	: >"$_dir/overlay_map.dtb"
	for _ov in vc4-kms-v3d disable-bt miniuart-bt; do
		: >"$_dir/$_ov.dtbo"
		: >"$_dir/$_ov-$_machine.dtbo"
		: >"$_dir/$_ov-1-6.12.93+git0+abc_def-r0-$_machine-20260916.dtbo"
	done
}

make_card() {
	_boot=$1
	mkdir -p "$_boot"
	cat >"$_boot/config.txt" <<'EOF'
enable_uart=1
dtparam=spi=on
EOF
	printf 'console=serial0,115200 root=/dev/mmcblk0p2 rootwait\n' \
		>"$_boot/cmdline.txt"
}

# A recording depmod, because this host has none and the CI host has a
# real one. Stubbing it is the only way the assertion means the same
# thing in both places, and it also makes the invocation itself
# observable: -b ROOT and the version out of the tarball, not the
# version this laptop happens to be running.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/depmod" <<'EOF'
#!/bin/sh
echo "depmod $*" >>"$DEPMOD_LOG"
# depmod -b ROOT VERSION, so $2 is the root and $3 the version.
mkdir -p "$2/lib/modules/$3"
echo "# written by the stub" >"$2/lib/modules/$3/modules.dep"
EOF
chmod +x "$WORK/bin/depmod"
DEPMOD_LOG=$WORK/depmod.log
: >"$DEPMOD_LOG"
export DEPMOD_LOG

run() {
	PATH="$WORK/bin:$PATH" BENCH_WORK=$WORK/bench sh "$SUT" "$@" 2>&1
}

# The same, with no depmod anywhere. BENCH_DEPMOD names the binary, so a
# name that does not exist reaches the same branch a host without depmod
# does, without having to strip PATH down to nothing.
run_without_depmod() {
	PATH="$WORK/bin:$PATH" BENCH_DEPMOD=bench-no-such-depmod \
		BENCH_WORK=$WORK/bench sh "$SUT" "$@" 2>&1
}

# ------------------------------------------------- a Pi 4 card, flat dtbo

boot=$WORK/boot4
root=$WORK/root4
deploy=$WORK/bench/build/tmp/deploy/images/raspberrypi4-64
mkdir -p "$root"
make_card "$boot"
make_deploy "$deploy" raspberrypi4-64 bcm2710

out=$(run install "$boot" "$root" "$deploy" || echo EXIT-FAILED)
absent "install succeeds on a flat-dtbo deploy tree" "$out" "EXIT-FAILED"

# The defect this pins: the old code took the overlays/ branch, found no
# such directory, and installed nothing while claiming otherwise.
count=$(find "$boot/rt/overlays" -name '*.dtbo' 2>/dev/null | wc -l)
check "the flat .dtbo files are installed" "$count" "3"

contains "and it says how many" "$out" "overlays 3 installed"

# One name each, not the three spellings deploy/images offers.
if [ -f "$boot/rt/overlays/vc4-kms-v3d.dtbo" ]; then
	ok "the plain overlay name is the one installed"
else
	no "the plain overlay name is the one installed"
fi
dupes=$(find "$boot/rt/overlays" -name '*+git0*' -o \
	-name '*-raspberrypi4-64.dtbo' 2>/dev/null | wc -l)
check "the versioned and machine-suffixed duplicates are not" "$dupes" "0"

if [ -f "$boot/rt/overlays/overlay_map.dtb" ]; then
	ok "overlay_map.dtb goes with the overlays, not the device trees"
else
	no "overlay_map.dtb goes with the overlays, not the device trees"
fi

contains "config.txt selects the RT kernel" \
	"$(cat "$boot/config.txt")" "kernel=kernel8-rt.img"
contains "and the Pi 4 device tree" \
	"$(cat "$boot/config.txt")" "device_tree=rt/bcm2711-rpi-4-b.dtb"
check "the choice is recorded on the card" \
	"$(cat "$boot/rt/DTB")" "bcm2711-rpi-4-b.dtb"

# The firmware infers the architecture from the DEFAULT kernel name.
# kernel8.img is a name it knows and kernel8-rt.img is not, so without
# this line the RT image is loaded as 32-bit and the board produces no
# console output whatsoever. Bisected on 17 September to kernel alone,
# no dtb and no overlays, which booted only once the line was there.
# ANCHORED, and counted rather than matched. The block writes a
# comment explaining arm_64bit=1 immediately above the setting, so
# an unanchored search of config.txt finds the word whether or not
# the line is there. Proved by deleting the echo: the substring
# form still passed.
#
# "|| true" because grep -c exits 1 when the count is zero, and
# under set -e that ends the suite instead of failing one case.
check "the block declares 64-bit explicitly, once" \
	"$(grep -c '^arm_64bit=1$' "$boot/config.txt" || true)" "1"

# modules.dep is generated, not shipped. Without depmod every modprobe
# reports the module as not found while every .ko sits on the card.
contains "depmod ran for the version inside the tarball" "$out" \
	"depmod   6.12.93-rt"

if [ -f "$root/lib/modules/6.12.93-rt/modules.dep" ]; then
	ok "and modules.dep exists where modprobe looks for it"
else
	no "and modules.dep exists where modprobe looks for it"
fi

# The version is read from the tarball and not from the host, because on
# this project the host deliberately runs a different kernel, and -b
# points it at the card rather than at this laptop's own /lib/modules.
contains "depmod was pointed at the card, not at the host" \
	"$(cat "$DEPMOD_LOG")" "depmod -b $root 6.12.93-rt"

# A host with no depmod must say what will happen on the board rather
# than install a module tree nothing can load and report success.
out=$(run_without_depmod install "$boot" "$root" "$deploy" || echo EXIT-FAILED)
absent "a host without depmod still completes the install" "$out" "EXIT-FAILED"
contains "and says modules.dep was not generated" "$out" \
	"modules.dep was"
contains "and says what modprobe will do on the board" "$out" \
	"not found"
contains "and says how to repair it there" "$out" "depmod -a"

# ------------------------------------------------- a Pi 3 card
#
# The defect this pins: device_tree= was the literal Pi 4 name whatever the
# card was for. A Pi 4 device tree on a Pi 3 is a board that does not boot
# and cannot say so.

boot3=$WORK/boot3
root3=$WORK/root3
deploy3=$WORK/bench/build/tmp/deploy/images/raspberrypi3-64
mkdir -p "$root3"
make_card "$boot3"
make_deploy "$deploy3" raspberrypi3-64 bcm2710

out=$(run install "$boot3" "$root3" "$deploy3" || echo EXIT-FAILED)
absent "install succeeds for a Pi 3" "$out" "EXIT-FAILED"

contains "a Pi 3 card gets a Pi 3 device tree" \
	"$(cat "$boot3/config.txt")" "device_tree=rt/bcm2710-rpi-3-b.dtb"
absent "and not the Pi 4 one" \
	"$(cat "$boot3/config.txt")" "bcm2711-rpi-4-b.dtb"

# raspberrypi3-64 covers the 3B and the 3B+, which take different files.
# A machine name is coarser than a board, so it says so rather than
# pretending the default is a fact.
contains "the 3B versus 3B+ ambiguity is stated, not hidden" \
	"$out" "3B+"

out=$(BENCH_RT_DTB=bcm2710-rpi-3-b-plus.dtb \
	run install "$boot3" "$root3" "$deploy3" || echo EXIT-FAILED)
absent "BENCH_RT_DTB is accepted" "$out" "EXIT-FAILED"
contains "and overrides the default" \
	"$(cat "$boot3/config.txt")" "device_tree=rt/bcm2710-rpi-3-b-plus.dtb"

# ------------------------------- selecting generic keeps arm_64bit

# A select that removed this line would leave the NEXT select rt with a
# config.txt that names a kernel the firmware then loads as 32-bit, and
# the failure would appear one boot after the change that caused it.
boot64=$WORK/boot64
mkdir -p "$WORK/root64"
make_card "$boot64"
out=$(run install "$boot64" "$WORK/root64" "$deploy" || echo EXIT-FAILED)
absent "install for the select test succeeds" "$out" "EXIT-FAILED"
out=$(run select "$boot64" generic || echo EXIT-FAILED)
check "selecting generic keeps the 64-bit declaration, once" \
	"$(grep -c '^arm_64bit=1$' "$boot64/config.txt" || true)" "1"
contains "and it still selects the stock kernel" \
	"$(cat "$boot64/config.txt")" "kernel=kernel8.img"

# ------------------------------------------------- select reads the card
#
# select runs on a laptop with no build tree in sight, so the device tree
# has to come from the card rather than from a guess.

out=$(run select "$boot3" generic || echo EXIT-FAILED)
absent "select generic succeeds" "$out" "EXIT-FAILED"
contains "generic selects the stock kernel" \
	"$(cat "$boot3/config.txt")" "kernel=kernel8.img"

out=$(run select "$boot3" rt || echo EXIT-FAILED)
absent "select rt succeeds" "$out" "EXIT-FAILED"
contains "and restores the device tree recorded at install" \
	"$(cat "$boot3/config.txt")" "device_tree=rt/bcm2710-rpi-3-b-plus.dtb"

rm -f "$boot3/rt/DTB"
rc=0
out=$(run select "$boot3" rt) || rc=$?
check "select rt refuses when the card does not record its device tree" \
	"$rc" "1"
contains "and says to run install" "$out" "Run install first"

# ------------------------------------------- no overlays is a loud failure
#
# config.txt is about to claim overlay_prefix=rt/overlays/. A silent zero
# there is a board booting without the overlays the image was designed
# around, which reads as a hardware fault.

bare=$WORK/bench/build/tmp/deploy/images/bare-64
mkdir -p "$bare"
: >"$bare/Image"
: >"$bare/bcm2711-rpi-4-b.dtb"
bootb=$WORK/bootbare
mkdir -p "$WORK/rootbare"
make_card "$bootb"

rc=0
out=$(BENCH_RT_DTB=bcm2711-rpi-4-b.dtb \
	run install "$bootb" "$WORK/rootbare" "$bare") || rc=$?
check "a deploy tree with no overlays is refused" "$rc" "1"
contains "and says what would have happened" "$out" "fail silently"

# --------------------------------------- two machines is not a default
#
# The defect this pins: the deploy directory defaulted to a hardcoded
# raspberrypi4-64. Which card is in front of you is not something a script
# can know, and newest-wins is the wrong rule because the newest build is
# not necessarily the card in your hand.

rc=0
out=$(run install "$boot" "$root") || rc=$?
check "an omitted deploy directory refuses when two machines exist" \
	"$rc" "1"
contains "and lists them" "$out" "raspberrypi3-64"
contains "and lists the other" "$out" "raspberrypi4-64"

# With one machine present it is unambiguous, so it proceeds.
solo=$WORK/solo
mkdir -p "$solo/build/tmp/deploy/images"
cp -r "$deploy" "$solo/build/tmp/deploy/images/raspberrypi4-64"
bootsolo=$WORK/bootsolo
mkdir -p "$WORK/rootsolo"
make_card "$bootsolo"

out=$(BENCH_WORK=$solo sh "$SUT" install "$bootsolo" "$WORK/rootsolo" 2>&1 ||
	echo EXIT-FAILED)
absent "one machine present is unambiguous, so it proceeds" \
	"$out" "EXIT-FAILED"
contains "and names the machine it chose" "$out" "raspberrypi4-64"

# ------------------------------------------------------------- status

out=$(run status "$boot" || echo EXIT-FAILED)
contains "status reports the selected kernel" "$out" "config.txt selects"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
