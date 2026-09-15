#!/bin/sh
#
# check-kernel-symbols.sh - is every line of a fragment a real request?
#
#   ./go ksym                      bench.cfg against the unpacked kernel
#   ./go ksym -f rt                bench.cfg and rt.cfg
#   ./go ksym -f router /path/to/linux
#
# This is the check that runs BEFORE a kernel is compiled, and it exists
# because ./go kconfig cannot. That one compares a fragment against a
# .config, which only exists after do_compile, so a fragment line that was
# never a Kconfig symbol survives a full build and is found at the end of
# it. Project 15 paid for that: router.cfg asked for CONFIG_NFT_CHAIN_NAT,
# CONFIG_NFT_RT and CONFIG_NFT_EXTHDR, none of which is a symbol, and the
# bill was one build cycle.
#
# The kernel source is unpacked by do_unpack, minutes into a build rather
# than hours, and it is all this needs.
#
# Two things are checked, and they fail for different reasons.
#
#   MISSING    The symbol is not declared anywhere in the tree. The line is
#              a typo, a symbol from another kernel version, or a module
#              object mistaken for a config option. It does nothing and it
#              always will. This is an error.
#
#   PROMPTLESS The symbol exists but has no prompt, so kconfig will not let
#              a fragment set it: it is chosen for you by whatever selects
#              it. A line like that is not a request, it is a prediction,
#              and it passes ./go kconfig for the wrong reason, which is
#              worse than failing. It is allowed only when the fragment
#              says so, on the line above:
#
#                  # consequence: selected by arch/arm64/Kconfig
#                  CONFIG_IRQ_FORCED_THREADING=y
#
#              The script then prints what actually selects it, so the
#              claim in the comment can be checked rather than believed.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

# Overridable so that tests/kernel-symbols-test.sh can point both halves of
# this script, the fragments and the tree, at a few hundred bytes of fake
# kernel instead of a gigabyte of real one.
FRAGMENT_DIR=${BENCH_FRAGMENT_DIR:-$REPO_DIR/meta-bench/recipes-kernel/linux/files}

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

# The kernel source, unpacked by BitBake.
#
# Not under tmp/work, which is where this first looked and found nothing.
# kernel.bbclass sets S to STAGING_KERNEL_DIR, and bitbake.conf defines
# that as ${TMPDIR}/work-shared/${MACHINE}/kernel-source: one shared tree
# per machine rather than one per recipe, so that a kernel and its modules
# build against the same sources. Only an alternate kernel recipe, meaning
# one whose KERNEL_PACKAGE_NAME is not "kernel", gets a kernel-source
# directory under its own WORKDIR instead.
#
# Both are covered by looking for the directory name rather than for a
# path shape, which is also why this does not try to match
# "linux-raspberrypi" anywhere: the name of the recipe is not the name of
# the directory its source lands in.
if [ -n "${1:-}" ]; then
	src=$1
else
	src=$(find "$KAS_BUILD_DIR/tmp/work-shared" "$KAS_BUILD_DIR/tmp/work" \
		-maxdepth 4 -type d -name kernel-source \
		-exec test -f "{}/Kconfig" ";" -print 2>/dev/null |
		sort | tail -1)
fi

[ -n "${src:-}" ] || die "no unpacked kernel source found under
       $KAS_BUILD_DIR/tmp/work-shared or tmp/work.

       It appears after do_unpack, which is minutes into a build rather
       than hours:

           kas shell kas/bench-rt.yml -c 'bitbake -c unpack virtual/kernel'

       and lands in tmp/work-shared/<machine>/kernel-source. Or pass a tree
       directly:

           ./go ksym -f rt ~/linux"

[ -f "$src/Kconfig" ] || die "$src has no Kconfig; that is not a kernel tree"

note "kernel   $src"

# One pass over the tree rather than one per symbol. A kernel has some two
# thousand Kconfig files and thirty thousand symbols, and grepping it once
# takes a second where grepping it thirty times takes a minute.
#
# The "|| true" on the greps below is not defensive clutter. Under set -e a
# grep that matches nothing returns 1 and takes the script with it, and the
# first run of this script proved how bad that is here: the branch that
# reports a symbol as missing was killed by the very grep that found it
# missing, so the check printed nothing and exited quietly. A checker that
# fails silently is worse than no checker. Its own test caught it.
index=$(mktemp)
selectors=$(mktemp)
trap 'rm -f "$index" "$selectors"' EXIT

grep -rn --include="Kconfig*" -E \
	"^[[:space:]]*(menu)?config[[:space:]]+[A-Za-z0-9_]+" "$src" \
	>"$index" 2>/dev/null || true

