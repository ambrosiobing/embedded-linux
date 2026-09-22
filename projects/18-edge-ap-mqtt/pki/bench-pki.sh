#!/bin/sh
# bench-pki.sh - the private certificate authority for Project 18.
#
#   bench-pki.sh init                 create the CA
#   bench-pki.sh server CN ADDRESS    a broker certificate, SAN carries ADDRESS
#   bench-pki.sh client CN            a device certificate
#   bench-pki.sh revoke CN            revoke it and regenerate the CRL
#   bench-pki.sh verify CN            check one certificate against CA and CRL
#   bench-pki.sh clock-rule STAMP     the notBefore rule, see below
#   bench-pki.sh list                 what has been issued, and what is revoked
#   bench-pki.sh deploy CN DIR        the four files the board needs, and only
#                                     those four
#
# THIS RUNS ON THE LAPTOP AND NEVER ON THE BOARD.
#
# A board that can sign certificates is a board whose compromise mints new
# identities, and this one is by design sitting in a room with its radio on
# and no uplink. Only two files ever leave here for the board: the broker's
# certificate and its key. The CA private key stays.
#
# WHERE IT WRITES, AND THE GUARD ON IT.
#
# $BENCH_PKI_DIR, defaulting to ~/.bench-pki, which is outside this
# repository on purpose. The guard below refuses to run if that directory
# is inside the checkout, because the one thing that must never happen to
# this project is a CA private key in a public repository. .gitignore is
# not enough on its own: it is one edit away from not covering a path, and
# the failure is unrecoverable in the way that matters, since a key that
# has been pushed is a key that has to be replaced rather than removed.
#
# ELLIPTIC CURVE, NOT RSA.
#
# P-256. The clients here include an ESP8266, where an RSA-2048 handshake
# is measured in seconds of a processor that has other work, and an ESP32.
# Both handle P-256 comfortably. The broker and the laptop do not care
# either way, so the constrained client decides.
#
# SPDX-License-Identifier: MIT
set -eu

# GIT BASH REWRITES ARGUMENTS THAT LOOK LIKE PATHS, AND EVERY OPENSSL
# SUBJECT LOOKS LIKE A PATH.
#
# openssl takes a subject as /CN=bench-ca. The MSYS layer under Git Bash
# sees a leading slash, decides it is a Unix path, and hands openssl the
# translated form. The first run of this script on the Windows laptop said:
#
#   req: subject name is expected to be in the format /type0=value0/...
#   This name is not in that format: 'C:/Program Files/Git/CN=bench-ca'
#
# which names the right symptom and the wrong cause, and sends the reader
# looking at their subject string.
#
# The obvious fix is MSYS_NO_PATHCONV=1, which switches the translation off
# altogether. That was tried second and is worse, because every other
# argument here IS a path and does need translating:
#
#   ecparam: Can't open "/tmp/pki-try/private/ca.key" for writing
#
# So the exclusion is by prefix and covers exactly the subject. Every other
# argument keeps its translation. On Linux and in CI this is an unset
# variable that nothing reads, so it costs nothing where it is not needed.
MSYS2_ARG_CONV_EXCL='/CN='
export MSYS2_ARG_CONV_EXCL

PKI_DIR=${BENCH_PKI_DIR:-$HOME/.bench-pki}
CA_DAYS=${BENCH_CA_DAYS:-3650}
# 825 days is the longest a public CA may issue for, and this is a private
# CA that could issue for a decade. It is kept anyway: a certificate whose
# lifetime exceeds the memory of the person who issued it is a certificate
# nobody rotates, and the revocation machinery below only stays exercised
# if something forces it to be used.
LEAF_DAYS=${BENCH_LEAF_DAYS:-825}

die() {
	echo "bench-pki: $*" >&2
	exit 1
}

need_openssl() {
	command -v openssl >/dev/null 2>&1 ||
		die "openssl is not installed"
}

