#!/bin/sh
#
# debug-decode-test.sh - the oops decoder, without an oops.
#
# decode.sh wraps the kernel's own decode_stacktrace.sh, and it exists for
# one reason: that script picks its tools with
#
#     UTIL_PREFIX=${CROSS_COMPILE:-}
#     ADDR2LINE=${UTIL_PREFIX}addr2line
#
# so with CROSS_COMPILE unset on an x86 host it runs the host addr2line
# against an arm64 vmlinux and prints "??:0" for every line. That is not
# an error anybody would recognise: a page of "??:0" reads as a kernel
# built without debug information.
#
# So the assertions here are mostly about the prefix. The one that
# matters most is the last: with no cross toolchain anywhere, the script
# must REFUSE rather than fall through to the host tools and produce a
# confident page of nonsense.
#
# decode_stacktrace.sh itself is a stub that records its arguments and
# its stdin, because what is being tested is how it is called, not what
# it does.
#
#   sh tests/debug-decode-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/projects/09-kernel-debug/host/decode.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN=$WORK/bin
mkdir -p "$BIN"

pass=0
fail=0

check() {
	if [ "$2" = "$3" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: wanted '$3', got '$2'"
		fail=$((fail + 1))
	fi
}

contains() {
	case $2 in
	*"$3"*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	*)
		echo "FAILED   $1: '$3' not in output"
		echo "$2" | sed 's/^/           /'
		fail=$((fail + 1))
		;;
	esac
}

# ------------------------------------------------------------- the inputs
VMLINUX=$WORK/vmlinux
LOG=$WORK/oops.log
MODDIR=$WORK/modules
mkdir -p "$MODDIR"
: >"$VMLINUX"
: >"$MODDIR/buggy.ko"

# A real enough oops for the stub to echo back.
cat >"$LOG" <<'EOF'
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
Call trace:
 fault_null+0x1c/0x30 [buggy]
 trigger_write+0x64/0xd0 [buggy]
EOF

# ------------------------------------------------------------- the stubs
DECODE=$WORK/decode_stacktrace.sh
cat >"$DECODE" <<'EOF'
#!/bin/sh
echo "$@" >"$ARGV_RECORD"
cat >"$STDIN_RECORD"
echo "CROSS_COMPILE=${CROSS_COMPILE:-UNSET}" >"$ENV_RECORD"
EOF
chmod 0755 "$DECODE"

make_addr2line() {
	cat >"$BIN/$1" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod 0755 "$BIN/$1"
}

ARGV_RECORD=$WORK/argv
STDIN_RECORD=$WORK/stdin
ENV_RECORD=$WORK/env
export ARGV_RECORD STDIN_RECORD ENV_RECORD

run() {
	rm -f "$ARGV_RECORD" "$STDIN_RECORD" "$ENV_RECORD"
	env -u CROSS_COMPILE PATH="$BIN:/usr/bin:/bin" \
		DECODE_STACKTRACE="$DECODE" \
		ARGV_RECORD="$ARGV_RECORD" STDIN_RECORD="$STDIN_RECORD" \
		ENV_RECORD="$ENV_RECORD" \
		sh "$SUT" "$@" 2>&1
}

# ----------------------------------------- no cross toolchain at all
#
# THE IMPORTANT ONE. Nothing named *addr2line is on PATH, so the script
# has no way to decode an arm64 vmlinux and must say so.
rc=0
out=$(run "$VMLINUX" "$LOG") || rc=$?
check "with no aarch64 addr2line, decoding is refused" "$rc" "1"
contains "the refusal explains what would otherwise happen" "$out" "??:0"
contains "the refusal offers a package to install" "$out" "binutils-aarch64"
check "and decode_stacktrace.sh was never reached" \
	"$(cat "$ARGV_RECORD" 2>/dev/null || echo NOT-RUN)" "NOT-RUN"

# ------------------------------------------- a cross toolchain is found
make_addr2line aarch64-linux-gnu-addr2line
rc=0
out=$(run "$VMLINUX" "$LOG") || rc=$?
check "with a cross addr2line, it runs" "$rc" "0"
check "the prefix is exported for decode_stacktrace.sh" \
	"$(cat "$ENV_RECORD")" "CROSS_COMPILE=aarch64-linux-gnu-"
contains "the chosen toolchain is named in the output" \
	"$out" "aarch64-linux-gnu-addr2line"
check "the base path is auto, not a guessed source root" \
	"$(cat "$ARGV_RECORD")" "$VMLINUX auto"
contains "the log reaches the script on stdin" \
	"$(cat "$STDIN_RECORD")" "fault_null"

# A missing modules directory is a real limitation, so it is stated
# rather than left for the reader to discover from unresolved addresses.
contains "without a modules directory, the limitation is named" \
	"$out" "buggy.ko"

# ------------------------------------------------ with a modules directory
rc=0
out=$(run "$VMLINUX" "$LOG" "$MODDIR") || rc=$?
check "the modules directory is passed through" \
	"$(cat "$ARGV_RECORD")" "$VMLINUX auto $MODDIR"
contains "and named in the output" "$out" "$MODDIR"

# ------------------------------------------- an explicit CROSS_COMPILE wins
rm -f "$BIN/aarch64-linux-gnu-addr2line"
make_addr2line aarch64-poky-linux-addr2line
rc=0
out=$(CROSS_COMPILE=aarch64-poky-linux- \
	env PATH="$BIN:/usr/bin:/bin" DECODE_STACKTRACE="$DECODE" \
	ARGV_RECORD="$ARGV_RECORD" STDIN_RECORD="$STDIN_RECORD" \
	ENV_RECORD="$ENV_RECORD" \
	sh "$SUT" "$VMLINUX" "$LOG" 2>&1) || rc=$?
check "an explicit CROSS_COMPILE is used as given" "$rc" "0"
check "and is not overridden by the search" \
	"$(cat "$ENV_RECORD")" "CROSS_COMPILE=aarch64-poky-linux-"

# --------------------------------- an explicit prefix that does not exist
#
# The prefix is set but the tool is absent. Falling through to the host
# toolchain here would be the same silent wrong answer, so it is refused
# and the refusal names the prefix it wanted.
rc=0
out=$(CROSS_COMPILE=aarch64-nonesuch- \
	env PATH="$BIN:/usr/bin:/bin" DECODE_STACKTRACE="$DECODE" \
	sh "$SUT" "$VMLINUX" "$LOG" 2>&1) || rc=$?
check "a CROSS_COMPILE whose addr2line is missing is refused" "$rc" "1"
contains "the refusal names the prefix it wanted" "$out" "aarch64-nonesuch-"

# ------------------------------------------------------- argument checking
rc=0
out=$(run "$VMLINUX" 2>&1) || rc=$?
check "too few arguments is a usage error" "$rc" "1"
contains "the usage names the three arguments" "$out" "modules dir"

rc=0
out=$(run "$WORK/no-such-vmlinux" "$LOG" 2>&1) || rc=$?
check "a missing vmlinux is refused" "$rc" "1"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
