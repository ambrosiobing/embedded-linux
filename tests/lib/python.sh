# tests/lib/python.sh - resolve a working Python, or skip saying what was
# not checked. Sourced, never run.
#
# WHY THIS EXISTS, AND WHY IT IS NOT COPIED INTO EACH SUITE.
#
# Seventeen suites in tests/ need a Python interpreter, and on Monday 19
# October 2026 fourteen of them exited with status 49 on the Windows
# authoring laptop, having printed nothing and asserted nothing. 49 is the
# Microsoft Store python3 stub's own exit status. scripts/host-check.sh
# counts a non-zero exit from any suite as a defect in the tree, so those
# fourteen silent 49s were most of what made ./go check report a broken
# tree on a laptop where nothing was broken.
#
# PRESENCE IS NOT THE CAPABILITY, which is the whole lesson. The stub is
# found by command -v, and it exits 0 for --version while running nothing
# at all, so a presence check and a version check both report a working
# interpreter that is not one. Executing something is the only probe that
# sees it. Two suites had the presence form of the guard and passed it; the
# other twelve had no guard and let set -eu carry the 49 outward.
#
# This file is in tests/lib/ rather than tests/ on purpose: ./go check and
# CI run every tests/*.sh, and a sourced fragment picked up by that glob
# would be executed as a suite that asserts nothing and always passes,
# which is a shape this repository has shipped before and should not ship
# again. The subdirectory is what keeps it out of the glob.
#
# Fourteen copies of this reasoning would have drifted. The suites are
# otherwise standalone and stay so; tests/common-test.sh already sources
# scripts/common.sh, so sourcing inside tests/ is not new here.
#
# SPDX-License-Identifier: MIT

# bench_python WHAT_WAS_NOT_CHECKED
#
# Sets PYTHON to an interpreter that runs, or prints a skip and exits 0.
#
# How PYTHON is resolved, and why an explicit one is never replaced, is in
# scripts/python-resolve.sh rather than repeated here.
#
# The resolution itself moved to scripts/python-resolve.sh on Tuesday 20
# October 2026, when ./go lint, ./go plot, ./go matrix and the PSK
# derivation in scripts/credentials-set.sh turned out to name python3
# directly and to have the same fault. Three callers wanting three
# different things on failure is why that file resolves and returns while
# this one decides what a test should do about it.
. "${BENCH_RESOLVE:-$ROOT/scripts/python-resolve.sh}"

bench_python() {
	if ! bench_resolve_python; then
		echo "SKIP: no working Python on this host, so $1"
		echo "      NOTHING below ran. That is a gap and not a pass."
		echo "      python3 here may be the Microsoft Store stub, which"
		echo "      exits 0 for --version while running nothing at all."
		exit 0
	fi
}

# bench_python_module MODULE WHAT_WAS_NOT_CHECKED REQUIRED
#
# REQUIRED is the value of the caller's own BENCH_REQUIRE_<MODULE>, passed
# in rather than derived, so the variable's name is visible at the call
# site instead of being assembled by eval. 1 turns the gap into a failure,
# which is what the environment that promised the module sets: see the
# Tests step in .github/workflows/ci.yml, and decision 128 for the rule.
#
# Absent and not required is a SKIP that names what went unchecked, because
# a missing module on a host that never had it is a gap rather than a
# defect, and reporting it as a defect is what made this whole class of
# false red lines.
bench_python_module() {
	if "$PYTHON" -c "import $1" >/dev/null 2>&1; then
		return 0
	fi
	if [ "${3:-0}" = "1" ]; then
		echo "FAILED   $PYTHON runs but has no $1, and this environment"
		echo "         promised it through BENCH_REQUIRE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')=1."
		echo "         $2"
		echo "         Run scripts/host-setup.sh, or:"
		echo "         sudo apt-get install -y python3-$1"
		exit 1
	fi
	echo "SKIP: $PYTHON runs but has no $1, so $2"
	echo "      NOTHING below ran. That is a gap and not a pass."
	echo "      Run scripts/host-setup.sh, or:"
	echo "      sudo apt-get install -y python3-$1"
	exit 0
}
