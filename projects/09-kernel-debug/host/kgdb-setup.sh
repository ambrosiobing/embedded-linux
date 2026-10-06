#!/bin/sh
#
# kgdb-setup.sh - find everything entry 02 needs, then print the commands.
#
#   ./go kgdb-setup                  checks /dev/ttyUSB0
#   ./go kgdb-setup /dev/ttyUSB1     another adapter
#
# WHY THIS EXISTS
#
# Entry 02 is the only entry in this notebook whose procedure branches on
# what happens to be installed on the host and on where BitBake put three
# files. On Tuesday 6 October 2026 that procedure was handed over as prose
# three times, each version containing placeholders to be filled in by
# hand, and the reply was "why so vague". It was a fair question: a
# procedure with a placeholder in it is not a procedure. So this script
# finds the paths, says which candidates it rejected and why, and prints
# the exact commands with the paths already in them.
#
# IT STARTS NOTHING, ON PURPOSE. agent-proxy owns the USB adapter for a
# whole debugging session and blocks, so it needs a window of its own, and
# a setup script that backgrounded it would leave a process holding the
# cable with nothing naming it. This prepares, reports, and prints.
#
# WHAT IT DOES NOT CHECK, said here rather than left to be assumed:
#
#   - whether the vmlinux it finds is from the build now running on the
#     board. Nothing on this host can know that. host/gdbinit says the
#     same thing at more length, and it is the failure that has cost this
#     project more time than any bug.
#   - whether the board is powered, wired or reachable. Wiring is pins 6,
#     8 and 10 with the red lead open; see docs/BRINGUP.md.
#
# SPDX-License-Identifier: MIT
set -eu

DEVICE="${1:-/dev/ttyUSB0}"
BENCH_WORK="${BENCH_WORK:-$HOME/bench}"
TMPDIR_BUILD="$BENCH_WORK/build/tmp"

fail=0

say()  { echo "$*"; }
note() { echo "    $*"; }
bad()  { echo "MISSING: $*" >&2; fail=1; }

# Is this an ELF file? The four byte magic, read with od rather than with
# readelf, which is absent on some hosts. The candidate lists below are only
# worth printing if they can be trusted, and a stray file named vmlinux is
# not a kernel. This runs on the host, never on the board, so GNU od is a
# fair assumption; BusyBox od has no -A and would need a different reader.
is_elf() {
	[ -f "$1" ] || return 1
	magic=$(od -An -t x1 -N 4 "$1" 2>/dev/null | tr -d ' \n')
	[ "$magic" = "7f454c46" ]
}

say "kgdb-setup.sh"
say "    work dir   $TMPDIR_BUILD"
say "    device     $DEVICE"
say ""

if [ ! -d "$TMPDIR_BUILD" ]; then
	echo "kgdb-setup.sh: $TMPDIR_BUILD does not exist." >&2
	echo "    Set BENCH_WORK to the directory holding build/tmp, or build" >&2
	echo "    the debug image first. Nothing below can be found without it." >&2
	exit 1
fi

# --- 1. the adapter ------------------------------------------------------
#
# agent-proxy.sh guards this too and in more detail. It is pre-flighted
# here so that a missing cable is found before anything is installed,
# rather than three steps later with two windows already open.
say "1. the adapter"
if [ -e "$DEVICE" ]; then
	note "$DEVICE exists"
	if [ -r "$DEVICE" ] && [ -w "$DEVICE" ]; then
		note "readable and writable"
	else
		bad "cannot read and write $DEVICE. On Debian and Ubuntu:"
		note "    sudo usermod -aG dialout \"\$USER\"   then log out and in"
	fi
else
	bad "$DEVICE does not exist. Plug the adapter in, then:"
	note "    ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null"
	note "    dmesg | tail -20"
fi

