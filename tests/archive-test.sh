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

# A second image for the same machine, which is what deploy/images really
# looks like after more than one build. Deliberately older, so newest-wins
# still returns the one above and the tests that depend on that are
# unaffected; this one exists to be chosen by name.
devstem=bench-image-dev-raspberrypi4-64
echo "dev image bytes" >"$deploy/$devstem.rootfs-20260915.wic.bz2"
touch -d '2026-09-15 10:00:00' "$deploy/$devstem.rootfs-20260915.wic.bz2"
touch -d '2026-09-16 10:00:00' "$deploy/$stem.rootfs-20260916.wic.bz2"

store=$tmp/store
run() {
	BENCH_WORK=$tmp/work BENCH_IMAGE_DIR=$store \
		sh "$repo/scripts/archive.sh" "$@" 2>&1
}

# The same, with an image named explicitly rather than found. This is the
# escape hatch the refusals point at, so it needs to work.
run_named() {
	_img=$1
	shift
	BENCH_WORK=$tmp/work BENCH_IMAGE_DIR=$store BENCH_IMAGE=$_img \
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
	if [ -n "$(find "$dir" -maxdepth 1 -name "*.$f" -print 2>/dev/null)" ]; then
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

echo "== the wrong system is refused too, even on the right board"
# The case the machine check cannot see. deploy/images holds every image
# built for a machine, so after building bench-rt and then archiving under
# bench-router, newest-wins returns bench-rt-image, the machine matches,
# and an RT image is filed as an LTE router. It flashes, it boots, and it
# is the wrong system: the label is the only thing that was ever wrong.
#
# Worse than the wrong-board case above, which at least fails loudly by
# not booting.
out=$(run bench-router || true)
case $out in
*"builds bench-router-image"*)
	ok "a target mismatch is refused, naming both"
	;;
*)
	no "a target mismatch is refused, naming both"
	echo "$out" | sed 's/^/       /'
	;;
esac

case $out in
*BENCH_IMAGE=*) ok "and it says how to name the right one" ;;
*) no "and it says how to name the right one" ;;
esac

# The refusal must be about the target and not a machine complaint in
# disguise: bench-router builds for raspberrypi4-64, same as the fixture.
case $out in
*"builds raspberrypi"*)
	no "the refusal is about the target, not the machine"
	;;
*) ok "the refusal is about the target, not the machine" ;;
esac

echo "== a prefix of another target is not a match"
# bench-image is a prefix of bench-image-dev. Matching on the target alone
# would file the dev image under the production configuration, so the
# comparison includes the machine: <target>-<machine>.rootfs.
out=$(run_named "$deploy/$devstem.rootfs-20260915.wic.bz2" bench-rpi4 || true)
case $out in
*"builds bench-image"*)
	ok "a dev image is refused under the production configuration"
	;;
*)
	no "a dev image is refused under the production configuration"
	echo "$out" | sed 's/^/       /'
	;;
esac

echo "== the machine is followed through an include"
# bench-dev.yml sets only a target and inherits the machine, so a naive
# read of that file finds no machine and would skip the check entirely.
# Named explicitly, because the dev image is deliberately not the newest.
#
# This assertion used to run "run bench-dev" against the bench-image
# fixture and accept anything that was not a machine complaint. When the
# target check was added it began refusing, and the catch-all branch
# reported that refusal as a pass. A test whose failure branch is "some
# other error occurred" is not testing the thing it names.
out=$(run_named "$deploy/$devstem.rootfs-20260915.wic.bz2" bench-dev ||
	echo "EXIT-FAILED")
case $out in
*EXIT-FAILED*)
	no "an inherited machine still matches"
	echo "$out" | sed 's/^/       /'
	;;
*) ok "an inherited machine still matches" ;;
esac

# Not a glob in [ ], which does not expand: the store path carries a dated
# directory, so ask find. And assert the name, because "a file arrived" is
# the assertion that would have passed before any of this was checked.
stored=$(find "$store/bench-dev" -name "$devstem.rootfs-*.wic.bz2" 2>/dev/null)
if [ -n "$stored" ]; then
	ok "and the dev image itself was stored, under its own name"
else
	no "and the dev image itself was stored, under its own name"
	find "$store/bench-dev" -type f 2>/dev/null | sed 's/^/       /'
fi

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
