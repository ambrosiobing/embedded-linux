#!/bin/sh
#
# bench-router-nftables-test.sh - the properties the ruleset has to have.
#
# "nft -c -f" checks syntax, which is the easy half and is done below when
# nft is present. The half that matters is semantic, and nft would accept
# every one of these mistakes without a word:
#
#   an input chain with policy accept, which exposes sshd and the metrics
#   endpoint to the carrier network the moment the bearer comes up;
#   a masquerade rule naming only one uplink, so failover moves the route
#   and the packets are then dropped on the way out;
#   a forward chain with no MSS clamp, so every client completes a TCP
#   handshake over LTE and then stalls on the first large response.
#
# All three are the kind of thing that works on the bench and fails in the
# field, so they are asserted here rather than remembered.
#
#   sh tests/bench-router-nftables-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RULES=$ROOT/meta-bench/recipes-bench/bench-router/files/nftables.conf

pass=0
fail=0

want() {
	if grep -q -- "$2" "$RULES"; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1"
		fail=$((fail + 1))
	fi
}

reject() {
	if grep -q -- "$2" "$RULES"; then
		echo "FAILED   $1"
		fail=$((fail + 1))
	else
		echo "ok       $1"
		pass=$((pass + 1))
	fi
}

want "the ruleset starts from a known state" "^flush ruleset"
want "there is an input chain" "chain input"
want "input drops by default" "hook input priority filter; policy drop;"
want "forward drops by default" "hook forward priority filter; policy drop;"
want "established traffic comes back" "ct state established,related accept"
want "invalid packets are dropped" "ct state invalid drop"
want "the loopback is not filtered" "iif lo accept"
want "ICMP survives, so path MTU discovery works" "meta l4proto icmp accept"
want "the LAN can reach the metrics endpoint" "9101"
want "the LAN gets DHCP and DNS" "udp dport { 53, 67 } accept"
want "masquerade names both uplinks" \
	'oifname { "eth0", "wwan0" } masquerade'
want "forwarding is from the LAN to an uplink only" \
	'iifname "wlan0" oifname { "eth0", "wwan0" } accept'
want "the MSS is clamped to the path MTU" "tcp option maxseg size set rt mtu"
want "what is dropped is counted" "counter"

# The rule that would undo the input policy, written the way someone in a
# hurry writes it at two in the morning.
reject "no blanket accept on input" "hook input priority filter; policy accept;"
reject "the metrics port is not opened on an uplink" 'iifname "wwan0" tcp dport'

# The forward chain must not accept from an uplink towards the LAN except
# for return traffic, which the conntrack rule already covers.
reject "no unsolicited path from an uplink into the LAN" \
	'iifname "wwan0" oifname "wlan0" accept'

# Syntax, when the tool is here. In a container without CAP_NET_ADMIN even
# a check run cannot open the netlink socket, so a refusal on permissions
# is reported and not counted as a failure: it says nothing about the file.
if command -v nft >/dev/null 2>&1; then
	if output=$(nft -c -f "$RULES" 2>&1); then
		echo "ok       nft accepts the ruleset"
		pass=$((pass + 1))
	else
		case $output in
		*"Operation not permitted"* | *"Permission denied"*)
			echo "note     nft cannot check without CAP_NET_ADMIN here"
			;;
		*)
			echo "FAILED   nft rejected the ruleset:"
			echo "$output"
			fail=$((fail + 1))
			;;
		esac
	fi
else
	echo "note     nft is not installed, syntax not checked"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
