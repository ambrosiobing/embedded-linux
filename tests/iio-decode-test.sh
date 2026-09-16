#!/bin/sh
#
# iio-decode-test.sh - the scan layout, computed rather than remembered.
#
# The specification's example C client walks an IIO buffer with literal
# offsets of 2, 4 and 8. Those are right for exactly one configuration:
# three 16-bit channels and a 64-bit timestamp, all enabled. Disable one
# channel, read the gyroscope instead, or meet a driver that reports 12
# bits inside 16, and every offset moves.
#
# Nothing raises an error when they do. The numbers come out plausible and
# wrong, which is the failure this project is about, so the layout is
# computed from what the kernel publishes and this suite is what says it is
# computed correctly.
#
# Every case here is a directory of small text files shaped like a real
# scan_elements, and a handful of bytes. No hardware, no IIO, no kernel.
#
#   sh tests/iio-decode-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-iio/files/iio-decode

# Find a python that RUNS, not one that exists.
#
# Windows ships a python3 stub in WindowsApps that is a real file, is on
# PATH, satisfies "command -v", and then prints a German advertisement for
# the Microsoft Store and exits non-zero. Checking for the file's existence
# reports success and every assertion below then fails with that
# advertisement quoted back as the diff.
#
# So the check is to run it. That is the difference between "is it there"
# and "does it work", and it is the same distinction this whole project is
# built around.
PY=
for candidate in ${PYTHON:-} python3 python; do
	[ -n "$candidate" ] || continue
	if "$candidate" -c 'import struct, sys' >/dev/null 2>&1; then
		PY=$candidate
		break
	fi
done
if [ -z "$PY" ]; then
	echo "skip     no working python on this host, so iio-decode is not run"
	echo "         (a python3 that only exists is not a python3; CI and the"
	echo "          build host both have a real one)"
	exit 0
fi

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

# channel DEVICE NAME INDEX TYPE [ENABLED]
channel() {
	_scan=$1/scan_elements
	mkdir -p "$_scan"
	echo "${5:-1}" >"$_scan/$2_en"
	echo "$3" >"$_scan/$2_index"
	echo "$4" >"$_scan/$2_type"
}

run() {
	"$PY" "$SUT" "$@" 2>&1 || true
}

# ------------------------------------------------- alignment, not addition
#
# Three 16-bit channels are six bytes. The timestamp does not start at six.
# It is 64-bit, so it is aligned to 8, and the scan is padded to 16. A
# client that added sizes would read the timestamp two bytes early and
# produce a number that is not obviously wrong.

d=$WORK/accel
channel "$d" in_accel_x 0 "le:s16/16>>0"
channel "$d" in_accel_y 1 "le:s16/16>>0"
channel "$d" in_accel_z 2 "le:s16/16>>0"
channel "$d" in_timestamp 3 "le:s64/64>>0"

out=$(run "$d" --layout)
contains "the scan is padded to 16 bytes, not 6 plus 8" "$out" "scan size 16 bytes"
contains "the timestamp is aligned to 8, not packed at 6" "$out" "in_timestamp index=3 le:s64/64>>0 at 8"
contains "the first channel is at 0" "$out" "in_accel_x index=0 le:s16/16>>0 at 0"

# ------------------------------------------------ disabling moves everything
#
# The offsets the specification hard-codes are 2, 4 and 8. Disable the y
# channel and the correct offsets become 0, 2 and 8: z moves from 4 to 2,
# and a client using the literals reads y's old slot and calls it z.

cp -r "$d" "$WORK/accel_noy"
echo 0 >"$WORK/accel_noy/scan_elements/in_accel_y_en"
out=$(run "$WORK/accel_noy" --layout)
contains "with y disabled, z moves to 2" "$out" "in_accel_z index=2 le:s16/16>>0 at 2"
contains "and the timestamp is still at 8" "$out" "in_timestamp index=3 le:s64/64>>0 at 8"
contains "and the scan is still 16 bytes" "$out" "scan size 16 bytes"

# --------------------------------------------------------- decoding values

"$PY" - "$WORK/accel.bin" <<'EOF'
import struct, sys
# two scans: (1, -1, 1000, 1_000_000_000) and (-32768, 32767, 0, 2_000_000_000)
with open(sys.argv[1], "wb") as fh:
    for x, y, z, ts in ((1, -1, 1000, 1000000000),
                        (-32768, 32767, 0, 2000000000)):
        fh.write(struct.pack("<hhh", x, y, z) + b"\x00\x00" + struct.pack("<q", ts))
EOF

