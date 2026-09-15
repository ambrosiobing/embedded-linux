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

FRAGMENT_DIR=$REPO_DIR/meta-bench/recipes-kernel/linux/files

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

# The newest fragment is the reference for "is the built .config newer than
# what it was built from".
fragment=$FRAGMENT_DIR/bench.cfg

# An explicit config wins. The best one is the running kernel own config,
# taken from the board with "zcat /proc/config.gz", because it proves what
# the hardware is executing rather than what a build tree once contained.
if [ -n "${1:-}" ]; then
	[ -r "$1" ] || die "cannot read $1"
	config=$1
else
	config=$(find "$KAS_BUILD_DIR/tmp/work" -path "*linux-raspberrypi*" \
		-name ".config" -newer "$fragment" 2>/dev/null | sort | tail -1)
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
