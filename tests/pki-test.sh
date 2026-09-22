#!/bin/sh
# pki-test.sh - Project 18's private certificate authority, end to end.
#
# Issue, verify, revoke, regenerate the CRL, verify again. All of it runs
# on a laptop with no board, no network and no broker, because openssl is
# the only thing it needs. That is the whole reason the PKI was built
# before the access point: it is the part of this project that can be
# finished and proven without hardware.
#
# The assertions worth reading are the negative ones. A PKI that issues
# certificates is easy and proves nothing; what matters is that a revoked
# certificate stops verifying, that a client certificate cannot be used as
# a server certificate, and that a request asking to be a certificate
# authority does not become one.
#
# SPDX-License-Identifier: MIT
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
pki="$root/projects/18-edge-ap-mqtt/pki/bench-pki.sh"

command -v openssl >/dev/null 2>&1 || {
	echo "SKIP: no openssl on this host"
	exit 0
}

# Outside the repository, which the tool itself insists on and which one of
# the assertions below checks.
work=$(mktemp -d)
BENCH_PKI_DIR="$work/ca"
export BENCH_PKI_DIR
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); }

bad() {
	fail=$((fail + 1))
	echo "FAIL: $1"
	shift
	for _line in "$@"; do echo "      $_line"; done
}

check_contains() {
	if printf '%s' "$3" | grep -q -- "$2"; then ok; else
		bad "$1" "wanted to find: $2" "in: $3"
	fi
}

# A distinguished name is printed as "CN=x" by the openssl on the Windows
# authoring laptop and as "CN = x" by the one on the Ubuntu runner, and
# both are the same name. Asserting on either spelling passes on one
# machine and fails on the other, which is how a suite acquires a reputation
# for being flaky rather than for being right.
check_matches() {
	if printf '%s' "$3" | grep -Eq -- "$2"; then ok; else
		bad "$1" "wanted to match: $2" "in: $3"
	fi
}

check_absent() {
	if printf '%s' "$3" | grep -q -- "$2"; then
		bad "$1" "did not want: $2" "but it is in: $3"
	else ok; fi
}

check_file() {
	if [ -f "$2" ]; then ok; else bad "$1" "no such file: $2"; fi
}

check_status() {
	if [ "$2" = "$3" ]; then ok; else
		bad "$1" "wanted exit $2, got $3"
	fi
}

run() {
	set +e
	out=$("$@" 2>&1)
	status=$?
	set -e
}

echo "== the CA =="
run sh "$pki" init
check_status "init succeeds" 0 "$status"
check_file "the CA certificate exists" "$BENCH_PKI_DIR/ca.crt"
check_file "the CA private key exists" "$BENCH_PKI_DIR/private/ca.key"
check_file "a CRL exists from the start" "$BENCH_PKI_DIR/bench-ca.crl"

# A CRL that only appears after the first revocation is a broker that
# cannot start until something has been revoked, which is a strange state
# to require of a new bench.

ca_text=$(openssl x509 -in "$BENCH_PKI_DIR/ca.crt" -noout -text)
check_contains "the CA is a CA" "CA:TRUE" "$ca_text"
check_contains "and cannot issue intermediates" "pathlen:0" "$ca_text"
check_contains "it may sign certificates" "Certificate Sign" "$ca_text"
check_contains "and CRLs" "CRL Sign" "$ca_text"
# A CA that can also do TLS server authentication is a CA whose key is
# reachable by anything that can make it terminate a connection.
check_absent "the CA is not also a TLS server" "TLS Web Server" "$ca_text"

run sh "$pki" init
check_status "a second init refuses rather than replacing the CA" 1 "$status"
check_contains "and says what replacing it would cost" "stops verifying" "$out"

echo "== the server certificate =="
run sh "$pki" server bench-ap 10.18.0.1
check_status "issuing a server certificate succeeds" 0 "$status"
srv=$(openssl x509 -in "$BENCH_PKI_DIR/issued/bench-ap.crt" -noout -text)
# The SAN is the whole of criterion 4. There is no DNS on this network, so
# the client dials an address, and a certificate with only a CN is one that
# every modern TLS stack refuses no matter what the CN says.
check_contains "the SAN carries the IP address" "IP Address:10.18.0.1" "$srv"
check_contains "it is a server certificate" "TLS Web Server" "$srv"
check_absent "and not also a client one" "TLS Web Client" "$srv"
check_contains "it is not a CA" "CA:FALSE" "$srv"

