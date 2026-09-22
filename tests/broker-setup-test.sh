#!/bin/sh
# broker-setup-test.sh - the board's side of getting certificates onto it.
#
# bench-broker-setup runs at first boot and installs the four files from
# the card's boot partition into the directory mosquitto reads. It is
# driven here against real certificates, issued by this project's own CA on
# this laptop, with no board anywhere.
#
# The assertions worth reading are the refusals, and the first one is the
# reason this script exists at all rather than being a line in a bring-up
# document: a CA private key on the card. Everything in the certificate
# directory looks alike, the one file that must never travel sits next to
# three that must, and a card is a small object that gets handed around and
# put in a drawer. A CA key that has left the laptop cannot be recalled by
# deleting it.
#
# SPDX-License-Identifier: MIT
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
setup="$root/meta-bench/recipes-bench/bench-broker/files/bench-broker-setup"
pki="$root/projects/18-edge-ap-mqtt/pki/bench-pki.sh"

command -v openssl >/dev/null 2>&1 || {
	echo "SKIP: no openssl on this host"
	exit 0
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
BENCH_PKI_DIR="$work/ca"
export BENCH_PKI_DIR

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
status_is() {
	if [ "$2" = "$3" ]; then ok; else bad "$1" "wanted exit $2, got $3"; fi
}

sh "$pki" init >/dev/null 2>&1 || {
	echo "SKIP: could not create a CA on this host"
	exit 0
}
sh "$pki" server bench-ap 10.18.0.1 >/dev/null

run_setup() {
	BENCH_BROKER_SOURCE=$1
	BENCH_BROKER_TARGET=$2
	BENCH_BROKER_OWNER=no-such-user-here
	export BENCH_BROKER_SOURCE BENCH_BROKER_TARGET BENCH_BROKER_OWNER
	set +e
	out=$(sh "$setup" 2>&1)
	status=$?
	set -e
}

fresh_card() {
	rm -rf "${work:?}/card" "${work:?}/etc"
	sh "$pki" deploy bench-ap "$work/card" >/dev/null
}

echo "== the ordinary first boot =="
fresh_card
run_setup "$work/card" "$work/etc"
status_is "a correct card is accepted" 0 "$status"
for f in ca.crt bench-ca.crl bench-ap.crt bench-ap.key; do
	if [ -f "$work/etc/$f" ]; then ok; else
		bad "$f is installed" "not at $work/etc/$f"
	fi
done
has "and it says what it did" "installed" "$out"

echo "== a CA private key on the card stops everything =="
# Before anything is copied, and deliberately before the other checks. A
# run that installed the good files first would leave a working board and a
# problem nobody looks for again.
fresh_card
cp "$BENCH_PKI_DIR/private/ca.key" "$work/card/ca.key"
rm -rf "${work:?}/etc"
run_setup "$work/card" "$work/etc"
status_is "the run is refused" 1 "$status"
has "and the refusal names the file" "ca.key" "$out"
has "and says what it means" "compromised" "$out"
if [ -d "$work/etc" ]; then
	bad "nothing was installed" "$work/etc exists, so files were copied"
else ok; fi

# The rest of the authority is not a secret but has no business travelling
# either, and its presence means somebody copied a directory rather than
# four files.
for extra in index.txt serial openssl.cnf; do
	fresh_card
	cp "$BENCH_PKI_DIR/$extra" "$work/card/$extra"
	rm -rf "${work:?}/etc"
	run_setup "$work/card" "$work/etc"
	status_is "a card carrying $extra is refused" 1 "$status"
done

echo "== a certificate and a key that are not a pair =="
# Easy to do and hard to see: same filenames, opaque contents. Mosquitto's
# own complaint names neither file, on a board whose only other way in is a
# serial cable.
fresh_card
sh "$pki" server other-host 10.18.0.9 >/dev/null
cp "$BENCH_PKI_DIR/issued/other-host.key" "$work/card/bench-ap.key"
rm -rf "${work:?}/etc"
run_setup "$work/card" "$work/etc"
status_is "a mismatched pair is refused" 1 "$status"
has "and the refusal says they are not a pair" "not a pair" "$out"
has "and gives the two commands to fix it" "bench-pki.sh deploy" "$out"

echo "== a certificate this CA did not sign =="
# Every client checks exactly this, so a board that started anyway would
# present a chain nothing on the bench can verify.
fresh_card
stranger="$work/stranger"
mkdir -p "$stranger"
BENCH_PKI_DIR="$stranger" sh "$pki" init >/dev/null 2>&1
BENCH_PKI_DIR="$stranger" sh "$pki" server bench-ap 10.18.0.1 >/dev/null 2>&1
cp "$stranger/issued/bench-ap.crt" "$work/card/bench-ap.crt"
cp "$stranger/issued/bench-ap.key" "$work/card/bench-ap.key"
rm -rf "${work:?}/etc"
run_setup "$work/card" "$work/etc"
status_is "a certificate from another CA is refused" 1 "$status"
has "and the refusal explains the consequence" "no client would connect" "$out"

echo "== an incomplete card =="
fresh_card
rm "$work/card/bench-ca.crl"
rm -rf "${work:?}/etc"
run_setup "$work/card" "$work/etc"
status_is "a missing file is refused" 1 "$status"
has "and it is named" "bench-ca.crl" "$out"

fresh_card
: >"$work/card/ca.crt"
rm -rf "${work:?}/etc"
run_setup "$work/card" "$work/etc"
status_is "an empty file is refused too" 1 "$status"
has "and named" "ca.crt" "$out"

echo "== the second boot, when the card has been emptied =="
# Leaving the certificates on the card after provisioning is worse than
# taking them off, so a board that has been provisioned must not then
# refuse to start because the card is clean.
fresh_card
rm -rf "${work:?}/etc"
run_setup "$work/card" "$work/etc"
status_is "first boot provisions" 0 "$status"
run_setup "$work/absent-dir" "$work/etc"
status_is "and a later boot with no card is fine" 0 "$status"
has "and says why it did nothing" "already complete" "$out"

echo "== no card and nothing installed =="
rm -rf "${work:?}/etc"
run_setup "$work/absent-dir" "$work/etc"
status_is "that is refused" 1 "$status"
has "and the refusal gives the deploy command" "bench-pki.sh deploy" "$out"
has "and the issue command before it" "bench-pki.sh server" "$out"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
