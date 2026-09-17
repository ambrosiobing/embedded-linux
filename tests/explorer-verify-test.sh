#!/bin/sh
#
# explorer-verify-test.sh - the acceptance test, against a fake sysfs.
#
# explorer-verify is the acceptance test for Project 6, which makes it the
# one program here whose own failures are most expensive: a checker that
# says "ok" for a peripheral that is not working turns a wiring problem
# into a week.
#
# The interesting assertions are therefore not that a working board reads
# as working. They are the six ways this board fails that look identical
# from a distance and are not:
#
#   the overlay did not load          no device at the address
#   the kernel lacks the driver       device at the address, nothing bound
#   the probe is unplugged            1-Wire master up, zero slaves
#   the inputs go nowhere             ADC bound, four floating channels
#   the fbdev shim is off             OLED bound, no framebuffer node
#   the index moved                   the OLED is fb0, not fb1
#
# Each of those has its own status word and each is asserted below.
#
# No hardware and no symlinks. sysfs is a tree of ordinary directories,
# which is why explorer-verify finds a driver through
# /sys/bus/*/drivers/<driver>/<device> rather than by reading a symlink
# back: this suite then runs on the Windows authoring laptop as well as in
# CI, instead of being skipped on one of them.
#
#   sh tests/explorer-verify-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-explorer/files/explorer-verify

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
		no "$1: '$3' should not be in output"
		printf '%s\n' "$2" | sed 's/^/         /'
		;;
	*) ok "$1" ;;
	esac
}

# status NAME OUTPUT -> the status word of that row, in -m output.
status() {
	printf '%s\n' "$2" | awk -v n="$1" '$1 == n { print $2; exit }'
}

is() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		no "$1"
		echo "         want: $3"
		echo "         got:  $2"
	fi
}

# --- fake sysfs builders ----------------------------------------------

# bind BUS DRIVER DEVICE: what the kernel makes when a driver claims a
# device. Both ends, because explorer-verify reads one and a person
# debugging reads the other.
bind() {
	mkdir -p "$W/sys/bus/$1/devices/$3"
	mkdir -p "$W/sys/bus/$1/drivers/$2/$3"
}

fresh() {
	W=$WORK/$1
	rm -rf "$W"
	mkdir -p "$W/sys/bus/i2c/devices" "$W/sys/bus/i2c/drivers" \
		"$W/sys/bus/spi/devices" "$W/sys/bus/spi/drivers" \
		"$W/sys/bus/w1/devices" "$W/sys/class/graphics" \
		"$W/sys/class/input" "$W/sys/class/leds" "$W/sys/class/rc" \
		"$W/proc/device-tree/soc"
}