# Who holds it. A terminal on the device is the commonest failure on this
# bench and it reads as a dead cable, so the holder is named rather than
# merely reported.
if command -v fuser >/dev/null 2>&1; then
	holder=$(fuser "$DEVICE" 2>/dev/null | tr -s ' ' || true)
	if [ -n "$(printf '%s' "$holder" | tr -d ' ')" ]; then
		bad "$DEVICE is held by pid(s):$holder"
		for pid in $holder; do
			name=$(ps -o comm= -p "$pid" 2>/dev/null || echo unknown)
			note "    pid $pid  $name"
		done
		note "    Quit it. In picocom that is Ctrl-A then Ctrl-X."
	else
		note "nothing is holding it"
	fi
else
	note "NOT CHECKED: fuser is absent, so nothing asked whether another"
	note "             program holds $DEVICE. If the console stays silent,"
	note "             that is the first thing to suspect."
fi
say ""

# --- 2. the tools --------------------------------------------------------
say "2. the tools"
if command -v agent-proxy >/dev/null 2>&1; then
	note "agent-proxy    $(command -v agent-proxy)"
else
	bad "agent-proxy is not on PATH. It is packaged by almost nobody:"
	note "    git clone https://git.kernel.org/pub/scm/utils/kernel/kgdb/agent-proxy.git"
	note "    cd agent-proxy && make"
	note "    sudo install -m0755 agent-proxy /usr/local/bin/"
fi

GDB=""
for g in gdb-multiarch aarch64-linux-gnu-gdb aarch64-poky-linux-gdb; do
	if command -v "$g" >/dev/null 2>&1; then
		GDB=$g
		break
	fi
done
if [ -n "$GDB" ]; then
	note "gdb            $(command -v "$GDB")"
else
	bad "no aarch64-capable gdb. Any one of these will do:"
	note "    sudo apt install gdb-multiarch"
	note "    (or gdb-multiarch, aarch64-linux-gnu-gdb, aarch64-poky-linux-gdb)"
fi

READER=""
for r in nc telnet socat; do
	if command -v "$r" >/dev/null 2>&1; then
		READER=$r
		break
	fi
done
if [ -n "$READER" ]; then
	note "console reader $READER"
else
	bad "no nc, telnet or socat, so nothing can read the console port."
	note "    sudo apt install netcat-openbsd"
fi
say ""

# --- 3. vmlinux and the gdb scripts --------------------------------------
#
# find chooses the input here, so every candidate is printed. A find piped
# to head picked the wrong kernel tree earlier on Tuesday 6 October 2026
# and the mistake was invisible because the answer happened to agree.
say "3. vmlinux and vmlinux-gdb.py"
# Counted in the loop rather than accumulated into a string and split
# again afterwards. The string version needed an unquoted expansion to
# count, shellcheck refuses that as SC2086, and CI refused the whole run
# on Tuesday 6 October 2026 because of it.
vmcount=0
vmfirst=""
for v in $(find "$TMPDIR_BUILD" -maxdepth 9 -name vmlinux -type f 2>/dev/null || true); do
	if is_elf "$v"; then
		note "candidate      $v"
		vmcount=$((vmcount + 1))
		if [ -z "$vmfirst" ]; then
			vmfirst=$v
		fi
	else
		note "not an ELF     $v   (ignored)"
	fi
done
VMDIR=""
if [ "$vmcount" = "0" ]; then
	bad "no ELF vmlinux under $TMPDIR_BUILD. Build the debug image."
elif [ "$vmcount" != "1" ]; then
	# A refusal that then prints a decision is worse than either on its
	# own, and this script did exactly that until it was tested. So the
	# choice is abandoned here rather than reported alongside the refusal.
	bad "$vmcount vmlinux files, listed above. This script will not choose"
	note "    between kernels, and has chosen nothing. Remove the trees you"
	note "    are not debugging, or start gdb yourself in the one you mean."
