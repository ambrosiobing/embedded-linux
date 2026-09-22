#!/bin/sh
# broker-config-test.sh - Project 18's broker, without a broker.
#
# Every assertion here is about meaning rather than syntax, because a
# mosquitto.conf that parses is no evidence at all. This bench's own
# conventions say it plainly about a different tool: nft -c will accept an
# input chain with policy accept, a masquerade rule naming one uplink and a
# forward chain with no MSS clamp, and all three work on a bench and fail
# in the field.
#
# The broker's equivalents are worse, because they fail open. A missing
# require_certificate is a broker that accepts anyone. A missing crlfile is
# revocation that changes a file on a laptop and nothing else. A listener
# on 1883 beside the TLS one is the listener every client eventually uses
# by accident. All three parse perfectly.
#
# SPDX-License-Identifier: MIT
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
files="$root/meta-bench/recipes-bench/bench-broker/files"
apfiles="$root/meta-bench/recipes-bench/bench-ap/files"

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
		bad "$1" "wanted: $2" "in the active configuration"
	fi
}
hasnt() {
	if printf '%s' "$3" | grep -q -- "$2"; then
		bad "$1" "did not want: $2" "but it is there"
	else ok; fi
}

# Comments stripped before anything is asserted absent, because the
# configuration explains at length why there is no plaintext listener and
# the word "1883" is all over that explanation.
active() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$'; }

conf=$(active "$files/mosquitto.conf")
acl=$(active "$files/mosquitto.acl")

echo "== there is exactly one listener, and it is the TLS one =="
has "the listener is 8883" "^listener 8883 " "$conf"
# Not 0.0.0.0. There is one interface today and there may be a second the
# day somebody plugs in the USB adapter to debug something, and a broker
# that follows them onto it is a broker on the bench network.
has "bound to an address rather than the wildcard" \
	"^listener 8883 10\.18\.0\.1$" "$conf"
hasnt "there is no plaintext listener" "1883" "$conf"
if [ "$(printf '%s\n' "$conf" | grep -c '^listener ')" -eq 1 ]; then ok; else
	bad "there is exactly one listener" \
		"found $(printf '%s\n' "$conf" | grep -c '^listener ')"
fi

echo "== the private CA is the only thing trusted =="
has "a CA file is named" "^cafile /etc/bench/pki/ca\.crt$" "$conf"
has "and the broker's own certificate" "^certfile " "$conf"
has "and its key" "^keyfile " "$conf"
# Without this line, revoking a certificate changes a file on the laptop
# and nothing else: the revoked device keeps connecting and the whole CRL
# machinery is theatre. This is acceptance criterion 8.
has "the revocation list is actually read" "^crlfile " "$conf"

echo "== identity, and the line that connects it to authorisation =="
has "a client with no certificate cannot connect" \
	"^require_certificate true$" "$conf"
# Without this the broker authenticates a certificate and then authorises
# an unrelated username, so the ACL is enforced against something the PKI
# never vouched for.
has "the certificate CN becomes the username" \
	"^use_identity_as_username true$" "$conf"
has "and anonymous access is off as well" "^allow_anonymous false$" "$conf"
has "TLS 1.2 is the floor" "^tls_version tlsv1\.2$" "$conf"
has "an ACL file is named" "^acl_file " "$conf"

