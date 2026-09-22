#!/bin/sh
#
# gadget-configfs-test.sh - the gadget script, without a gadget.
#
# bench-gadget builds a USB device out of a directory tree. That is the
# property this suite exploits: configfs is a filesystem, so an ordinary
# directory stands in for it and the whole build and teardown can be run
# on a laptop with no board, no controller and no cable.
#
# What that does and does not prove:
#
#   IT DOES prove the ORDER. libcomposite turns the tree into descriptors
#   at the moment the controller name is written to UDC and not before,
#   so a tree that is incomplete when UDC is written fails with ENODEV
#   and no explanation of which part was missing. The suite asserts UDC
#   is written last and contains the controller name.
#
#   IT DOES prove the teardown is resilient. A failed teardown leaves the
#   half-removed tree that makes the next "up" refuse, and the unit's
#   ExecStopPost gets no third chance.
#
#   IT DOES NOT prove the gadget enumerates. Nothing here speaks USB.
#   configfs also rejects writes the kernel does not like, and an
#   ordinary directory accepts anything, so a value this suite is happy
#   with can still be refused by the real thing.
#
#   sh tests/gadget-configfs-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-gadget/files/bench-gadget
DESC=$ROOT/meta-bench/recipes-bench/bench-gadget/files/hid-keyboard.desc

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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
		echo "FAILED   $1: '$3' not in output"
		echo "$2" | sed 's/^/           /'
		fail=$((fail + 1))
		;;
	esac
}

