#!/bin/sh
#
# archive-test.sh - scripts/archive.sh against a fake deploy tree.
#
# The whole point of archiving is that it is the last chance to keep an
# image before the build tree is deleted, so the failure modes matter more
# than usual: a copied symlink into a tree that is about to go, a Pi 4 image
# filed under a Pi 3 configuration, or a record that does not say which
# commit it came from. None of that needs Yocto to test. BENCH_WORK is an
# ordinary environment variable, so a directory of dummy files shaped like
# deploy/images exercises every path.
#
# SPDX-License-Identifier: MIT

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

ok() {
	pass=$(( pass + 1 ))
	echo "ok   $1"
}

no() {
	fail=$(( fail + 1 ))
	echo "FAIL $1"
}

check() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		no "$1"
		echo "       want: $3"
		echo "       got:  $2"
	fi
}

contains() {
	if grep -q "$3" "$2"; then
		ok "$1"
	else
		no "$1"
		echo "       $2 does not contain $3"
	fi
}

# A build tree shaped like the real one: one directory per machine, each
# artefact written under a timestamped name and offered again under a short
# symlink, which is what Yocto produces and the reason archive.sh resolves
# before deriving the companion names.
deploy=$tmp/work/build/tmp/deploy/images/raspberrypi4-64
stem=bench-image-raspberrypi4-64
mkdir -p "$deploy"
echo "image bytes" >"$deploy/$stem.rootfs-20260916.wic.bz2"
echo "bmap" >"$deploy/$stem.rootfs-20260916.wic.bmap"
echo "pkg 1.0" >"$deploy/$stem.rootfs-20260916.manifest"
for suffix in wic.bz2 wic.bmap manifest; do
	ln -s "$stem.rootfs-20260916.$suffix" "$deploy/$stem.$suffix"
done

# Git Bash on Windows makes copies for ln -s unless the host allows real
# symlinks, so say which of the two this run actually tested. The copy case
# is not a weaker fixture for anything except the dereference assertion
# below, which can only pass vacuously there.
if [ -L "$deploy/$stem.wic.bz2" ]; then
	symlinks=real
else
	symlinks=copies
	echo "note: ln -s produced copies on this host, so the dereference"
	echo "      assertion below passes without being exercised. CI and the"
	echo "      Yocto build host both make real symlinks."
fi

store=$tmp/store
run() {
	BENCH_WORK=$tmp/work BENCH_IMAGE_DIR=$store \
		sh "$repo/scripts/archive.sh" "$@" 2>&1
}

echo "== an image is archived with its bmap, manifest and record"
out=$(run bench-rpi4 || echo "EXIT-FAILED")
case $out in
*EXIT-FAILED*)
	no "archive succeeds"
	echo "$out" | sed 's/^/       /'
	;;
*) ok "archive succeeds" ;;
esac

dir=$(find "$store" -name PROVENANCE.txt -exec dirname {} \; | head -1)
if [ -n "$dir" ]; then
	ok "a store directory was created"
else
	no "a store directory was created"
	exit 1
fi

check "the configuration names the directory" \
	"$(basename "$(dirname "$dir")")" "bench-rpi4"

for f in wic.bz2 wic.bmap manifest; do
	if ls "$dir" | grep -q "$f\$"; then
		ok "the $f was copied"
	else
		no "the $f was copied"
	fi
done

echo "== a symlink is dereferenced, not copied as a link ($symlinks)"
# This is the failure that passes every visual inspection and archives
# nothing: a link into a build tree that ./go clean is about to delete.
link=$(find "$dir" -name '*.wic.bz2' -type l | head -1)
if [ -z "$link" ]; then
	ok "no symlinks in the store"
else
	no "no symlinks in the store"
fi
if [ "$symlinks" = real ]; then
	check "the content came with it" "$(cat "$dir/$stem.wic.bz2")" \
		"image bytes"
fi

echo "== the record says what it is"
prov=$dir/PROVENANCE.txt
contains "the machine is recorded" "$prov" "raspberrypi4-64"
contains "the configuration is recorded" "$prov" "kas/bench-rpi4.yml"
contains "the commit is recorded" "$prov" "^commit"
contains "a sha256 is recorded" "$prov" "[0-9a-f][0-9a-f][0-9a-f][0-9a-f]"
contains "it says how to flash it" "$prov" "go flash"
contains "it says how to rebuild it" "$prov" "git checkout"

echo "== the wrong board is refused, not filed"
# A Pi 4 image filed under bench-rpi3 is a card that does not boot and
# reads as dead hardware. Newest-wins is right after a build and wrong
# here, so the machine in the kas file has to agree with the one in the
# path.
out=$(run bench-rpi3 || true)
case $out in
*"builds raspberrypi3-64"*)
	ok "a machine mismatch is refused with both names"
	;;
*)
	no "a machine mismatch is refused with both names"
	echo "$out" | sed 's/^/       /'
	;;
esac

echo "== the machine is followed through an include"
# bench-dev.yml sets only a target and inherits the machine, so a naive
# read of that file finds no machine and would skip the check entirely.
out=$(run bench-dev || echo "EXIT-FAILED")
case $out in
*EXIT-FAILED*)
	no "an inherited machine still matches"
	echo "$out" | sed 's/^/       /'
	;;
*) ok "an inherited machine still matches" ;;
esac

echo "== an unknown configuration is refused"
out=$(run bench-nonesuch || true)
case $out in
*"no such configuration"*) ok "an unknown configuration is refused" ;;
*) no "an unknown configuration is refused" ;;
esac

echo "== listing"
out=$(run list || true)
case $out in
*bench-rpi4*raspberrypi4-64*) ok "list shows the config and the machine" ;;
*)
	no "list shows the config and the machine"
	echo "$out" | sed 's/^/       /'
	;;
esac

out=$(run available || true)
case $out in
*raspberrypi4-64*) ok "available shows what the build tree holds" ;;
*)
	no "available shows what the build tree holds"
	echo "$out" | sed 's/^/       /'
	;;
esac

echo "== an empty build tree is a clear refusal, not a traceback"
out=$(BENCH_WORK=$tmp/empty BENCH_IMAGE_DIR=$store \
	sh "$repo/scripts/archive.sh" bench-rpi4 2>&1 || true)
case $out in
*"no build tree"*) ok "a missing build tree is named" ;;
*)
	no "a missing build tree is named"
	echo "$out" | sed 's/^/       /'
	;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