else
	VMDIR=$(dirname "$vmfirst")
	note "chosen         $VMDIR/vmlinux"
	if [ -f "$VMDIR/vmlinux-gdb.py" ]; then
		note "gdb scripts    $VMDIR/vmlinux-gdb.py"
	else
		bad "no vmlinux-gdb.py beside that vmlinux. host/gdbinit sources"
		note "    ./vmlinux-gdb.py relative to gdb's working directory, so"
		note "    without it there is no lx-symbols and no module symbols."
		note "    debug.cfg sets CONFIG_GDB_SCRIPTS to produce it."
	fi
fi
say ""

# --- 4. the module, and whether it has symbols ---------------------------
#
# BitBake leaves several copies of a module and they are not equivalent:
# the one under package/ or image/ is stripped, and gdb resolves nothing
# from it while saying nothing about why. Path heuristics are guesswork,
# so each candidate is measured: a module with symbols has a .debug_info
# section, and readelf reads a foreign ELF's section table fine.
say "4. buggy.ko, and which copy has symbols"
kos=$(find "$TMPDIR_BUILD" -name buggy.ko -type f 2>/dev/null || true)
KO=""
if [ -z "$(printf '%s' "$kos" | tr -d ' ')" ]; then
	bad "no buggy.ko under $TMPDIR_BUILD. Is bench-buggy in the image?"
elif ! command -v readelf >/dev/null 2>&1; then
	bad "readelf is absent, so no candidate could be tested for symbols."
	note "    Candidates found, untested:"
	for k in $kos; do
		note "    $k"
	done
	note "    sudo apt install binutils"
else
	for k in $kos; do
		if readelf -S "$k" 2>/dev/null | grep -q debug_info; then
			note "has symbols    $k"
			if [ -z "$KO" ]; then
				KO=$k
			fi
		else
			note "STRIPPED       $k"
		fi
	done
	if [ -z "$KO" ]; then
		bad "every buggy.ko found is stripped. gdb will show raw addresses"
		note "    in the module's frames, which looks like a corrupted stack"
		note "    and is not one."
	fi
fi
say ""

# --- 5. put the module where lx-symbols will look ------------------------
#
# host/gdbinit defines lxmod as "lx-symbols .", so the module has to sit
# in gdb's working directory, which is the vmlinux directory. The notebook
# never said this, which is why module frames came back nameless.
say "5. the module beside vmlinux, where lx-symbols looks"
if [ -n "$KO" ] && [ -n "$VMDIR" ]; then
	if [ -f "$VMDIR/buggy.ko" ] && cmp -s "$KO" "$VMDIR/buggy.ko"; then
		note "already there and identical"
	else
		cp "$KO" "$VMDIR/buggy.ko"
		note "copied         $KO"
		note "to             $VMDIR/buggy.ko"
	fi
else
	note "SKIPPED: needs both a vmlinux directory and an unstripped module."
fi
say ""

# --- what to run next ----------------------------------------------------
if [ "$fail" != "0" ]; then
	echo "kgdb-setup.sh: fix the MISSING lines above and run this again." >&2
	echo "    Nothing was started, so nothing is holding the cable." >&2
	exit 1
fi

say "Everything entry 02 needs is present. Three windows, in this order,"
say "and the board stays OFF until the third one is running."
say ""
say "  window 1   cd $PWD"
say "             ./go proxy $DEVICE"
say ""
say "  window 2   cd $HOME"
say "             $READER localhost 5550 | tee proj09-kgdb-\$(date +%F-%H%M).log"
say ""
say "  window 3   cd $VMDIR"
say "             $GDB -x $PWD/projects/09-kernel-debug/host/gdbinit vmlinux"
say ""
say "Then power the board on, and from a shell on the board:"
say ""
say "             echo g > /proc/sysrq-trigger"
say ""
say "The heartbeat LED on GPIO17 freezes when the kernel has stopped. At"
say "the gdb prompt: kgdb, then lxmod, then break fault_null, continue."
say ""
say "One thing this script cannot check: that $VMDIR/vmlinux is from the"
say "build now running on the board. A mismatch resolves to the wrong"
say "symbols confidently and silently. Read host/gdbinit on that."