present() {
	if [ -e "$2" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: $2 does not exist"
		fail=$((fail + 1))
	fi
}

for f in "$SUT" "$DESC"; do
	[ -f "$f" ] || { echo "FAILED   input missing: $f"; exit 1; }
done

# ------------------------------------------------------------- the stand-in
# Every absolute path the script uses is redirected into the work tree.
# Nothing here touches the real /sys.
CFG=$WORK/cfg
UDCDIR=$WORK/udc
G=$CFG/usb_gadget/bench
BG=$WORK/bench-gadget

sed -e "s|^G=.*|G=$G|" \
    -e "s|^DESC=.*|DESC=$WORK/hid-keyboard.bin|" \
    -e "s|/sys/kernel/config|$CFG|g" \
    -e "s|/sys/class/udc|$UDCDIR|g" \
    "$SUT" >"$BG"

reset_tree() {
	rm -rf "$CFG" "$UDCDIR"
	mkdir -p "$CFG" "$UDCDIR"
	: >"$UDCDIR/fe980000.usb"
}

# A 63 byte stand-in for what the recipe assembles.
: >"$WORK/hid-keyboard.bin"
i=0
while [ "$i" -lt 63 ]; do
	printf 'X' >>"$WORK/hid-keyboard.bin"
	i=$((i + 1))
done

# --------------------------------------------------- refuses without a UDC
reset_tree
rm -f "$UDCDIR"/*
rc=0
out=$(sh "$BG" up 2>&1) || rc=$?
check "with no UDC, up refuses" "$rc" "1"
contains "and says the port is not in peripheral mode" "$out" "peripheral mode"
contains "and names the overlay to check" "$out" "dr_mode=peripheral"

# ------------------------------------------------ refuses a missing descriptor
reset_tree
mv "$WORK/hid-keyboard.bin" "$WORK/hid-keyboard.bin.hidden"
rc=0
out=$(sh "$BG" up 2>&1) || rc=$?
check "with no report descriptor, up refuses" "$rc" "1"
contains "and blames the package rather than the board" "$out" "broken bench-gadget package"
mv "$WORK/hid-keyboard.bin.hidden" "$WORK/hid-keyboard.bin"

# --------------------------------------------------------- refuses a bad NET
reset_tree
rc=0
out=$(NET=rndis sh "$BG" up 2>&1) || rc=$?
check "an unknown NET is refused" "$rc" "1"
contains "and the refusal names what was given" "$out" "rndis"

# ------------------------------------------------------------- the happy path
reset_tree
out=$(sh "$BG" up 2>&1)
contains "up reports the controller it bound to" "$out" "fe980000.usb"
contains "and the function set" "$out" "ecm, acm and hid"

present "the device descriptor is written" "$G/idVendor"
check "idVendor is the Linux Foundation's" "$(cat "$G/idVendor")" "0x1d6b"
check "idProduct is the composite gadget id" "$(cat "$G/idProduct")" "0x0104"

present "one configuration exists" "$G/configs/c.1"
check "MaxPower asks for 500 mA" "$(cat "$G/configs/c.1/MaxPower")" "500"

present "the ecm function exists" "$G/functions/ecm.usb0"
present "the acm function exists" "$G/functions/acm.usb0"
present "the hid function exists" "$G/functions/hid.usb0"

# THE ASSERTION THIS SUITE EXISTS FOR. UDC is written last and holds the
# controller name; writing it earlier binds an incomplete tree, which
# fails with ENODEV and names nothing.
check "UDC holds the controller name" "$(cat "$G/UDC")" "fe980000.usb"

# The MACs must be locally administered: second hex digit 2, 6, A or E.
# Otherwise the host invents a new interface name on every boot and every
# host-side rule that refers to it breaks.
host_mac=$(cat "$G/functions/ecm.usb0/host_addr")
case $host_mac in
?[26aeAE]:*)
	echo "ok       the host MAC is locally administered ($host_mac)"
	pass=$((pass + 1))
	;;
*)
	echo "FAILED   the host MAC $host_mac is not locally administered"
	echo "           the second hex digit must be 2, 6, A or E"
	fail=$((fail + 1))
	;;
esac

check "the HID function is a boot keyboard" \
	"$(cat "$G/functions/hid.usb0/protocol")" "1"
check "with an 8 byte report" \
	"$(cat "$G/functions/hid.usb0/report_length")" "8"
check "and the descriptor was copied in" \
	"$(wc -c <"$G/functions/hid.usb0/report_desc" | tr -d ' ')" "63"

# ------------------------------------------------------ refuses to build twice
out=$(sh "$BG" up 2>&1)
contains "a second up refuses rather than building over the tree" \
	"$out" "already exists"

# ----------------------------------------------------------------- NET=ncm
reset_tree
sh "$BG" up >/dev/null 2>&1
rm -rf "$CFG"; mkdir -p "$CFG"
out=$(NET=ncm sh "$BG" up 2>&1)
contains "NET=ncm builds the ncm function instead" "$out" "ncm, acm and hid"
present "and the ncm directory exists" "$G/functions/ncm.usb0"

# --------------------------------------------------------------- the teardown
reset_tree
sh "$BG" up >/dev/null 2>&1
# Replace the copied function links with real symlinks, which is what
# configfs gives. Git Bash copies directories for ln -s without
# privileges, so the happy path above exercises the awkward case and this
# exercises the real one.
for f in ecm acm hid; do
	rm -rf "$G/configs/c.1/$f.usb0"
	ln -s "$G/functions/$f.usb0" "$G/configs/c.1/$f.usb0" 2>/dev/null || true
done
rc=0
out=$(sh "$BG" down 2>&1) || rc=$?

if [ "$rc" -eq 0 ]; then
	contains "down reports success" "$out" "torn down"
	if [ -d "$G" ]; then
		echo "FAILED   down returned 0 but the tree is still there"
		fail=$((fail + 1))
	else
		echo "ok       the tree is gone"
		pass=$((pass + 1))
	fi
else
	# This host could not make symlinks, so the teardown hit the
	# awkward case. That is still a result: it must have CONTINUED and
	# reported, not aborted at the first failure.
	contains "a partial teardown says so rather than failing silently" \
		"$out" "PARTIAL teardown"
	contains "and names something it could not remove" \
		"$out" "could not remove"
	contains "and says what that means for the next up" \
		"$out" "will refuse"
fi

# ------------------------------------------------------ down on nothing is fine
rm -rf "$CFG"; mkdir -p "$CFG"
rc=0
out=$(sh "$BG" down 2>&1) || rc=$?
check "down with no tree is not an error" "$rc" "0"
contains "and says so" "$out" "nothing to tear down"

# ------------------------------------------------------------------- status
reset_tree
out=$(sh "$BG" status 2>&1)
contains "status reports an absent tree" "$out" "tree:  absent"
contains "status finds the controller" "$out" "fe980000.usb"
sh "$BG" up >/dev/null 2>&1
out=$(sh "$BG" status 2>&1)
contains "status reports the bound controller" "$out" "bound: fe980000.usb"

# ------------------------------------------------------------ usage and exit
rc=0
sh "$BG" frobnicate >/dev/null 2>&1 || rc=$?
check "an unknown subcommand exits 2" "$rc" "2"

# ------------------------------------------- the descriptor the recipe assembles
# The recipe asserts 63 bytes at build time. This checks the SOURCE the
# recipe reads, so a bad edit is caught on a laptop rather than in a
# build, and it uses the same comment-stripping rule.
octets=$(sed 's/#.*//' "$DESC" | tr ' \t' '\n\n' |
	grep -cE '^[0-9a-fA-F][0-9a-fA-F]$' || true)
