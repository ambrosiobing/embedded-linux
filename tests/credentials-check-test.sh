#!/bin/sh
#
# credentials-check-test.sh - the guard that would have saved an evening.
#
# scripts/credentials.sh runs inside flash.sh while the card is
# still in the reader and refuses a card that provisions a network and
# carries no file to provision from. This suite builds the two directory
# trees it reads, so it needs no card and no reader.
#
# The cases that matter are the two it must NOT fire on: an image with no
# provisioning program, which is most of them, and a card that has the
# file. A guard that nags where the file has no reader is a guard people
# switch off.
#
#   sh tests/credentials-check-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/credentials.sh

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
	[ $# -gt 1 ] && printf '         %s\n' "$2"
	return 0
}

# build_card PROGRAM FILE
#
# PROGRAM is a path under the rootfs to create, or "none". FILE is a name
# to create on the boot partition, or "none".
build_card() {
	rm -rf "$WORK/boot" "$WORK/root"
	mkdir -p "$WORK/boot" "$WORK/root/usr/bin"
	[ "$1" = none ] || { mkdir -p "$(dirname "$WORK/root/$1")"; : >"$WORK/root/$1"; }
	[ "$2" = none ] || : >"$WORK/boot/$2"
}

# The store the copy comes from is passed explicitly, the way flash.sh
# passes it, so these tests never touch whatever the operator has at
# ~/bench/credentials.
run() {
	sh "$SUT" "$WORK/boot" "$WORK/root" "$WORK/store" 2>&1
}

store() {
	rm -rf "$WORK/store"
	mkdir -p "$WORK/store"
	[ "$1" = none ] || { echo "SSID=x"; echo "PSK=y"; } >"$WORK/store/$1"
}

echo "--- the case it exists for"

# THE CASE THE WHOLE THING EXISTS FOR: the card needs the file, the
# laptop has a copy, and nobody has to type anything.
build_card usr/bin/bench-wifi-setup none
store wifi.conf
status=0
out=$(run) || status=$?
if [ "$status" -eq 0 ]; then
	ok "a wireless image with no wifi.conf takes the stored copy"
else
	no "a wireless image with no wifi.conf takes the stored copy" "$out"
fi
if [ -f "$WORK/boot/wifi.conf" ]; then
	ok "and the file is on the card afterwards"
else
	no "and the file is on the card afterwards"
fi
case $out in
*"copied from"*) ok "and the output says where it came from" ;;
*) no "and the output says where it came from" "$out" ;;
esac

# And the case where there is nothing to copy, which is the one that
# cost an evening on Friday 16 October 2026.
build_card usr/bin/bench-wifi-setup none
store none
status=0
out=$(run) || status=$?
if [ "$status" -ne 0 ]; then
	ok "no file and no stored copy is refused"
else
	no "no file and no stored copy is refused" "exit was 0"
fi
case $out in
*"wifi.conf is MISSING"*) ok "and the refusal names the file" ;;
*) no "and the refusal names the file" "$out" ;;
esac
case $out in
*"./go credentials"*)
	ok "and names the one command that ends the retyping" ;;
*)
	no "and names the one command that ends the retyping" "$out" ;;
esac

echo "--- the two cases it must stay quiet for"

build_card usr/bin/bench-wifi-setup wifi.conf
store none
status=0
out=$(run) || status=$?
if [ "$status" -eq 0 ]; then
	ok "a wireless image with wifi.conf passes"
else
	no "a wireless image with wifi.conf passes" "$out"
fi
case $out in
*"wifi.conf already on the card"*) ok "and says so, so a clean run is still informative" ;;
*) no "and says so, so a clean run is still informative" "$out" ;;
esac

build_card none none
store none
status=0
out=$(run) || status=$?
if [ "$status" -eq 0 ]; then
	ok "an image with no provisioning program is left alone"
else
	no "an image with no provisioning program is left alone" "$out"
fi
case $out in
*credentials*)
	no "and says nothing about credentials at all" "$out" ;;
*)
	ok "and says nothing about credentials at all" ;;
esac

echo "--- the second file, which is Project 15's"

build_card usr/bin/bench-router-setup none
store none
status=0
out=$(run) || status=$?
if [ "$status" -ne 0 ]; then
	ok "a router image with no router.conf is refused"
else
	no "a router image with no router.conf is refused" "exit was 0"
fi
case $out in
*"router.conf is MISSING"*) ok "and the refusal names that file" ;;
*) no "and the refusal names that file" "$out" ;;
esac

echo "--- a directory that is not there is an argument error, not a pass"

status=0
sh "$SUT" "$WORK/nowhere" "$WORK/root" "$WORK/store" >/dev/null 2>&1 || status=$?
if [ "$status" -eq 2 ]; then
	ok "a missing directory exits 2 rather than 0"
else
	no "a missing directory exits 2 rather than 0" "exit was $status"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
