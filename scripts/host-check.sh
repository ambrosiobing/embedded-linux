#!/bin/sh
#
# host-check.sh - everything that can be proven in two minutes, before
# committing to a build that takes three hours.
#
# The cross build is the only way to prove the recipe, but it is not the
# only way to prove the source. libgpiod on Ubuntu 24.04 and Debian 13 is
# v2, the same API the daemon targets, so the host compiler catches a typo
# in the GPIO calls long before BitBake would.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

cd "$REPO_DIR"
fail=0

step() {
	printf '\n--- %s\n' "$1"
}

step "static layer checks"
python3 scripts/lint.py || fail=1

step "shell files parse"
# Always available, unlike shellcheck, and it catches the one thing
# that matters most after a copy between machines.
BENCH_SH="go scripts/*.sh tests/*.sh meta-bench/recipes-bench/bench-status/files/bench-state"
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
	shellcheck -s sh -e SC1090,SC1091 \
		go scripts/*.sh tests/*.sh \
		meta-bench/recipes-bench/bench-status/files/bench-state || fail=1
else
	echo "shellcheck absent, skipped (scripts/host-setup.sh installs it)"
fi

step "state machine"
sh tests/bench-state-test.sh || fail=1

step "compile the daemon against host libgpiod"
if pkg-config --exists libgpiod; then
	version=$(pkg-config --modversion libgpiod)
	echo "libgpiod $version"
	case $version in
	2.*) ;;
	*) echo "warning: this is libgpiod v$version; the daemon targets v2" ;;
	esac

	out=$(mktemp -d)/bench-status
	# Stricter than the recipe on purpose: a warning should surface here.
	if gcc -Wall -Wextra -Werror -O2 \
		$(pkg-config --cflags libgpiod) \
		meta-bench/recipes-bench/bench-status/files/bench-status.c \
		-o "$out" $(pkg-config --libs libgpiod); then
		echo "compiled clean"
		# No GPIO chip on most hosts, so exit 1 is the correct outcome.
		if timeout 5 "$out"; then
			echo "note: this host has a usable GPIO chip"
		else
			echo "runs and reports no usable chip, as expected off-target"
		fi
	else
		fail=1
	fi
else
	echo "libgpiod-dev absent, skipped (scripts/host-setup.sh installs it)"
fi

step "compile the SDK example against host libgpiod"
if pkg-config --exists libgpiod; then
	make -C sdk/hello-gpiod clean >/dev/null 2>&1 || true
	make -C sdk/hello-gpiod || fail=1
	make -C sdk/hello-gpiod clean >/dev/null 2>&1 || true
else
	echo "skipped"
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "host checks passed. Next: ./go build"
else
	echo "host checks FAILED. Fix these before starting a three-hour build."
	exit 1
fi
