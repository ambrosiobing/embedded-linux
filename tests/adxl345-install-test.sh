#!/bin/sh
#
# adxl345-install-test.sh - build Project 11's packages in a clean Debian
# container, then install and purge them in a second, cleaner one.
#
# This closes the two gaps tests/adxl345-build-test.sh names in its own
# comment: "What is not: either dependency field, and installing or
# purging, which is the rest of criterion 5 and wants a board or a
# container."
#
# Two containers rather than one, because they answer different questions:
#
#   stage 1, debian:trixie        dpkg-buildpackage WITHOUT -d, so
#                                Build-Depends is verified rather than
#                                skipped, and libgpiod-dev comes from a
#                                package so dh_shlibdeps runs strict
#   stage 2, debian:trixie-slim   apt install of the three .deb files, so
#                                Depends is resolved against the archive
#                                on a system where adduser is NOT present
#
# The second base matters more than it looks. adduser stopped being
# essential in Debian trixie, and adxl345-tools' postinst calls addgroup
# and adduser under set -e, so a missing Depends on adduser fails exactly
# here and nowhere earlier.
#
# IT SKIPS BY DEFAULT. ./go check and CI run every tests/*.sh, and this
# one pulls two container images and writes to a package database, so it
# runs only when asked:
#
#   BENCH_INSTALL_TEST=1 sh tests/adxl345-install-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/libadxl345/files/adxl345-linux
PROVER=$ROOT/scripts/adxl345-install-purge.sh
BASE_BUILD=debian:trixie
BASE_RUN=debian:trixie-slim

pass=0
fail=0
skip=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
	[ $# -gt 1 ] && printf '         %s\n' "$2"
	return 0
}

skipped() {
	echo "skipped  $1"
	skip=$((skip + 1))
}

done_summary() {
	echo
	printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
	[ "$fail" -eq 0 ]
}

echo "--- the tree and the prover this needs"
for f in "$SRC/debian/control" "$SRC/debian/rules" "$PROVER"; do
	if [ -f "$f" ]; then
		ok "present: $(echo "$f" | sed "s|$ROOT/||")"
	else
		no "missing: $f"
	fi
done
[ "$fail" -eq 0 ] || done_summary || exit 1

if [ "${BENCH_INSTALL_TEST:-}" != 1 ]; then
	skipped "BENCH_INSTALL_TEST is not 1, so no container was started.
         This pulls $BASE_BUILD and $BASE_RUN and installs packages,
         which is not something ./go check should do on its own."
	done_summary
	exit 0
fi

RT=
for c in docker podman; do
	if command -v "$c" >/dev/null 2>&1; then
		RT=$c
		break
	fi
done
if [ -z "$RT" ]; then
	skipped "neither docker nor podman is on this host, so the packages
         were not installed anywhere. Criterion 5's second half needs
         one of them, or a board."
	done_summary
	exit 0
fi
if ! "$RT" info >/dev/null 2>&1; then
	skipped "$RT is installed but not answering, so no container was
         started. On WSL this usually means the Docker service is not
         running."
	done_summary
	exit 0
fi
ok "$RT is present and answering"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/build"
cp -r "$SRC" "$WORK/build/adxl345-1.0.0"
cp "$PROVER" "$WORK/adxl345-install-purge.sh"
# The copy is what gets built, so debian/rules in the repository is never
# touched. The build test makes the same choice for the same reason.

echo
echo "--- stage 1: build in $BASE_BUILD, with Build-Depends verified"
# No -d. If the Build-Depends line is wrong or incomplete,
# dpkg-checkbuilddeps stops the build here, which is the point: the build
# test has to pass -d because its hosts carry libgpiod under /usr/local,
# and a container has no such excuse.
build_script='set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	build-essential dpkg-dev lintian \
	debhelper dh-python cmake pkg-config libgpiod-dev python3-all
cd /work/build/adxl345-1.0.0
dpkg-buildpackage -us -uc -b
cd /work/build
lintian --no-tag-display-limit ./*.changes || true
'
if "$RT" run --rm -v "$WORK:/work" "$BASE_BUILD" \
	sh -c "$build_script" >"$WORK/build.log" 2>&1; then
	ok "dpkg-buildpackage completed in $BASE_BUILD with Build-Depends checked"
else
	no "the container build failed" "$(tail -25 "$WORK/build.log")"
	done_summary || exit 1
fi

built=$(ls "$WORK/build"/*.deb 2>/dev/null | wc -l)
if [ "$built" -eq 3 ]; then
	ok "three .deb files came out of the container"
else
	no "$built .deb files came out, wanted 3"
	done_summary || exit 1
fi

# dh_shlibdeps ran strict in there, because libgpiod-dev is a Debian
# package in trixie. Reading the resolved field back is the check that
# criterion 5's dependency half actually has content.
deps=$(cd "$WORK/build" && dpkg-deb -f ./adxl345-tools_*.deb Depends)
printf 'note     adxl345-tools Depends: %s\n' "$deps"
for d in libadxl345-1 adduser libc6 python3; do
	if printf '%s' "$deps" | grep -q "$d"; then
		ok "Depends names $d"
	else
		no "Depends does not name $d, so one substitution came out empty"
	fi
done

lintian_errors=$(grep -c '^E: ' "$WORK/build.log" || true)
if [ "$lintian_errors" = 0 ]; then
	ok "lintian reported no errors in $BASE_BUILD"
else
	no "lintian reported $lintian_errors errors" \
		"$(grep '^E: ' "$WORK/build.log" | head -10)"
fi
grep '^W: ' "$WORK/build.log" | head -20 | while read -r line; do
	printf 'note     lintian warning, printed and not scored: %s\n' "$line"
done

echo
echo "--- stage 2: install and purge in $BASE_RUN"
run_script='set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
cd /work
BENCH_DISPOSABLE_SYSTEM=1 sh ./adxl345-install-purge.sh /work/build
'
if "$RT" run --rm -v "$WORK:/work" -e BENCH_DISPOSABLE_SYSTEM=1 \
	"$BASE_RUN" sh -c "$run_script" >"$WORK/run.log" 2>&1; then
	ok "install and purge passed in $BASE_RUN"
else
	no "install or purge failed in $BASE_RUN"
fi

# The prover's own lines are forwarded whether it passed or failed, because
# its notes are the record of what survived a purge and they are worth
# reading on a pass.
echo
echo "--- what the prover reported inside $BASE_RUN"
sed 's/^/         /' "$WORK/run.log"

done_summary
