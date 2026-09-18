#!/bin/sh
# Turn a raw oops into one with file names and line numbers.
#
#   ./projects/09-kernel-debug/host/decode.sh vmlinux oops.log
#   ./projects/09-kernel-debug/host/decode.sh vmlinux oops.log ./modules
#
# THIS RUNS ON THE HOST. The board has neither the symbols nor the
# toolchain, and putting them there would be a debug image carrying its
# own debugger.
#
# WHAT IT WRAPS
#
# scripts/decode_stacktrace.sh from the kernel tree, whose usage is
#
#   decode_stacktrace.sh <vmlinux> [<base path>|auto] [<modules path>]
#
# reading the log on stdin. The wrapper exists for one reason that is not
# obvious from that line and costs an evening when it is missed.
#
# THE CROSS COMPILER PREFIX
#
# decode_stacktrace.sh picks its tools like this:
#
#     UTIL_PREFIX=${CROSS_COMPILE:-}
#     READELF=${UTIL_PREFIX}readelf
#     ADDR2LINE=${UTIL_PREFIX}addr2line
#
# With CROSS_COMPILE unset on an x86 host, it runs the HOST addr2line
# against an arm64 vmlinux. That does not fail cleanly: it either errors
# per address or returns "??:0" for every line, and a page of "??:0"
# reads as a stripped kernel rather than as the wrong tool.
#
# SPDX-License-Identifier: MIT
set -eu

die() {
	echo "decode.sh: $*" >&2
	exit 1
}

[ $# -ge 2 ] || die "usage: decode.sh <vmlinux> <oops.log> [<modules dir>]
    <vmlinux>     from the SAME build as the kernel that crashed
    <oops.log>    the console log, raw, including the Call trace lines
    <modules dir> directory holding buggy.ko, if the trace enters it"

VMLINUX="$1"
LOG="$2"
MODULES="${3:-}"

[ -f "$VMLINUX" ] || die "$VMLINUX is not a file"
[ -f "$LOG" ] || die "$LOG is not a file"

# --- find the kernel script ----------------------------------------------
# Not shipped here: it belongs to the kernel tree, and a copy would rot
# against the tree it is supposed to match.
DECODE="${DECODE_STACKTRACE:-}"
if [ -z "$DECODE" ]; then
	for candidate in \
		./scripts/decode_stacktrace.sh \
		"${KERNEL_SRC:-/nonexistent}/scripts/decode_stacktrace.sh" \
		"/lib/modules/$(uname -r)/build/scripts/decode_stacktrace.sh"
	do
		if [ -x "$candidate" ]; then
			DECODE="$candidate"
			break
		fi
	done
fi

[ -n "$DECODE" ] || die "decode_stacktrace.sh not found.
    It lives in the kernel source tree under scripts/. Point at it with:
        DECODE_STACKTRACE=/path/to/linux/scripts/decode_stacktrace.sh
    On the build laptop the kernel source is under the BitBake work
    directory; kas/bench-debug.yml keeps it by excluding
    linux-raspberrypi from rm_work."

# --- the cross prefix, which is the whole point of this wrapper ----------
if [ -z "${CROSS_COMPILE:-}" ]; then
	for prefix in aarch64-linux-gnu- aarch64-poky-linux- aarch64-none-linux-gnu-
	do
		if command -v "${prefix}addr2line" >/dev/null 2>&1; then
			CROSS_COMPILE="$prefix"
			break
		fi
	done
fi

[ -n "${CROSS_COMPILE:-}" ] || die "no aarch64 addr2line found, and
    CROSS_COMPILE is unset. Without it decode_stacktrace.sh silently uses
    the host's x86 addr2line on an arm64 vmlinux and prints ??:0 for every
    line, which looks like a kernel built without debug information.

    Either install a cross binutils:
        sudo apt-get install binutils-aarch64-linux-gnu
    or source the bench SDK, which brings its own:
        . /opt/poky/*/environment-setup-cortexa53-poky-linux
    then set CROSS_COMPILE to its prefix."

command -v "${CROSS_COMPILE}addr2line" >/dev/null 2>&1 ||
	die "CROSS_COMPILE is ${CROSS_COMPILE} but ${CROSS_COMPILE}addr2line
    is not on PATH. That prefix is what decode_stacktrace.sh will use."

export CROSS_COMPILE

# Say what was chosen. Every input this script picked for itself is named,
# so that a wrong answer can be argued with rather than only disbelieved.
echo "decode.sh: vmlinux     $VMLINUX" >&2
echo "decode.sh: script      $DECODE" >&2
echo "decode.sh: toolchain   ${CROSS_COMPILE}addr2line" >&2
if [ -n "$MODULES" ]; then
	echo "decode.sh: modules     $MODULES" >&2
else
	echo "decode.sh: modules     none given; addresses inside buggy.ko" >&2
	echo "decode.sh:             will stay unresolved. Pass the directory" >&2
	echo "decode.sh:             holding buggy.ko as the third argument." >&2
fi
echo >&2

# "auto" is the base path: decode_stacktrace.sh works it out from the
# vmlinux rather than being told a source root that is probably wrong on
# this machine anyway, since the kernel was built in a BitBake work
# directory that no longer exists at the same path.
if [ -n "$MODULES" ]; then
	exec "$DECODE" "$VMLINUX" auto "$MODULES" < "$LOG"
else
	exec "$DECODE" "$VMLINUX" auto < "$LOG"
fi
