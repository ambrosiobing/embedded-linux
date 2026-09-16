#!/bin/sh
#
# kernel-symbols-test.sh - the pre-build fragment check, against a kernel
# tree of six files.
#
# The check itself needs an unpacked kernel, which is a gigabyte and only
# exists on a build host. What it does with that kernel is pure text: find
# a symbol's declaration, decide whether it carries a prompt, and find what
# selects it. All three can be exercised against a few hundred bytes of
# Kconfig that reproduces the shapes a real tree contains.
#
# The shapes that matter, and all five are here:
#
#   config X / bool "..."        the ordinary case
#   menuconfig X / bool "..."    a subsystem head, which IIO and FTRACE are
#   config X / bool / prompt ... a conditionally visible symbol, which is
#                                how GPIO_CDEV is written, and which a
#                                naive check calls promptless
#   config X / bool 'single'     Kconfig takes either quote, and the kernel
#                                uses both
#   config X / bool              genuinely promptless, settable only by
#                                whatever selects it
#
# The last one is the whole point. A fragment line for a promptless symbol
# is a prediction rather than a request, it passes ./go kconfig for the
# wrong reason, and this is the only check that can tell the difference.
#
# Two of these shapes are here because the check got them wrong first. The
# single-quoted prompt made it call eighty-one ordinary netfilter symbols
# promptless; the missing-symbol branch was killed by its own grep under
# set -e and printed nothing at all.
#
#   sh tests/kernel-symbols-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/check-kernel-symbols.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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

# -------------------------------------------------------- a fake kernel

SRC=$WORK/linux
mkdir -p "$SRC/kernel/irq" "$SRC/drivers/gpio" "$SRC/drivers/iio" \
	"$SRC/arch/arm64" "$SRC/net"

# The root Kconfig is what the script uses to decide this is a kernel.
cat >"$SRC/Kconfig" <<'EOF'
mainmenu "Fake Kernel Configuration"
source "kernel/irq/Kconfig"
EOF

cat >"$SRC/kernel/irq/Kconfig" <<'EOF'
config IRQ_FORCED_THREADING
	bool

config SPARSE_IRQ
	bool "Support sparse irq numbering"
	help
	  Ordinary symbol with an ordinary prompt.
EOF

# A prompt on its own line, conditional on EXPERT. This is how GPIO_CDEV is
# written in a real tree, and reading only the line after "config" calls it
# promptless, which it is not.
cat >"$SRC/drivers/gpio/Kconfig" <<'EOF'
config GPIO_CDEV
	bool
	prompt "Character device (/dev/gpiochipN) support" if EXPERT
	default y

config GPIO_CDEV_V1
	bool "Support GPIO ABI Version 1"
	default y
	depends on GPIO_CDEV
EOF

cat >"$SRC/drivers/iio/Kconfig" <<'EOF'
menuconfig IIO
	tristate "Industrial I/O support"
	help
	  A subsystem head. Declared with menuconfig, not config.

config IIO_BUFFER
	bool "Enable buffer support within IIO"
	depends on IIO
EOF

# Kconfig takes single quotes too, and the kernel uses them: eighty-one
# times in net/netfilter/Kconfig alone. A check that only knows double
# quotes calls every one of them promptless.
cat >"$SRC/net/Kconfig" <<'EOF'
config NF_CONNTRACK_TIMESTAMP
	bool  'Connection tracking timestamping'
	depends on NETFILTER_ADVANCED
EOF

cat >"$SRC/arch/arm64/Kconfig" <<'EOF'
config ARM64
	def_bool y
	select ARCH_SUPPORTS_RT
	select IRQ_FORCED_THREADING
	select GPIO_CDEV
EOF

FRAGS=$WORK/files
mkdir -p "$FRAGS"
export BENCH_FRAGMENT_DIR="$FRAGS"

run() {
	rc=0
	out=$(sh "$SUT" "$@" "$SRC" 2>&1) || rc=$?
	printf '%s' "$out"
}

# ------------------------------------------------- every shape resolves

cat >"$FRAGS/bench.cfg" <<'EOF'
# The shapes a real tree contains.
CONFIG_SPARSE_IRQ=y
CONFIG_GPIO_CDEV=y
CONFIG_IIO=y
CONFIG_IIO_BUFFER=y
CONFIG_NF_CONNTRACK_TIMESTAMP=y
# CONFIG_GPIO_CDEV_V1 is not set
EOF

rc=0
out=$(sh "$SUT" "$SRC" 2>&1) || rc=$?
check "a fragment of real symbols passes" "$rc" "0"
contains "an ordinary symbol is found" "$out" "ok          CONFIG_SPARSE_IRQ"
contains "a standalone prompt line counts as a prompt" "$out" \
	"ok          CONFIG_GPIO_CDEV "
contains "menuconfig counts as a declaration" "$out" "ok          CONFIG_IIO "
contains "an is-not-set line is checked too" "$out" \
	"ok          CONFIG_GPIO_CDEV_V1"
contains "a single-quoted prompt counts as a prompt" "$out" \
	"ok          CONFIG_NF_CONNTRACK_TIMESTAMP"
contains "the count is reported" "$out" "6 symbols, all real"

# --------------------------------------------- a symbol that is not one

cat >"$FRAGS/bench.cfg" <<'EOF'
CONFIG_SPARSE_IRQ=y
CONFIG_NFT_CHAIN_NAT=y
EOF

