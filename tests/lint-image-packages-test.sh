#!/bin/sh
#
# lint-image-packages-test.sh - the not-a-package marker fires, and stays quiet.
#
# scripts/lint.py reads a comment naming kernel-module-foo in an image recipe
# as a promise that foo belongs on a card, because on Project 1 that promise
# was made in three paragraphs and kept by no IMAGE_INSTALL line, and the
# board reported it by having no network interface.
#
# On Saturday 24 October 2026 bench-iio-image met the other direction.
# CONFIG_IIO_SYSFS_TRIGGER is =y in bench.cfg, so it is built into the
# kernel, there is no .ko, and kernel-module-iio-trig-sysfs is a package that
# cannot exist. do_rootfs said so after the whole kernel had compiled. The
# recipe then has to explain that, naming the package, or the next person to
# add the line back cannot find the paragraph saying why it went. That comment
# is indistinguishable from the defect above by name alone.
#
# So the exemption is a marker that is checked rather than believed, and this
# file is what makes sure it is still checked. The case that matters most is
# the LAST one: a marker wrapped across lines with the package on the first
# line and the symbol on a later one. check-kernel-symbols.sh carried exactly
# that defect on the same day, replacing its record of a claim on every marker
# line instead of appending, so a wrapped claim was truncated to its tail and
# reported as unchecked while naming its file the whole time.
#
# No build, no hardware, no Yocto host. Each case is a temporary image recipe
# written into the real tree, because lint.py finds its own root from its own
# path and a copy of the tree would not be the thing under test. The fixture
# is UNTRACKED and removed by a trap, so an interrupted run leaves a stray
# file that check-clean.py reports rather than a mangled tracked recipe.
#
#   sh tests/lint-image-packages-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE=$ROOT/meta-bench/recipes-core/images/bench-lintfixture-image.bb

# The rule under test lives in Python, so a host without a working
# interpreter checks nothing here. That has to be a SKIP that says so and
# not a pass: the silence assertions below would all pass against an
# interpreter that printed nothing because it never ran, which is the
# Microsoft Store stub's exact behaviour and the reason this helper exists.
. "$ROOT/tests/lib/python.sh"
bench_python "the not-a-package marker in scripts/lint.py went unchecked"

pass=0
fail=0

say() {
	if [ "$1" = yes ]; then
		pass=$((pass + 1))
		printf 'ok   %s\n' "$2"
	else
		fail=$((fail + 1))
		printf 'FAIL %s\n' "$2"
	fi
}

TMP=$(mktemp -d)
trap 'rm -f "$FIXTURE"; rm -rf "$TMP"' EXIT

out=$TMP/out

# The fixture names a package no image installs and no kernel builds, so it
# can never be excused by accident. A real package name here would be worse
# than useless: lint asks whether ANY image installs a name, so a fixture
# installing kernel-module-iio-trig-sysfs would silence the real finding in
# bench-iio-image and this suite would pass by breaking the thing it guards.
ABSENT=kernel-module-bench-lintfixture

# Only the fixture's own findings are read. Everything else lint reports is
# some other rule's business, and filtering by filename is what lets this test
# assert silence without claiming the whole tree is clean.
run() { # marker-body
	{
		printf 'SUMMARY = "Not a real image. tests/lint-image-packages-test.sh"\n'
		printf '\nrequire recipes-core/images/bench-image.bb\n'
		printf '\nIMAGE_INSTALL:append = " \\\n    i2c-tools \\\n"\n'
		printf '\n# This fixture talks about %s.\n' "$ABSENT"
		if [ -n "$1" ]; then
			printf '%s\n' "$1"
		fi
	} >"$FIXTURE"
	# lint.py finds its own root from its own path, so it is named
	# absolutely and there is no cd to chain onto. The first draft of this
	# line was "cd && python || true" piped into grep, which the
	# repository's own linter rejected as SC2015 on its first run. A test
	# of a checker caught by that checker is the cheapest possible version
	# of that mistake.
	"$PYTHON" "$ROOT/scripts/lint.py" >"$TMP/raw" 2>&1 || true
	grep 'bench-lintfixture-image' "$TMP/raw" >"$out" || true
}

said() { # description pattern
	if grep -q "$2" "$out"; then say yes "$1"; else say no "$1"; fi
}

quiet() { # description
	if [ -s "$out" ]; then
		say no "$1"
		sed 's/^/     /' "$out"
	else
		say yes "$1"
	fi
}

# --- no marker at all, which is the defect the rule was written for -------
run ""
said "a comment naming an uninstalled module fails" "which no image installs"
said "and it names the package it matched" "$ABSENT"

# --- the marker, naming a symbol that really is built in ------------------
run "# not-a-package: $ABSENT
# not-a-package: CONFIG_IIO_SYSFS_TRIGGER is =y in bench.cfg"
quiet "a marker naming a built-in symbol is accepted"

# --- the marker resting on a symbol that is =m, so the package does exist -
run "# not-a-package: $ABSENT
# not-a-package: CONFIG_IIO_HRTIMER_TRIGGER is =y in bench.cfg"
said "a marker contradicted by a fragment fails" "does produce a module package"
said "and it names the fragment that contradicts it" "iio.cfg"
said "and it reports the value it found" "=m"

# --- the marker naming no symbol, so nothing could contradict it ----------
run "# not-a-package: $ABSENT does not exist, take my word for it"
said "a marker with no CONFIG symbol fails" "names no CONFIG symbol"

# --- the marker resting on a symbol no fragment sets ----------------------
run "# not-a-package: $ABSENT
# not-a-package: CONFIG_BENCH_INVENTED_TRIGGER is =y somewhere"
said "a marker resting on an unknown symbol fails" "which no kernel fragment"
said "and it names the symbol it could not find" "CONFIG_BENCH_INVENTED_TRIGGER"

# --- the marker excusing a package that IS installed ----------------------
#
# Both halves cannot be true. This is the case that catches a marker left
# behind after the module came back, which would otherwise read as an
# explanation of why a package present on every card is absent.
run "# not-a-package: kernel-module-iio-trig-hrtimer
# not-a-package: CONFIG_IIO_SYSFS_TRIGGER is =y in bench.cfg"
said "a marker excusing an installed package fails" "an image installs it"

# --- the wrapped marker, which is the regression this file exists for -----
#
# The package is on the first line and the symbol is on the third. A reader
# that keeps only the last marker line sees a symbol and no package, excuses
# nothing, and reports the comment as naming an uninstalled module. A reader
# that keeps only the first sees a package and no symbol and reports that
# nothing can contradict it. Both wrong answers are asserted against.
run "# not-a-package: $ABSENT
# not-a-package: is built into the kernel, because bench.cfg sets
# not-a-package: CONFIG_IIO_SYSFS_TRIGGER to =y rather than =m"
quiet "a marker wrapped across three lines is read whole"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
