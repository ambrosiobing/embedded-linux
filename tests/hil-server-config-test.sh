#!/bin/sh
#
# hil-server-config-test.sh - the lab server's configuration, as invariants.
#
# These files are installed on a machine this repository does not build, so
# nothing here is checked by BitBake and nothing is checked by a boot until
# somebody powers a board on. What can be checked is that they still say the
# things they have to say.
#
# The properties below are not style. Each one, if it drifted, would
# produce a lab that looks configured and does not work:
#
#   dnsmasq without port=0 binds 53 on every interface, including the
#   server's Wi-Fi, which on a shared network is somebody else's problem;
#   without the exact option 43 string the boot ROM ignores the offer and
#   the board sits dark with nothing in any log;
#   an export without no_root_squash gives a root filesystem the DUT cannot
#   write to, which fails late and looks like a corrupt image;
#   ser2net on 0.0.0.0 offers a root shell to whatever network the server
#   is on.
#
#   sh tests/hil-server-config-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVER=$ROOT/projects/04-netboot-hil/server

pass=0
fail=0

want() {
	if grep -q -- "$3" "$SERVER/$2"; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1"
		fail=$((fail + 1))
	fi
}

reject() {
	if grep -q -- "$3" "$SERVER/$2"; then
		echo "FAILED   $1"
		fail=$((fail + 1))
	else
		echo "ok       $1"
		pass=$((pass + 1))
	fi
}

# ------------------------------------------------- both dnsmasq topologies

for conf in bench-isolated.conf bench-proxy.conf; do
	want "$conf is a DHCP server and not a resolver" \
		"dnsmasq.d/$conf" "^port=0"
	want "$conf answers only on the lab cable" \
		"dnsmasq.d/$conf" "^bind-interfaces"
	want "$conf carries the exact boot ROM string" \
		"dnsmasq.d/$conf" 'pxe-service=0,"Raspberry Pi Boot"'
	want "$conf serves TFTP" "dnsmasq.d/$conf" "^enable-tftp"
	want "$conf points at the TFTP root" \
		"dnsmasq.d/$conf" "^tftp-root=/srv/tftp"
	want "$conf logs every DHCP transaction" \
		"dnsmasq.d/$conf" "^log-dhcp"
done

# --------------------------------------- the two topologies are different

want "the isolated topology hands out addresses" \
	"dnsmasq.d/bench-isolated.conf" "^dhcp-range=192.168.7.10,192.168.7.20"
want "the proxy topology does not" \
	"dnsmasq.d/bench-proxy.conf" ",proxy"
reject "the isolated topology is not accidentally a proxy" \
	"dnsmasq.d/bench-isolated.conf" ",proxy"

# An island has no router and no DNS, and saying so explicitly is not the
# same as saying nothing: an absent option makes the client fall back to
# its own idea, and a DUT that believes it has a default route spends
# thirty seconds at every boot finding out otherwise.
want "the island offers no router" \
	"dnsmasq.d/bench-isolated.conf" "^dhcp-option=3"
want "the island offers no DNS server" \
	"dnsmasq.d/bench-isolated.conf" "^dhcp-option=6"

# ------------------------------------------------------------ the export

want "the export is writable by the DUT's root" \
	"exports" "no_root_squash"
want "the export is limited to the lab subnet" \
	"exports" "192.168.7.0/24"
reject "the export is not offered to everybody" "exports" '^\*'
reject "the export is not offered to the world" "exports" "0.0.0.0/0"

# ------------------------------------------------------------- the console

want "ser2net listens on localhost only" \
	"ser2net.yaml" "accepter: tcp,localhost,4003"
want "ser2net uses the stable device name" \
	"ser2net.yaml" "/dev/tty-dut3"
want "a stale session does not block the next run" \
	"ser2net.yaml" "kickolduser: true"
reject "ser2net does not bind every address" "ser2net.yaml" "tcp,0.0.0.0"

want "the udev rule names the port by physical path" \
	"udev/99-bench-tty.rules" "KERNELS=="
want "the udev rule creates the symlink everything else uses" \
	"udev/99-bench-tty.rules" 'SYMLINK+="tty-dut3"'
reject "the udev rule does not match on a device name" \
	"udev/99-bench-tty.rules" 'KERNEL=="ttyUSB'

# ------------------------------------------- the installer refuses to guess

want "install.sh demands a topology" "install.sh" "isolated | proxy"
# The single quotes and the escape are both deliberate: this is a grep
# pattern that has to match install.sh's text literally, dollar sign and
# all. Expanding it here would search for this test's own empty $other and
# assert nothing. shellcheck cannot tell a pattern from an expression, so
# the intent is stated rather than the warning left to be re-discovered.
# shellcheck disable=SC2016
want "install.sh removes the topology not chosen" \
	"install.sh" 'rm -f "/etc/dnsmasq.d/bench-\$other.conf"'

# Nothing downstream may name ttyUSB0 as a device to open. The whole point
# of the udev rule is that allocation order is not a promise, and one
# forgotten reference undoes it.
#
# One context is legitimate and has to be allowed: "udevadm info -n
# /dev/ttyUSB0" is how the operator finds the port path to put in the rule
# in the first place. That is naming the device in order to stop naming it.
# The first version of this check flagged it, which is the same false
# positive the firewall test hit when a comment cross-referenced another
# image: a rule that cannot tell use from mention is a rule that gets
# silenced rather than fixed.
for file in ser2net.yaml install.sh; do
	if grep -v udevadm "$SERVER/$file" | grep -q '^[^#]*/dev/ttyUSB0'; then
		echo "FAILED   $file names ttyUSB0 as a device to use"
		fail=$((fail + 1))
	else
		echo "ok       $file names ttyUSB0 only to find the port path"
		pass=$((pass + 1))
	fi
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
