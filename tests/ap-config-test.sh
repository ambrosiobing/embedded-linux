#!/bin/sh
# ap-config-test.sh - Project 18's access point, without an access point.
#
# Two halves. The first drives bench-ap-setup against fixture files where
# /boot/ap.conf would be, including the three Windows text traps and every
# refusal. The second asserts the shipped configuration files mean what the
# design says, which is not the same as checking they parse.
#
# The cross-file assertions are the ones worth having. A dnsmasq range and
# a static address are each individually valid and wrong together, and
# nothing on a board reports that: clients simply get an address they
# cannot use and the symptom is "the wireless does not work".
#
# SPDX-License-Identifier: MIT
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
files="$root/meta-bench/recipes-bench/bench-ap/files"
setup="$files/bench-ap-setup"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() {
	fail=$((fail + 1))
	echo "FAIL: $1"
	shift
	for _l in "$@"; do echo "      $_l"; done
}

has() {
	if printf '%s' "$3" | grep -q -- "$2"; then ok; else
		bad "$1" "wanted: $2" "in: $3"
	fi
}
hasnt() {
	if printf '%s' "$3" | grep -q -- "$2"; then
		bad "$1" "did not want: $2" "but found it"
	else ok; fi
}
status_is() {
	if [ "$2" = "$3" ]; then ok; else bad "$1" "wanted exit $2, got $3"; fi
}

BENCH_AP_TEMPLATE="$files/hostapd.conf.in"
BENCH_AP_TARGET="$work/hostapd.conf"
export BENCH_AP_TEMPLATE BENCH_AP_TARGET

run_setup() {
	BENCH_AP_SOURCE="$1"
	export BENCH_AP_SOURCE
	set +e
	out=$(sh "$setup" 2>&1)
	status=$?
	set -e
}

echo "== the ordinary case =="
printf 'SSID=bench-18\nPASSPHRASE=correct-horse\nCHANNEL=11\nCOUNTRY=AT\n' \
	>"$work/ok.conf"
run_setup "$work/ok.conf"
status_is "a complete file is accepted" 0 "$status"
conf=$(cat "$BENCH_AP_TARGET")
has "the SSID reaches hostapd" "^ssid=bench-18$" "$conf"
has "the passphrase reaches hostapd" "^wpa_passphrase=correct-horse$" "$conf"
has "the channel is the one asked for" "^channel=11$" "$conf"
has "and the country" "^country_code=AT$" "$conf"
hasnt "no placeholder survives" "@" "$conf"
# The passphrase is in this file. It is printed at boot on a console
# somebody is watching, so the script reports its length instead.
hasnt "the passphrase is not echoed to the console" "correct-horse" "$out"
has "but its length is" "13 characters" "$out"

echo "== the three Windows text traps =="
# A UTF-8 byte order mark on the first key, which Notepad writes by
# default, and which makes the first key unrecognisable to a plain match.
printf '\357\273\277SSID=bom-test\nPASSPHRASE=eightchars\n' >"$work/bom.conf"
run_setup "$work/bom.conf"
status_is "a byte order mark does not hide the first key" 0 "$status"
has "and the SSID is intact" "^ssid=bom-test$" "$(cat "$BENCH_AP_TARGET")"

printf 'SSID=crlf-test\r\nPASSPHRASE=eightchars\r\nCHANNEL=1\r\n' \
	>"$work/crlf.conf"
run_setup "$work/crlf.conf"
status_is "CRLF endings are accepted" 0 "$status"
crlf_out=$(cat "$BENCH_AP_TARGET")
has "and the SSID is clean" "^ssid=crlf-test$" "$crlf_out"
# A carriage return inside the passphrase is the failure that is invisible:
# hostapd starts, the network appears, and no client can ever join it.
if printf '%s' "$crlf_out" | od -c | grep -q '\\r'; then
	bad "no carriage return survives into hostapd.conf" \
		"one is still in the generated file"
else ok; fi

# The third trap, and the one this repository lost a board to: read returns
# false on a final line with no newline, so a plain loop drops the last key.
printf 'SSID=nonewline\nPASSPHRASE=lastkeyhere' >"$work/nonl.conf"
run_setup "$work/nonl.conf"
status_is "a file with no final newline is accepted" 0 "$status"
has "and the last key is not dropped" "^wpa_passphrase=lastkeyhere$" \
	"$(cat "$BENCH_AP_TARGET")"