rc=0
out=$(sh "$SUT" "$SRC" 2>&1) || rc=$?
check "an undeclared symbol fails the check" "$rc" "1"
contains "and is named" "$out" "MISSING     CONFIG_NFT_CHAIN_NAT"
contains "and says what it means" "$out" "The line does nothing"
# A partial tree makes real symbols look missing, and a wall of those reads
# as a broken fragment rather than a broken input. Say which it is.
contains "and warns that this tree is too small to trust" "$out" \
	"is not a"

# ------------------------------------- a promptless symbol, unannounced

cat >"$FRAGS/bench.cfg" <<'EOF'
CONFIG_IRQ_FORCED_THREADING=y
EOF

rc=0
out=$(sh "$SUT" "$SRC" 2>&1) || rc=$?
check "a promptless symbol fails when it is presented as a request" \
	"$rc" "1"
contains "and is named" "$out" "PROMPTLESS  CONFIG_IRQ_FORCED_THREADING"
contains "and the selector is found for you" "$out" "arch/arm64/Kconfig"
contains "and the fix is offered" "$out" "# consequence:"

# ---------------------------------------- the same symbol, acknowledged

cat >"$FRAGS/bench.cfg" <<'EOF'
# consequence: promptless, selected by arch/arm64/Kconfig
CONFIG_IRQ_FORCED_THREADING=y
EOF

rc=0
out=$(sh "$SUT" "$SRC" 2>&1) || rc=$?
check "a promptless symbol passes when it is declared a consequence" \
	"$rc" "0"
contains "and is reported as one" "$out" \
	"consequence CONFIG_IRQ_FORCED_THREADING"
contains "with the selector printed, so the claim can be checked" "$out" \
	"arch/arm64/Kconfig"
contains "and it is counted separately" "$out" "1 recorded as consequences"

# ------------------------------- the marker has to sit directly above it

cat >"$FRAGS/bench.cfg" <<'EOF'
# consequence: promptless, selected by arch/arm64/Kconfig

CONFIG_IRQ_FORCED_THREADING=y
EOF

rc=0
out=$(sh "$SUT" "$SRC" 2>&1) || rc=$?
check "a marker separated by a blank line does not carry" "$rc" "1"

# --------------------------------------------- a second fragment, by -f

cat >"$FRAGS/bench.cfg" <<'EOF'
CONFIG_SPARSE_IRQ=y
EOF
cat >"$FRAGS/rt.cfg" <<'EOF'
CONFIG_NOT_A_SYMBOL_AT_ALL=y
EOF

rc=0
out=$(sh "$SUT" -f rt "$SRC" 2>&1) || rc=$?
check "-f adds a second fragment" "$rc" "1"
contains "and both are read" "$out" "bench.cfg"
contains "including the one named" "$out" "CONFIG_NOT_A_SYMBOL_AT_ALL"

rc=0
out=$(sh "$SUT" -f nosuch "$SRC" 2>&1) || rc=$?
check "a fragment that does not exist is an error" "$rc" "1"
contains "and says which" "$out" "nosuch.cfg"

# ------------------------------------- finding the tree without being told
#
# This is the part that was wrong first. The search looked under tmp/work
# for a path containing the recipe name, and BitBake does not put the
# kernel there: kernel.bbclass sets S to STAGING_KERNEL_DIR, which
# bitbake.conf defines as tmp/work-shared/<machine>/kernel-source. The
# script found nothing and said so, which on a build host reads as a
# failed unpack rather than as a wrong search.

cat >"$FRAGS/bench.cfg" <<'EOF'
CONFIG_SPARSE_IRQ=y
EOF

SHARED=$WORK/bench/build/tmp/work-shared/raspberrypi4-64
mkdir -p "$SHARED"
cp -r "$SRC" "$SHARED/kernel-source"

rc=0
out=$(BENCH_WORK=$WORK/bench sh "$SUT" 2>&1) || rc=$?
check "the kernel is found where BitBake actually puts it" "$rc" "0"
contains "and the path is reported" "$out" "work-shared/raspberrypi4-64/kernel-source"

# An alternate kernel recipe, one whose KERNEL_PACKAGE_NAME is not
# "kernel", gets its own kernel-source under WORKDIR instead.
rm -rf "$WORK/bench/build/tmp/work-shared"
ALT=$WORK/bench/build/tmp/work/raspberrypi4_64-poky-linux/linux-other/1.0
mkdir -p "$ALT"
cp -r "$SRC" "$ALT/kernel-source"
rc=0
out=$(BENCH_WORK=$WORK/bench sh "$SUT" 2>&1) || rc=$?
check "and under a recipe work directory when it lives there" "$rc" "0"

rm -rf "$WORK/bench"
rc=0
out=$(BENCH_WORK=$WORK/bench sh "$SUT" 2>&1) || rc=$?
check "an unbuilt tree is an error, not an empty pass" "$rc" "1"
contains "and it says where it looked" "$out" "work-shared"
# kernel_configme, not unpack: do_unpack empties STAGING_KERNEL_DIR and
# do_kernel_checkout is what fills it, so the advice has to name a task
# that actually leaves a tree behind.
contains "and how to produce one" "$out" "-c kernel_configme virtual/kernel"

# ------------------------------------------------- not a kernel at all

cat >"$FRAGS/bench.cfg" <<'EOF'
CONFIG_SPARSE_IRQ=y
EOF
mkdir -p "$WORK/notakernel"
rc=0
out=$(sh "$SUT" "$WORK/notakernel" 2>&1) || rc=$?
check "a directory with no root Kconfig is refused" "$rc" "1"
contains "and says why" "$out" "not a kernel tree"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
