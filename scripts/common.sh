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

# BitBake keeps one memory-resident server per build directory, so a second
# run does not run alongside the first: it waits on the handshake and prints
# "Retrying server connection" every thirty seconds, forever, with no hint
# that another build is the reason.
require_no_running_build() {
	if pgrep -f 'bitbake/bin/bitbake' >/dev/null 2>&1; then
		die "another BitBake run already owns this build directory.
       BitBake allows one at a time per build dir. Let the first finish, or
       stop it, then run this again."
	fi
}

# Under WSL the guest filesystem reports the virtual disk maximum, not what
# Windows can actually supply. The VHDX grows on demand out of the host
# drive, so a build can exhaust Windows while the guest still claims
# hundreds of free gigabytes. Not hypothetical: it filled a 254 GB system
# drive to zero here and took the filesystem read-only in the middle of an
# SDK build.
require_host_disk_gb() {
	want=$1
	[ -d /mnt/c ] || return 0
	have=$(df -BG --output=avail /mnt/c 2>/dev/null | tail -1 | tr -dc "0-9")
	[ -n "${have:-}" ] || return 0
	if [ "$have" -lt "$want" ]; then
		die "the Windows drive behind WSL has ${have} GB free and this needs
       ${want} GB there. The guest will report far more, because the virtual
       disk grows on demand out of exactly this space."
	fi
}

require_tool() {
	command -v "$1" >/dev/null 2>&1 ||
		die "$1 is not installed. Run scripts/host-setup.sh."
}

# A build directory inside the checkout is not a build directory anyone
# asked for. kas falls back to paths relative to the current directory when
# KAS_WORK_DIR and KAS_BUILD_DIR are absent from the environment, so a bare
# "kas shell kas/<config>.yml" run from a checkout builds there, with its
# own downloads and sstate-cache, re-fetching what the shared caches
# already hold.
#
# It is a warning rather than an error because the tree is harmless once
# noticed, and deleting several gigabytes of somebody else's work is not a
# decision a helper function should take. .gitignore already keeps it out
# of commits; what it cannot do is say where the build actually went.
warn_stray_build_tree() {
	[ -d "$REPO_DIR/build" ] || return 0
	echo "warning: there is a build tree inside the checkout at" >&2
	echo "         $REPO_DIR/build" >&2
	echo "         Something ran kas without KAS_BUILD_DIR set, so it built" >&2
	echo "         there instead of in $BENCH_WORK, with its own caches." >&2
	echo "         Nothing here uses it. Once you are sure, remove it and" >&2
	echo "         its downloads and sstate-cache siblings." >&2
}
