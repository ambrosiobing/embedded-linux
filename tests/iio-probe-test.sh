#!/bin/sh
#
# iio-probe-test.sh - the sensor inventory, against a fake bus.
#
# The inventory is an acceptance criterion of Project 10: the specification
# asks for an honest list of which sensors of the shield work with which
# driver. "Honest" is the load-bearing word, and it is what this suite
# checks, because the interesting rows are the ones that report a failure.
#
# A part can answer on I2C and have no driver. A driver can be configured
# in the kernel and absent from the rootfs. A driver can be installed and
# never bind, because nothing in the device tree described the part. From
# a program that lists /sys/bus/iio/devices those three are identical and
# all of them look like "no sensor". They have different fixes, so they
# get different rows, and each of those rows is asserted here.
#
# None of it needs hardware. i2cdetect is a stub printing a grid, sysfs is
# a directory tree, and /proc/modules is a file.
#
#   sh tests/iio-probe-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-iio/files/iio-probe

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

mkdir -p "$WORK/bin" "$WORK/sys/bus/iio/devices" "$WORK/sys/class/hwmon" \
	"$WORK/sys/bus/i2c/drivers"

# A grid the way i2cdetect draws one. 0x6a, 0x1e, 0x5d and 0x44 answer;
# 0x19 answers; 0x3c does not. UU is added later for the claimed case.
write_scan() {
	cat >"$WORK/bin/i2cdetect" <<EOF
#!/bin/sh
cat <<'GRID'
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:                         -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- 19 -- -- -- -- 1e --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- -- -- -- -- -- -- -- -- -- ${1:---} -- -- --
40: -- -- -- -- 44 -- -- -- -- -- -- -- -- -- -- --
50: -- -- -- -- -- -- -- -- -- -- -- -- -- 5d -- --
60: -- -- -- -- -- -- -- -- -- -- 6a -- -- -- -- --
70: -- -- -- -- -- -- -- --
GRID
EOF
	chmod +x "$WORK/bin/i2cdetect"
}
write_scan

# modinfo answers for whichever modules the current case says are
# installed. The list is a file so a case can rewrite it.
: >"$WORK/installed"
cat >"$WORK/bin/modinfo" <<'EOF'
#!/bin/sh
# modinfo -F filename NAME
for a in "$@"; do last=$a; done
if grep -qx "$last" "$BENCH_TEST_INSTALLED"; then
	echo "/lib/modules/6.12.93-v8/kernel/drivers/$last.ko.xz"
	exit 0
fi
exit 1
EOF
chmod +x "$WORK/bin/modinfo"

PATH=$WORK/bin:$PATH
export PATH
export BENCH_TEST_INSTALLED="$WORK/installed"
export BENCH_IIO_ROOT="$WORK"

# sysfs as the kernel lays it out, keyed on the I2C address.
#
# A bound i2c client is /sys/bus/i2c/devices/<bus>-00<addr>, it has a
# "driver" link when something claimed it, and the devices that driver
# registered hang underneath it: iio:deviceN for an IIO driver, hwmon/hwmonN
# for a hwmon one. Both are reachable by path, which is what lets this suite
# run on a host whose shell turns symlinks into copies.
#
# "driver" is a directory here rather than a link for the same reason.
# iio-probe only tests it with [ -e ], which is true of both, and a fixture
# that cannot be built on the authoring machine is a fixture that does not
# get run.
i2c_client() {
	printf '%s/sys/bus/i2c/devices/1-00%s' "$WORK" "$(printf '%s' "$1" | sed 's/^0x//')"
}

bind_driver() {
	mkdir -p "$(i2c_client "$1")/driver"
}

unbind_driver() {
	rm -rf "$(i2c_client "$1")/driver"
}

add_iio_device() {
	_d=$(i2c_client "$1")/iio:device$2
	mkdir -p "$_d"
	echo "$3" >"$_d/name"
}

add_hwmon_device() {
	_d=$(i2c_client "$1")/hwmon/hwmon$2
	mkdir -p "$_d"
	echo "$3" >"$_d/name"
}

# "|| true" is not laziness, it is the difference between a failure and a
# silence.
#
# Without it, a crashing iio-probe takes this whole suite down with it under
# set -e: the first assertion's command substitution fails, the script ends,
# and the developer sees an empty log and an exit status. CI reports FAIL
# either way, but nobody learns which row went missing.
#
# With it, a crash shows up as the assertions about content failing by name,
# which is the diagnosis. The exit status is asserted separately below so
# that a crash is still reported as a crash rather than only as absent
# output.
run() {
	sh "$SUT" "$@" 2>&1 || true
}

run_status() {
	_rc=0
	sh "$SUT" >/dev/null 2>&1 || _rc=$?
	echo "$_rc"
}