# A board where everything worked.
build_good() {
	fresh good

	bind i2c rtc-ds1307 1-0068
	mkdir -p "$W/sys/bus/i2c/devices/1-0068/rtc/rtc0"
	echo "rtc-ds1307" >"$W/sys/bus/i2c/devices/1-0068/rtc/rtc0/name"

	bind i2c pcf857x 1-0020
	mkdir -p "$W/sys/bus/i2c/devices/1-0020/gpio/gpiochip4"

	bind i2c pcf8591 1-0048
	mkdir -p "$W/sys/bus/i2c/devices/1-0048/hwmon/hwmon2"
	echo 122 >"$W/sys/bus/i2c/devices/1-0048/hwmon/hwmon2/in0_input"

	bind i2c bmp280 1-0076
	mkdir -p "$W/sys/bus/i2c/devices/1-0076/iio:device0"
	echo 96.512 >"$W/sys/bus/i2c/devices/1-0076/iio:device0/in_pressure_input"

	bind spi ssd130x-spi spi0.0
	# fb0 AND NOT fb1. With vc4 absent from this image there is no HDMI
	# framebuffer, so the OLED takes index 0 and the project
	# specification's /dev/fb1 is wrong. Finding it by name is the point.
	mkdir -p "$W/sys/class/graphics/fb0"
	echo "ssd130xdrmfb" >"$W/sys/class/graphics/fb0/name"

	mkdir -p "$W/sys/bus/w1/devices/w1_bus_master1" \
		"$W/sys/bus/w1/devices/28-0000075f1b2c"
	echo 1 >"$W/sys/bus/w1/devices/w1_bus_master1/w1_master_slave_count"
	echo 21562 >"$W/sys/bus/w1/devices/28-0000075f1b2c/temperature"

	mkdir -p "$W/sys/class/rc/rc0"
	echo "gpio_ir_recv" >"$W/sys/class/rc/rc0/device_name"

	mkdir -p "$W/sys/class/leds/explorer:led1" "$W/sys/class/leds/explorer:led2"
	echo "none usb-gadget [heartbeat] timer" \
		>"$W/sys/class/leds/explorer:led1/trigger"
	echo "[none] usb-gadget heartbeat timer" \
		>"$W/sys/class/leds/explorer:led2/trigger"

	# Deliberately NOT in index order. The joystick is input3 and the
	# beeper is input1, because four of the joystick's five lines come
	# up over I2C and land wherever the expander's probe puts them.
	mkdir -p "$W/sys/class/input/input1/event7" \
		"$W/sys/class/input/input3/event2"
	echo "beeper" >"$W/sys/class/input/input1/name"
	echo "explorer700-keys" >"$W/sys/class/input/input3/name"

	mkdir -p "$W/proc/device-tree/soc/serial@7e201000"
	printf 'okay' >"$W/proc/device-tree/soc/serial@7e201000/status"
}

run() {
	EXPLORER_ROOT=$W sh "$SUT" "$@" 2>&1 || true
}

# The exit status, and the "|| rc=$?" is load bearing. Under set -e a
# failing command inside a function called from a command substitution
# ends the subshell, so a plain "cmd; echo $?" printed nothing at all for
# every case that was supposed to fail, and every such assertion compared
# "1" against the empty string. It looked like the program was wrong.
run_status() {
	rc=0
	EXPLORER_ROOT=$W sh "$SUT" "$@" >/dev/null 2>&1 || rc=$?
	echo "$rc"
}

echo "--- a board where everything worked"

build_good
out=$(run -m)

is "DS3231 is ok" "$(status DS3231 "$out")" ok
is "PCF8574 is ok" "$(status PCF8574 "$out")" ok
is "BMP280 is ok" "$(status BMP280 "$out")" ok
is "SSD1306 is ok" "$(status SSD1306 "$out")" ok
is "DS18B20 is ok" "$(status DS18B20 "$out")" ok
is "IR is ok" "$(status IR "$out")" ok
is "Joystick is ok" "$(status Joystick "$out")" ok
is "Buzzer is ok" "$(status Buzzer "$out")" ok
is "exit status is 0 when the board is good" "$(run_status -m)" 0

contains "the OLED is found at fb0, not the specification's fb1" \
	"$out" "/dev/fb0"
contains "the 1-Wire temperature is reported" "$out" "21562"
contains "the joystick is found by name, at input3" "$out" "input3"
contains "the beeper is found by name, at input1" "$out" "input1"
contains "LED1 reports the bracketed trigger only" "$out" "LED 1 ok trigger heartbeat"
contains "LED2 reports its own trigger" "$out" "LED 2 ok trigger none"

echo
echo "--- the ADC never reports a measurement"

# THE ASSERTION THIS WHOLE SUITE EXISTS FOR. All four PCF8591 inputs
# leave this board through a screw terminal, so they float. A checker that
# printed in0_input would be manufacturing evidence, and it would look
# exactly like a working sensor.
is "the ADC is unterminated, not ok" "$(status PCF8591 "$out")" unterminated
absent "the ADC's floating channel value is not printed" "$out" "122"
contains "and it says where the inputs go" "$out" "screw terminal"

echo
echo "--- nothing loaded at all"

fresh empty
mkdir -p "$W/proc/device-tree/soc/serial@7e201000"
printf 'okay' >"$W/proc/device-tree/soc/serial@7e201000/status"
out=$(run -m)

