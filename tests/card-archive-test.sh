#!/bin/sh
#
# card-archive-test.sh - the card archiver, with no card and no root.
#
# scripts/card-archive.sh exists because Project 10's microSD card is the
# only copy of an afternoon of work that no recipe here can rebuild. A
# backup program that has never been exercised is the worst kind of program
# to trust, and this repository recorded on Thursday 1 October 2026 that
# four separate defects were sitting in programs that had never been run.
#
# Everything below uses a REGULAR FILE as the source, which is a path the
# program supports deliberately. So the suite needs no card, no reader, no
# usbipd and no root, and it still exercises the naming, the stamp, the
# refusals, the provenance and, most importantly, whether the archive it
# writes decompresses back to the bytes that went in.
#
# What it cannot check is the block-device half: the root-disk guard, the
# mounted-filesystem guard, the size ceiling and the config.txt
# identification all need a real device. Those are stated here as a known
# gap rather than left to look covered.
#
#   sh tests/card-archive-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/card-archive.sh

WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

STORE=$WORK/store
PROJECT=10-iio-iks4a1

pass=0
fail=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
}

contains() {
	case $2 in
	*"$3"*) ok "$1" ;;
	*)
		no "$1: '$3' not in output"
		printf '%s\n' "$2" | sed 's/^/         /'
		;;
	esac
}

# Every run gets the same store and none of them touch the real one under
# $HOME/bench/images. A test that archived into the operator's own store
# would be indistinguishable from a real archive the next time anybody read
# the list.
run() {
	BENCH_IMAGE_DIR=$STORE sh "$SUT" "$@" 2>&1
}

refuses() {
	_what=$1
	shift
	_status=0
	_out=$(run "$@") || _status=$?
	if [ "$_status" -ne 0 ]; then
		ok "$_what"
	else
		no "$_what: it succeeded instead"
		printf '%s\n' "$_out" | sed 's/^/         /'
	fi
	REFUSAL=$_out
}

# The mirror of refuses, and it exists because of what happened the first
# time this suite was checked against a broken archiver.
#
# conv=sync was put back into the dd on purpose, to watch the round-trip
# assertion fail. It never ran. The program refused, which is correct, and
# the archive was being run as a bare command substitution under set -eu,
# so the whole file stopped at that line and printed ten green lines with
# no tally and no failure. A suite whose output on a real defect is a short
# green list is worse than no suite at all.
must_succeed() {
	_what=$1
	shift
	_status=0
	OUT=$(run "$@") || _status=$?
	if [ "$_status" -eq 0 ]; then
		ok "$_what"
		return 0
	fi
	no "$_what: the program refused"
	printf '%s\n' "$OUT" | sed 's/^/         /'
	echo
	echo "$pass passed, $fail failed"
	exit 1
}

# ------------------------------------------------------------- the refusals

refuses "a project that does not exist is refused" 99-not-a-project /dev/null
contains "and it says where the list of projects is" "$REFUSAL" "./go projects"

refuses "a source that does not exist is refused" "$PROJECT" "$WORK/absent.img"
contains "naming the missing source" "$REFUSAL" "absent.img"

: >"$WORK/empty.img"
refuses "an empty source is refused" "$PROJECT" "$WORK/empty.img"
contains "and says it is empty rather than archiving nothing" \
	"$REFUSAL" "is empty"

refuses "one argument is refused" "$PROJECT"
contains "with the usage line" "$REFUSAL" "card-archive.sh PROJECT DEVICE"

refuses "an empty store has nothing to list" list
contains "and says where the store would be" "$REFUSAL" "$STORE"

# ---------------------------------------------------------- a real archive
#
# 9 MB and not a round number of 4 MiB blocks, which is the case that
# matters: a card is rarely a whole multiple of the block size, and dd with
# conv=sync would pad the tail out and make the archive larger than the
# thing it copied. The round-trip assertion below is what catches that.
dd if=/dev/urandom of="$WORK/card.img" bs=1024 count=9001 status=none
SRC_SHA=$(sha256sum "$WORK/card.img" | cut -d' ' -f1)
SRC_BYTES=$(wc -c <"$WORK/card.img")

must_succeed "a card is archived from a regular file" "$PROJECT" \
	"$WORK/card.img"
out=$OUT
contains "a regular source says which checks it skipped" "$out" \
	"device and card checks skipped"
contains "and the end-to-end verify is a second read, announced" "$out" \
	"second full read"
contains "and it reports the comparison, not just the write" "$out" \
	"byte for byte"

DEST=$(find "$STORE" -name PROVENANCE.txt -exec dirname {} \; | head -1)
if [ -n "$DEST" ]; then
	ok "a store directory was created"
else
	no "a store directory was created"
	exit 1
fi