run sh "$pki" server named-host bench-ap.lan
check_status "a name is accepted too" 0 "$status"
named=$(openssl x509 -in "$BENCH_PKI_DIR/issued/named-host.crt" -noout -text)
# IP: and DNS: are different SAN types and putting an address in as DNS
# produces a certificate that looks correct and never matches.
check_contains "a hostname goes in as DNS, not IP" "DNS:bench-ap.lan" "$named"

echo "== client certificates =="
run sh "$pki" client ble-gateway
check_status "issuing a client certificate succeeds" 0 "$status"
run sh "$pki" client keystore-verify
check_status "and a second one" 0 "$status"
cli=$(openssl x509 -in "$BENCH_PKI_DIR/issued/ble-gateway.crt" -noout -text)
check_contains "it is a client certificate" "TLS Web Client" "$cli"
# The split is the point. One certificate that is both lets any device
# holding it impersonate the broker to every other device on the network.
check_absent "and cannot act as the broker" "TLS Web Server" "$cli"
check_matches "the CN is the identity the ACL will see" "CN ?= ?ble-gateway" "$cli"

run sh "$pki" client "../../escape"
check_status "a common name that is a path is refused" 1 "$status"
check_contains "and the refusal says why" "becomes a filename" "$out"

echo "== verification =="
run sh "$pki" verify bench-ap
check_status "the server certificate verifies" 0 "$status"
run sh "$pki" verify ble-gateway
check_status "a client certificate verifies" 0 "$status"

echo "== revocation, which is the criterion most often assumed =="
run sh "$pki" revoke ble-gateway
check_status "revoking succeeds" 0 "$status"

run sh "$pki" verify ble-gateway
check_status "the revoked certificate no longer verifies" 2 "$status"
check_contains "and openssl says why" "certificate revoked" "$out"

run sh "$pki" verify keystore-verify
check_status "the other client is untouched" 0 "$status"
run sh "$pki" verify bench-ap
check_status "and so is the server" 0 "$status"

crl=$(openssl crl -in "$BENCH_PKI_DIR/bench-ca.crl" -noout -text)
check_contains "the CRL has a revoked entry" "Serial Number" "$crl"
check_matches "signed by the CA" "CN ?= ?bench-ca" "$crl"

out=$(sh "$pki" list)
# The bug this caught the first time it ran: the CA database leaves the
# revocation date empty for a valid row, IFS collapses the two tabs, every
# column shifts, and the name comes out blank while the row still looks
# like a row.
check_contains "list names a valid certificate" "bench-ap" "$out"
check_contains "list names the revoked one" "REVOKED" "$out"
check_contains "and names it too" "ble-gateway" "$out"

echo "== the request does not get to choose its own extensions =="
# Two separate defences, and the first draft of this section credited the
# wrong one. Setting copy_extensions to copy was expected to make the
# CA:TRUE request succeed and it did not: the extension sections name
# basicConstraints explicitly, and a named extension beats a copied one.
# Removing that line as well is what finally let the request through, which
# is how the real mechanism was established rather than assumed.
#
# So both are asserted, and they cover different things:
#   the named extension   decides basicConstraints and extendedKeyUsage
#   copy_extensions none  covers everything the section does not name
#
# The second is not academic. client_ext says nothing about subjectAltName,
# so with copying on, a device could put any address it liked into its own
# certificate and anything matching on a SAN would believe it.
cat >"$work/evil.cnf" <<'EVIL'
[ req ]
distinguished_name = dn
req_extensions     = evil
prompt             = no

[ dn ]
CN = polite-looking-device

[ evil ]
basicConstraints = critical,CA:TRUE
keyUsage         = critical,keyCertSign,cRLSign
subjectAltName   = IP:10.18.0.1, DNS:bench-ap
EVIL
openssl ecparam -name prime256v1 -genkey -noout -out "$work/evil.key" 2>/dev/null
MSYS2_ARG_CONV_EXCL='/CN=' openssl req -new -key "$work/evil.key" \
	-config "$work/evil.cnf" -out "$work/evil.csr" 2>/dev/null
csr_text=$(openssl req -in "$work/evil.csr" -noout -text)
check_contains "the request really does ask to be a CA" "CA:TRUE" "$csr_text"
check_contains "and to be the broker's own address" "10.18.0.1" "$csr_text"

