#!/bin/sh
# tracker-at-test.sh - Project 16's parsers, timer octets, CoAP and machine.
#
# The wrapper exists because scripts/host-check.sh runs tests/*.sh and
# nothing else, so a suite written in Python needs a shell file to be found
# at all. The work is in tests/tracker-at-test.py beside it.
#
# This one runs anywhere Python does. Its sibling
# tests/tracker-state-test.sh drives the same scenarios through a real
# pseudo-terminal, so it covers the transport as well and skips on a host
# with no pty. Between them the only thing left needing hardware is whether
# a SIM7070G actually answers the way the tables say it does.
#
# SPDX-License-Identifier: MIT
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# python3 on the Windows authoring laptop is the Microsoft Store stub,
# which exits without running anything and takes the suite's pass with it.
# Trying the versioned name first and falling back is enough, and PYTHON
# overrides both for a host where neither guess is right.
python=${PYTHON:-}
if [ -z "$python" ]; then
	for candidate in python3 python; do
		if "$candidate" -c "import sys" >/dev/null 2>&1; then
			python=$candidate
			break
		fi
	done
fi
if [ -z "$python" ]; then
	echo "SKIP: no working Python on this host"
	exit 0
fi

exec "$python" "$here/tracker-at-test.py"
