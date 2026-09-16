#!/bin/sh
#
# archive.sh - keep a flashable copy of a built image, with its provenance.
#
#   scripts/archive.sh [CFG]      save the newest image built for CFG
#   scripts/archive.sh available  what the build tree still holds
#   scripts/archive.sh list       what the store already holds
#
#   BENCH_IMAGE=/path/to.wic.bz2 scripts/archive.sh CFG   save that one
#
# Why this exists. A build is one to three hours and the build tree is
# disposable by design: ./go clean deletes it, and so does anything that
# reclaims disk. Losing the tree costs nothing except the ability to put
# that exact image back on a card without paying the hours again.
#
# Why the provenance file is not optional. An image on its own is a mystery
# card: it boots, and nothing about it says which commit produced it, which
# layer revisions were pinned, or which board it is for. The same repository
# refuses to build without pinned layers for the same reason, and an
# archived artefact with no record of its inputs is the same defect one
# stage later.
#
# The store lives outside the repository, next to the caches, because these
# are build outputs and nothing BitBake writes belongs in git. It survives
# ./go clean, which deletes only the build tree.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

STORE=${BENCH_IMAGE_DIR:-$BENCH_WORK/images}
DEPLOY=$KAS_BUILD_DIR/tmp/deploy/images

# Every image the build tree still holds, newest first. This is the rescue
# list: after a build for two machines, or several builds over days, the
# deploy directory holds more than the one image the last build produced.
available() {
	[ -d "$DEPLOY" ] || die "no build tree at $DEPLOY. Nothing to archive."
	found=$(find "$DEPLOY" -name '*.wic.bz2' -printf '%T@ %p\n' 2>/dev/null |
		sort -rn | cut -d' ' -f2-)
	[ -n "$found" ] || die "no .wic.bz2 under $DEPLOY."
	printf '%s\n' "$found" | while read -r path; do
		printf '  %s  %6s  %s\n' \
			"$(date -r "$path" '+%Y-%m-%d %H:%M')" \
			"$(du -h "$path" | cut -f1)" \
			"${path#"$DEPLOY"/}"
	done
}

# What has already been saved. Printed with the machine and the commit,
# because those are the two facts that decide whether a stored image is the
# one you want on the card in front of you.
list_store() {
	[ -d "$STORE" ] || die "nothing archived yet. Store would be $STORE."
	found=$(find "$STORE" -name 'PROVENANCE.txt' | sort)
	[ -n "$found" ] || die "nothing archived yet under $STORE."
	printf '%s\n' "$found" | while read -r prov; do
		dir=$(dirname "$prov")
		machine=$(sed -n 's/^machine  *//p' "$prov" | head -1)
		commit=$(sed -n 's/^commit  *//p' "$prov" | head -1)
		size=$(du -sh "$dir" | cut -f1)
		printf '  %-46s %-18s %-12s %s\n' \
			"${dir#"$STORE"/}" "$machine" "$commit" "$size"
	done
}

# The machine a configuration builds for, following includes, because
# bench-dev.yml overrides only the target and inherits the machine from the
# file it includes. Guessing instead would defeat the point of the check
# below.
kas_machine() {
	_file=$1
	_depth=0
	while [ "$_depth" -lt 5 ]; do
		_m=$(sed -n 's/^machine:[[:space:]]*//p' "$_file" | head -1)
		if [ -n "$_m" ]; then
			printf '%s\n' "$_m"
			return 0
		fi
		_inc=$(sed -n 's|^[[:space:]]*-[[:space:]]*\(.*\.yml\)$|\1|p' \
			"$_file" | head -1)
		[ -n "$_inc" ] || return 0
		_file=$REPO_DIR/kas/$(basename "$_inc")
		[ -f "$_file" ] || return 0
		_depth=$(( _depth + 1 ))
	done
}

# The companion file for an image, under either of the two names the same
# artefact has in deploy/images. Prints nothing when neither exists, which
# the caller reports rather than treating as fatal: an image without its
# bmap is still worth keeping.
sibling() {
	_link=$1
	_real=$2
	_suffix=$3
	for _base in "${_real%.wic.bz2}" "${_link%.wic.bz2}"; do
		if [ -f "$_base$_suffix" ]; then
			printf '%s\n' "$_base$_suffix"
			return 0
		fi
	done
}

