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
	found=$(find "$DEPLOY" -name '*.wic.bz2' -type f -printf '%T@ %p\n' 2>/dev/null |
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
		# Entries archived before the store carried project numbers have
		# no project line. Printed as a dash rather than omitted, so the
		# column stays aligned and the gap is visible rather than
		# looking like the project is zero.
		project=$(sed -n 's/^project  *\([0-9]*\).*/\1/p' "$prov" | head -1)
		size=$(du -sh "$dir" | cut -f1)
		printf '  %-4s %-46s %-18s %-12s %s\n' \
			"${project:--}" "${dir#"$STORE"/}" "$machine" "$commit" "$size"
	done
}

# The project a configuration belongs to, as a zero-padded number.
#
# "bench-rt" does not say "Project 8" to anybody reading a folder in a
# year, and the store is meant to be readable long after the build tree it
# came from is gone. Every project-specific kas file already states it in
# its opening line, so this reads that rather than introducing a second
# place for the same fact to be wrong.
#
# DELIBERATELY DOES NOT FOLLOW INCLUDES, unlike kas_machine and kas_target.
# bench-rt.yml includes bench-rpi4.yml, which is the shared base rather
# than a project; following the chain would find whatever the base happened
# to mention and label every image with it. A configuration that names no
# project has none, and the four that do are bench-rpi4, bench-dev,
# bench-rpi3 and bench-release, which build the base image and its variants
# rather than any one project's.
kas_project() {
	_n=$(sed -n '1,10p' "$1" | grep -o 'Project [0-9]\{1,2\}' | head -1 |
		sed 's/Project //')
	[ -n "$_n" ] || return 0
	printf '%02d\n' "$_n"
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

# The image a configuration builds, following includes for the same reason
# kas_machine does: bench-rt-generic.yml sets only a local_conf_header and
# inherits its target from bench-rt.yml.
#
# One consequence worth knowing. bench-rt and bench-rt-generic resolve to
# the SAME target, bench-rt-image, because the control differs from the
# variable in one kernel symbol rather than in the image. So their output
# files are named identically and the second build overwrites the first in
# deploy/images. The target check below cannot tell them apart and does not
# try; what keeps them apart is the store, which is one directory per
# configuration, and the operator naming the file with BENCH_IMAGE when
# both have been built.
kas_target() {
	_file=$1
	_depth=0
	while [ "$_depth" -lt 5 ]; do
		_t=$(sed -n 's/^target:[[:space:]]*//p' "$_file" | head -1)
		if [ -n "$_t" ]; then
			printf '%s\n' "$_t"
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
	kasfile=$(resolve_kas_config "$config")
	config=$(basename "$kasfile" .yml)
	[ -d "$DEPLOY" ] || die "no build tree at $DEPLOY. Build first."

	if [ -n "${BENCH_IMAGE:-}" ]; then
		image=$BENCH_IMAGE
		[ -f "$image" ] || die "BENCH_IMAGE is not a file: $image"
	else
		image=$(find "$DEPLOY" -name '*.wic.bz2' -type f -printf '%T@ %p\n' \
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

	# And the same question about the target, which the machine check
	# cannot answer.
	#
	# deploy/images holds one directory per machine and every image for
	# that machine inside it. So after building bench-rt and then wanting
	# to archive the router image, "newest wins" returns bench-rt-image,
	# the machine matches, the check above passes, and an RT image is
	# filed under bench-router. It would flash, it would boot, and it
	# would be the wrong system entirely: a card labelled "LTE router"
	# carrying a real-time kernel and no ModemManager.
	#
	# That is worse than the wrong-board case it sits beneath. A wrong
	# board does not boot and the symptom is immediate. A wrong target
	# boots fine and the mislabelling is only discovered by whoever
	# trusted the label.
	#
	# Matched against "<target>-<machine>.rootfs" rather than just the
	# target, because bench-image is a prefix of bench-image-dev and a
	# prefix match would file a dev image under the production
	# configuration.
	# Against BOTH names the artefact has, because the short one is a
	# symlink written after the file it points at and therefore usually
	# wins newest-by-mtime:
	#
	#   bench-image-raspberrypi4-64.rootfs-20260916.wic.bz2   the real file
	#   bench-image-raspberrypi4-64.wic.bz2                   the symlink
	#
	# A first version of this check keyed on ".rootfs" being present and
	# skipped everything else as "not a Yocto name". The symlink has no
	# .rootfs in it, so the check quietly did nothing in the exact case it
	# was written for. tests/archive-test.sh found that on its first run,
	# which is the second time this file has been saved by a fixture
	# shaped like the real deploy tree rather than like the happy path.
	want_target=$(kas_target "$kasfile")
	real=$(readlink -f "$image" 2>/dev/null || echo "$image")
	if [ -n "$want_target" ]; then
		matched=no
		checked=no
		for candidate in "$(basename "$image")" "$(basename "$real")"; do
			case $candidate in
			*.wic.bz2) checked=yes ;;
			*) continue ;;
			esac
			case $candidate in
			"$want_target-$machine".rootfs*.wic.bz2) matched=yes ;;
			"$want_target-$machine".wic.bz2) matched=yes ;;
			esac
		done
		if [ "$checked" = no ]; then
			# A file named by hand from outside the build tree need not
			# follow the Yocto convention, and refusing something the
			# operator pointed at by name is second-guessing a deliberate
			# act. Say what was not checked instead.
			note "name is not <target>-<machine>[.rootfs].wic.bz2, target unchecked"
		elif [ "$matched" = no ]; then
			die "kas/$config.yml builds $want_target, but that image is
       $(basename "$real")

       Both are for $machine, so the board is right and the system is not.
       deploy/images holds every image ever built for a machine, and
       newest-wins returns the last one built rather than the one you asked
       for. That mistake flashes and boots, and only the label is wrong,
       which makes it worse than the wrong-board case.

       Name the one you meant:
       BENCH_IMAGE=<path> scripts/archive.sh $config
       scripts/archive.sh available   lists what the tree holds"
		fi
	fi

	commit=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
	dirty=
	if [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
		dirty=-dirty
	fi
	stamp=$(date '+%Y-%m-%d')_$commit$dirty
	# Named by project first, so the store sorts and reads as the twenty
	# projects do: proj08-bench-rt, proj15-bench-router.
	#
	# "proj" spelled out rather than a bare number, because "08-bench-rt"
	# reads as a date or a sequence position to anybody who does not
	# already know the convention, and this store is meant to be legible
	# long after the build tree is gone.
	#
	# A configuration with no project keeps its own name alone rather than
	# being given a number that would be a guess.
	project=$(kas_project "$kasfile")
	dest=$STORE/${project:+proj$project-}$config/$stamp

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
	# real was resolved above, for the target check.
	bmap=$(sibling "$image" "$real" .wic.bmap)
	manifest=$(sibling "$image" "$real" .manifest)

	# A SECOND IMAGE IN THE SAME DIRECTORY IS REFUSED, NAMING BOTH.
	#
	# The store path is <project>-<config>/<date>_<commit>[-dirty], and
	# that is not unique: two builds of the same configuration from the
	# same commit on the same day land here together. They differ only by
	# a build timestamp in the middle of the filename, and the second
	# archive REWRITES PROVENANCE.txt, so the first image is left present,
	# undescribed, and with no recorded sha256. Flashing the wrong one is
	# then a coin toss that nothing downstream can catch.
	#
	# It happened on 17 September: proj08-bench-rt/2026-09-17_63b179f
	# ended up holding both ...rootfs-20260917080243.wic.bz2 and
	# ...rootfs-20260917104455.wic.bz2 with one record between them.
	# The gap was written up in the skill before it bit; this is the guard
	# that was missing.
	#
	# Re-archiving the SAME image is allowed, because that is idempotent
	# and is what a repeated command should do.
	if [ -d "$dest" ]; then
		existing=$(find "$dest" -maxdepth 1 -name '*.wic.bz2' -type f \
			! -name "$(basename "$real")" -print 2>/dev/null | head -1)
		if [ -n "$existing" ]; then
			die "$dest already holds a different image:
       have  $(basename "$existing")
       new   $(basename "$real")
       Both are $config at $commit on the same day, so they share a
       store path and the second would overwrite PROVENANCE.txt and
       leave the first undescribed.
       Move the old one aside and archive again:
           mv $dest ${dest}-$(date '+%H%M')"
		fi
	fi

	mkdir -p "$dest"
	note "image   $image"
	note "store   $dest"

	# Everything is stored under ONE base name, the resolved real one.
	#
	# This used to copy each file under whatever basename it was found by,
	# and those differ. The image is usually found as the short symlink,
	# because the link is written last and therefore wins newest-by-mtime;
	# the .bmap is found by resolving that link first, so it arrives under
	# the timestamped name. The store then held:
	#
	#   bench-rt-image-raspberrypi4-64.rootfs.wic.bz2
	#   bench-rt-image-raspberrypi4-64.rootfs-20260916142705.wic.bmap
	#
	# flash.sh looks for ${image%.bz2}.bmap, which is not that. So it
	# printed "no bmap given, copy entire image" and wrote all 1.1 GiB
	# instead of the 274 MiB actually used: 1m 33s rather than 25s.
	#
	# Silent again. archive.sh reported success because both files
	# arrived, and flash.sh reported what it was doing in a line that
	# reads like information rather than like a fault.
	#
	# -L because the useful names in deploy/images are symlinks, and a
	# symlink into a build tree that is about to be deleted archives
	# nothing at all.
	base=$(basename "$real")
	cp -L "$image" "$dest/$base"
	# Written as if/else rather than "test && cp || note", which is not
	# an if/else: when the copy itself fails the note runs and the exit
	# status is the note's. Shellcheck calls this SC2015 and it has
	# already cost this repository a CI run.
	# Renamed onto the image's base, not copied under their own, so that
	# flash.sh's ${image%.bz2}.bmap finds it. See the note above.
	stem=${base%.wic.bz2}
	if [ -f "$bmap" ]; then
		cp -L "$bmap" "$dest/$stem.wic.bmap"
	else
		note "no .bmap beside the image, the whole card will be written"
	fi
	if [ -f "$manifest" ]; then
		cp -L "$manifest" "$dest/$stem.manifest"
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

	# "$real" and not "$image". The copy above stores the file under
	# basename "$real", the timestamped name, because cp -L follows the
	# symlink that deploy/images uses as its stable name. Passing "$image"
	# here made the "To flash" line in PROVENANCE.txt name the SYMLINK,
	# which is not what was archived and does not exist in the store: every
	# archive taken before 17 September prints a copy-and-paste flash
	# command for a file that is not there.
	write_provenance "$dest" "$config" "$machine" "$real" "$commit" "$dirty"

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
		if [ -n "$project" ]; then
			printf 'project   %s  (projects/%s-*)\n' "$project" "$project"
		fi
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
