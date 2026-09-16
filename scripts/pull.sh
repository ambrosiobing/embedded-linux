#!/bin/sh
#
# pull.sh - git pull, refused while a build is running.
#
#   scripts/pull.sh          or  ./go pull
#
# WHY THIS IS NOT JUST "GIT PULL"
#
# kas does not copy this checkout into the build directory. It registers it
# as a layer, in place, and BitBake reads the recipes from here for the
# whole length of a build. So a pull is not an operation on a source tree
# next to a build; it is an edit to the running build's metadata.
#
# BitBake reparses during a build and compares each task's basehash against
# the one it started with. A recipe file that changed underneath produces:
#
#   ERROR: When reparsing .../linux-raspberrypi_6.12.bb:do_fetch, the
#   basehash value changed from 657647e2... to 1b9f07b4... The metadata is
#   not deterministic and this needs to be fixed.
#
# That message blames the metadata, which is the one thing that was not at
# fault. The metadata is deterministic; it was replaced mid-flight.
#
# It cost a kernel here. A pull three hours into a bench-rt-image build
# added two lines to linux-raspberrypi_%.bbappend for an unrelated project:
#
#   BENCH_NETBOOT_KERNEL ?= "0"
#   SRC_URI += '${@"file://netboot.cfg" if ... == "1" else ""}'
#
# Both inert for that build, since the switch was off and the expression
# expanded to nothing. The basehash covers the expression and what it
# depends on, not what it evaluated to, so five kernel tasks changed
# signature and the build failed at 6201 of 6258 tasks.
#
# THE RECOVERY, WHICH IS WHY THE COMMIT IS PRINTED BELOW
#
# Restoring just the changed recipe file to the commit the build started
# from restores the basehashes, the existing stamps match, and BitBake
# resumes instead of recompiling:
#
#   git checkout <commit> -- path/to/changed.bbappend
#   ./go rt
#   git checkout HEAD -- path/to/changed.bbappend     afterwards
#
# The alternative is to keep the new metadata and let the kernel rebuild,
# which is correct and costs a couple of hours.
#
# This script prints the commit before pulling so that the recovery above
# is possible without digging it out of a scrollback.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

require_tool git

cd "$REPO_DIR" || die "cannot enter $REPO_DIR"

# The same pgrep the build scripts use, with a different explanation. A
# second build is refused because BitBake allows one per build directory;
# a pull is refused because it rewrites what the first one is reading.
#
# And say so when the question could not be asked. pgrep is absent on Git
# Bash, where "pgrep ... >/dev/null 2>&1" is simply false and the guard
# waves everything through. No build runs on that host, so nothing is at
# risk, but a check that reports success without having looked is the
# failure this repository keeps finding in itself. It says which it did.
if ! command -v pgrep >/dev/null 2>&1; then
	note "pgrep is absent, so a running build cannot be detected here"
	note "this guard is not in force on this host"
elif pgrep -f 'bitbake/bin/bitbake' >/dev/null 2>&1; then
	die "a BitBake run is in progress, and this checkout is its layer.

       Pulling now edits the metadata of the running build. BitBake
       reparses as it goes, sees a task's basehash change, and stops with
       \"The metadata is not deterministic\", naming recipes you did not
       touch. Work already done is not lost, but the tasks downstream of
       whatever changed are, and for a kernel that is most of an hour.

       Wait for it to finish. If you need the new commits now, clone
       somewhere else and read them there:

           git -C $REPO_DIR log --oneline origin/main"
fi

before=$(git rev-parse --short HEAD 2>/dev/null) ||
	die "$REPO_DIR is not a git checkout"

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
	note "the working tree has local changes; git will say if they conflict"
fi

note "at       $before  $(git log --format=%s -1)"

git pull "$@"

after=$(git rev-parse --short HEAD)

if [ "$before" = "$after" ]; then
	note "unchanged, already at $after"
	exit 0
fi

note "now      $after  $(git log --format=%s -1)"

# The one line worth keeping. If a build is started and something later
# needs to be put back, this is the commit to put it back to.
note "if a build started before this pull needs rescuing, its metadata was"
note "at $before:  git checkout $before -- <path>"

# Recipe-level changes are the ones that move basehashes. Files under
# projects/ and walkthrough/ are prose and cannot. Saying which arrived is
# cheaper than finding out from a reparse error three hours later.
changed=$(git diff --name-only "$before" "$after" -- \
	meta-bench kas 2>/dev/null | head -20)
if [ -n "$changed" ]; then
	note "metadata that changed, which is what moves a basehash:"
	printf '%s\n' "$changed" | sed 's/^/---          /'
else
	note "no metadata under meta-bench or kas changed, only prose and tests"
fi