save() {
	config=$1
	kasfile=$REPO_DIR/kas/$config.yml
	[ -f "$kasfile" ] || die "no such configuration: kas/$config.yml"
	[ -d "$DEPLOY" ] || die "no build tree at $DEPLOY. Build first."

	if [ -n "${BENCH_IMAGE:-}" ]; then
		image=$BENCH_IMAGE
		[ -f "$image" ] || die "BENCH_IMAGE is not a file: $image"
	else
		image=$(find "$DEPLOY" -name '*.wic.bz2' -printf '%T@ %p\n' \
			2>/dev/null | newest_path image)
		[ -n "$image" ] || die "no .wic.bz2 under $DEPLOY. Build first."
	fi

	# The machine is taken from the path rather than from the filename,
	# because deploy/images holds one directory per MACHINE and that
	# directory is the only part of the layout Yocto guarantees. An image
	# named explicitly may sit outside the build tree, in which case its
	# parent directory is the best available answer.
	case $image in
	"$DEPLOY"/*)
		rel=${image#"$DEPLOY"/}
		machine=${rel%%/*}
		;;
	*)
		machine=$(basename "$(dirname "$image")")
		;;
	esac

	# Refusing here is the whole reason this check exists. "Newest wins"
	# is right immediately after a build and wrong the moment you archive
	# under a configuration you did not just build: it would file a Pi 4
	# image under bench-rpi3, and the next person to flash it gets a dark
	# board that reads as dead hardware.
	want=$(kas_machine "$kasfile")
	if [ -n "$want" ] && [ "$want" != "$machine" ]; then
		die "kas/$config.yml builds $want, but the newest image is $machine.
       Build that configuration first, or name the file explicitly:
       BENCH_IMAGE=<path> scripts/archive.sh $config"
	fi

	commit=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
	dirty=
	if [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
		dirty=-dirty
	fi
	stamp=$(date '+%Y-%m-%d')_$commit$dirty
	dest=$STORE/$config/$stamp

	# deploy/images offers each artefact under two names: the real
	# bench-image-<machine>.rootfs-<timestamp>.wic.bz2 and a short
	# symlink to it. Either can be the one the search returned, so the
	# .bmap and .manifest are looked for under both bases rather than
	# derived from whichever name happened to win.
	#
	# Found by tests/archive-test.sh on its first run, which is the
	# argument for a fixture shaped like the real deploy tree instead of
	# like the happy path. A missing .bmap is not a broken archive, it is
	# a card written in full instead of in its used blocks and a lost
	# package list, which is the kind of defect nobody notices until the
	# tree it came from is gone.
	real=$(readlink -f "$image" 2>/dev/null || echo "$image")
	bmap=$(sibling "$image" "$real" .wic.bmap)
	manifest=$(sibling "$image" "$real" .manifest)

	mkdir -p "$dest"
	note "image   $image"
	note "store   $dest"

	# -L because the useful names in deploy/images are symlinks to the
	# timestamped real files, and a symlink into a build tree that is
	# about to be deleted archives nothing at all.
	cp -L "$image" "$dest/"
	# Written as if/else rather than "test && cp || note", which is not
	# an if/else: when the copy itself fails the note runs and the exit
	# status is the note's. Shellcheck calls this SC2015 and it has
	# already cost this repository a CI run.
	if [ -f "$bmap" ]; then
		cp -L "$bmap" "$dest/"
	else
		note "no .bmap beside the image, the whole card will be written"
	fi
	if [ -f "$manifest" ]; then
		cp -L "$manifest" "$dest/"
	else
		note "no .manifest beside the image"
	fi

	# The locked layer revisions, which are what make the image
	# rebuildable rather than merely re-flashable. Absent kas is not a
	# failure: the image is still worth keeping, and the file says so.
	if command -v kas >/dev/null 2>&1; then
		kas dump --lock "$kasfile" >"$dest/$config.lock.yml" 2>/dev/null ||
			note "kas dump --lock failed, layer revisions not recorded"
	else
		note "kas absent, layer revisions not recorded"
	fi

	write_provenance "$dest" "$config" "$machine" "$image" "$commit" "$dirty"

	note "archived $(du -sh "$dest" | cut -f1)"
	note "flash it with: ./go flash /dev/sdX $dest/$(basename "$image")"
}

write_provenance() {
	dest=$1
	config=$2
	machine=$3
	image=$4
	commit=$5
	dirty=$6

	{
		echo "Archived image, embedded-linux-bench"
		echo "===================================="
		echo
		echo "What this is: a flashable copy of one built image, kept so"
		echo "that the board can be put back to this exact state without"
		echo "repeating the build."
		echo
		printf 'archived  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
		printf 'config    kas/%s.yml\n' "$config"
		printf 'machine   %s\n' "$machine"
		printf 'commit    %s\n' "$commit"
		if [ -n "$dirty" ]; then
			echo
			echo "WARNING: the working tree had uncommitted changes when"
			echo "this was built, so no commit describes it exactly. The"
			echo "diff below is what differed from $commit."
			echo
			git -C "$REPO_DIR" status --short 2>/dev/null | sed 's/^/    /'
			echo
		fi
		printf 'built by  %s\n' "$(uname -srm)"
		echo
		echo "Files"
		echo "-----"
		for f in "$dest"/*; do
			[ -f "$f" ] || continue
			case $f in
			*/PROVENANCE.txt) continue ;;
			esac
			printf '  %-52s %s\n' "$(basename "$f")" \
				"$(du -h "$f" | cut -f1)"
		done
		echo
		echo "sha256"
		echo "------"
		for f in "$dest"/*.wic.bz2 "$dest"/*.bmap; do
			[ -f "$f" ] || continue
			printf '  %s  %s\n' \
				"$(sha256sum "$f" | cut -d' ' -f1)" \
				"$(basename "$f")"
		done
		echo
		echo "To flash"
		echo "--------"
		echo
		printf '  ./go flash /dev/sdX %s\n' \
			"$dest/$(basename "$image")"
		echo
		echo "The .bmap beside it is what lets bmaptool skip the empty"
		echo "blocks. Without it the whole card is written instead."
		echo
		echo "To rebuild instead of re-flashing"
		echo "---------------------------------"
		echo
		printf '  git checkout %s\n' "$commit"
		printf '  kas build kas/%s.lock.yml\n' "$config"
		echo
		echo "The lock file beside this one pins every layer to the commit"
		echo "that was actually built, which a branch name does not."
	} >"$dest/PROVENANCE.txt"
}

case "${1:-}" in
available) available ;;
list) list_store ;;
"") save bench-rpi4 ;;
*) save "$1" ;;
esac
