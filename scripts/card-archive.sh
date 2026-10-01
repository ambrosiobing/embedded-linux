#!/bin/sh
#
# card-archive.sh - keep a flashable copy of a microSD card, with provenance.
#
#   sudo scripts/card-archive.sh PROJECT /dev/sdX   image the card
#   sudo scripts/card-archive.sh PROJECT card.img   image a file instead
#   scripts/card-archive.sh list                    what the store holds
#   sudo scripts/card-archive.sh verify DIR /dev/sdX   compare one later
#
# WHY THIS IS A SECOND PROGRAM AND NOT A FLAG ON archive.sh.
#
# archive.sh keeps the OUTPUT OF A BUILD: a .wic.bz2 that BitBake wrote,
# with a .bmap, a .manifest and a kas lock file beside it, and a rebuild
# line that is one git checkout and one kas build. Everything it stores can
# be made again from a commit, so what it is really saving is the three
# hours.
#
# Project 10's card is none of that. It is Raspberry Pi OS written by
# Raspberry Pi Imager and then changed by hand on the board: four
# out-of-tree ST drivers compiled against a linux-source-6.18 tree unpacked
# into /usr/src, modules loaded by insmod rather than by any image recipe,
# programs copied into place, and measurements accumulating under
# /var/lib/bench. No commit in this repository describes it and no command
# here rebuilds it. That is exactly why the card itself has to be the
# artefact rather than a convenience: for this project the card IS the
# build output, and it exists in one copy, in one reader, on one bench.
#
# The store layout, the stamp and the PROVENANCE.txt fields deliberately
# match archive.sh, so the two kinds of artefact sort and read together.
# The directory carries a -card suffix because the two are RESTORED BY
# DIFFERENT TOOLS, and a stored artefact that does not say how to put it
# back is the defect this file exists to avoid.
#
# WHAT IT READS AND WHAT IT WRITES. It reads the source and writes nothing
# to it. The danger here is therefore not the card, it is naming the wrong
# source: /dev/sda on a laptop is usually the laptop. Every guard below is
# about that, and about the destination filling up halfway through a
# fifteen-minute read.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

STORE=${BENCH_IMAGE_DIR:-$BENCH_WORK/images}

# The largest source that is plausibly a card. A bench card is 8 to 64 GB;
# a laptop's system disk is 256 GB or more. This is the guard that stands
# between a mistyped letter and a 1 TB read, and it is a refusal rather
# than a warning because the operator who typed the wrong letter is not
# reading warnings.
MAX_GB=${BENCH_CARD_MAX_GB:-128}

IDENT_HOST=
IDENT_OS=
IDENT_KERNEL=
IDENT_MODULES=
CARD_LOOKS_RPI=no

# What has already been kept. The hostname column is read off the card at
# archive time, because a card image has no MACHINE: nothing built it.
list_store() {
	[ -d "$STORE" ] || die "nothing archived yet. Store would be $STORE."
	found=$(find "$STORE" -name 'PROVENANCE.txt' -path '*-card/*' | sort)
	[ -n "$found" ] || die "no card images under $STORE."
	printf '%s\n' "$found" | while read -r prov; do
		dir=$(dirname "$prov")
		host=$(sed -n 's/^hostname  *//p' "$prov" | head -1)
		commit=$(sed -n 's/^commit  *//p' "$prov" | head -1)
		size=$(du -sh "$dir" | cut -f1)
		printf '  %-44s %-16s %-12s %s\n' \
			"${dir#"$STORE"/}" "${host:--}" "$commit" "$size"
	done
}

# Partition N of a disk. mmcblk0 and nvme0n1 end in a digit and take a p,
# sdb does not. Getting this wrong names a device that does not exist,
# which reads as "the card has no partitions" rather than as a bug here.
part() {
	case $1 in
	*[0-9]) printf '%sp%s\n' "$1" "$2" ;;
	*) printf '%s%s\n' "$1" "$2" ;;
	esac
}