# The guard. Refuses with the two paths it compared, because a refusal that
# does not name what it matched cannot be argued with, and on this bench
# that is how guards get switched off.
refuse_inside_repo() {
	_repo=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
	_pki=$1
	case "$_pki/" in
	"$_repo"/*)
		echo "bench-pki: refusing to put a certificate authority inside" >&2
		echo "           the repository." >&2
		echo "  BENCH_PKI_DIR $_pki" >&2
		echo "  repository    $_repo" >&2
		echo "The CA private key must never be committable. Set" >&2
		echo "BENCH_PKI_DIR to a path outside the checkout." >&2
		exit 2
		;;
	esac
}

# The shell's path translation applies to arguments, never to the contents
# of a file that a program opens itself. openssl reads `dir` out of the
# configuration below and uses it as given, so on Git Bash a POSIX path
# written in there is a path openssl cannot open:
#
#   Using configuration from C:\Users\...\Temp/pki-try/openssl.cnf
#   Could not open file or uri for loading CA private key from
#   /tmp/pki-try/private/ca.key: No such file or directory
#
# The configuration file itself was found, because that was an argument.
# What is inside it was not, because that was not. cygpath exists only
# where this matters and the fallback is the path unchanged, so this is a
# no-op on Linux and in CI.
native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		printf '%s\n' "$1"
	fi
}

write_config() {
	# Written rather than shipped, so that `dir` is absolute and correct on
	# whatever machine this runs on. An openssl.cnf with a relative dir
	# works from one directory and fails from every other one, which is the
	# kind of bug that gets diagnosed as a permissions problem.
	_dir=$(native_path "$PKI_DIR")
	cat >"$PKI_DIR/openssl.cnf" <<CONFIG
[ ca ]
default_ca = bench_ca

[ bench_ca ]
dir               = $_dir
database          = \$dir/index.txt
serial            = \$dir/serial
crlnumber         = \$dir/crlnumber
new_certs_dir     = \$dir/newcerts
certificate       = \$dir/ca.crt
private_key       = \$dir/private/ca.key
default_md        = sha256
default_days      = $LEAF_DAYS
default_crl_days  = 30
policy            = policy_cn
email_in_dn       = no
rand_serial       = no
unique_subject    = no
copy_extensions   = none

# copy_extensions is none on purpose, and it is the second of two defences
# rather than the first. This was stated the other way round at first and
# the test disagreed, which is worth recording where the setting is.
#
# Setting it to copy and issuing a request that asks for
# basicConstraints CA:TRUE still produces CA:FALSE, because the extension
# sections below name basicConstraints explicitly and a named extension
# wins over a copied one. So the sections are the defence that decides.
#
# What copy_extensions = none actually covers is everything the sections do
# NOT name. client_ext says nothing about subjectAltName, so with copy a
# device could put any name or address it liked into its own certificate,
# and a broker that matched on a SAN would believe it. That is the hole
# this line closes, and the test asserts it in those terms.

[ policy_cn ]
commonName = supplied

[ req ]
distinguished_name = req_dn
prompt             = no

[ req_dn ]
CN = placeholder

[ server_ext ]
basicConstraints       = critical,CA:FALSE
keyUsage               = critical,digitalSignature,keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName         = \$ENV::BENCH_SAN

[ client_ext ]
basicConstraints       = critical,CA:FALSE
keyUsage               = critical,digitalSignature
extendedKeyUsage       = clientAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer

# serverAuth and clientAuth are separate, and that is the point rather than
# tidiness. A certificate carrying both lets any client that holds one
# impersonate the broker to every other client, which turns one stolen
# device into a machine that can collect the whole bench's traffic.
CONFIG
}

cmd_init() {
	[ ! -f "$PKI_DIR/ca.crt" ] ||
		die "a CA already exists at $PKI_DIR/ca.crt.
       Remove it by hand if you mean to replace it.
       Every certificate it issued stops verifying the moment it is gone."

	mkdir -p "$PKI_DIR/private" "$PKI_DIR/newcerts" "$PKI_DIR/issued"
	chmod 700 "$PKI_DIR/private"
	: >"$PKI_DIR/index.txt"
	echo 1000 >"$PKI_DIR/serial"
	echo 1000 >"$PKI_DIR/crlnumber"
	write_config

	openssl ecparam -name prime256v1 -genkey -noout \
		-out "$PKI_DIR/private/ca.key"
	chmod 600 "$PKI_DIR/private/ca.key"

	openssl req -x509 -new -key "$PKI_DIR/private/ca.key" \
		-sha256 -days "$CA_DAYS" -subj "/CN=bench-ca" \
		-addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
		-addext "keyUsage=critical,keyCertSign,cRLSign" \
		-out "$PKI_DIR/ca.crt"

	cmd_gencrl
	echo "bench-pki: CA at $PKI_DIR/ca.crt, valid $CA_DAYS days"
	echo "bench-pki: the private key is $PKI_DIR/private/ca.key and stays here"
}

require_ca() {
	[ -f "$PKI_DIR/ca.crt" ] ||
		die "no CA at $PKI_DIR. Run: bench-pki.sh init"
}

issue() {
	_cn=$1
	_ext=$2
	require_ca
	case "$_cn" in
	*/* | *..* | "")
		die "refusing the common name '$_cn': it becomes a filename"
		;;
	esac

	openssl ecparam -name prime256v1 -genkey -noout \
		-out "$PKI_DIR/issued/$_cn.key"
	chmod 600 "$PKI_DIR/issued/$_cn.key"
	openssl req -new -key "$PKI_DIR/issued/$_cn.key" \
		-subj "/CN=$_cn" -out "$PKI_DIR/issued/$_cn.csr"
	# openssl's own message is kept and printed. The first draft sent it to
	# /dev/null and died with "openssl ca refused to issue", which is a
	# refusal that names nothing: when the CRL step failed the same way, the
	# cause was a path inside the configuration file and the message said
	# none of that. A guard that cannot be argued with gets switched off.
	if ! _err=$(openssl ca -config "$PKI_DIR/openssl.cnf" -batch \
		-extensions "$_ext" -days "$LEAF_DAYS" \
		-in "$PKI_DIR/issued/$_cn.csr" \
		-out "$PKI_DIR/issued/$_cn.crt" 2>&1); then
		die "openssl ca refused to issue for '$_cn':
