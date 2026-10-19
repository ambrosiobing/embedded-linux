#!/bin/sh
#
# host-check.sh - everything that can be proven in two minutes, before
# committing to a build that takes three hours.
#
# The cross build is the only way to prove the recipe, but it is not the
# only way to prove the source. libgpiod on Ubuntu 24.04 and later is v2,
# the same API the daemon targets, so the host compiler catches a mistake in
# the GPIO calls long before BitBake would.
#
# A skipped compile counts as a failure rather than a pass with a note. The
# whole point of this script is to compile before the long build starts, so
# saying "passed" when it did not compile would be worse than useless.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

cd "$REPO_DIR" || die "cannot enter $REPO_DIR"

fail=0

# AN ABSENT HOST TOOL IS COUNTED SEPARATELY FROM A DEFECT.
#
# The header above says a skipped compile counts as a failure rather than a
# pass with a note, and that stays. This file exists to compile before three
# hours of build start, so reporting "passed" without the compile would be
# worse than useless, and the exit status below is still non-zero when a
# compile did not happen.
#
# What changed on Monday 19 October 2026 is what it SAYS. Until then the
# last line read "host checks FAILED. Fix these before starting a
# three-hour build." On win11 aquamarine that sentence was false in both
# halves: there is no pkg-config and no compiler there by a rule of this
# bench rather than by accident, so nothing needed fixing, and no build
# starts on that laptop anyway. A red line whose only meaning is "wrong
# machine" is what teaches a reader to skim red lines, which is the harm
# decisions 125 and 128 are both about.
#
# So absence is counted and named, and the verdict distinguishes "this tree
# has defects" from "this host cannot ask". Note that shellcheck has always
# been note-and-continue here rather than a failure, which is a real
# distinction and is kept: the compiles are the point of this file, and a
# missing linter is a bonus withheld rather than a question unasked.
absent=0
absent_list=""

missing() {
	absent=$((absent + 1))
	case " $absent_list " in
	*" $1 "*) ;;
	*) absent_list="$absent_list $1" ;;
	esac
}

# ONE INTERPRETER, RESOLVED ONCE, FOR EVERY PYTHON STEP BELOW.
#
# python3 was named directly in two places: the static layer checks and
# py_compile over every Python file in the tree. On win11 aquamarine
# python3 is the Microsoft Store stub, which runs nothing, so that loop
# reported FORTY files as having compile errors when the interpreter was
# the only thing wrong. Forty red lines meaning "wrong machine" is the
# strongest form of the harm this file's verdict was changed for: nobody
# reads the forty-first.
#
# The stub is invisible to the usual probes. command -v finds it, and it
# exits 0 for --version while running nothing at all, so executing
# something is the only test that distinguishes it.
#
# PYTHON overrides the search for a host where neither name is right.
PY=${PYTHON:-}
if [ -z "$PY" ]; then
	for candidate in python3 python; do
		if "$candidate" -c "import sys" >/dev/null 2>&1; then
			PY=$candidate
			break
		fi
	done
fi

step() {
	printf '\n--- %s\n' "$1"
}

# Every shell file, found rather than listed, so a new one cannot quietly
# escape the check. Two sources, because common.sh is sourced and has no
# shebang, while bench-state and bench-wifi-setup have a shebang and no
# extension. Markdown is excluded: the docs quote shebangs inside examples.
#
# WHAT A SEARCH CHOOSES, IT HAS TO SAY. Both halves used to start at the
# repository root and walk into the layers kas clones here when
# KAS_WORK_DIR is unset: poky, meta-openembedded and meta-raspberrypi.
# On the build host on Saturday 17 October 2026 that fed
# meta-raspberrypi's pi-bluetooth recipe to shellcheck as a shell script,
# which produced 28 findings about BitBake syntax and a failed run. The
# three directories are pruned here and in scripts/lint.py, and both say
# when they skipped one.
#
# The first-line test is the second half of the same fix. A shebang means
# a shell script only on the first line, and that recipe writes an init
# script with a heredoc, so the string sits in the middle of a BitBake
# file. Pruning the layers is what fixed today's run; this is what keeps
# a recipe in meta-bench from doing the same thing tomorrow.
BENCH_PRUNE="--exclude-dir=.git --exclude-dir=poky"
BENCH_PRUNE="$BENCH_PRUNE --exclude-dir=meta-openembedded"
BENCH_PRUNE="$BENCH_PRUNE --exclude-dir=meta-raspberrypi"

