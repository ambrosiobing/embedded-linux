#!/bin/sh
#
# check-kernel-config.sh - prove that the fragment reached the kernel.
#
# A fragment that is silently ignored is the classic Yocto trap: the build
# succeeds, the option is absent, and the driver fails on the board a week
# later. This compares every line of meta-bench/recipes-kernel/linux/files/bench.cfg
# against the .config that was actually built.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

# Overridable so that tests/kernel-config-test.sh can point the fragments
# and the build tree at a few hundred bytes of fake instead of a kernel.
FRAGMENT_DIR=${BENCH_FRAGMENT_DIR:-$REPO_DIR/meta-bench/recipes-kernel/linux/files}

# Which fragments to check. bench.cfg goes into every image; router.cfg and
# rt.cfg are opt in, so asking for them is opt in too:
#
#   ./go kconfig                     bench.cfg against the last build
#   ./go kconfig -f rt /tmp/config   bench.cfg and rt.cfg against a config
#                                    taken off the board
#
# Repeatable, because the real-time image gets both fragments and a check
# that only looked at one of them would pass on a kernel missing half of
# what was asked for.
fragments=
while [ $# -gt 0 ]; do
	case ${1:-} in
	-f)
		[ $# -ge 2 ] || die "-f needs a fragment name, such as: -f rt"
		fragments="$fragments $2"
		shift 2
		;;
	-*) die "unknown option: $1" ;;
	*) break ;;
	esac
done

fragments="bench$fragments"
for name in $fragments; do
	[ -f "$FRAGMENT_DIR/$name.cfg" ] ||
		die "no fragment at $FRAGMENT_DIR/$name.cfg"
done

# An explicit config wins. The best one is the running kernel own config,
# taken from the board with "zcat /proc/config.gz", because it proves what
# the hardware is executing rather than what a build tree once contained.
#
# This search used to carry "-newer $fragment", meaning to skip a .config
# older than the fragment it should have been built from. It was wrong
# twice over. Git sets mtime to checkout time, so any "git pull" that
# touches a fragment makes every existing .config look stale and the search
# returns nothing, which reports itself as "no built kernel .config found"
# and sends you hunting for a build problem that is not there. And the
# guard protected against nothing: a .config predating a fragment line is
# a .config missing that line, which this script already reports as a
# MISMATCH. An honest failure was being turned into a confusing absence.
# When several kernels have been built, take the most recently written
# .config, which is the one the last build produced.
#
# This used to be "sort | tail -1" over the paths, and that is a version
# sort done lexically, which gets kernel versions exactly backwards:
#
#   linux-raspberrypi/6.12.93+git/...    sorts first
#   linux-raspberrypi/6.6.63+git/...     sorts last, because "6" > "1"
#
# So after building the 6.12 real-time kernel it silently checked the 6.6
# one from the day before, reported CONFIG_PREEMPT_RT as missing, and the
# obvious reading of that is that the fragment failed. It had not; the
# check was looking at another kernel. Ranking by modification time cannot
# get this wrong, and unlike the mtime FILTER removed above it never
# excludes everything: there is always a newest.
if [ -n "${1:-}" ]; then
	[ -r "$1" ] || die "cannot read $1"
	config=$1
else
	config=$(find "$KAS_BUILD_DIR/tmp/work" -path "*linux-raspberrypi*" \
		-name ".config" -printf '%T@ %p\n' 2>/dev/null |
		newest_path ".config")
fi

if [ -z "$config" ]; then
	die "no built kernel .config found.

       A build that was a complete sstate hit never compiles the kernel,
       so no work directory exists for RM_WORK_EXCLUDE to preserve.
       Either force one with: bitbake -c compile -f virtual/kernel
       or pass the running kernel own config, which is better evidence:

           scp root@BOARD:/proc/config.gz /tmp/
           zcat /tmp/config.gz > /tmp/config
           ./go kconfig /tmp/config"
fi

note "config   $config"
# When it was built, so that a check passing against a week-old tree is
# visible rather than implied.
note "built    $(date -r "$config" '+%Y-%m-%d %H:%M' 2>/dev/null || echo unknown)"

fail=0

check_fragment() {
	file=$1
	note "fragment $file"
	while IFS= read -r line; do
		case $line in
		'' | '#'*'is not set')
			# "# CONFIG_X is not set" is a request, so check it too.
			sym=$(echo "$line" |
				sed -n 's/^# \(CONFIG_[A-Z0-9_]*\) is not set$/\1/p')
			[ -n "$sym" ] || continue
			if grep -q "^${sym}=" "$config"; then
				echo "MISMATCH  $sym is set, the fragment wants it off"
				fail=1
			else
				echo "ok        $sym off"
			fi
			;;
		'#'*) ;;
		CONFIG_*)
			if grep -qxF "$line" "$config"; then
				echo "ok        $line"
			else
				sym=${line%%=*}
				echo "MISMATCH  $line   (built: $(grep "^${sym}=" "$config" ||
					echo "not set"))"
				fail=1
			fi
			;;
		esac
	done <"$file"
}

for name in $fragments; do
	check_fragment "$FRAGMENT_DIR/$name.cfg"
done

[ "$fail" -eq 0 ] || die "the fragment did not fully reach the kernel."
note "every option in every checked fragment is in the built .config"
