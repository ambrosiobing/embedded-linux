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

# Every shell file in the repository. common.sh is included: it is sourced
# rather than run, but it still has to parse.
BENCH_SH="go scripts/*.sh tests/*.sh \
meta-bench/recipes-bench/bench-status/files/bench-state"

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

	step "compile the SDK example against host libgpiod"
	make -C sdk/hello-gpiod clean >/dev/null 2>&1 || true
	if make -C sdk/hello-gpiod; then
		echo "SDK example compiled"
	else
		fail=1
	fi
	make -C sdk/hello-gpiod clean >/dev/null 2>&1 || true
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "host checks passed. Next: ./go build"
else
	echo "host checks FAILED. Fix these before starting a three-hour build."
	exit 1
fi