case $DEST in
*/proj10-iio-iks4a1-card/*)
	ok "named by project number, like the Yocto store, with a -card suffix" ;;
*)
	no "named by project number, like the Yocto store, with a -card suffix"
	echo "         got $DEST" ;;
esac

# The stamp is <date>_<commit>, and -dirty when the tree is not clean. Which
# of those is right depends on the tree the suite is run in, so the
# assertion is the AGREEMENT between them rather than either one.
stamp=$(basename "$DEST")
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
	case $stamp in
	*-dirty) ok "a dirty working tree is marked in the stamp" ;;
	*) no "a dirty working tree is marked in the stamp: $stamp" ;;
	esac
else
	case $stamp in
	*-dirty) no "a clean working tree is not marked dirty: $stamp" ;;
	*) ok "a clean working tree is not marked dirty" ;;
	esac
fi

IMG=$(find "$DEST" -name '*.img.gz' | head -1)
# Not written as "test && ok || no", which is not an if/else and is the
# SC2015 that has already cost this repository a CI run.
if [ -n "$IMG" ]; then
	ok "the image was written"
else
	no "the image was written"
fi
contains "the image names the project and the day" "$(basename "$IMG")" \
	"$PROJECT-card-$(date '+%Y-%m-%d').img.gz"

# THE ASSERTION THE WHOLE FILE IS FOR. An archive that does not come back
# out is not an archive, and every other property here is cosmetic beside
# it.
back=$(gzip -dc "$IMG" | sha256sum | cut -d' ' -f1)
if [ "$back" = "$SRC_SHA" ]; then
	ok "the archive decompresses to exactly the bytes that went in"
else
	no "the archive decompresses to exactly the bytes that went in"
	echo "         source  $SRC_SHA"
	echo "         archive $back"
fi

back_bytes=$(gzip -dc "$IMG" | wc -c)
if [ "$back_bytes" = "$SRC_BYTES" ]; then
	ok "and to exactly the same length, with no block padding on the tail"
else
	no "and to exactly the same length, with no block padding on the tail"
	echo "         source  $SRC_BYTES bytes, archive $back_bytes bytes"
fi

# The program claims to read the source and write nothing to it. That claim
# is cheap to make and cheap to check.
now=$(sha256sum "$WORK/card.img" | cut -d' ' -f1)
if [ "$now" = "$SRC_SHA" ]; then
	ok "the source is unchanged, so nothing was written back to it"
else
	no "the source is unchanged, so nothing was written back to it"
fi

# ------------------------------------------------------------- SHA256SUMS
#
# Written as a separate file and not only inside the prose, because this
# directory crosses to a Windows desktop and the only check available there
# is sha256sum -c on the file beside the image.
if [ -f "$DEST/SHA256SUMS" ]; then
	ok "a SHA256SUMS was written beside the image"
else
	no "a SHA256SUMS was written beside the image"
fi
if (cd "$DEST" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
	ok "and sha256sum -c verifies it where it stands"
else
	no "and sha256sum -c verifies it where it stands"
fi

# ------------------------------------------------------------ the provenance

prov=$(cat "$DEST/PROVENANCE.txt")
contains "the provenance says this is a card image, not a built image" \
	"$prov" "card image and not a built"
contains "it records the project and its directory" "$prov" \
	"project   10  (projects/$PROJECT)"
contains "it records the source it was read from" "$prov" "card.img"
contains "it records the raw size in bytes" "$prov" "$SRC_BYTES bytes"
contains "it records the commit" "$prov" "commit    "
contains "it records the sha256 of the compressed file" "$prov" \
	"the compressed file"
contains "and of the decompressed contents, which is what a restore gives" \
	"$prov" "the card contents, decompressed"
contains "the decompressed hash is the real one" "$prov" "$SRC_SHA"
contains "it says the comparison was against the source, not itself" \
	"$prov" "compared against the card and not only against itself"
contains "it says how to flash with Imager" "$prov" "Use custom"
contains "and warns that Imager customisation would overwrite the card" \
	"$prov" "customisation rewrites them"
contains "it gives the dd route as well, for WSL" "$prov" "gzip -dc"
contains "and says to identify the device with lsblk first" "$prov" "lsblk"
contains "it warns that a smaller card truncates the restore" "$prov" \
	"a few megabytes smaller"
contains "it says how to rebuild instead, naming BRINGUP" "$prov" \
	"projects/$PROJECT/docs/BRINGUP.md"
contains "and RESUME" "$prov" "projects/$PROJECT/docs/RESUME.md"
contains "and it says what a rebuild cannot give back" "$prov" \
	"cannot be rebuilt"

# ------------------------------------------------------------------- list

out=$(run list)
contains "list finds the entry" "$out" "proj10-iio-iks4a1-card"

# --------------------------------------------------- repeating, and not

# The same source again writes the same name, which is what a repeated
# command should do. It must not refuse.
status=0
out=$(run "$PROJECT" "$WORK/card.img") || status=$?
if [ "$status" -eq 0 ]; then
	ok "archiving the same source again is idempotent, not an error"
else
	no "archiving the same source again is idempotent, not an error"
	printf '%s\n' "$out" | sed 's/^/         /'
fi

# A DIFFERENT image already in the same stamp directory is refused. Two
# cards archived for one project at one commit on one day share this path,
# and the second would rewrite PROVENANCE.txt and leave the first present
# with no recorded hash. archive.sh met that on Thursday 17 September 2026
# with two images and one record between them.
: >"$DEST/some-other-card-2026-09-30.img.gz"
refuses "a different image already on the same stamp is refused" \
	"$PROJECT" "$WORK/card.img"
contains "naming both of them" "$REFUSAL" "some-other-card-2026-09-30.img.gz"
contains "and saying what would have been lost" "$REFUSAL" "undescribed"
contains "and giving the command that makes room" "$REFUSAL" "mv $DEST"
rm -f "$DEST/some-other-card-2026-09-30.img.gz"

# ------------------------------------- an interrupted run leaves no archive
#
# The first real run of card-archive.sh was launched in a foreground shell,
# the tab was closed forty-two per cent into a seventeen minute read, and
# the store was left holding a 1.55 GB file named exactly as a finished
# archive is named, with no PROVENANCE.txt and no SHA256SUMS. That reads as
# an archive to anybody who looks at the directory, and the card it came
# from was about to be overwritten on the strength of it.
#
# So the image is written as <name>.img.gz.partial and renamed only after
# the comparison passes. What this suite can check is that a successful run
# leaves no .partial behind, and that a .partial from a previous death is
# announced, discarded, and never mistaken for the image.
#
# WHAT IT CANNOT CHECK is the interruption itself. Killing a running dd
# mid-pipeline from inside a test that must also work on a laptop with no
# card is not something this file attempts, so the rename is checked by its
# two observable ends rather than by the event between them.

leftover=$(find "$DEST" -name '*.partial' | head -1)
if [ -z "$leftover" ]; then
	ok "a finished run leaves no .partial behind"
else
	no "a finished run leaves no .partial behind: $leftover"
fi

# A stale partial, exactly as a killed run leaves one.
stale=$DEST/$PROJECT-card-$(date '+%Y-%m-%d').img.gz.partial
dd if=/dev/urandom of="$stale" bs=1024 count=100 status=none

must_succeed "a stale .partial does not block the next run" "$PROJECT" 	"$WORK/card.img"
contains "and the run says a previous attempt died" "$OUT" 	"left by an interrupted run"

# TRUE BY TRUNCATION, NOT BY THE rm IN THE SCRIPT, and the difference was
# found by removing that rm and watching this pass anyway. The write
# redirects onto the same path, which truncates it, so the file would go
# even with no cleanup line at all. The property is still worth pinning,
# because it is what the operator sees; the note above it is the part that
# pins the script's own cleanup. Said here so the next reader does not
# conclude from a green line that the rm is tested. This project has
# already shipped a test that asserted a bug and a test that could not
# report one; a test that credits the wrong mechanism is the same family.
if [ -f "$stale" ]; then
	no "the stale .partial is gone afterwards"
else
	ok "the stale .partial is gone afterwards"
fi

# The guard that refuses a second image on the same stamp must not count a
# .partial as that second image, or a killed run would block its own retry.
# find -name '*.img.gz' does not match '*.img.gz.partial', which is why.
back3=$(gzip -dc "$IMG" | sha256sum | cut -d' ' -f1)
if [ "$back3" = "$SRC_SHA" ]; then
	ok "and the archive it wrote is the real one, not the leftover"
else
	no "and the archive it wrote is the real one, not the leftover"
fi

# ------------------------------------------------- the verify can be skipped
#
# It costs a second full read of the card, so it can be turned off. What
# must not happen is a provenance file that reads the same either way: an
# unverified archive that looks verified is worse than one that says it is
# not.
rm -rf "$STORE"
out=$(BENCH_IMAGE_DIR=$STORE BENCH_CARD_SKIP_VERIFY=1 \
	sh "$SUT" "$PROJECT" "$WORK/card.img" 2>&1)
contains "the end-to-end verify can be skipped" "$out" "SKIPPED"
DEST2=$(find "$STORE" -name PROVENANCE.txt -exec dirname {} \; | head -1)
prov2=$(cat "$DEST2/PROVENANCE.txt")
contains "and the provenance says so rather than claiming a comparison" \
	"$prov2" "SKIPPED"
contains "and spells out what was and was not established" "$prov2" \
	"not the same as verified to match"
case $prov2 in
*"compared against the card and not only against itself"*)
	no "a skipped verify does not claim the card was compared" ;;
*)
	ok "a skipped verify does not claim the card was compared" ;;
esac

# Skipping the comparison must still leave a restorable archive, because
# the decompression check is not the part that was skipped.
IMG2=$(find "$STORE" -name '*.img.gz' | head -1)
back2=$(gzip -dc "$IMG2" | sha256sum | cut -d' ' -f1)
if [ "$back2" = "$SRC_SHA" ]; then
	ok "and the archive is still a faithful copy"
else
	no "and the archive is still a faithful copy"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