BENCH_SH=$( {
	# shellcheck disable=SC2086
	grep -rl $BENCH_PRUNE --exclude=*.md "^#!/bin/sh" . |
		while IFS= read -r f; do
			case $(head -n 1 "$f") in
			"#!/bin/sh"*) printf '%s\n' "$f" ;;
			esac
		done
	find . \( -path ./.git -o -path ./poky \
		-o -path ./meta-openembedded \
		-o -path ./meta-raspberrypi \) -prune \
		-o -name "*.sh" -print
} | sed "s|^[.]/||" | sort -u)

step "static layer checks"
if [ -n "$PY" ]; then
	"$PY" scripts/lint.py || fail=1
else
	echo "no working Python on this host, so the layer checks were NOT run."
	missing python3
fi

step "shell files parse"
# Always available, unlike shellcheck, and it catches the one thing that
# matters most after a copy between machines.
for f in $BENCH_SH; do
	if sh -n "$f"; then
		echo "ok   $f"
	else
		echo "FAILED $f"
		fail=1
	fi
done

step "python programs compile"
# lte-watchdog and lte-exporter are Python and have no extension, so they
# are found by their shebang the same way the shell files are. A syntax
# error in either of them is a watchdog that dies on its first start, which
# on a gateway means the box is offline and cannot be reached to be fixed.
BENCH_PY=$( {
	# shellcheck disable=SC2086
	grep -rl $BENCH_PRUNE --exclude=*.md "^#!/usr/bin/env python3" . |
		while IFS= read -r f; do
			case $(head -n 1 "$f") in
			"#!/usr/bin/env python3"*) printf '%s\n' "$f" ;;
			esac
		done
	find . \( -path ./.git -o -path ./poky \
		-o -path ./meta-openembedded \
		-o -path ./meta-raspberrypi \) -prune \
		-o -name "*.py" -print
} | sed "s|^[.]/||" | sort -u)
if [ -z "$PY" ]; then
	# Counted once, not once per file. Forty identical lines saying the
	# interpreter is absent is the noise that hides the one line that
	# matters, and the count is of checks not asked, not of files.
	echo "no working Python on this host, so NONE of these compiled:"
	for f in $BENCH_PY; do
		echo "    $f"
	done
	missing python3
else
	for f in $BENCH_PY; do
		if "$PY" -m py_compile "$f"; then
			echo "ok   $f"
		else
			echo "FAILED $f"
			fail=1
		fi
	done
fi
find . -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true

step "shell scripts"
if command -v shellcheck >/dev/null 2>&1; then
	# shellcheck disable=SC2086
	if shellcheck -s sh -e SC1090,SC1091 $BENCH_SH; then
		echo "shellcheck clean"
	else
		fail=1
	fi
else
	echo "shellcheck absent, skipped (scripts/host-setup.sh installs it)"
fi

