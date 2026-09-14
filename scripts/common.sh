# Shared settings for the bench scripts. Sourced, never executed.
# SPDX-License-Identifier: MIT

set -eu

# Used by the scripts that source this file, which shellcheck cannot see.
# shellcheck disable=SC2034
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd) || exit 1

# Everything BitBake writes goes here: the cloned layers, the build tree and
# the two caches. Keep it on a native Linux file system.
BENCH_WORK=${BENCH_WORK:-$HOME/bench}

KAS_WORK_DIR=$BENCH_WORK
KAS_BUILD_DIR=$BENCH_WORK/build
export KAS_WORK_DIR KAS_BUILD_DIR

die() {
	echo "error: $*" >&2
	exit 1
}

note() {
	echo "--- $*"
}

# A case-insensitive file system silently corrupts a BitBake build: two
# recipes whose names differ only in case become one file. Windows mounts
# under WSL2 are the usual route to that, and they are also slow enough to
# turn a three-hour build into an overnight one.
require_case_sensitive() {
	dir=$1
	case $dir in
	/mnt/*) die "$dir is a Windows mount. Use a path under HOME instead." ;;
	esac

	mkdir -p "$dir"
	probe=$dir/.bench-case-probe
	rm -f "$probe" "$dir/.bench-case-PROBE" 2>/dev/null || true
	: >"$probe"
	if [ -e "$dir/.bench-case-PROBE" ]; then
		rm -f "$probe"
		die "$dir is case-insensitive; build inside the Linux file system."
	fi
	rm -f "$probe"
}

require_disk_gb() {
	dir=$1
	want=$2
	mkdir -p "$dir"
	have=$(df -BG --output=avail "$dir" 2>/dev/null | tail -1 | tr -dc '0-9')
	[ -n "${have:-}" ] || return 0
	[ "$have" -ge "$want" ] ||
		die "$dir has ${have} GB free, the build needs ${want} GB."
}

require_tool() {
	command -v "$1" >/dev/null 2>&1 ||
		die "$1 is not installed. Run scripts/host-setup.sh."
}
