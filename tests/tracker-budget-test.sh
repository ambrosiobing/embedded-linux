#!/bin/sh
# tracker-budget-test.sh - Project 16's charge arithmetic.
#
# The wrapper exists because scripts/host-check.sh runs tests/*.sh and
# nothing else. The work is in tests/tracker-budget-test.py beside it.
#
# Runs anywhere Python does, and needs no numpy: measure/budget.py is
# standard library only, unlike Project 3's analyze.py which it otherwise
# resembles. That is deliberate. A suite that cannot run on the laptop the
# work is done on is a suite whose failures are found by somebody else.
#
# SPDX-License-Identifier: MIT
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# python3 on the Windows authoring laptop is the Microsoft Store stub,
# which exits without running anything and takes the suite's pass with it.
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

exec "$python" "$here/tracker-budget-test.py"
