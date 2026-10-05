#!/bin/sh
#
# overlays-check-test.sh - scripts/check-overlays.sh fires, and stays quiet.
#
# The check it exercises exists because on Sunday 4 October 2026 a card was
# flashed, booted and debugged for two hours before anyone listed its
# overlays directory. config.txt asked for three and the card had one.
#
# A check that has never failed is not a check that is working, so this
# file drives it in both directions against fixtures: a boot partition that
# is correct, one missing an overlay, one missing the directory itself, and
# the three ways a dtoverlay line does not name a file.
#
# No card, no hardware, no build. The fixtures are directories in /tmp.
#
#   sh tests/overlays-check-test.sh
#
# Every assertion goes through a helper rather than "A && say yes || say no".
# That chain is not if-then-else, and when it is split over two lines for
# width the repository's own linter cannot see it either. CI's shellcheck
# can, which is how the last batch was found.
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=$ROOT/scripts/check-overlays.sh

pass=0
fail=0

say() {
	if [ "$1" = yes ]; then
		pass=$((pass + 1))
		printf 'ok   %s\n' "$2"
	else
		fail=$((fail + 1))
		printf 'FAIL %s\n' "$2"
	fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

out=$TMP/out
status=0

run() { # boot-dir
	status=0
	sh "$CHECK" "$1" >"$out" 2>&1 || status=$?
}

exited_zero() {
	if [ "$status" -eq 0 ]; then say yes "$1"; else say no "$1"; fi
}

exited_nonzero() {
	if [ "$status" -ne 0 ]; then say yes "$1"; else say no "$1"; fi
}

said() { # description pattern
	if grep -q "$2" "$out"; then say yes "$1"; else say no "$1"; fi
}

did_not_say() { # description pattern
	if grep -q "$2" "$out"; then say no "$1"; else say yes "$1"; fi
}

# --- a card that is correct ---------------------------------------------
b=$TMP/good
mkdir -p "$b/overlays"
cat >"$b/config.txt" <<'EOF'
enable_uart=1
dtoverlay=disable-bt
dtoverlay=ramoops,base-addr=0x0b000000,total-size=0x20000
dtoverlay=gpio-led,gpio=17,label=heartbeat,trigger=heartbeat
EOF
touch "$b/overlays/disable-bt.dtbo" "$b/overlays/ramoops.dtbo" \
	"$b/overlays/gpio-led.dtbo"

run "$b"
exited_zero "a complete card passes"
said "and says so" "every requested overlay is present"

# A name with parameters after a comma is the overlay name, not the whole
# line. This is the case that would silently pass everything if the sed were
# wrong, so it is asserted rather than assumed.
said "names are read up to the first comma" "requested *3: disable-bt gpio-led ramoops"

# --- one overlay missing, which is the real defect -----------------------
b=$TMP/missing
mkdir -p "$b/overlays"
cp "$TMP/good/config.txt" "$b/config.txt"
touch "$b/overlays/disable-bt.dtbo"

run "$b"
exited_nonzero "a card missing two overlays fails"
said "and names gpio-led" "gpio-led"
said "and names ramoops" "ramoops"
did_not_say "it must not name the one that is present" "disable-bt   (expected"

# --- the directory itself absent, which has a different cause ------------
b=$TMP/nodir
mkdir -p "$b"
cp "$TMP/good/config.txt" "$b/config.txt"

run "$b"
exited_nonzero "no overlays directory fails"
said "and says the directory is the problem, not the files" "does not exist"

# --- the three lines that name no file -----------------------------------
# A commented overlay is not a request, a bare dtoverlay= ends parameter
# scope for the previous overlay, and dtparam is a different directive.
b=$TMP/notrequests
mkdir -p "$b/overlays"
cat >"$b/config.txt" <<'EOF'
dtparam=i2c_arm=on
#dtoverlay=act-led,activelow=off
# dtoverlay=vc4-kms-v3d
dtoverlay=disable-bt
dtoverlay=
EOF
touch "$b/overlays/disable-bt.dtbo"

run "$b"
exited_zero "comments, a bare dtoverlay= and dtparam are not requests"
said "but the commented ones are named rather than hidden" \
	"commented out, not checked: act-led vc4-kms-v3d"

# --- a prefix this check does not follow ---------------------------------
b=$TMP/prefix
mkdir -p "$b/overlays"
printf 'overlay_prefix=myoverlays/\ndtoverlay=disable-bt\n' >"$b/config.txt"
touch "$b/overlays/disable-bt.dtbo"

run "$b"
said "it says when config.txt moves the directory out from under it" \
	"does not follow the prefix"

# --- not a boot partition at all -----------------------------------------
b=$TMP/empty
mkdir -p "$b"
run "$b"
exited_nonzero "a directory with no config.txt is refused"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
