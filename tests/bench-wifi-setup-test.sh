#!/bin/sh
#
# bench-wifi-setup-test.sh - the provisioning script, without a board.
#
# It reads a file written on Windows and produces a supplicant config, so
# the cases that matter are the line endings and the missing fields rather
# than anything to do with radios.
#
#   sh tests/bench-wifi-setup-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-provision/files/bench-wifi-setup

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

run() {
	rm -f "$WORK/out.conf"
	BENCH_WIFI_SOURCE="$WORK/in.conf" BENCH_WIFI_TARGET="$WORK/out.conf" \
		sh "$SUT" >"$WORK/log" 2>&1
}

# A file written on Windows, with CRLF endings.
printf 'SSID=BenchNet\r\nPSK=deadbeef\r\n' >"$WORK/in.conf"
run
check "CRLF input gives a clean ssid" \
	"$(sed -n 's/.*ssid="\(.*\)"/\1/p' "$WORK/out.conf")" "BenchNet"
check "CRLF input gives a clean psk" \
	"$(sed -n 's/^ *psk=//p' "$WORK/out.conf")" "deadbeef"

# Unix endings work too.
printf 'SSID=Plain\nPSK=cafe\n' >"$WORK/in.conf"
run
check "LF input works" \
	"$(sed -n 's/.*ssid="\(.*\)"/\1/p' "$WORK/out.conf")" "Plain"

# Notepad writes no final newline, and "while read" returns false on an
# unterminated last line, which silently dropped the last key. This is the
# bug that produced a board with an SSID and no passphrase.
printf 'SSID=NoNewline\r\nPSK=beef' >"$WORK/in.conf"
run
check "a missing final newline still yields a psk" \
	"$(sed -n 's/^ *psk=//p' "$WORK/out.conf")" "beef"

# Notepad writes a UTF-8 byte order mark by default, which would otherwise
# hide the first key. Three bytes, written in octal so this file stays ASCII.
printf '\357\273\277SSID=BomNet\r\nPSK=f00d\r\n' >"$WORK/in.conf"
run
check "a byte order mark is tolerated" \
	"$(sed -n 's/.*ssid="\(.*\)"/\1/p' "$WORK/out.conf")" "BomNet"

# The file is a secret and must not be world readable. Windows filesystems
# carry only the executable bit, so probe whether chmod means anything here
# rather than reporting a failure that is really the filesystem. Same idea
# as the case-sensitivity probe in scripts/common.sh.
probe=$WORK/mode-probe
: >"$probe"
chmod 600 "$probe"
if [ "$(stat -c '%a' "$probe")" = "600" ]; then
	check "the config is mode 600" "$(stat -c '%a' "$WORK/out.conf")" "600"
else
	echo "skip     mode 600 check, this filesystem does not carry mode bits"
fi

# Missing fields are refused rather than producing a broken config.
printf 'SSID=OnlyName\n' >"$WORK/in.conf"
if run 2>/dev/null; then
	echo "FAILED   a missing PSK is refused"
	fail=$((fail + 1))
else
	echo "ok       a missing PSK is refused"
	pass=$((pass + 1))
fi

# No credentials at all is not an error: the board simply has no WiFi.
rm -f "$WORK/in.conf"
if run; then
	echo "ok       a missing file exits cleanly"
	pass=$((pass + 1))
else
	echo "FAILED   a missing file should exit 0"
	fail=$((fail + 1))
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
