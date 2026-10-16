#!/bin/sh
#
# credentials-set.sh - type the network key once, on the build laptop.
#
#   ./go credentials            the wireless network
#   ./go credentials wifi       the same thing, said explicitly
#   ./go credentials show       what is stored, masked
#
# The file it writes is what scripts/credentials.sh copies onto every
# card at flash time, which is why this is typed once rather than after
# every flash. It lives outside the repository and outside every image:
#
#   $BENCH_CREDENTIALS, or $BENCH_WORK/credentials, or ~/bench/credentials
#
# NOTHING IS ECHOED AND NOTHING IS PRINTED
#
# The passphrase is read with the terminal's echo turned off, is never
# written anywhere, and is not what goes in the file: the file gets the
# 64 character key derived from it, which is the form the supplicant
# configuration wants unquoted. The confirmation prints "SSID=<set>" and
# "PSK=<set>" so that a terminal recording, a screenshot or a pasted
# session carries no secret.
#
# SPDX-License-Identifier: MIT

set -eu

store=${BENCH_CREDENTIALS:-${BENCH_WORK:-$HOME/bench}/credentials}
what=${1:-wifi}

mask() {
	sed 's/=.*/=<set>/' "$1"
}

case $what in
show)
	if [ -d "$store" ] && [ -n "$(ls -A "$store" 2>/dev/null)" ]; then
		for f in "$store"/*; do
			echo "--- $f"
			mask "$f" | sed 's/^/    /'
		done
	else
		echo "nothing stored in $store"
	fi
	exit 0
	;;
wifi) file=wifi.conf ;;
*)
	echo "usage: ./go credentials [wifi|show]" >&2
	echo "" >&2
	echo "router.conf has more fields than this prompts for and is" >&2
	echo "written by hand into $store for now." >&2
	exit 2
	;;
esac

[ -t 0 ] || {
	echo "credentials-set: this prompts, so it needs a terminal." >&2
	exit 2
}

mkdir -p "$store"
chmod 700 "$store"

printf 'network name (SSID): '
read -r ssid
[ -n "$ssid" ] || { echo "credentials-set: no SSID given." >&2; exit 1; }

printf 'passphrase (not echoed): '
# The trap matters: without it a Ctrl-C at the prompt leaves the
# terminal with echo off, and the next thing typed into that shell is
# invisible, which looks like a hung terminal rather than a cancelled
# command.
stty_state=$(stty -g)
trap 'stty "$stty_state"; echo; exit 1' INT TERM
stty -echo
read -r secret
stty "$stty_state"
trap - INT TERM
echo

[ -n "$secret" ] || { echo "credentials-set: no passphrase given." >&2; exit 1; }

umask 077

# wpa_passphrase is the obvious tool and is not on every build host; the
# derivation is PBKDF2 with HMAC-SHA1, 4096 rounds, the network name as
# the salt, which is one line of Python and gives the same 64 characters.
if command -v wpa_passphrase >/dev/null 2>&1; then
	psk=$(wpa_passphrase "$ssid" "$secret" |
		sed -n 's/^[[:space:]]*psk=\([0-9a-f]\{64\}\)$/\1/p')
else
	psk=$(python3 -c "import hashlib,sys;print(hashlib.pbkdf2_hmac('sha1',sys.argv[2].encode(),sys.argv[1].encode(),4096,32).hex())" \
		"$ssid" "$secret")
fi

[ -n "$psk" ] || {
	echo "credentials-set: the key derivation produced nothing." >&2
	echo "       A passphrase shorter than 8 characters is the usual" >&2
	echo "       reason; wpa_passphrase refuses those." >&2
	exit 1
}

{
	printf 'SSID=%s\n' "$ssid"
	printf 'PSK=%s\n' "$psk"
} >"$store/$file"
chmod 600 "$store/$file"

echo "--- stored $store/$file"
mask "$store/$file" | sed 's/^/    /'
echo "--- every ./go flash from now on copies it onto the card"