is "DS3231 is absent" "$(status DS3231 "$out")" absent
is "SSD1306 is absent" "$(status SSD1306 "$out")" absent
is "DS18B20 is absent" "$(status DS18B20 "$out")" absent
is "exit status is 1 when nothing is there" "$(run_status -m)" 1
contains "and the overlay is named as a suspect" "$out" "overlay not loaded"

echo
echo "--- the device is there and no driver took it"

build_good
rm -rf "$W/sys/bus/i2c/drivers/bmp280"
out=$(run -m)

is "a device with no driver is no-driver, not absent" \
	"$(status BMP280 "$out")" no-driver
contains "and it points at the kernel configuration" "$out" "explorer.cfg"
is "exit status is 1" "$(run_status -m)" 1

echo
echo "--- the wrong driver took it"

build_good
rm -rf "$W/sys/bus/i2c/drivers/pcf857x"
mkdir -p "$W/sys/bus/i2c/drivers/pcf8575/1-0020"
out=$(run -m)

is "a foreign driver is no-driver" "$(status PCF8574 "$out")" no-driver
contains "and the output names what did bind" "$out" "bound to pcf8575"

echo
echo "--- 1-Wire: a bus with no probe on it is not a failure"

build_good
rm -rf "$W/sys/bus/w1/devices/28-0000075f1b2c"
echo 0 >"$W/sys/bus/w1/devices/w1_bus_master1/w1_master_slave_count"
out=$(run -m)

# The DS18B20 ships loose in the box and plugs into a three-pin header.
# A bus with zero slaves is a missing part or a missing pull-up, which is
# a different fix from a missing driver and must not be a red result.
is "zero slaves is not-fitted" "$(status DS18B20 "$out")" not-fitted
contains "and both causes are named" "$out" "pull-up"
is "exit status stays 0: a loose part is not a defect" "$(run_status -m)" 0

echo
echo "--- 1-Wire: no master at all IS a failure"

build_good
rm -rf "$W/sys/bus/w1/devices/w1_bus_master1"
out=$(run -m)

is "no master is absent" "$(status DS18B20 "$out")" absent
contains "and it names the kernel symbol" "$out" "W1_MASTER_GPIO"
is "exit status is 1" "$(run_status -m)" 1

echo
echo "--- the OLED bound and the framebuffer shim is off"

build_good
rm -rf "$W/sys/class/graphics/fb0"
out=$(run -m)

is "bound with no fb node is unchecked, not absent" \
	"$(status SSD1306 "$out")" unchecked
contains "and it names the symbol that would create one" \
	"$out" "DRM_FBDEV_EMULATION"
is "exit status stays 0: the panel is bound" "$(run_status -m)" 0

echo
echo "--- a foreign framebuffer is not mistaken for the OLED"

build_good
echo "vc4drmfb" >"$W/sys/class/graphics/fb0/name"
mkdir -p "$W/sys/class/graphics/fb1"
echo "ssd130xdrmfb" >"$W/sys/class/graphics/fb1/name"
out=$(run -m)

contains "with an HDMI fb0 present the OLED is found at fb1" "$out" "/dev/fb1"
absent "and fb0 is not claimed" "$out" "/dev/fb0"

echo
echo "--- the console reports which half it checked"

build_good
out=$(run -m)
is "uart0 okay is unchecked, never ok" "$(status Console "$out")" unchecked
contains "because the test is on the other end of the cable" \
	"$out" "login prompt on the PC"

build_good
printf 'disabled' >"$W/proc/device-tree/soc/serial@7e201000/status"
out=$(run -m)
is "a disabled uart0 is absent" "$(status Console "$out")" absent
contains "and disable-bt is named" "$out" "disable-bt"

echo
echo "--- human readable output is aligned and machine output is not"

build_good
human=$(run)
machine=$(run -m)
contains "human output pads the status column" "$human" "DS3231     ok  "
absent "machine output does not" "$machine" "DS3231     ok"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
