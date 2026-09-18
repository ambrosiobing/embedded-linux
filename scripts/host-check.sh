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

step() {
	printf '\n--- %s\n' "$1"
}

# Every shell file, found rather than listed, so a new one cannot quietly
# escape the check. Two sources, because common.sh is sourced and has no
# shebang, while bench-state and bench-wifi-setup have a shebang and no
# extension. Markdown is excluded: the docs quote shebangs inside examples.
BENCH_SH=$( {
	grep -rl --exclude-dir=.git --exclude=*.md "^#!/bin/sh" .
	find . -path ./.git -prune -o -name "*.sh" -print
} | sed "s|^[.]/||" | sort -u)

step "static layer checks"
python3 scripts/lint.py || fail=1

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
	grep -rl --exclude-dir=.git --exclude=*.md "^#!/usr/bin/env python3" .
	find . -path ./.git -prune -o -name "*.py" -print
} | sed "s|^[.]/||" | sort -u)
for f in $BENCH_PY; do
	if python3 -m py_compile "$f"; then
		echo "ok   $f"
	else
		echo "FAILED $f"
		fail=1
	fi
done
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
	fail=1
elif ! pkg-config --exists libgpiod; then
	echo "libgpiod development files are not installed."
	echo "Run scripts/host-setup.sh, or: sudo apt-get install -y libgpiod-dev"
	fail=1
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
	fail=1
elif ! pkg-config --exists libdrm; then
	echo "libdrm development files are not installed."
	echo "Run scripts/host-setup.sh, or: sudo apt-get install -y libdrm-dev"
	fail=1
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

echo
if [ "$fail" -eq 0 ]; then
	echo "host checks passed. Next: ./go build"
else
	echo "host checks FAILED. Fix these before starting a three-hour build."
	exit 1
fi
