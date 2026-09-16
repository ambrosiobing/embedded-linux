#!/bin/sh
#
# pull-test.sh - the pull that is refused while a build is running.
#
# kas registers this checkout as a layer in place, so BitBake reads recipes
# from here for the whole of a build. A pull mid-build is an edit to the
# running build's metadata, and BitBake stops with "The metadata is not
# deterministic", naming recipes nobody touched.
#
# That happened: a pull three hours into a bench-rt-image build added two
# inert lines to linux-raspberrypi_%.bbappend for an unrelated project and
# took out five kernel tasks at 6201 of 6258.
#
# The guard is a pgrep, which is testable without BitBake: a script at a
# path ending in bitbake/bin/bitbake, left running in the background, is
# indistinguishable to pgrep -f from the real thing.
#
#   sh tests/pull-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# The scripts under test are copied into the clone below.

WORK=$(mktemp -d)
cleanup() {
	[ -z "${faker:-}" ] || kill "$faker" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT

pass=0
fail=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
}

contains() {
	case $2 in
	*"$3"*) ok "$1" ;;
	*)
		no "$1: '$3' not in output"
		printf '%s\n' "$2" | sed 's/^/       /'
		;;
	esac
}

# A checkout with a fake origin, so "git pull" is a real pull of nothing
# rather than a network call.
origin=$WORK/origin
clone=$WORK/clone
git init -q --bare "$origin"

git init -q "$WORK/seed"
cd "$WORK/seed"
git config user.email t@example.invalid
git config user.name test
mkdir -p meta-bench/recipes-kernel/linux kas projects
echo "SRC_URI += \"file://bench.cfg\"" >meta-bench/recipes-kernel/linux/a.bbappend
echo "prose" >projects/notes.md
git add -A
git commit -qm "first"
git remote add origin "$origin"
git push -q origin HEAD:main

git clone -q "$origin" "$clone"
cd "$clone"
git config user.email t@example.invalid
git config user.name test
git checkout -q -B main origin/main 2>/dev/null || true

# common.sh derives REPO_DIR from the script's own location, so pointing an
# environment variable at the clone would not move it. The scripts are
# copied into the clone instead and run from there, which is also how they
# are really used: the checkout under test is the checkout they live in.
mkdir -p "$clone/scripts"
cp "$ROOT/scripts/common.sh" "$ROOT/scripts/pull.sh" "$clone/scripts/"
# No "$@". pull.sh forwards its arguments to git pull, but nothing here
# passes any, and a parameter that is never supplied is one shellcheck
# flags as SC2120 rather than one a reader learns anything from.
run() {
	BENCH_WORK=$WORK/bench sh "$clone/scripts/pull.sh" 2>&1
}

echo "== with no build running"

out=$(run || echo EXIT-FAILED)
case $out in
*EXIT-FAILED*)
	no "a pull with nothing running succeeds"
	printf '%s\n' "$out" | sed 's/^/       /'
	;;
*) ok "a pull with nothing running succeeds" ;;
esac

contains "it names the commit it started from" "$out" "at       "
contains "and says nothing changed" "$out" "unchanged, already at"

echo "== with a build running"

# pgrep is absent on Git Bash, where the guard cannot work and nothing
# needs it: no build runs on that host. Skipping is honest; reporting a
# pass would not be, and reporting a failure would train people to ignore
# this suite on the machine they edit from.
if ! command -v pgrep >/dev/null 2>&1; then
	echo "skip     no pgrep on this host, so the guard cannot be exercised"
	echo "         (CI and the WSL build host both have it)"
	out=$(run || true)
	contains "and pull.sh says the guard is not in force" \
		"$out" "not in force on this host"
	echo
	echo "$pass passed, $fail failed"
	[ "$fail" -eq 0 ]
	exit
fi

# Indistinguishable to pgrep -f from the real thing, which is the whole
# point: the guard matches on the command line, so the command line is what
# the test has to reproduce.
mkdir -p "$WORK/fake/bitbake/bin"
cat >"$WORK/fake/bitbake/bin/bitbake" <<'EOF'
#!/bin/sh
sleep 30
EOF
chmod +x "$WORK/fake/bitbake/bin/bitbake"
"$WORK/fake/bitbake/bin/bitbake" &
faker=$!

# pgrep needs the process to exist; give it a moment to be scheduled rather
# than assuming, because a race here would make this test pass for the
# wrong reason on a loaded machine.
i=0
while [ "$i" -lt 20 ]; do
	pgrep -f 'bitbake/bin/bitbake' >/dev/null 2>&1 && break
	sleep 0.1 2>/dev/null || sleep 1
	i=$((i + 1))
done

if pgrep -f 'bitbake/bin/bitbake' >/dev/null 2>&1; then
	ok "the fake build is visible to pgrep"
else
	no "the fake build is visible to pgrep"
	echo "       the refusal below cannot be trusted; skipping"
	kill "$faker" 2>/dev/null || true
	echo
	echo "$pass passed, $fail failed"
	[ "$fail" -eq 0 ]
	exit
fi

rc=0
out=$(run) || rc=$?

if [ "$rc" -ne 0 ]; then
	ok "a pull is refused while a build is running"
else
	no "a pull is refused while a build is running"
	printf '%s\n' "$out" | sed 's/^/       /'
fi

contains "the refusal says why, in terms of the layer" \
	"$out" "this checkout is its layer"
contains "and names the error the user would otherwise see" \
	"$out" "not deterministic"
contains "and says what to do instead" "$out" "Wait for it to finish"

kill "$faker" 2>/dev/null || true
faker=

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