check "hid-keyboard.desc is 63 octets" "$octets" "63"

first=$(sed 's/#.*//' "$DESC" | tr ' \t' '\n\n' |
	grep -E '^[0-9a-fA-F][0-9a-fA-F]$' | head -n 1)
last=$(sed 's/#.*//' "$DESC" | tr ' \t' '\n\n' |
	grep -E '^[0-9a-fA-F][0-9a-fA-F]$' | tail -n 1)
check "it begins with Usage Page (Generic Desktop)" "$first" "05"
check "it ends with End Collection" "$last" "c0"

# ------------------------------------- the specification's own file list
#
# THIS BLOCK EXISTS BECAUSE THE OTHER AUDIT COULD NOT FIND THIS.
#
# An audit of the documents against the tree checks that everything a
# document NAMES exists. It came back clean here while three deliverables
# from the specification's repository layout were missing, because no
# document in the repository mentioned them: a project that never names a
# thing is perfectly consistent with not having it.
#
# So the specification's file list is ticked off directly. These are the
# artefacts it names that are not recipes or figures, mapped onto where
# this repository puts them.
BRIDGE=$ROOT/meta-bench/recipes-bench/bench-kbd-bridge/files
GADGET=$ROOT/meta-bench/recipes-bench/bench-gadget/files
HOST=$ROOT/projects/14-usb-gadget/host

for spec_file in \
	"$GADGET/bench-gadget" \
	"$GADGET/bench-gadget.service" \
	"$GADGET/hid-keyboard.desc" \
	"$BRIDGE/kbd_bridge.c" \
	"$BRIDGE/usage_table.h" \
	"$BRIDGE/kbd-bridge.service" \
	"$BRIDGE/80-bench-kbd.rules" \
	"$HOST/linux/70-pi-gadget.rules" \
	"$HOST/linux/nm-pi-gadget.nmconnection" \
	"$HOST/windows/README.md" \
	"$ROOT/projects/14-usb-gadget/docs/DESCRIPTORS.md"
do
	present "the specification names $(basename "$spec_file")" "$spec_file"
done

# The host NetworkManager profile must refuse to become the default
# route. Without that line a host accepting the Pi's lease can route
# through it, and a keyboard becomes the way to the internet.
if grep -q '^never-default=true' "$HOST/linux/nm-pi-gadget.nmconnection"; then
	echo "ok       the host profile refuses to become the default route"
	pass=$((pass + 1))
else
	echo "FAILED   nm-pi-gadget.nmconnection lacks never-default=true"
	fail=$((fail + 1))
fi

# And the board declines to offer one, independently.
if grep -q '^EmitRouter=no' \
		"$ROOT/meta-bench/recipes-bench/bench-gadget/files/20-usb0.network"; then
	echo "ok       and the board does not offer one either"
	pass=$((pass + 1))
else
	echo "FAILED   20-usb0.network does not set EmitRouter=no"
	fail=$((fail + 1))
fi

# Step 9 of the specification: a hotkey replays the last macro.
if grep -q 'HOTKEY_CODE' "$BRIDGE/kbd_bridge.c" &&
		grep -q 'last_macro' "$BRIDGE/kbd_bridge.c"; then
	echo "ok       the bridge implements the replay hotkey"
	pass=$((pass + 1))
else
	echo "FAILED   kbd_bridge.c has no replay hotkey (specification step 9)"
	fail=$((fail + 1))
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