out=$(run "$d" --raw <"$WORK/accel.bin")
check "the header names the channels in scan order" \
	"$(printf '%s\n' "$out" | head -1)" "in_accel_x,in_accel_y,in_accel_z,in_timestamp"
check "the first scan decodes" \
	"$(printf '%s\n' "$out" | sed -n 2p)" "1,-1,1000,1000000000"
check "and the extremes of a signed 16-bit channel" \
	"$(printf '%s\n' "$out" | sed -n 3p)" "-32768,32767,0,2000000000"

# ------------------------------------------- 12 bits inside 16, shifted
#
# The case that breaks a struct.unpack written from memory. The sensor
# reports 12 bits sitting at the top of a 16-bit word, so the value must be
# shifted right by 4 and then sign extended from bit 11, not from bit 15.

d12=$WORK/twelve
channel "$d12" in_accel_x 0 "le:s12/16>>4"
"$PY" - "$WORK/twelve.bin" <<'EOF'
import struct, sys
# 0x8000 is -2048 once shifted right by 4 and sign extended from 12 bits.
# 0x7ff0 is  2047. A reader that forgot the shift would say -32768 and 32752.
with open(sys.argv[1], "wb") as fh:
    fh.write(struct.pack("<H", 0x8000))
    fh.write(struct.pack("<H", 0x7FF0))
    fh.write(struct.pack("<H", 0x0010))
EOF
out=$(run "$d12" --raw <"$WORK/twelve.bin")
check "12 bits in 16, shifted, sign extends from bit 11" \
	"$(printf '%s\n' "$out" | sed -n 2p)" "-2048"
check "and the positive extreme" "$(printf '%s\n' "$out" | sed -n 3p)" "2047"
check "and a small value is not shifted twice" \
	"$(printf '%s\n' "$out" | sed -n 4p)" "1"

# ------------------------------------------------------ unsigned and big
#
# Both appear in real drivers, and both are a single character in the type
# string, which is exactly the kind of difference a remembered layout does
# not notice.

du=$WORK/unsigned
channel "$du" in_pressure 0 "be:u24/32>>0"
"$PY" - "$WORK/unsigned.bin" <<'EOF'
import struct, sys
with open(sys.argv[1], "wb") as fh:
    fh.write(struct.pack(">I", 0x00ABCDEF))
EOF
out=$(run "$du" --raw <"$WORK/unsigned.bin")
check "big endian, unsigned, 24 bits in 32" \
	"$(printf '%s\n' "$out" | sed -n 2p)" "11259375"

# ------------------------------------------------- scale, and what escapes it

out=$(run "$d" <"$WORK/accel.bin")
# in_accel_x_scale was not written for this device, so nothing is scaled and
# the counts are honest rather than multiplied by an invented 1.0.
check "with no scale attribute the value stays a count" \
	"$(printf '%s\n' "$out" | sed -n 2p)" "1,-1,1000,1000000000"

echo "0.5" >"$d/in_accel_x_scale"
out=$(run "$d" <"$WORK/accel.bin")
contains "a scale attribute is applied to its own channel" "$out" "0.500000,-1,1000,"

# And the one that matters: a timestamp is nanoseconds and must never be
# scaled, however plausibly a scale attribute might turn up beside it.
echo "0.001" >"$d/in_timestamp_scale"
out=$(run "$d" <"$WORK/accel.bin")
contains "a timestamp is never scaled, even when a scale exists" \
	"$out" ",1000000000"

# --------------------------------------------------------- partial scans

"$PY" - "$WORK/short.bin" <<'EOF'
import struct, sys
with open(sys.argv[1], "wb") as fh:
    fh.write(struct.pack("<hhh", 1, 2, 3) + b"\x00\x00" + struct.pack("<q", 7))
    fh.write(b"\x01\x02\x03")            # a torn scan at the end
EOF
out=$(run "$d" --raw <"$WORK/short.bin")
contains "a torn final scan is reported" "$out" "not a whole number of"
check "and dropped rather than decoded as zeros" \
	"$(printf '%s\n' "$out" | grep -c '^[-0-9]')" "1"

# ------------------------------------------------------- nothing enabled

dnone=$WORK/nothing
channel "$dnone" in_accel_x 0 "le:s16/16>>0" 0
out=$(run "$dnone" --layout)
contains "a device with no enabled channels says so" "$out" "no enabled channels"
contains "and says when to enable them" "$out" "before enabling the buffer"

# ----------------------------------------------------- an unparsable type

dbad=$WORK/bad
channel "$dbad" in_accel_x 0 "something else entirely"
out=$(run "$dbad" --layout)
contains "an unparsable type names the channel" "$out" "in_accel_x"
contains "and quotes what it could not parse" "$out" "something else entirely"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