# ------------------------------------------- every part gets a row, always
#
# The regression this suite was written around. module_present() began as
#
#     [ "$_mod" = none ] && return 1
#
# and under set -e that non-zero return travelled out through a command
# substitution and killed the subshell running the loop. The table stopped
# after four rows. The two that disappeared were the STTS22H and the
# LIS2DUXS12, the only parts with driver=none, which are the two rows the
# whole program exists to print. The result looked like a complete
# inventory in which every sensor worked.

check "the inventory runs to completion" "$(run_status)" "0"

out=$(run)
for part in LSM6DSV16X LIS2MDL LPS22DF SHT40 STTS22H LIS2DUXS12; do
	contains "$part has a row" "$out" "$part"
done

rows=$(run -m | grep -c '^0x' || true)
check "all six parts appear in the CSV" "$rows" "6"
contains "the CSV has a header" "$(run -m | head -1)" "address,part,driver"

# --------------------------------------------------- the five verdicts

# Nothing installed and nothing bound: the image is missing the driver.
contains "a part on the bus with no module reads no-driver-in-image" \
	"$(run -m)" "0x6a,LSM6DSV16X,st_lsm6dsx,iio,present,missing,,no-driver-in-image"

# Installed but nothing bound: the driver is there and nothing matched it,
# which points at the overlay rather than at the image. Telling those two
# apart is the reason this program is not three lines of shell.
echo st_lsm6dsx >"$WORK/installed"
contains "installed but unbound reads not-bound" \
	"$(run -m)" "0x6a,LSM6DSV16X,st_lsm6dsx,iio,present,installed,,not-bound"

# Bound and registered nothing. Rare, and its own fault: the driver
# matched and its probe failed, which puts the answer in dmesg rather than
# in the image or the overlay.
bind_driver 0x6a
contains "bound but registering nothing is its own verdict" \
	"$(run -m)" "0x6a,LSM6DSV16X,st_lsm6dsx,iio,present,installed,,bound-no-device"

# Bound, with the two devices one chip produces. One LSM6DSV16X is two IIO
# devices sharing one FIFO, and an inventory that reported it as one would
# be hiding the fact the whole FIFO measurement depends on.
add_iio_device 0x6a 0 lsm6dsv16x_accel
add_iio_device 0x6a 1 lsm6dsv16x_gyro
out=$(run -m)
contains "a bound driver with devices reads working" "$out" ",working"
contains "and names the devices it created" "$out" "lsm6dsv16x_accel"
contains "both devices of the one chip are listed" "$out" "lsm6dsv16x_gyro"

# A part with no mainline driver is unsupported, not broken, and says so.
contains "driver=none reads unsupported" \
	"$(run -m)" "0x19,LIS2DUXS12,none,none,present,none,,unsupported"

# Nothing at the address at all.
contains "a part that does not answer reads not-on-bus" \
	"$(run -m)" "0x3c,STTS22H,none,none,absent"

# ------------------------------------------------- hwmon is not IIO
#
# The SHT40 is driven by sht4x, a hwmon driver. It never appears under
# /sys/bus/iio/devices, and a program that enumerates IIO devices looking
# for humidity finds nothing and reports no error. So it is looked up in a
# different place, and the table says which subsystem each part is in.

bind_driver 0x44
add_hwmon_device 0x44 0 sht4x
echo st_lsm6dsx >"$WORK/installed"
echo sht4x >>"$WORK/installed"
out=$(run -m)
contains "the SHT40 is found under hwmon" \
	"$out" "0x44,SHT40,sht4x,hwmon,present,installed,sht4x,working"
contains "and its subsystem column says hwmon, not iio" "$out" ",hwmon,"

# The same part must NOT appear as an IIO device, because it is not one.
# An inventory that quietly listed it under IIO would send the next reader
# to /sys/bus/iio/devices looking for humidity that is not there.
iio_names=$(ls "$WORK/sys/bus/iio/devices" 2>/dev/null || true)
case $iio_names in
*sht4x*) no "the SHT40 does not masquerade as an IIO device" ;;
*) ok "the SHT40 does not masquerade as an IIO device" ;;
esac

# -------------------------------------------- UU is success, not failure
#
# i2cdetect prints UU for an address a bound driver has claimed, and
# refuses to probe it. That reads like an error to anybody who has not met
# it, and it is the normal state once the overlay is applied, so it gets
# its own word.

write_scan UU
contains "an address claimed by a driver is reported as claimed" \
	"$(run -m)" "0x3c,STTS22H,none,none,claimed"

# ------------------------------------------------------------ evidence

out=$(run -v)
contains "-v shows the raw i2cdetect output" "$out" "i2cdetect -y 1"
contains "and the iio device list it drew conclusions from" "$out" "iio devices"

# The table without -m explains its own verdicts, because a status word
# with no legend sends the reader to the source.
out=$(run)
contains "the plain table explains its status words" "$out" "status meanings"
contains "including where to look when a driver did not bind" \
	"$out" "look at the overlay, not the image"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
