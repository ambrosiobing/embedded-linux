#!/bin/sh
#
# reproduce.sh - build the tagged commit a second time and diff the result.
#
#   scripts/reproduce.sh [ref]      default: the current HEAD
#
# The claim being tested is narrow and worth stating precisely: a clean
# build from the same commit produces the same package list. It does not
# claim bit-identical images; timestamps and build paths still differ, which
# is what buildhistory is for.
#
# The second build uses its own sstate cache so that it genuinely rebuilds,
# and shares the download directory so that it does not fetch 10 GB twice.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

ref=${1:-HEAD}
require_tool kas
require_tool git

first=$KAS_BUILD_DIR/buildhistory
[ -d "$first" ] || die "no buildhistory from the first build. Run ./go build."

second_work=$BENCH_WORK/reproduce
note "second build in $second_work (ref $ref)"
rm -rf "$second_work"
mkdir -p "$second_work"

git -C "$REPO_DIR" worktree list >/dev/null 2>&1 ||
	die "$REPO_DIR is not a git repository."
git clone --quiet --shared "$REPO_DIR" "$second_work/meta-bench"
git -C "$second_work/meta-bench" checkout --quiet "$ref"

(
	KAS_WORK_DIR=$second_work
	KAS_BUILD_DIR=$second_work/build
	export KAS_WORK_DIR KAS_BUILD_DIR
	# Share downloads, keep sstate separate so the rebuild is real.
	SSTATE_DIR=$second_work/sstate-cache
	DL_DIR=$BENCH_WORK/downloads
	export SSTATE_DIR DL_DIR
	kas build "$second_work/meta-bench/kas/bench-rpi4.yml"
)

a=$(find "$first" -name installed-package-names.txt | sort | head -1)
b=$(find "$second_work/build/buildhistory" -name installed-package-names.txt |
	sort | head -1)
[ -n "$a" ] && [ -n "$b" ] || die "no installed-package-names.txt to compare."

note "diffing $a against $b"
if diff -u "$a" "$b"; then
	note "identical package lists: the build reproduces."
else
	die "the package lists differ. Read the diff above before claiming
       reproducibility."
fi
