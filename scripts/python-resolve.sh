# scripts/python-resolve.sh - find a Python that runs. Sourced, never run.
#
# ONE COPY OF THE RESOLUTION, THREE POLICIES ON TOP OF IT.
#
# python3 on the Windows authoring laptop is the Microsoft Store stub. It
# is found by command -v, and it exits 0 for --version while running
# nothing at all, so presence and version checks both report a working
# interpreter that is not one. Executing something is the only probe that
# sees it, and the stub writes its refusal to stderr, so a command
# substitution around it captures an empty string rather than a message.
#
# On Monday 19 October 2026 that cost fourteen test suites, which exited
# with the stub's own status of 49 having asserted nothing, and the
# py_compile loop in scripts/host-check.sh, which reported forty files as
# having compile errors. Decision 133 has the account.
#
# What each caller wants when there is no interpreter differs, which is why
# this file resolves and returns rather than printing or exiting:
#
#   tests/lib/python.sh     skips the suite, saying what went unchecked
#   scripts/host-check.sh   counts a check it could not ask, and continues
#   go                      says so and stops, because a person typed it
#   scripts/credentials-set.sh  names this as the cause instead of blaming
#                               the passphrase
#
# Three copies of eight lines is how fourteen copies start.
#
# SPDX-License-Identifier: MIT

# bench_resolve_python
#
# Sets PYTHON to an interpreter that runs and returns 0, or returns 1 and
# leaves PYTHON empty. Prints nothing either way.
#
# PYTHON names the interpreter when it is already set, and is reported
# rather than replaced when it does not work: substituting a different
# interpreter for the one somebody asked for is how a program comes to run
# on a toolchain nobody meant to use. Unset, the two usual spellings are
# tried in order, because the working one on the authoring laptop is
# python and on every other host here it is python3.
bench_resolve_python() {
	PYTHON=${PYTHON:-}
	if [ -z "$PYTHON" ]; then
		for _bench_py in python3 python; do
			if "$_bench_py" -c "import sys" >/dev/null 2>&1; then
				PYTHON=$_bench_py
				break
			fi
		done
	fi
	[ -n "$PYTHON" ] && "$PYTHON" -c "import sys" >/dev/null 2>&1
}