$_err"
	fi
	rm -f "$PKI_DIR/issued/$_cn.csr"
}

cmd_server() {
	[ $# -eq 2 ] || die "usage: bench-pki.sh server CN ADDRESS"
	_cn=$1
	_addr=$2
	# An IP address goes in as IP: and a name as DNS:, and getting this
	# wrong produces a certificate that looks right and fails to verify.
	# There is no DNS on this network, so IP is the ordinary case here.
	case "$_addr" in
	[0-9]*.[0-9]*.[0-9]*.[0-9]*) BENCH_SAN="IP:$_addr" ;;
	*) BENCH_SAN="DNS:$_addr" ;;
	esac
	export BENCH_SAN
	issue "$_cn" server_ext
	echo "bench-pki: issued $PKI_DIR/issued/$_cn.crt with $BENCH_SAN"
	echo "bench-pki: copy that and $_cn.key to the board; nothing else"
}

cmd_client() {
	[ $# -eq 1 ] || die "usage: bench-pki.sh client CN"
	# The server extension section references $ENV::BENCH_SAN, and openssl
	# reads the whole configuration file even when it is using a different
	# section, so the variable has to exist or the parse fails with a
	# message about an undefined variable that says nothing about clients.
	BENCH_SAN="DNS:unused"
	export BENCH_SAN
	issue "$1" client_ext
	echo "bench-pki: issued $PKI_DIR/issued/$1.crt for clientAuth"
}

cmd_gencrl() {
	BENCH_SAN=${BENCH_SAN:-DNS:unused}
	export BENCH_SAN
	if ! _err=$(openssl ca -config "$PKI_DIR/openssl.cnf" -gencrl \
		-out "$PKI_DIR/bench-ca.crl" 2>&1); then
		die "could not generate the CRL:
$_err"
	fi
}

cmd_revoke() {
	[ $# -eq 1 ] || die "usage: bench-pki.sh revoke CN"
	require_ca
	_crt=$PKI_DIR/issued/$1.crt
	[ -f "$_crt" ] || die "no certificate for '$1' at $_crt"
	BENCH_SAN=${BENCH_SAN:-DNS:unused}
	export BENCH_SAN
	if ! _err=$(openssl ca -config "$PKI_DIR/openssl.cnf" -revoke "$_crt" \
		2>&1); then
		die "could not revoke '$1':
$_err"
	fi
	cmd_gencrl
	echo "bench-pki: revoked $1 and regenerated the CRL"
	echo "bench-pki: the broker rereads crlfile on restart, so restart it"
}

cmd_verify() {
	[ $# -eq 1 ] || die "usage: bench-pki.sh verify CN"
	require_ca
	_crt=$PKI_DIR/issued/$1.crt
	[ -f "$_crt" ] || die "no certificate for '$1' at $_crt"
	[ -f "$PKI_DIR/bench-ca.crl" ] || cmd_gencrl
	# -crl_check is the whole point. Without it a revoked certificate
	# verifies perfectly, which is what makes revocation the criterion most
	# likely to be believed without ever being tested.
	openssl verify -CAfile "$PKI_DIR/ca.crt" \
		-crl_check -CRLfile "$PKI_DIR/bench-ca.crl" "$_crt"
}

# Copy exactly what the board needs onto the card, and nothing else.
#
# THE MISTAKE THIS EXISTS TO PREVENT IS COPYING private/ca.key.
#
# Everything in this directory looks alike: four files with similar names,
# one of which is the key that signs every identity on the bench. A
# wildcard copy, or a hurried one at the end of a session, puts it on a FAT
# partition that anybody who picks up the card can read. A CA key that has
# left the laptop is not recoverable by deleting it; every certificate it
# ever signed has to be reissued.
#
# So the file list here is explicit rather than a glob, and the board side
# refuses to start if it finds a CA key anyway. Two guards on the same
# mistake, at both ends, because this one cannot be undone.
cmd_deploy() {
	[ $# -eq 2 ] || die "usage: bench-pki.sh deploy CN DIR
       CN is the broker's certificate, usually bench-ap.
       DIR is the pki directory on the card's boot partition."
	require_ca
	_cn=$1
	_dst=$2
	[ -f "$PKI_DIR/issued/$_cn.crt" ] ||
		die "no certificate for '$_cn'. Issue one first:
       bench-pki.sh server $_cn 10.18.0.1"
	[ -f "$PKI_DIR/bench-ca.crl" ] || cmd_gencrl

	mkdir -p "$_dst"
	# Named one at a time. A loop over issued/* would carry every client
	# certificate onto the card as well, and a client key on the broker is
	# an identity two machines can present.
	cp "$PKI_DIR/ca.crt" "$_dst/ca.crt"
	cp "$PKI_DIR/bench-ca.crl" "$_dst/bench-ca.crl"
	cp "$PKI_DIR/issued/$_cn.crt" "$_dst/bench-ap.crt"
	cp "$PKI_DIR/issued/$_cn.key" "$_dst/bench-ap.key"
	chmod 600 "$_dst/bench-ap.key" 2>/dev/null || true

	# Checked after the copy rather than trusted beforehand, because the
	# destination is a directory somebody may have put things in.
	if [ -e "$_dst/ca.key" ] || [ -e "$_dst/private" ]; then
		echo "bench-pki: STOP. There is a CA private key in $_dst." >&2
		echo "  Whatever put it there, it must not go on a card." >&2
		echo "  Remove it before the card leaves the reader." >&2
		exit 3
	fi

	echo "bench-pki: copied four files to $_dst"
	echo "  ca.crt         the only thing the broker will trust"
	echo "  bench-ca.crl   revocations, read at broker startup"
	echo "  bench-ap.crt   the broker's own certificate"
	echo "  bench-ap.key   its private key, mode 600"
	echo "bench-pki: the CA private key stays at $PKI_DIR/private/ca.key"
}

cmd_list() {
	require_ca
	[ -s "$PKI_DIR/index.txt" ] || { echo "nothing issued yet"; return 0; }
	# awk with -F tab, and not a `while IFS=... read` loop, which is what
	# this was first and which printed an empty name for every valid row.
	# The CA database puts the revocation date in field three and leaves it
	# empty for a certificate that is still valid, so a valid row has two
	# tabs together. IFS treats a run of whitespace characters as one
	# delimiter, and a tab is a whitespace character, so the empty field
	# vanished and every column after it shifted left by one. The row still
	# looked plausible, which is the problem: it printed a state and a date
	# and simply lost the name.
	echo "state    expires     common name"
	awk -F'\t' '
		$1 == "V" { s = "valid  " }
		$1 == "R" { s = "REVOKED" }
		$1 == "E" { s = "expired" }
		$1 != "V" && $1 != "R" && $1 != "E" { next }
		{
			cn = $6
			sub(/^.*\/CN=/, "", cn)
			sub(/\/.*$/, "", cn)
			# ASN.1 UTCTime, YYMMDDHHMMSSZ, which sorts but does not read.
			y = substr($2, 1, 2) + 0
			printf "%s  %04d-%s-%s  %s\n", s, (y < 50 ? 2000 + y : 1900 + y),
				substr($2, 3, 2), substr($2, 5, 2), cn
		}
	' "$PKI_DIR/index.txt"
	# Named so the reader knows what was not consulted: this is the CA's
	# own database, not the files in issued/, so a certificate deleted from
	# disk still shows here and that is correct. Revocation is a statement
	# by the CA, not the absence of a file.
	echo
	echo "(from the CA database; deleting a file does not revoke anything)"
}

# The clock rule, which is the subtlest thing in this project.
#
# The board has no battery-backed real-time clock and no uplink, so at boot
# systemd moves the clock forward to roughly the image build time and no
# further. If the CA's notBefore is later than that, every certificate on
# the bench is "not yet valid", every client fails, and the error names the
# certificate rather than the clock.
#
# So: the CA must be created before the image is built. This checks it, and
# it needs no board.
cmd_clock_rule() {
	[ $# -eq 1 ] ||
		die "usage: bench-pki.sh clock-rule IMAGE_BUILD_STAMP
       where the stamp is the contents of /etc/timestamp from the image,
       as YYYYMMDDHHMMSS, or any date(1) can parse"
	require_ca
	_stamp=$1
	_not_before=$(openssl x509 -in "$PKI_DIR/ca.crt" -noout -startdate |
		sed 's/^notBefore=//')

	_ca_epoch=$(date -u -d "$_not_before" +%s 2>/dev/null) ||
		die "could not parse the CA notBefore: $_not_before"
	case "$_stamp" in
	[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
		# /etc/timestamp's own format, which date(1) will not take as is.
		_p=$(echo "$_stamp" | sed 's/\(....\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/')
		;;
	*) _p=$_stamp ;;
	esac
	_img_epoch=$(date -u -d "$_p" +%s 2>/dev/null) ||
		die "could not parse the image stamp: $_stamp"

	if [ "$_ca_epoch" -lt "$_img_epoch" ]; then
		echo "clock rule holds"
		echo "  CA notBefore  $_not_before"
		echo "  image built   $_p UTC"
		return 0
	fi
	echo "CLOCK RULE BROKEN: the CA is newer than the image." >&2
	echo "  CA notBefore  $_not_before" >&2
	echo "  image built   $_p UTC" >&2
	echo "On a board with no RTC and no uplink the clock comes up at about" >&2
	echo "the image build time, which is before this CA exists, so every" >&2
	echo "certificate reads as not yet valid and every client fails with" >&2
	echo "an error about the certificate rather than about the clock." >&2
	echo "Rebuild the image, or reissue the CA with an earlier notBefore." >&2
	return 1
}

need_openssl
case "${1:-}" in
init | server | client | revoke | verify | list | clock-rule | gencrl | deploy)
	# Checked twice, and the first one is the one that was missing.
	#
	# The first draft resolved the path with `cd`, which needs the
	# directory to exist, so it created it and then refused. Pointed at a
	# path inside the checkout it made exactly the directory it exists to
	# prevent, printed a correct refusal, and left the thing behind. A
	# guard with a side effect is not a guard.
	#
	# So: once on the path as written, before anything is created, and
	# again after resolution, because the first check reads the path
	# literally and a symlink outside the tree can point into it.
	# An absolute path in either convention. The first version tested only
	# for a leading slash, which made every Windows absolute path look
	# relative: BENCH_PKI_DIR=C:\Users\...\Temp\pki became
	# $PWD/C:\Users\...\Temp\pki, which is inside the checkout, and the
	# guard refused a perfectly good directory.
	#
	# It refused with both paths printed, which is the only reason it took
	# seconds rather than an argument to see. A guard that fires wrongly
	# and cannot say why is one people learn to switch off.
	case "$PKI_DIR" in
	/* | [A-Za-z]:[/\\]*) refuse_inside_repo "$PKI_DIR" ;;
	*) refuse_inside_repo "$PWD/$PKI_DIR" ;;
	esac
	mkdir -p "$PKI_DIR"
	PKI_DIR=$(CDPATH='' cd -- "$PKI_DIR" && pwd)
	refuse_inside_repo "$PKI_DIR"
	;;
esac

case "${1:-}" in
init)       cmd_init ;;
server)     shift; cmd_server "$@" ;;
client)     shift; cmd_client "$@" ;;
revoke)     shift; cmd_revoke "$@" ;;
verify)     shift; cmd_verify "$@" ;;
gencrl)     cmd_gencrl ;;
list)       cmd_list ;;
clock-rule) shift; cmd_clock_rule "$@" ;;
deploy)     shift; cmd_deploy "$@" ;;
*)
	sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
	;;
esac