BENCH_SAN='DNS:unused' openssl ca -config "$BENCH_PKI_DIR/openssl.cnf" \
	-batch -extensions client_ext -in "$work/evil.csr" \
	-out "$work/evil.crt" >/dev/null 2>&1 || true
if [ -f "$work/evil.crt" ]; then
	evil=$(openssl x509 -in "$work/evil.crt" -noout -text)
	check_contains "but the certificate issued is not a CA" "CA:FALSE" "$evil"
	check_absent "and cannot sign certificates" "Certificate Sign" "$evil"
	# This one is what copy_extensions = none is actually for. The section
	# never mentions subjectAltName, so nothing else would strip it.
	check_absent "and did not get the address it asked for" \
		"10.18.0.1" "$evil"
	check_absent "nor the name" "DNS:bench-ap" "$evil"
else
	bad "the CA refused the request outright" \
		"that is also an acceptable outcome, but this test asserts the" \
		"weaker and more dangerous path: that issuing it is harmless"
fi

echo "== the clock rule =="
# The subtlest thing in this project. The board has no real-time clock and
# no uplink, so at boot the clock reaches roughly the image build time and
# stops. A CA created after that makes every certificate on the bench read
# as not yet valid, and the error names the certificate rather than the
# clock.
ca_start=$(openssl x509 -in "$BENCH_PKI_DIR/ca.crt" -noout -startdate |
	sed 's/^notBefore=//')
ca_epoch=$(date -u -d "$ca_start" +%s)
before=$(date -u -d "@$((ca_epoch - 86400))" +%Y%m%d%H%M%S)
after=$(date -u -d "@$((ca_epoch + 86400))" +%Y%m%d%H%M%S)

run sh "$pki" clock-rule "$after"
check_status "an image built after the CA is fine" 0 "$status"
check_contains "and says so" "clock rule holds" "$out"

run sh "$pki" clock-rule "$before"
check_status "an image built before the CA is refused" 1 "$status"
check_contains "and the refusal names the clock, not the certificate" \
	"no RTC" "$out"
check_contains "and prints both timestamps it compared" "$ca_start" "$out"

echo "== the CA never lands in the repository =="
inside="$root/projects/18-edge-ap-mqtt/pki/should-not-exist"
run env BENCH_PKI_DIR="$inside" sh "$pki" init
check_status "a CA inside the checkout is refused" 2 "$status"
check_contains "and the refusal names both paths" "refusing to put" "$out"
# A guard with a side effect is not a guard. The first version resolved the
# path with cd, which needs the directory, so it created the very thing it
# then complained about.
if [ -e "$inside" ]; then
	bad "the refusal created nothing" "but $inside exists"
	rmdir "$inside" 2>/dev/null || true
else
	ok
fi

echo "== deploy copies four files and not the fifth =="
# The fifth is private/ca.key, and it is the one mistake in this project
# that cannot be undone by deleting anything. Everything in the directory
# looks alike and a card is a small object that gets handed around.
card="$work/card"
run sh "$pki" deploy bench-ap "$card"
check_status "deploy succeeds" 0 "$status"
for f in ca.crt bench-ca.crl bench-ap.crt bench-ap.key; do
	check_file "the card gets $f" "$card/$f"
done

count=$(find "$card" -type f | wc -l)
check_status "and gets exactly four files" 4 "$count"

if [ -e "$card/ca.key" ] || [ -e "$card/private" ]; then
	bad "the CA private key is not on the card" "but something is"
else ok; fi

# keystore-verify was issued above and is a different device's identity. A
# loop over issued/* would put it here, and a client key on the broker is
# an identity two machines can present.
if find "$card" -name 'keystore-verify*' | grep -q .; then
	bad "no other device's certificate is on the card" \
		"keystore-verify came along"
else ok; fi

# The certificate on the card is the broker's, under the name the
# configuration expects, whatever the CN was called locally.
card_cn=$(openssl x509 -in "$card/bench-ap.crt" -noout -subject)
check_matches "and it is the broker's certificate" "CN ?= ?bench-ap" \
	"$card_cn"

run sh "$pki" deploy no-such-name "$work/card2"
check_status "deploying a name that was never issued is refused" 1 "$status"
check_contains "and says how to issue it" "bench-pki.sh server" "$out"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