echo "== the ACL file the configuration names actually exists =="
acl_path=$(printf '%s' "$conf" | sed -n 's|^acl_file ||p')
# A document that names an artefact is a claim about it. Here the claim is
# in a configuration file and the cost of it being wrong is a broker that
# refuses to start, on a board with no other network.
case "$acl_path" in
/etc/bench/*)
	if [ -f "$files/$(basename "$acl_path")" ]; then ok; else
		bad "acl_file names a file this recipe installs" \
			"configuration says $acl_path" \
			"but $files/$(basename "$acl_path") does not exist"
	fi
	;;
*) bad "acl_file is under /etc/bench" "it says $acl_path" ;;
esac

echo "== the ACL gives publishers no way to read =="
for who in ble-gateway keystore-verify esp32-01 bench-laptop; do
	has "$who has a rule" "^user $who$" "$acl"
done

# The direction is the whole point of per-device certificates. Written with
# readwrite everywhere, the PKI would still authenticate everyone correctly
# and one compromised sensor would see the entire bench.
rule_for() {
	printf '%s\n' "$acl" | awk -v u="user $1" '
		$0 == u { grab = 1; next }
		/^user / { grab = 0 }
		grab && /^topic / { print; exit }'
}

# MECHANICAL, NOT A LIST.
#
# The first version of this checked four hardcoded rules, which meant the
# test was a second copy of the ACL and agreed with it by construction. It
# also encoded topic prefixes that turned out to be invented: the ACL said
# bench/17/# while the project that would publish there actually uses
# bench/stwin.
#
# The rule is that a device writes under its own common name, so that is
# what is asserted, for every user the file contains rather than for a list
# this test carries. A device added tomorrow is checked by the same line.
for who in $(printf '%s\n' "$acl" | sed -n 's/^user //p'); do
	rule=$(rule_for "$who")
	mode=$(printf '%s' "$rule" | awk '{print $2}')
	topic=$(printf '%s' "$rule" | awk '{print $3}')

	case "$who" in
	bench-laptop)
		# The one identity whose job is to see everything, and therefore
		# the one that must not be able to write anything.
		if [ "$mode" = "read" ] && [ "$topic" = "bench/#" ]; then ok; else
			bad "$who observes the whole bench and cannot publish" \
				"it has: ${rule:-nothing}"
		fi
		;;
	*)
		if [ "$topic" = "bench/$who/#" ]; then ok; else
			bad "$who writes under its own name" \
				"expected topic bench/$who/#" \
				"it has: ${rule:-nothing}"
		fi
		# write, except the one documented exception. Project 20's
		# verifier publishes a value and subscribes for the answer.
		case "$who:$mode" in
		keystore-verify:readwrite) ok ;;
		*:write) ok ;;
		*)
			bad "$who publishes and does not read" \
				"mode is '$mode', and only keystore-verify may be readwrite"
			;;
		esac
		;;
	esac
done

# A subscriber that can also publish is a debugging tool that can inject a
# reading into somebody else's results.
hasnt "the laptop cannot publish" "^topic write bench/#$" "$acl"
# No topic line outside a user block, or it becomes a default permission
# granted to every identity including ones added later.
if [ "$(printf '%s\n' "$acl" | awk '
	/^user /  { inuser = 1; next }
	/^topic / { if (!inuser) print }
' | wc -l)" -eq 0 ]; then ok; else
	bad "no topic rule sits outside a user block" \
		"one does, and it would apply to every identity"
fi

echo "== the broker bounds what one client can cost it =="
# Authentication is not trust. Every client holds a certificate this bench
# issued and one of them may still be a device with a loop in its firmware.
# mosquitto's default message size is 256 MB, which one publish can reach,
# on a board with a gigabyte shared with everything else.
has "one message is bounded" "^message_size_limit " "$conf"
has "and so is the number of connections" "^max_connections " "$conf"
limit=$(printf '%s' "$conf" | sed -n 's/^message_size_limit //p')
if [ "$limit" -gt 0 ] && [ "$limit" -le 1048576 ]; then ok; else
	bad "the message limit is a bound rather than a formality" \
		"it is $limit bytes"
fi

echo "== the documented contract and the enforced one are the same =="
# A document that describes a configuration is a claim about it, and
# nothing tests it. This project's own ACL invented topic prefixes once
# already, so the two are checked against each other rather than trusted.
proto="$root/projects/18-edge-ap-mqtt/docs/PROTOCOL.md"
if [ -f "$proto" ]; then
	ptext=$(cat "$proto")
	has "the protocol document states the naming rule" \
		"bench/<your common name>/" "$ptext"
	has "and names the listener the configuration actually opens" \
		"8883" "$ptext"
	# The one cross-project requirement, which is easy to forget because
	# it lives in another project's file.
	has "and records that Project 17 must retopic to publish here" \
		"STWIN_TOPIC" "$ptext"
	has "with the value it has to become" "bench/ble-gateway/stwin" "$ptext"
	# Every identity the ACL grants has to appear in the document, or a
	# device exists that nothing tells anybody about.
	for who in $(printf '%s\n' "$acl" | sed -n 's/^user //p'); do
		has "the document mentions $who" "$who" "$ptext"
	done
else
	bad "docs/PROTOCOL.md exists" "the ACL's rule is documented nowhere"
fi

echo "== the broker and the access point agree on the address =="
# Two files, each valid alone, that are wrong together: a broker bound to
# an address the interface does not have starts, fails to bind, and
# restarts until systemd gives up. The log reads as a broker problem.
net_addr=$(sed -n 's|^Address=\([0-9.]*\)/.*|\1|p' "$apfiles/10-bench-ap.network")
listen_addr=$(printf '%s' "$conf" | sed -n 's|^listener 8883 ||p')
if [ "$net_addr" = "$listen_addr" ]; then ok; else
	bad "the listener address is the one the interface is given" \
		"10-bench-ap.network assigns $net_addr" \
		"mosquitto.conf listens on $listen_addr"
fi

echo "== the drop-in does not start two brokers =="
dropin="$files/mosquitto-bench.conf"
drop=$(cat "$dropin")
# A drop-in appends to a list, and mosquitto.service already has an
# ExecStart. Without the empty assignment first, the unit carries two.
if printf '%s\n' "$drop" | grep -q '^ExecStart=$'; then ok; else
	bad "ExecStart is cleared before it is set" \
		"a drop-in appends, so without the empty assignment the unit" \
		"has two ExecStart lines and starts a second broker that" \
		"cannot bind the port the first one took"
fi
has "and then set to this project's configuration" \
	"^ExecStart=.*-c /etc/bench/mosquitto\.conf$" "$drop"
has "the broker waits for the address" "After=.*systemd-networkd" "$drop"

echo "== no key or certificate is in the repository =="
# The image carries capability and the card carries identity. A private key
# committed once is a private key that has to be replaced rather than
# removed, so this is checked rather than trusted to habit.
found=$(find "$root/meta-bench" "$root/projects/18-edge-ap-mqtt" \
	-name '*.key' -o -name '*.crt' -o -name '*.pem' 2>/dev/null || true)
if [ -z "$found" ]; then ok; else
	bad "no certificate or key is committed" "$found"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