echo "== the refusals, which are the board's only feedback =="
run_setup "$work/absent.conf"
status_is "a missing ap.conf is refused" 1 "$status"
has "and the message names the file" "absent.conf" "$out"
# This board has no other network. A refusal that does not say what to
# write costs somebody the walk to find the serial cable.
has "and says what to write" "SSID=" "$out"
has "and mentions the console" "serial console" "$out"

printf 'SSID=short\nPASSPHRASE=seven77\n' >"$work/short.conf"
run_setup "$work/short.conf"
status_is "a seven character passphrase is refused" 1 "$status"
has "and the refusal gives the length" "7 characters" "$out"
has "and the rule" "8 to 63" "$out"

printf 'PASSPHRASE=eightchars\n' >"$work/nossid.conf"
run_setup "$work/nossid.conf"
status_is "a missing SSID is refused" 1 "$status"
has "by name" "no SSID=" "$out"

printf 'SSID=x\nPASSPHRASE=eightchars\nCOUNTRY=Germany\n' >"$work/cc.conf"
run_setup "$work/cc.conf"
status_is "a country that is not two letters is refused" 1 "$status"
has "and the refusal quotes what it saw" "Germany" "$out"

printf 'SSID=x\nPASSPHRASE=eightchars\nCHANNEL=eleven\n' >"$work/ch.conf"
run_setup "$work/ch.conf"
status_is "a channel that is not a number is refused" 1 "$status"
has "and quotes it" "eleven" "$out"

long=$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
	21 22 23 24 25 26 27 28 29 30 31 32 33)
printf 'SSID=%s\nPASSPHRASE=eightchars\n' "$long" >"$work/long.conf"
run_setup "$work/long.conf"
status_is "an SSID of 33 characters is refused" 1 "$status"
has "and the refusal gives the maximum" "maximum is 32" "$out"

# Comments are stripped before anything is asserted absent.
#
# The first version of the TKIP assertion below failed, and it was right to
# fail: the word is in the template, in the comment explaining that TKIP is
# deliberately not in the pairwise list. A check that reads prose as
# configuration is the mirror of the one this repository already shipped,
# where a regex matched its own file's comments and silenced itself.
active() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$'; }

echo "== the shipped hostapd template means what the design says =="
tpl=$(active "$files/hostapd.conf.in")
has "WPA2 only, which is RSN" "^wpa=2$" "$tpl"
has "and CCMP" "^rsn_pairwise=CCMP$" "$tpl"
# TKIP in the pairwise list is how a network that looks like WPA2
# negotiates something weaker with an old client, and nothing reports it.
hasnt "TKIP is absent" "TKIP" "$tpl"
hasnt "and there is no WPA1 fallback" "^wpa=1" "$tpl"
has "clients cannot reach each other" "^ap_isolate=1$" "$tpl"
has "the regulatory domain is advertised" "^ieee80211d=1$" "$tpl"
has "the SSID is not hidden" "^ignore_broadcast_ssid=0$" "$tpl"
has "and the driver is nl80211" "^driver=nl80211$" "$tpl"

echo "== dnsmasq serves addresses and nothing else =="
dns=$(active "$files/dnsmasq-ap.conf")
# port=0 is the difference between no DNS service and a DNS service that
# answers SERVFAIL, which looks to a client like a broken network.
has "the DNS listener is off" "^port=0$" "$dns"
has "it binds the interface it owns" "^bind-interfaces$" "$dns"
has "and only that one" "^interface=wlan0$" "$dns"
has "it is authoritative for its own island" "^dhcp-authoritative$" "$dns"
# Telling a client about a gateway that does not exist makes it spend
# timeouts discovering that, and a phone usually decides the network is
# broken and leaves.
has "no default route is offered" "^dhcp-option=3$" "$dns"
has "and no DNS server" "^dhcp-option=6$" "$dns"

echo "== the two files have to agree, and each is valid alone =="
net=$(cat "$files/10-bench-ap.network")
has "the access point has a static address" "Address=10.18.0.1/24" "$net"
has "it asks nobody for one" "DHCP=no" "$net"

