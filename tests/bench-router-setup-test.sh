#!/bin/sh
#
# bench-router-setup-test.sh - the router provisioning, without a board.
#
# Same shape as bench-wifi-setup-test.sh and for the same reason: the file
# this script reads is written on Windows, by hand, after flashing, and
# every trap in it is a text trap rather than a networking one. The three
# that have actually cost this bench time are CRLF endings, a byte order
# mark on the first key, and a last line with no newline, which ends a
# plain "while read" before the body runs and silently drops the last key.
#
# The substitution is tested with an ampersand and a slash in the
# passphrase on purpose. Those are the two characters that turn a sed-based
# template fill into a corrupted file, which is why this script does not
# use sed.
#
#   sh tests/bench-router-setup-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FILES=$ROOT/meta-bench/recipes-bench/bench-router/files
SUT=$FILES/bench-router-setup

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/templates" "$WORK/out"
cp "$FILES/lte.nmconnection.in" "$FILES/bench-ap.nmconnection.in" \
	"$WORK/templates/"

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

run() {
	rm -rf "$WORK/out"
	mkdir -p "$WORK/out"
	BENCH_ROUTER_SOURCE="$WORK/in.conf" \
	BENCH_ROUTER_TARGET="$WORK/out" \
	BENCH_ROUTER_TEMPLATES="$WORK/templates" \
		sh "$SUT" >"$WORK/log" 2>&1
}

value() {
	# The value of one key in one generated keyfile.
	grep "^$2=" "$WORK/out/$1" 2>/dev/null | head -1 | cut -d= -f2-
}

# ------------------------------------------------- a file written on Windows

printf 'AP_SSID=bench-lte\r\nAP_PSK=s3cret&pass/word\r\nAPN=internet\r\n' \
	>"$WORK/in.conf"
run
check "CRLF: ssid has no carriage return" \
	"$(value bench-ap.nmconnection ssid)" "bench-lte"
check "CRLF: the psk survived & and /" \
	"$(value bench-ap.nmconnection psk)" "s3cret&pass/word"
check "CRLF: the apn reached the gsm profile" \
	"$(value lte.nmconnection apn)" "internet"
check "the placeholder is gone" \
	"$(grep -c '@' "$WORK/out/bench-ap.nmconnection")" "0"

# ------------------------------------------------------ no trailing newline

# Notepad writes the last line without one. A plain "while read" returns
# false on that line and never runs the body, so the last key vanishes.
# Here that key is the APN, and a missing APN is a modem that registers and
# never connects, which is a full evening of blaming the antenna.
printf 'AP_SSID=bench-lte\nAP_PSK=longenough\nAPN=internet' >"$WORK/in.conf"
run
check "no final newline: the last key is not lost" \
	"$(value lte.nmconnection apn)" "internet"

# ------------------------------------------------------- byte order mark

printf '\357\273\277AP_SSID=bench-lte\nAP_PSK=longenough\nAPN=internet\n' \
	>"$WORK/in.conf"
run
check "BOM: the first key is still recognised" \
	"$(value bench-ap.nmconnection ssid)" "bench-lte"

# ------------------------------------------------------------- permissions

printf 'AP_SSID=bench-lte\nAP_PSK=longenough\nAPN=internet\n' >"$WORK/in.conf"
run
# Only where the file system has POSIX modes at all. A checkout on NTFS
# under Git for Windows reports 0644 for everything, so asserting there
# would fail on the authoring machine and prove nothing about the target.
# The check still runs in CI and on the build host, which is where the
# claim has to hold.
#
# stat, not "ls -l | cut". The pipe is what shellcheck's SC2012 objects to,
# and it was worth fixing rather than silencing: stat asks for the mode,
# where the pipe counts columns in a listing meant for people.
: >"$WORK/modeprobe"
chmod 600 "$WORK/modeprobe"
if [ "$(stat -c %a "$WORK/modeprobe" 2>/dev/null)" = "600" ]; then
	mode=$(stat -c %a "$WORK/out/bench-ap.nmconnection")
	check "the keyfile is not readable by anyone else" "$mode" "600"
	mode=$(stat -c %a "$WORK/out/lte.nmconnection")
	check "the gsm keyfile is not readable either" "$mode" "600"
else
	echo "note     this file system has no POSIX modes, permissions unchecked"
fi

# A test, not a listing: the question is whether one named file is there.
if [ -e "$WORK/out/.ap.stage" ]; then
	echo "FAILED   a staging file was left behind"
	fail=$((fail + 1))
else
	echo "ok       no staging file left behind"
	pass=$((pass + 1))
fi

# ---------------------------------------------------------- partial input

# An APN and no access point is a legitimate configuration: a router with
# only a cellular uplink, administered over the cable.
printf 'APN=internet\n' >"$WORK/in.conf"
run
check "apn only: the gsm profile is written" \
	"$(value lte.nmconnection apn)" "internet"
if [ -e "$WORK/out/bench-ap.nmconnection" ]; then
	echo "FAILED   apn only: an access point was invented"
	fail=$((fail + 1))
else
	echo "ok       apn only: no access point invented"
	pass=$((pass + 1))
fi

# Half an access point is not.
printf 'AP_SSID=bench-lte\nAPN=internet\n' >"$WORK/in.conf"
if run; then
	echo "FAILED   an SSID with no passphrase should be refused"
	fail=$((fail + 1))
else
	echo "ok       an SSID with no passphrase is refused"
	pass=$((pass + 1))
fi

# WPA needs eight characters and NetworkManager reports that only at
# activation time, so the access point would simply never appear.
printf 'AP_SSID=bench-lte\nAP_PSK=short\nAPN=internet\n' >"$WORK/in.conf"
if run; then
	echo "FAILED   a passphrase under eight characters should be refused"
	fail=$((fail + 1))
else
	echo "ok       a passphrase under eight characters is refused"
	pass=$((pass + 1))
fi

# ------------------------------------------------------------- no file

rm -f "$WORK/in.conf"
if run; then
	echo "ok       a missing file leaves the shipped profiles alone"
	pass=$((pass + 1))
else
	echo "FAILED   a missing file must not be an error"
	fail=$((fail + 1))
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
