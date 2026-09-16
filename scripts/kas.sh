#!/bin/sh
#
# kas.sh - run kas against any configuration, in the right build directory.
#
#   scripts/kas.sh shell                    interactive, bench-rpi4
#   scripts/kas.sh shell bench-rt           interactive, another config
#   scripts/kas.sh bitbake bench-rt -c unpack virtual/kernel
#
# This exists because of a mistake that cost a kernel fetch and several
# gigabytes of a nearly full disk.
#
# Every build directory in this repository is decided by common.sh, which
# points KAS_WORK_DIR and KAS_BUILD_DIR at $BENCH_WORK. kas reads those from
# the environment; when they are absent it falls back to its own defaults,
# which are relative to the current directory. So this:
#
#     kas shell kas/bench-rt.yml -c 'bitbake -c unpack virtual/kernel'
#
# run from a checkout, quietly builds in <checkout>/build with its own
# <checkout>/downloads and <checkout>/sstate-cache, re-fetching everything
# the shared caches already hold. It does not fail. It produces a correct
# result in the wrong place, which is worse, because the next command you
# run looks in the right place and sees the previous project's tree.
#
# Anything that invokes kas goes through here so that cannot happen twice.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

usage() {
	sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

action=${1:-}
[ -n "$action" ] || usage
shift

# The configuration is optional for an interactive shell and required for a
# command, because a command run against the wrong configuration is the
# thing this script exists to prevent.
case ${1:-} in
bench-*)
	config=$1
	shift
	;;
*)
	if [ "$action" = bitbake ]; then
		die "which configuration? For example:
       ./go bitbake bench-rt -c unpack virtual/kernel"
	fi
	config=bench-rpi4
	;;
esac

kasfile=$REPO_DIR/kas/$config.yml
[ -f "$kasfile" ] || die "no such configuration: kas/$config.yml"

require_tool kas
require_no_running_build
warn_stray_build_tree

note "config     kas/$config.yml"
note "build dir  $KAS_BUILD_DIR"

case $action in
shell)
	[ $# -eq 0 ] || die "shell takes no further arguments; use: ./go bitbake"
	exec kas shell "$kasfile"
	;;
bitbake)
	[ $# -gt 0 ] || die "nothing to run. For example:
       ./go bitbake bench-rt -c unpack virtual/kernel"
	# kas takes one string, so the arguments are rejoined. They are
	# BitBake's own and are not reinterpreted here.
	exec kas shell "$kasfile" -c "bitbake $*"
	;;
*) usage ;;
esac
