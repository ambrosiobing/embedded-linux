#!/bin/sh
# Split the console cable into a terminal port and a gdb port.
#
#   ./go proxy                       /dev/ttyUSB0 at 115200
#   ./go proxy /dev/ttyUSB1          another adapter
#   ./go proxy /dev/ttyUSB0 921600   another baud rate
#
# THIS RUNS ON THE HOST, NOT ON THE BOARD. It is the one piece of this
# project that is deliberately in no image: it owns the host's USB
# adapter, and a debugger on a board that is about to stop running is no
# use to anybody.
#
# WHY IT EXISTS
#
# The kernel's debugger and the kernel's console are the same UART. When
# the kernel enters kgdb it takes that UART over in polled mode and
# speaks the gdb remote protocol on it; the rest of the time the same
# wire carries console text. Two programs cannot both hold
# /dev/ttyUSB0, so agent-proxy holds it and offers two TCP ports:
#
#   5550   the console. Point a terminal at it, and log the session.
#   5551   the gdb port. Point gdb's "target remote" at it.
#
# WHAT GOES WRONG WITHOUT IT, and it is worth knowing because the symptom
# is not obvious: a terminal program holding the device makes agent-proxy
# fail to open it, and if a terminal and gdb somehow share the line, the
# console text arrives in gdb's packet parser as garbage and the protocol
# packets print as mojibake on the console. Neither failure says "two
# programs are on one cable".
#
# SPDX-License-Identifier: MIT
set -eu

DEVICE="${1:-/dev/ttyUSB0}"
BAUD="${2:-115200}"
CONSOLE_PORT="${CONSOLE_PORT:-5550}"
GDB_PORT="${GDB_PORT:-5551}"

die() {
	echo "agent-proxy.sh: $*" >&2
	exit 1
}

# --- the tool itself -----------------------------------------------------
if ! command -v agent-proxy >/dev/null 2>&1; then
	cat >&2 <<EOF
agent-proxy.sh: agent-proxy is not on PATH.

It is not packaged by most distributions. Build it on the host:

    git clone https://git.kernel.org/pub/scm/utils/kernel/kgdb/agent-proxy.git
    cd agent-proxy && make
    sudo install -m0755 agent-proxy /usr/local/bin/

Debian and Ubuntu also carry it inside the "agent-proxy" source of some
kgdb tool bundles; if yours has a package, use that.
EOF
	exit 1
fi

# --- the device ----------------------------------------------------------
[ -e "$DEVICE" ] || die "$DEVICE does not exist. Adapters usually appear as
    /dev/ttyUSB0 (FTDI, CP210x, CH340) or /dev/ttyACM0. Plug it in, then:
        ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
        dmesg | tail -20"

# An if rather than "A && B || C", which is SC2015 and is not
# if-then-else: when A succeeds and B fails, C runs anyway. Here that
# would be harmless, and the pattern has already cost this repository
# thirteen red CI runs in one sitting, so it is not written at all.
if [ ! -r "$DEVICE" ] || [ ! -w "$DEVICE" ]; then
	die "cannot read and write $DEVICE.
    On Debian and Ubuntu the device belongs to group dialout:
        sudo usermod -aG dialout \"\$USER\"    # then log out and back in
    Check with: ls -l $DEVICE"
fi

# --- who else is holding it ----------------------------------------------
#
# The single commonest failure on this bench, and the one that looks like
# a dead cable. A guard that refuses has to NAME WHAT IT MATCHED,
# otherwise the reader either believes it or switches it off, and on a
# long debugging session people switch it off.
holder=""
if command -v fuser >/dev/null 2>&1; then
	holder=$(fuser "$DEVICE" 2>/dev/null | tr -s ' ' || true)
elif command -v lsof >/dev/null 2>&1; then
	holder=$(lsof -t "$DEVICE" 2>/dev/null | tr '\n' ' ' || true)
else
	# Say what was NOT checked, rather than printing a clean result
	# from a question that could not be asked.
	echo "agent-proxy.sh: neither fuser nor lsof is installed, so nothing" >&2
	echo "    checked whether another program already holds $DEVICE." >&2
	echo "    If the console stays silent, close every terminal on it." >&2
fi

if [ -n "$(printf '%s' "$holder" | tr -d ' ')" ]; then
	echo "agent-proxy.sh: $DEVICE is already held by pid(s):$holder" >&2
	for pid in $holder; do
		name=$(ps -o comm= -p "$pid" 2>/dev/null || echo "unknown")
		echo "    pid $pid  $name" >&2
	done
	die "close those first. A terminal program holding the device is why
    agent-proxy cannot open it, and the failure reads as a dead cable.
    Connect the terminal to port $CONSOLE_PORT instead, never to $DEVICE."
fi

# --- go ------------------------------------------------------------------
#
# The invocation is printed before it runs. agent-proxy's argument order
# is unusual (the port pair first, then a target host of 0 meaning "a
# serial device follows"), and a version that wanted it differently would
# otherwise fail with a usage message that does not name this script.
echo "agent-proxy.sh: $DEVICE at $BAUD"
echo "    console  telnet localhost $CONSOLE_PORT    (log this session)"
echo "    gdb      target remote localhost:$GDB_PORT"
echo
echo "+ agent-proxy ${CONSOLE_PORT}^${GDB_PORT} 0 ${DEVICE},${BAUD}"
exec agent-proxy "${CONSOLE_PORT}^${GDB_PORT}" 0 "${DEVICE},${BAUD}"
