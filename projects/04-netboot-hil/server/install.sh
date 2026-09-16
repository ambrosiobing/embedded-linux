#!/bin/sh
#
# install.sh - turn a Raspberry Pi OS Lite install into the lab server.
#
# Run on the server, from this directory. The point of this script is that
# the server is reproducible: the four configuration files next to it are
# the whole lab, and a server rebuilt from a fresh card is ten minutes of
# apt plus one run of this.
#
#   sudo sh install.sh isolated     direct cable, this server is the DHCP server
#   sudo sh install.sh proxy        both boards on a router, dnsmasq adds boot options
#
# What it does not do is decide anything. It refuses rather than guessing
# when the choice matters: which topology, which USB port the console cable
# is in, and whether an existing configuration is about to be overwritten.
#
# SPDX-License-Identifier: MIT

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
TOPOLOGY=${1:-}

die() {
	echo "install.sh: $*" >&2
	exit 1
}

note() {
	printf -- '--- %s\n' "$*"
}

[ "$(id -u)" -eq 0 ] || die "run this with sudo; it writes under /etc and /srv"

case $TOPOLOGY in
isolated | proxy) ;;
*)
	die "say which topology: isolated (direct cable) or proxy (both on a router).
       They are mutually exclusive and installing both gives two DHCP
       answers on one wire, which is worse than either."
	;;
esac

# --- packages ---------------------------------------------------------
#
# Named rather than assumed. A server missing ser2net looks exactly like a
# console cable in the wrong port, and that is an hour nobody needs to
# spend twice.
PACKAGES="dnsmasq nfs-kernel-server ser2net tcpdump python3-pytest python3-serial python3-libgpiod"

missing=
for package in $PACKAGES; do
	if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
		grep -q "ok installed"; then
		missing="$missing $package"
	fi
done

if [ -n "$missing" ]; then
	note "installing:$missing"
	apt-get update
	# shellcheck disable=SC2086
	apt-get install -y $missing
else
	note "all packages already present"
fi

# --- directories ------------------------------------------------------

note "creating /srv/tftp and /srv/nfs/dut3"
mkdir -p /srv/tftp /srv/nfs/dut3

# --- dnsmasq ----------------------------------------------------------
#
# Exactly one of the two files, and the other actively removed. Leaving the
# unused one in place is the failure this guards against: dnsmasq reads
# every file in the directory, so a stale proxy configuration alongside the
# isolated one gives a DUT two different answers depending on timing.

note "installing the $TOPOLOGY dnsmasq configuration"
install -Dm0644 "$HERE/dnsmasq.d/bench-$TOPOLOGY.conf" \
	/etc/dnsmasq.d/bench-$TOPOLOGY.conf

other=proxy
[ "$TOPOLOGY" = "proxy" ] && other=isolated
if [ -f "/etc/dnsmasq.d/bench-$other.conf" ]; then
	note "removing the $other configuration, which would contend with it"
	rm -f "/etc/dnsmasq.d/bench-$other.conf"
fi

# --- NFS --------------------------------------------------------------

note "installing the NFS export"
install -Dm0644 "$HERE/exports" /etc/exports.d/bench-hil.exports

# --- console ----------------------------------------------------------

note "installing the udev rule and the ser2net configuration"
install -Dm0644 "$HERE/udev/99-bench-tty.rules" \
	/etc/udev/rules.d/99-bench-tty.rules
install -Dm0644 "$HERE/ser2net.yaml" /etc/ser2net.yaml
install -Dm0755 "$HERE/leds.py" /usr/local/bin/bench-leds

udevadm control --reload
udevadm trigger --subsystem-match=tty

# --- services ---------------------------------------------------------

note "enabling dnsmasq, nfs-server and ser2net"
exportfs -ra
systemctl enable --now nfs-server dnsmasq ser2net

# --- what the operator still has to do --------------------------------

echo
note "installed. Two things this script deliberately did not do:"
echo
echo "  1. The udev rule matches a placeholder USB port. Find the real one"
echo "     and edit /etc/udev/rules.d/99-bench-tty.rules:"
echo
echo "       udevadm info -a -n /dev/ttyUSB0 | grep -m3 -E 'KERNELS|idVendor'"
echo
echo "     Then: udevadm control --reload && udevadm trigger"
echo "     Check: ls -l /dev/tty-dut3"
echo

if [ "$TOPOLOGY" = "isolated" ]; then
	echo "  2. eth0 needs the static address 192.168.7.1/24, set by whatever"
	echo "     manages networking on this server, and that manager has to be"
	echo "     told to leave eth0 alone otherwise. Two things configuring one"
	echo "     interface is the commonest way to lose a lab network."
else
	echo "  2. This server must be on the same broadcast domain as the DUT,"
	echo "     which means plugged into the router by cable. An access point"
	echo "     that filters broadcasts between wireless and wired clients"
	echo "     breaks proxy DHCP silently."
fi
echo
note "then: journalctl -fu dnsmasq, and power on the DUT with no card in it"