grep -rn --include="Kconfig*" -E \
	"^[[:space:]]*(select|imply)[[:space:]]+[A-Za-z0-9_]+" "$src" \
	>"$selectors" 2>/dev/null || true

note "symbols  $(wc -l <"$index" | tr -d ' ') declarations indexed"

# Does the block starting at FILE:LINE carry a prompt? A prompt is either a
# quoted string on the type line, or a standalone prompt line, which is how
# a conditionally visible symbol such as GPIO_CDEV is written.
#
# Both quote characters count. Kconfig accepts single quotes and the kernel
# uses them: net/netfilter/Kconfig alone has eighty-one of them, so a check
# that only knew about double quotes would call eighty-one ordinary
# settable symbols promptless, in one file. It did, until this test tree
# grew a netfilter Kconfig.
has_prompt() {
	file=$1
	line=$2
	sed -n "$((line + 1)),$((line + 40))p" "$file" |
		awk -v sq="'" '
		/^[ \t]*(menu)?config[ \t]/ { exit }
		/^[ \t]*(endmenu|endif|endchoice)/ { exit }
		/^[ \t]*(bool|tristate|int|hex|string|prompt)[ \t]/ {
			rest = $0
			sub(/^[ \t]*(bool|tristate|int|hex|string|prompt)[ \t]+/, \
				"", rest)
			first = substr(rest, 1, 1)
			if (first == "\"" || first == sq) { print "yes"; exit }
		}
		'
}

fail=0
promptless=0
checked=0
missing=0
declared=$(wc -l <"$index" | tr -d ' ')

check_fragment() {
	frag=$1
	note "fragment $frag"
	marker=no

	while IFS= read -r line; do
		case $line in
		"# consequence:"*)
			marker=yes
			continue
			;;
		CONFIG_*)
			sym=${line%%=*}
			sym=${sym#CONFIG_}
			;;
		"# CONFIG_"*"is not set")
			sym=$(echo "$line" |
				sed -n 's/^# CONFIG_\([A-Za-z0-9_]*\) is not set$/\1/p')
			[ -n "$sym" ] || { marker=no; continue; }
			;;
		*)
			# Any other line, comment or blank, ends the marker's
			# reach. It has to sit directly above what it excuses.
			marker=no
			continue
			;;
		esac

		checked=$((checked + 1))
		hits=$(grep -E "(menu)?config[[:space:]]+${sym}[[:space:]]*\$" \
			"$index" 2>/dev/null || true)

		if [ -z "$hits" ]; then
			echo "MISSING     CONFIG_$sym is not declared anywhere"
			echo "            in this kernel. The line does nothing."
			missing=$((missing + 1))
			fail=1
			marker=no
			continue
		fi

		prompt=
		for hit in $(echo "$hits" | cut -d: -f1,2 | tr '\n' ' '); do
			file=${hit%%:*}
			num=${hit##*:}
			if [ "$(has_prompt "$file" "$num")" = yes ]; then
				prompt=$file
				break
			fi
		done

		if [ -n "$prompt" ]; then
			echo "ok          CONFIG_$sym  ${prompt#"$src"/}"
			marker=no
			continue
		fi

		promptless=$((promptless + 1))
		who=$(grep -E "(select|imply)[[:space:]]+${sym}[[:space:]]*(\$|if )" \
			"$selectors" 2>/dev/null | head -3 |
			sed "s|^$src/||" | cut -d: -f1 | sort -u | tr '\n' ' ')

		if [ "$marker" = yes ]; then
			echo "consequence CONFIG_$sym  promptless, selected by:" \
				"${who:-nothing found}"
		else
			echo "PROMPTLESS  CONFIG_$sym has no prompt, so a fragment"
			echo "            cannot set it. Selected by:" \
				"${who:-nothing found}"
			echo "            Either drop the line, or mark it:"
			echo "            # consequence: <why it will be right anyway>"
			fail=1
		fi
		marker=no
	done <"$frag"
}

for name in $fragments; do
	check_fragment "$FRAGMENT_DIR/$name.cfg"
done

echo
if [ "$fail" -eq 0 ]; then
	note "$checked symbols, all real, $promptless recorded as consequences"
	note "Next: build, then ./go kconfig to check the values reached it"
	exit 0
fi

# A partial tree produces MISSING for symbols that exist perfectly well in
# the part that is absent, and a wall of those reads as a broken fragment
# rather than as a broken input. A whole kernel declares tens of thousands
# of symbols; anything near a thousand is a handful of files.
if [ "$missing" -gt 0 ] && [ "$declared" -lt 5000 ]; then
	echo "note: this tree declares only $declared symbols, which is not a"
	echo "      whole kernel. Some of the MISSING lines above are likely"
	echo "      symbols living in a part of the tree that is not here."
fi

die "a fragment line is not the request it looks like. See above."
