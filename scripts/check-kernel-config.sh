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

fragment=$REPO_DIR/meta-bench/recipes-kernel/linux/files/bench.cfg
[ -f "$fragment" ] || die "no fragment at $fragment"

config=$(find "$KAS_BUILD_DIR/tmp/work" -path '*linux-raspberrypi*' \
	-name '.config' -newer "$fragment" 2>/dev/null | sort | tail -1)
[ -n "$config" ] ||
	config=$(find "$KAS_BUILD_DIR/tmp/work" -path '*linux-raspberrypi*' \
		-name '.config' 2>/dev/null | sort | tail -1)
[ -n "$config" ] || die "no built kernel .config found. Build first, and keep
       RM_WORK_EXCLUDE containing linux-raspberrypi."

note "fragment $fragment"
note "config   $config"

fail=0
while IFS= read -r line; do
	case $line in
	'' | '#'*'is not set')
		# "# CONFIG_X is not set" is a request, so check it too.
		sym=$(echo "$line" | sed -n 's/^# \(CONFIG_[A-Z0-9_]*\) is not set$/\1/p')
		[ -n "$sym" ] || continue
		if grep -q "^${sym}=" "$config"; then
			echo "MISMATCH  $sym is set, fragment asks for it to be off"
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
done <"$fragment"

[ "$fail" -eq 0 ] || die "the fragment did not fully reach the kernel."
note "every option in the fragment is in the built .config"