addr=$(printf '%s' "$net" | sed -n 's|^Address=\([0-9.]*\)/.*|\1|p')
prefix=$(printf '%s' "$addr" | cut -d. -f1-3)
range=$(printf '%s' "$dns" | sed -n 's/^dhcp-range=//p')
low=$(printf '%s' "$range" | cut -d, -f1)
high=$(printf '%s' "$range" | cut -d, -f2)

# The assertion that no single file could make. Both are individually
# valid with a range in another subnet, and the board reports nothing: the
# clients get addresses and cannot reach the broker.
for end in "$low" "$high"; do
	if [ "$(printf '%s' "$end" | cut -d. -f1-3)" = "$prefix" ]; then ok; else
		bad "the DHCP range is inside the access point's subnet" \
			"address $addr is in $prefix.0/24" \
			"but the range end $end is not"
	fi
done

# And the server must not hand out its own address.
if [ "$low" = "$addr" ] || [ "$high" = "$addr" ]; then
	bad "the range does not include the access point itself" \
		"$addr is an end of the range $range"
else ok; fi

echo "== the island serves time, because certificates need it =="
# The finding that arrived after the design was written. A station with no
# real-time clock powers up in 1970, checks the broker's certificate, finds
# a notBefore in 2026 and refuses with an error that mentions no clock.
# Both of this project's station clients are in that position.
has "an NTP server is offered over DHCP" "^dhcp-option=42," "$dns"

ntp_addr=$(printf '%s' "$dns" | sed -n 's/^dhcp-option=42,//p')
# Cross-file again: handing out an NTP address the interface does not have
# is a client that waits for a timeout and then has no time, which shows up
# as a TLS failure rather than as anything about time.
if [ "$ntp_addr" = "$addr" ]; then ok; else
	bad "the NTP server offered is the access point itself" \
		"the interface has $addr" \
		"but DHCP hands out $ntp_addr"
fi

chrony=$(active "$files/chrony.conf")
# Without this, chronyd refuses to answer at all, because by default a
# server will not hand out a time it cannot vouch for. Correct on the
# internet, and here it leaves every client in 1970.
has "the local clock is served even though it is synchronised to nothing" \
	"^local stratum " "$chrony"
has "and at a deliberately poor stratum" "^local stratum 10" "$chrony"
has "the island's subnet is allowed" "^allow 10\.18\.0\.0/24$" "$chrony"
# There is no uplink. An upstream server here is a daemon spending every
# poll interval failing to reach something.
hasnt "no upstream server is configured" "^server " "$chrony"
hasnt "and no pool" "^pool " "$chrony"
# A fifty year offset cannot be slewed. Without makestep the clock creeps
# towards the right answer over a period longer than the project.
has "a large offset is stepped rather than slewed" "^makestep " "$chrony"

chrony_drop=$(cat "$files/chrony-bench.conf")
if printf '%s\n' "$chrony_drop" | grep -q '^ExecStart=$'; then ok; else
	bad "the chrony drop-in clears ExecStart before setting it" \
		"a drop-in appends, so without the empty assignment the unit" \
		"carries two ExecStart lines and starts two daemons on one port"
fi
has "and points chronyd at this project's configuration" \
	"^ExecStart=.*-f /etc/bench/chrony\.conf$" "$chrony_drop"

echo "== the units order themselves correctly =="
setup_unit=$(cat "$files/bench-ap-setup.service")
hostapd_unit=$(cat "$files/bench-hostapd.service")
dnsmasq_unit=$(cat "$files/bench-dnsmasq.service")
has "the configuration is built before hostapd reads it" \
	"Before=bench-hostapd.service" "$setup_unit"
has "and hostapd requires that it succeeded" \
	"Requires=bench-ap-setup.service" "$hostapd_unit"
# hostapd reads /run, so a unit pointing at /etc is reading a file that
# does not exist and never will.
has "hostapd reads the generated file, not a shipped one" \
	"/run/bench/hostapd.conf" "$hostapd_unit"
# This is the board's only network. A hostapd that exits and stays dead
# leaves a machine reachable only from the serial console.
has "hostapd is restarted, because it is the only way in" \
	"Restart=always" "$hostapd_unit"
# dnsmasq binds the address rather than the wildcard, so starting before
# the address exists is a failure and not a slow start.
has "dnsmasq waits for the address" "After=.*systemd-networkd" "$dnsmasq_unit"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