# Every test in tests/, so adding one is enough to have it run.
for t in tests/*.sh; do
	step "test: $(basename "$t")"
	sh "$t" || fail=1
done

step "compile the daemon against host libgpiod"
if ! command -v pkg-config >/dev/null 2>&1; then
	echo "pkg-config is not installed. Run scripts/host-setup.sh."
	missing pkg-config
elif ! pkg-config --exists libgpiod; then
	echo "libgpiod development files are not installed."
	echo "Run scripts/host-setup.sh, or: sudo apt-get install -y libgpiod-dev"
	missing libgpiod-dev
else
	version=$(pkg-config --modversion libgpiod)
	echo "libgpiod $version"
	case $version in
	2.*) ;;
	*)
		echo "warning: this is libgpiod v$version, the daemon targets v2."
		echo "The compile below will fail on the v2 calls, which is correct:"
		echo "the target has v2 even when this host does not."
		;;
	esac

	out=$(mktemp -d)/bench-status

	# Word splitting on the pkg-config output is intended: it returns a
	# list of flags, not one argument.
	# shellcheck disable=SC2046
	if gcc -Wall -Wextra -Werror -O2 \
		$(pkg-config --cflags libgpiod) \
		meta-bench/recipes-bench/bench-status/files/bench-status.c \
		-o "$out" $(pkg-config --libs libgpiod); then
		echo "compiled clean with -Werror"
		# No GPIO chip on most build hosts, so exit 1 is correct here.
		if timeout 5 "$out"; then
			echo "note: this host has a usable GPIO chip"
		else
			echo "runs and reports no usable chip, as expected off-target"
		fi
	else
		fail=1
	fi

	step "compile lte-gpio against host libgpiod"
	# Project 15's control-line tool, same treatment as the daemon: the
	# compiler is the only thing on this host that can say anything about
	# it, so it says it with -Werror.
	out=$(mktemp -d)/lte-gpio
	lte_src=meta-bench/recipes-bench/bench-lte/files/lte-gpio.c
	# Word splitting on the pkg-config output is intended here too.
	# shellcheck disable=SC2046
	if gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags libgpiod) \
		"$lte_src" -o "$out" $(pkg-config --libs libgpiod); then
		echo "compiled clean with -Werror"
		if timeout 5 "$out" info; then
			echo "note: this host has a usable GPIO chip"
		else
			echo "runs and reports no usable chip, as expected off-target"
		fi
	else
		fail=1
	fi

	step "compile tracker-gpio against host libgpiod"
	# Project 16's power key and instrument marker. Same treatment as
	# lte-gpio, which it deliberately does not share a package with: that
	# one lives in bench-lte, whose package drags ModemManager and
	# NetworkManager into any image that installs it, and this project's
	# whole argument is that a tracker installs neither.
	#
	# "info" is the subcommand to run here because it is the only one that
	# touches no line. "pwrkey" and "marker-hold" both refuse without an
	# offset in the configuration, which is correct on a board and would be
	# a confusing non-zero exit in a check.
	out=$(mktemp -d)/tracker-gpio
	tracker_src=meta-bench/recipes-bench/bench-tracker/files/tracker-gpio.c
	# Word splitting on the pkg-config output is intended here too.
	# shellcheck disable=SC2046
	if gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags libgpiod) \
		"$tracker_src" -o "$out" $(pkg-config --libs libgpiod); then
		echo "compiled clean with -Werror"
		if timeout 5 "$out" info; then
			echo "reports its configuration and refuses what is unset"
		else
			fail=1
		fi
	else
		fail=1
	fi

	step "compile the real-time toggler against host libgpiod"
	# Project 8's instrument. It is the one program here that is
	# measured rather than merely run, so a warning about a conversion
	# or an uninitialised variable is a warning about a number that
	# ends up in a results table.
	out=$(mktemp -d)/rt-toggle
	rt_src=meta-bench/recipes-bench/bench-rt/files/rt-toggle.c
	# Word splitting on the pkg-config output is intended here too.
	# shellcheck disable=SC2046
	if gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags libgpiod) \
		"$rt_src" -o "$out" $(pkg-config --libs libgpiod); then
		echo "compiled clean with -Werror"
		# No GPIO chip on a build host, and no permission to go
		# SCHED_FIFO either, so a non-zero exit is the correct
		# outcome and proves the binary links and starts.
		if timeout 5 "$out" -d 1 -o /dev/null; then
			echo "note: this host has a usable GPIO chip"
		else
			echo "runs and reports no usable chip, as expected"
		fi
	else
		fail=1
	fi

	step "compile the sensor hub daemon"
	# Project 12's daemon is the one program here that talks to two
	# libraries at once, and the sd-bus vtable is a table of macros
	# whose mistakes are compile errors rather than run-time ones. That
	# makes this compile worth more than most: it is the only thing
	# short of a board that can check the interface declaration at all.
	if ! pkg-config --exists libsystemd libcbor; then
		echo "libsystemd or libcbor development files are missing."
		echo "Run scripts/host-setup.sh, or:"
		echo "  sudo apt-get install -y libsystemd-dev libcbor-dev"
		fail=1
	else
		out=$(mktemp -d)/sensorhubd
		hub_src=meta-bench/recipes-bench/bench-sensorhub/files
		hub_cflags=$(pkg-config --cflags libsystemd libcbor)
		hub_libs=$(pkg-config --libs libsystemd libcbor)
		# Word splitting on the pkg-config output is intended here too.
		# shellcheck disable=SC2086
		if gcc -Wall -Wextra -Werror -O2 -I"$hub_src" $hub_cflags \
			"$hub_src/sensorhubd.c" "$hub_src/proto.c" \
			-o "$out" $hub_libs; then
			echo "compiled clean with -Werror"
		else
			fail=1
		fi
	fi

	step "compile the SDK example against host libgpiod"
	make -C sdk/hello-gpiod clean >/dev/null 2>&1 || true
	if make -C sdk/hello-gpiod; then
		echo "SDK example compiled"
	else
		fail=1
	fi
	make -C sdk/hello-gpiod clean >/dev/null 2>&1 || true
fi

step "compile drmfill against host libdrm"
# Project 7's DRM test program. Its own step rather than one more block
# inside the libgpiod branch above, because it needs libdrm and nothing
# else: a host with libgpiod and no libdrm should still check everything
# it can, and say what it could not.
#
# libdrm on any current distribution is the same API the target has, so
# the host compiler catches a mistake in the DRM calls long before BitBake
# would. That is the whole argument for this file.
if ! command -v pkg-config >/dev/null 2>&1; then
	echo "pkg-config is not installed. Run scripts/host-setup.sh."
	missing pkg-config
elif ! pkg-config --exists libdrm; then
	echo "libdrm development files are not installed."
	echo "Run scripts/host-setup.sh, or: sudo apt-get install -y libdrm-dev"
	missing libdrm-dev
else
	echo "libdrm $(pkg-config --modversion libdrm)"
	out=$(mktemp -d)/drmfill
	drm_src=meta-bench/recipes-bench/bench-lcd35a/files/drmfill.c
	# Word splitting on the pkg-config output is intended: it returns a
	# list of flags, not one argument.
	# shellcheck disable=SC2046
	if gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags libdrm) \
		"$drm_src" -o "$out" $(pkg-config --libs libdrm); then
		echo "compiled clean with -Werror"
		# No panel on any build host, so this finds no ili9486 card and
		# exits 1. That is the correct answer here, and it exercises the
		# card-walking path that replaced the specification's hard-coded
		# /dev/dri/card1.
		if timeout 5 "$out" -t 1; then
			echo "note: this host has a card driven by ili9486"
		else
			echo "runs and reports no panel, as expected off-target"
		fi
	else
		fail=1
	fi
fi

step "compile kbd_bridge against host libevdev"
# Project 14's evdev to HID bridge. Its own step for the same reason as
# drmfill above: it needs libevdev and nothing else, so a host missing it
# should still check everything else and say what it could not.
#
# This file was committed, pushed and shipped in an image recipe without a
# compiler ever reading it. Nothing here and nothing in CI compiled it
# until both were added together. usage_table.h is committed beside the
# source, so -I on that directory is the whole include path.
if ! command -v pkg-config >/dev/null 2>&1; then
	echo "pkg-config is not installed. Run scripts/host-setup.sh."
	missing pkg-config
elif ! pkg-config --exists libevdev; then
	echo "libevdev development files are not installed."
	echo "Run scripts/host-setup.sh, or: sudo apt-get install -y libevdev-dev"
	missing libevdev-dev
else
	echo "libevdev $(pkg-config --modversion libevdev)"
	out=$(mktemp -d)/kbd-bridge
	kbd_src=meta-bench/recipes-bench/bench-kbd-bridge/files
	# Word splitting on the pkg-config output is intended: it returns a
	# list of flags, not one argument.
	# shellcheck disable=SC2046
	if gcc -Wall -Wextra -Werror -O2 -I"$kbd_src" $(pkg-config --cflags libevdev) \
		"$kbd_src/kbd_bridge.c" -o "$out" $(pkg-config --libs libevdev); then
		echo "compiled clean with -Werror"
		# No /dev/input/bench-kbd on a build host, so this refuses and
		# names the path it could not open. That exercises the link
		# against libevdev, which the compile alone does not prove.
		if timeout 5 "$out" 2>/dev/null; then
			echo "note: this host has /dev/input/bench-kbd"
		else
			echo "runs and refuses without a keyboard, as expected off-target"
		fi
	else
		fail=1
	fi
fi

echo
if [ "$fail" -ne 0 ]; then
	echo "host checks FAILED: something above is wrong with the tree."
	echo "Fix these before starting a three-hour build."
	exit 1
elif [ "$absent" -ne 0 ]; then
	echo "NO DEFECT FOUND, and $absent of these checks could not be asked on"
	echo "this host. Absent:$absent_list"
	echo
	echo "This is not a go-ahead for a build, and the exit status says so,"
	echo "because the compiles are the point of this file and they did not"
	echo "happen. It is not a finding against the tree either. Run it on the"
	echo "build laptop, where scripts/host-setup.sh installs all of these;"
	echo "docs/BUILD-HOST.md is the list."
	exit 1
else
	echo "host checks passed. Next: ./go build"
fi