# The disk carrying the running root filesystem, with its partition suffix
# removed. Compared against the source below, because this is the one
# mistake that cannot be recovered by noticing it afterwards.
root_disk() {
	_src=$(awk '$2 == "/" { print $1; exit }' /proc/mounts 2>/dev/null)
	case $_src in
	/dev/*) ;;
	*) return 0 ;;
	esac
	# /dev/sdb2 -> /dev/sdb, /dev/mmcblk0p2 -> /dev/mmcblk0
	printf '%s\n' "$_src" | sed 's/p\{0,1\}[0-9]\{1,\}$//'
}

# Everything known about the card, read with its two partitions mounted
# read-only, and then unmounted again BEFORE a single byte is imaged.
#
# An ext4 mount replays the journal unless it is told not to, which is a
# write to the thing being archived, so the rootfs is mounted ro,noload.
# That is the difference between identifying a card and modifying it.
identify() {
	_dev=$1
	_p1=$(part "$_dev" 1)
	_p2=$(part "$_dev" 2)

	_m=$(mktemp -d)
	if mount -o ro "$_p1" "$_m" 2>/dev/null; then
		if [ -f "$_m/config.txt" ]; then
			CARD_LOOKS_RPI=yes
		fi
		umount "$_m" 2>/dev/null || true
	fi
	if mount -o ro,noload "$_p2" "$_m" 2>/dev/null; then
		if [ -f "$_m/etc/hostname" ]; then
			IDENT_HOST=$(head -1 "$_m/etc/hostname")
		fi
		if [ -f "$_m/etc/os-release" ]; then
			IDENT_OS=$(sed -n 's/^PRETTY_NAME="\{0,1\}//p' \
				"$_m/etc/os-release" | sed 's/"$//' | head -1)
		fi
		# find and not "ls | tr", which is SC2012 and fails CI at the
		# info severity this repository runs shellcheck at. The linter
		# here catches it too, which is how this line was found.
		if [ -d "$_m/lib/modules" ]; then
			IDENT_KERNEL=$(find "$_m/lib/modules" -mindepth 1 -maxdepth 1 \
				-printf '%f ' 2>/dev/null)
		fi
		# The out-of-tree modules are the whole reason this card is worth
		# keeping, so they are named individually rather than counted.
		IDENT_MODULES=$(find "$_m/root" -name '*.ko' -printf '%f ' \
			2>/dev/null)
		umount "$_m" 2>/dev/null || true
	fi
	rmdir "$_m" 2>/dev/null || true
}

# ------------------------------------------------------------------ verify
#
# The comparison against the card, done AFTER the fact.
#
# BENCH_CARD_SKIP_VERIFY exists because the comparison costs a second full
# read, and on Thursday 1 October 2026 it was used in earnest: the usbipd
# link to the reader was dropping at about eight minutes against a seventeen
# minute pass, so halving the time the card had to stay attached was the
# difference between an archive and no archive. That was the right trade and
# it left a debt, because an archive never compared against its card has no
# witness except the program that wrote it.
#
# This pays the debt without re-archiving. It checks two links of the chain:
# that the stored image still hashes to what its own record says, and that
# the card still hashes to the same value. The result is APPENDED to the
# provenance, dated, and says it was not part of the original run.
# Rewriting the original "skipped" statement would make the record describe
# a run that did not happen.
verify_store() {
	dir=$1
	src=$2

	[ -d "$dir" ] || die "no such directory: $dir"
	prov=$dir/PROVENANCE.txt
	[ -f "$prov" ] || die "$dir has no PROVENANCE.txt.
       An image with no record is not an archive, and there is nothing
       here to verify against."
	img=$(find "$dir" -maxdepth 1 -name '*.img.gz' -type f | head -1)
	[ -n "$img" ] || die "$dir holds no .img.gz.
       A .partial is not an archive, it is an interrupted read."

	# The hash of the DECOMPRESSED contents, which is the only one a card
	# can be compared against. The compressed hash depends on the gzip
	# implementation and the compression level and says nothing about the
	# card.
	recorded=$(sed -n 's/^  \([0-9a-f]\{64\}\)  the card contents, decompressed$/\1/p' "$prov" | head -1)
	[ -n "$recorded" ] || die "$prov records no decompressed sha256.
       It may predate this program, or have been edited."

	[ -e "$src" ] || die "no such source: $src"
	if [ -b "$src" ]; then
		mounted=$(grep "^$src" /proc/mounts | awk '{ print $1 " on " $2 }')
		if [ -n "$mounted" ]; then
			die "$src has mounted filesystems:
$(printf '%s\n' "$mounted" | sed 's/^/       /')
       A mounted ext4 can differ from its image by a journal replay
       alone, so the comparison would fail for a reason that is not a
       fault in the archive. Unmount them and verify again."
		fi
	fi

	note "archive   $(basename "$img")"
	note "recorded  $recorded"

	note "re-reading the archive"
	have=$(gzip -dc "$img" | sha256sum | cut -d' ' -f1)
	if [ "$have" != "$recorded" ]; then
		die "the stored image no longer hashes to its own record.
       record   $recorded
       now      $have
       The archive has been damaged since it was written, so comparing
       it against the card would answer the wrong question. Nothing here
       implicates the card."
	fi
	note "the archive still matches its own record"

	note "reading the source, a full read"
	src_sha=$(dd if="$src" bs=4M status=none | sha256sum | cut -d' ' -f1)

	if [ "$src_sha" = "$recorded" ]; then
		append_comparison "$prov" "$src" matched "$recorded" "$src_sha"
		note "verified, the archive is byte for byte the source"
		note "appended to $prov"
		return 0
	fi

	append_comparison "$prov" "$src" "DID NOT MATCH" "$recorded" "$src_sha"
	die "the source does not match the archive.
       archive  $recorded
       source   $src_sha
       Appended to $prov as a failure rather than left unsaid.
       Either the card changed after it was archived, which is normal if
       it has been booted since, or this archive is not of that card.
       Do not treat it as a copy of it."
}

# Appended, never substituted. A record that is edited to look better than
# the run it describes is worth less than no record.
append_comparison() {
	_prov=$1
	_src=$2
	_result=$3
	_recorded=$4
	_got=$5
	{
		echo
		echo "Comparison against the card, performed after archiving"
		echo "-----------------------------------------------------"
		echo
		printf 'checked    %s\n' "$(date '+%A %d %B %Y, %H:%M:%S %z')"
		printf 'source     %s\n' "$_src"
		printf 'checked on %s\n' "$(uname -srm)"
		printf 'result     %s\n' "$_result"
		printf 'archive    %s\n' "$_recorded"
		printf 'source     %s\n' "$_got"
		echo
		echo "This comparison was NOT part of the original archive run,"
		echo "which recorded the end-to-end check as skipped. It is"
		echo "appended rather than replacing that statement, because"
		echo "rewriting it would make this file describe a run that did"
		echo "not happen."
	} >>"$_prov"
}

save() {
	project=$1
	src=$2

	[ -d "$REPO_DIR/projects/$project" ] ||
		die "no projects/$project in this repository.
       ./go projects lists them."
	[ -e "$src" ] || die "no such source: $src"

	is_block=no
	if [ -b "$src" ]; then
		is_block=yes
	elif [ ! -f "$src" ]; then
		die "$src is neither a block device nor a regular file."
	fi

	if [ "$is_block" = yes ]; then
		# --- the wrong-device guards, worst mistake first ---

		rd=$(root_disk)
		if [ -n "$rd" ] && [ "$rd" = "$src" ]; then
			die "$src carries the running root filesystem.
       That is this machine, not the card."
		fi

		mounted=$(grep "^$src" /proc/mounts | awk '{ print $1 " on " $2 }')
		if [ -n "$mounted" ]; then
			die "$src has mounted filesystems:
$(printf '%s\n' "$mounted" | sed 's/^/       /')
       A filesystem being written to images inconsistently. Unmount
       them and archive again."
		fi

		bytes=$(blockdev --getsize64 "$src" 2>/dev/null || echo 0)
		[ "$bytes" -gt 0 ] || die "cannot read the size of $src."
		gb=$(( bytes / 1000000000 ))
		if [ "$gb" -gt "$MAX_GB" ]; then
			die "$src is ${gb} GB, and a bench card is 8 to 64 GB.
       This is almost certainly the wrong device. Check lsblk.
       Override with BENCH_CARD_MAX_GB if it really is the card."
		fi

		identify "$src"
		if [ "$CARD_LOOKS_RPI" = no ]; then
			die "$src has no config.txt on its first partition, so it is
       not a Raspberry Pi card. Refusing rather than reading
       ${gb} GB of whatever it is. Check lsblk."
		fi
	else
		bytes=$(wc -c <"$src")
		[ "$bytes" -gt 0 ] || die "$src is empty."
		# A file the operator named is a file the operator chose. The
		# device guards above are about a mistyped letter, which this is
		# not, so they are skipped and the gap is stated rather than left
		# to be inferred from their silence.
		note "source is a regular file, device and card checks skipped"
	fi

	commit=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
	dirty=
	if [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
		dirty=-dirty
	fi
	day=$(date '+%Y-%m-%d')
	stamp=${day}_$commit$dirty

	number=${project%%-*}
	dest=$STORE/proj$number-${project#*-}-card/$stamp
	out=$dest/$project-card-$day.img.gz

	# THE IMAGE DOES NOT CARRY ITS FINAL NAME UNTIL IT IS VERIFIED.
	#
	# It is written as <name>.partial and renamed only after the
	# comparison below succeeds. The first real run of this program, on
	# Thursday 1 October 2026, was launched in a foreground shell, the
	# tab was closed forty-two per cent of the way through a seventeen
	# minute read, and the store was left holding a 1.55 GB file named
	# exactly as a finished archive is named, with no PROVENANCE.txt and
	# no SHA256SUMS beside it.
	#
	# At a glance that is an archive. A week later it is certainly an
	# archive. The card it came from was an hour away from being
	# overwritten on the strength of it, and what caught it was checking
	# for the two record files rather than for the image.
	#
	# A program whose failure leaves something that looks like success is
	# the shape of defect this repository keeps writing down, so the fix
	# is not a warning in a document: an interrupted run now leaves
	# <name>.img.gz.partial, which is not an archive and cannot be read
	# as one. The duplicate guard below ignores it for the same reason,
	# because *.img.gz does not match *.img.gz.partial.
	staging=$out.partial

	# A SECOND, DIFFERENT IMAGE ON THE SAME STAMP IS REFUSED.
	#
	# Two cards archived for the same project at the same commit on the
	# same day share this path, and the second would rewrite
	# PROVENANCE.txt and leave the first present, undescribed and with no
	# recorded sha256. archive.sh learned this on Thursday 17 September
	# 2026, when proj08-bench-rt held two images and one record between
	# them. Writing the same name again is allowed, because a repeated
	# command should be idempotent.
	if [ -d "$dest" ]; then
		other=$(find "$dest" -maxdepth 1 -name '*.img.gz' -type f \
			! -name "$(basename "$out")" -print 2>/dev/null | head -1)
		if [ -n "$other" ]; then
			die "$dest already holds a different image:
       have  $(basename "$other")
       new   $(basename "$out")
       The second would overwrite PROVENANCE.txt and leave the first
       undescribed. Move the old one aside and archive again:
           mv $dest ${dest}-$(date '+%H%M')"
		fi
	fi

	mkdir -p "$dest"

	# A partial from an interrupted run is not evidence of anything and
	# the space it holds is needed by this one. Said out loud rather than
	# removed silently, because it means a previous attempt died.
	if [ -f "$staging" ]; then
		note "discarding $(du -h "$staging" | cut -f1) left by an interrupted run"
		rm -f "$staging"
	fi

	# Free space is checked against the UNCOMPRESSED size rather than
	# against a guess at the compression ratio. A card whose free space has
	# been written over compresses hardly at all, and a read that dies at
	# ninety per cent has cost the whole fifteen minutes and left a file
	# that looks like an archive.
	avail_k=$(df -Pk "$dest" | awk 'NR == 2 { print $4 }')
	need_k=$(( bytes / 1024 ))
	if [ "$avail_k" -lt "$need_k" ]; then
		die "$dest has $(( avail_k / 1024 )) MB free and the source is
       $(( need_k / 1024 )) MB. gzip usually needs far less, but a
       card whose free space has been written over compresses hardly
       at all, and running out mid-read leaves a file that looks like
       an archive. Free the space or set BENCH_IMAGE_DIR elsewhere."
	fi

	note "source  $src  ($(( bytes / 1000000 )) MB)"
	[ -z "$IDENT_HOST" ] || note "hostname  $IDENT_HOST"
	[ -z "$IDENT_OS" ] || note "system  $IDENT_OS"
	[ -z "$IDENT_KERNEL" ] || note "modules for  $IDENT_KERNEL"
	note "store   $dest"

	# pigz when it is there, because this is fifteen minutes of one core
	# otherwise and the laptop has more. Both write the same format, and
	# .img.gz is what Raspberry Pi Imager reads directly on the Windows
	# side, which is where this card gets written.
	zip=gzip
	if command -v pigz >/dev/null 2>&1; then
		zip=pigz
	fi
	note "compressing with $zip"

	# NO conv=noerror,sync, and both halves of that matter.
	#
	# noerror turns an unreadable block into zeros and carries on, so a
	# card with a failing sector would be archived as a card with a hole in
	# it and nothing would say so. Worse, the verification below reads the
	# source a second time the same way, gets the same zeros, and AGREES.
	# A read error has to be a refusal, because the one moment the operator
	# can still act on it is before the card is reused.
	#
	# sync pads the last short read out to the block size, which would make
	# the archive a few megabytes larger than the card it came from. dd
	# writing that back then reports a failure on the final block, and the
	# operator has to decide whether a restore that ended in an error
	# worked. Without it the image is exactly the size recorded above.
	dd if="$src" bs=4M status=progress 2>"$dest/.dd.log" |
		"$zip" >"$staging" || die "the read failed. $dest/.dd.log has what dd said."
	read_report=$(tail -1 "$dest/.dd.log")
	rm -f "$dest/.dd.log"
	note "read    $read_report"

	# The sha256 of the RESTORABLE BYTES, obtained by decompressing what
	# was just written. This is not the same as hashing the source: it
	# proves the archive decompresses from end to end, which is the
	# property that matters when it is read back in a year, where hashing
	# the source would prove only that the source was read.
	note "verifying the archive decompresses"
	raw_sha=$(gzip -dc "$staging" | sha256sum | cut -d' ' -f1)
	gz_sha=$(sha256sum "$staging" | cut -d' ' -f1)

	# And the end-to-end check, which is the only one that compares the
	# archive against the source rather than against itself. It costs a
	# second full read, and the alternative is trusting the report of the
	# tool that did the work. Project 2 recorded dd reporting complete
	# success three times while the bytes went to three different places,
	# and only reading the target back told them apart.
	if [ "${BENCH_CARD_SKIP_VERIFY:-}" = 1 ]; then
		note "end-to-end verify SKIPPED by BENCH_CARD_SKIP_VERIFY"
		src_sha=skipped
	else
		note "re-reading the source to compare, this is a second full read"
		src_sha=$(dd if="$src" bs=4M status=none |
			sha256sum | cut -d' ' -f1)
		if [ "$src_sha" != "$raw_sha" ]; then
			die "the archive does not match the source.
       source   $src_sha
       archive  $raw_sha
       It keeps the .partial name and is NOT an archive:
       $staging
       Left in place so it can be re-hashed rather than deleted on
       a guess, and discarded by the next run. Do not reuse the card."
		fi
		note "verified, the archive is byte for byte the source"
	fi

	# Only now does it get the name an archive has. Everything above
	# this line can fail, and everything above this line leaves a
	# .partial rather than something that reads as a finished archive.
	mv "$staging" "$out"

	printf '%s  %s\n' "$gz_sha" "$(basename "$out")" >"$dest/SHA256SUMS"

	write_provenance "$dest" "$project" "$number" "$out" "$commit" "$dirty" \
		"$bytes" "$raw_sha" "$gz_sha" "$src_sha" "$src"

	note "archived $(du -sh "$dest" | cut -f1)"
	note "Raspberry Pi Imager reads .img.gz as it is, no unpacking first"
}

write_provenance() {
	dest=$1
	project=$2
	number=$3
	out=$4
	commit=$5
	dirty=$6
	bytes=$7
	raw_sha=$8
	gz_sha=$9
	shift 9
	src_sha=$1
	src=$2

	{
		echo "Archived card image, embedded-linux-bench"
		echo "========================================="
		echo
		echo "What this is: a byte for byte copy of one microSD card,"
		echo "compressed, kept because nothing in this repository can"
		echo "rebuild what is on it. It is a card image and not a built"
		echo "image: no BitBake run produced it and no commit describes"
		echo "it. Read the rebuild section before assuming otherwise."
		echo
		printf 'archived  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
		printf 'project   %s  (projects/%s)\n' "$number" "$project"
		printf 'source    %s\n' "$src"
		printf 'raw size  %s bytes  (%s MB)\n' "$bytes" "$(( bytes / 1000000 ))"
		[ -z "$IDENT_HOST" ] || printf 'hostname  %s\n' "$IDENT_HOST"
		[ -z "$IDENT_OS" ] || printf 'system    %s\n' "$IDENT_OS"
		[ -z "$IDENT_KERNEL" ] || printf 'kernel    %s\n' "$IDENT_KERNEL"
		printf 'commit    %s\n' "$commit"
		printf 'imaged on %s\n' "$(uname -srm)"
		if [ -n "$IDENT_MODULES" ]; then
			echo
			echo "Out-of-tree modules found under /root"
			echo "-------------------------------------"
			printf '  %s\n' "$IDENT_MODULES"
			echo
			echo "These are the reason this image exists. They were built"
			echo "on the board against a kernel source tree unpacked there,"
			echo "and no recipe in this repository produces them."
		fi
		if [ -n "$dirty" ]; then
			echo
			echo "WARNING: the working tree had uncommitted changes when"
			echo "this card was imaged, so no commit describes the"
			echo "repository side of it exactly. What differed from"
			printf '%s:\n' "$commit"
			echo
			git -C "$REPO_DIR" status --short 2>/dev/null | sed 's/^/    /'
		fi
		echo
		echo "sha256"
		echo "------"
		printf '  %s  the compressed file\n' "$gz_sha"
		printf '  %s  the card contents, decompressed\n' "$raw_sha"
		if [ "$src_sha" = skipped ]; then
			echo
			echo "The end to end comparison against the source was"
			echo "SKIPPED. The archive was verified to decompress, which"
			echo "is not the same as verified to match the card it came"
			echo "from."
		else
			echo
			echo "The source was read a second time and hashed, and that"
			echo "hash is the decompressed one above, so this archive was"
			echo "compared against the card and not only against itself."
		fi
		echo
		echo "To flash"
		echo "--------"
		echo
		echo "Raspberry Pi Imager, on Windows, with the reader on the"
		echo "Windows side, as docs/CARD.md describes. Imager reads"
		echo ".img.gz without unpacking it first: Operating System, then"
		echo "Use custom, then this file."
		echo
		echo "  Do NOT let Imager apply its OS customisation to this"
		echo "  image. The hostname, the user and the ssh keys are"
		echo "  already inside it, and the customisation rewrites them"
		echo "  on first boot."
		echo
		echo "From WSL instead, with the card attached by usbipd and"
		echo "identified by lsblk first:"
		echo
		printf '  gzip -dc %s | sudo dd of=/dev/sdX bs=4M status=progress\n' \
			"$(basename "$out")"
		echo "  sync"
		echo
		echo "The card written from this image must be at least the raw"
		echo "size above. A nominally identical card from another maker"
		echo "can be a few megabytes smaller, and dd then stops short,"
		echo "leaving a full first partition and a truncated rootfs."
		echo
		echo "To rebuild instead of re-flashing"
		echo "---------------------------------"
		echo
		printf '  projects/%s/docs/BRINGUP.md   how the card was made\n' "$project"
		printf '  projects/%s/docs/RESUME.md    what has to be reloaded\n' "$project"
		echo
		echo "That route is longer than it looks, and it is the reason"
		echo "this image exists. Raspberry Pi Imager writes the base"
		echo "system in minutes. What took an afternoon is the rest, and"
		echo "none of it is in any recipe here:"
		echo
		echo "  - a matching linux-source tree unpacked under /usr/src"
		echo "  - the out-of-tree ST drivers built against it"
		echo "  - the bench programs placed by hand"
		echo "  - the measurements under /var/lib/bench"
		echo
		echo "A rebuild reproduces the first three with work and the"
		echo "fourth not at all, because measurements are observations"
		echo "and cannot be rebuilt."
	} >"$dest/PROVENANCE.txt"
}

case "${1:-}" in
list) list_store ;;
verify)
	shift
	[ $# -eq 2 ] || die "usage: card-archive.sh verify DIR DEVICE
       The directory is one stamp inside the store, the one holding
       PROVENANCE.txt, and the device is the card to compare it against."
	verify_store "$1" "$2"
	;;
"" | -h | --help)
	sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
	;;
*)
	[ $# -eq 2 ] || die "usage: card-archive.sh PROJECT DEVICE
       e.g. sudo scripts/card-archive.sh 10-iio-iks4a1 /dev/sdb"
	save "$1" "$2"
	;;
esac
