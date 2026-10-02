#!/bin/sh
#
# adxl345-install-purge.sh - install Project 11's three Debian packages on
# a disposable system, prove what landed, purge them, and prove what is
# left.
#
# This is the half of acceptance criterion 5 that tests/adxl345-build-test.sh
# names and cannot do: "either dependency field, and installing or purging,
# which is the rest of criterion 5 and wants a board or a container."
#
# IT LIVES IN scripts/ AND NOT IN tests/ ON PURPOSE. scripts/host-check.sh
# runs "for t in tests/*.sh", so a file in tests/ that installs packages
# would install them on whatever host typed ./go check. The guard below is
# the second line of defence; the directory is the first.
#
# Run it inside a container, or on a board that can be reflashed, never on
# a working system:
#
#   BENCH_DISPOSABLE_SYSTEM=1 sh scripts/adxl345-install-purge.sh DIR
#
# DIR must hold the three .deb files. tests/adxl345-install-test.sh builds
# them in a container and calls this; on a board, build them there or copy
# them across.
#
# SPDX-License-Identifier: MIT

set -eu

pass=0
fail=0

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

note() {
	printf 'note     %s\n' "$1"
}

summary() {
	echo
	printf '%d passed, %d failed\n' "$pass" "$fail"
	[ "$fail" -eq 0 ]
}

# THE GUARD. An install test that can run by accident is worse than no
# install test, because it changes the machine that was asking a question.
if [ "${BENCH_DISPOSABLE_SYSTEM:-}" != 1 ]; then
	echo "refusing: this installs and purges packages, creates a system"
	echo "          account and two groups, and reloads udev rules. Set"
	echo "          BENCH_DISPOSABLE_SYSTEM=1 only on a container or a"
	echo "          board you can reflash."
	exit 2
fi

[ $# -eq 1 ] || {
	echo "usage: adxl345-install-purge.sh DIR-OF-DEBS"
	exit 2
}
DEBS=$1
[ -d "$DEBS" ] || {
	echo "FAILED   not a directory: $DEBS"
	exit 1
}
[ "$(id -u)" = 0 ] || {
	echo "FAILED   this needs root to install packages"
	exit 1
}

cd "$DEBS"

echo "--- the three packages are here"
for p in libadxl345-1 libadxl345-dev adxl345-tools; do
	n=0
	for f in "$p"_*.deb; do
		[ -e "$f" ] && n=$((n + 1))
	done
	if [ "$n" -eq 1 ]; then
		ok "$p has exactly one .deb"
	else
		no "$p has $n .deb files, wanted 1"
	fi
done
[ "$fail" -eq 0 ] || summary || exit 1

echo
echo "--- the system before, so the residue afterwards means something"
had_group_i2c=0
had_group_gpio=0
had_user=0
for g in i2c gpio; do
	if getent group "$g" >/dev/null; then
		note "group $g already exists, so its survival proves nothing"
		eval "had_group_$g=1"
	fi
done
if getent passwd adxl345 >/dev/null; then
	note "user adxl345 already exists, so its survival proves nothing"
	had_user=1
fi

echo
echo "--- install, which is where a missing Depends shows itself"
# apt rather than dpkg -i, because dpkg does not resolve dependencies and
# would report success on a package whose Depends cannot be satisfied.
# The point of a slim base is that adduser is NOT installed: it stopped
# being essential in Debian trixie, and adxl345-tools' postinst calls
# addgroup and adduser under set -e.
if apt-get install -y --no-install-recommends \
	./libadxl345-1_*.deb ./libadxl345-dev_*.deb ./adxl345-tools_*.deb \
	>/tmp/adxl-install.log 2>&1; then
	ok "apt resolved every Depends and configured all three packages"
else
	no "apt could not install the three packages" \
		"$(tail -20 /tmp/adxl-install.log)"
	summary || exit 1
fi

for p in libadxl345-1 libadxl345-dev adxl345-tools; do
	st=$(dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null || echo "??")
	case "$st" in
	ii*) ok "$p is installed and configured, status $st" ;;
	*) no "$p status is '$st', wanted ii" ;;
	esac
done

echo
echo "--- what the .install files promised is on the filesystem"
# Asked through dpkg -L rather than by guessing paths, because the
# multiarch triplet is not knowable here, and because /lib being a symlink
# to /usr/lib means a guessed path can be right and still not be the path
# dpkg recorded.
have() {
	if dpkg -L "$1" 2>/dev/null | grep -q -- "$2"; then
		ok "$1 ships something matching $2"
	else
		no "$1 ships nothing matching $2"
	fi
}
have libadxl345-1 'libadxl345.so.1'
have libadxl345-dev 'include/adxl345/adxl.h'
have libadxl345-dev 'pkgconfig/adxl345.pc'
have adxl345-tools 'bin/adxl-map'
have adxl345-tools 'bin/adxl-motion'
have adxl345-tools 'python3/dist-packages/adxl345'
have adxl345-tools '60-adxl345.rules'

rule=$(dpkg -L adxl345-tools | grep '60-adxl345.rules$' | head -1)
if [ -n "$rule" ] && [ -f "$rule" ]; then
	ok "the udev rule landed at $rule"
	if grep -q 'GROUP="i2c"' "$rule" && grep -q 'GROUP="gpio"' "$rule"; then
		ok "the installed rule still names both groups"
	else
		no "the installed rule does not name both groups"
	fi
else
	no "the udev rule is not on the filesystem"
fi

echo
echo "--- the postinst did its work, which is the clean-install half"
for g in i2c gpio; do
	if getent group "$g" >/dev/null; then
		ok "group $g exists"
	else
		no "group $g was not created, so the postinst did not complete"
	fi
done
if getent passwd adxl345 >/dev/null; then
	ok "the service account adxl345 exists"
	home=$(getent passwd adxl345 | cut -d: -f6)
	if [ "$home" = /nonexistent ]; then
		ok "its home is /nonexistent, the pair lintian asked for"
	else
		no "its home is '$home', wanted /nonexistent"
	fi
else
	no "the service account adxl345 was not created"
fi
for g in i2c gpio; do
	if id -nG adxl345 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
		ok "adxl345 is a member of $g"
	else
		no "adxl345 is not a member of $g, so the service would open
         neither the bus nor the GPIO line"
	fi
done

echo
echo "--- the library is linkable, and one version rather than two"
if ldconfig -p | grep -q 'libadxl345.so.1'; then
	ok "ldconfig knows libadxl345.so.1"
else
	no "ldconfig does not list libadxl345.so.1, so nothing could link it"
fi
pc=$(dpkg -L libadxl345-dev | grep 'adxl345.pc$' | head -1)
deb_version=$(dpkg-query -W -f='${Version}' libadxl345-1)
if [ -n "$pc" ] && [ -f "$pc" ]; then
	pc_version=$(sed -n 's/^Version: *//p' "$pc")
	if [ "$pc_version" = "$deb_version" ]; then
		ok "adxl345.pc and the package agree on $pc_version"
	else
		no "adxl345.pc says $pc_version and the package says $deb_version"
	fi
else
	no "adxl345.pc is not on the filesystem"
fi

echo
echo "--- the reader refuses a bus that is not there, without faulting"
# NOT criterion 6. Criterion 6 is a user outside the i2c group getting a
# clear error on a bus that EXISTS, and a container has no /dev/i2c-* at
# all. What is checked here is only that an absent device is reported and
# does not fault.
set +e
out=$(adxl-map 2>&1)
rc=$?
set -e
if [ "$rc" -ne 0 ] && [ "$rc" -lt 128 ]; then
	ok "adxl-map exited $rc with no bus present"
else
	no "adxl-map exited $rc, which is a signal or a false success" "$out"
fi
if printf '%s' "$out" | grep -qi 'i2c'; then
	ok "its message names the bus it could not open"
else
	no "its message does not name the bus" "$out"
fi

echo
echo "--- purge, and what is allowed to survive it"
# The file list is taken BEFORE the purge, because dpkg -L says nothing
# about a package that is gone.
dpkg -L libadxl345-1 libadxl345-dev adxl345-tools 2>/dev/null |
	sort -u >/tmp/adxl-shipped.txt
shipped_files=0
while read -r f; do
	[ -f "$f" ] && shipped_files=$((shipped_files + 1))
done </tmp/adxl-shipped.txt
note "$shipped_files regular files shipped by the three packages"

if apt-get purge -y adxl345-tools libadxl345-dev libadxl345-1 \
	>/tmp/adxl-purge.log 2>&1; then
	ok "apt purged all three packages"
else
	no "purge failed" "$(tail -20 /tmp/adxl-purge.log)"
fi

left=0
while read -r f; do
	if [ -e "$f" ] && [ ! -d "$f" ]; then
		echo "         left behind: $f"
		left=$((left + 1))
	fi
done </tmp/adxl-shipped.txt
if [ "$left" -eq 0 ]; then
	ok "no file the packages shipped survives the purge"
else
	no "$left shipped files survive the purge"
fi

# dh_python3 compiles the module at install time, so the .pyc files are in
# no .install file and in no dpkg -L. A package that leaves them leaves a
# directory of bytecode nothing owns.
pyleft=$(find /usr/lib/python3 -maxdepth 3 -name adxl345 2>/dev/null | wc -l)
if [ "$pyleft" -eq 0 ]; then
	ok "the python3 module directory and its bytecode are gone"
else
	no "a python3 adxl345 directory survives the purge, which is the
         bytecode dh_python3 generated rather than anything shipped"
fi

if ldconfig -p | grep -q 'libadxl345.so'; then
	no "ldconfig still lists libadxl345 after the purge"
else
	ok "ldconfig no longer lists libadxl345"
fi

echo
echo "--- the residue that is meant to be there"
# Debian policy does not ask a package to delete the system account or the
# groups it created, and deleting an account can orphan files it owns
# elsewhere. There is no postrm here and that is deliberate. So "purge
# leaves nothing behind" is scored on FILES, and the account and the
# groups are named rather than silently tolerated.
for g in i2c gpio; do
	eval "had=\$had_group_$g"
	if getent group "$g" >/dev/null; then
		if [ "$had" = 1 ]; then
			note "group $g survives and predated the install"
		else
			note "group $g was created by the postinst and survives the
         purge, which policy permits and no postrm undoes"
		fi
	else
		note "group $g is gone"
	fi
done
if getent passwd adxl345 >/dev/null; then
	if [ "$had_user" = 1 ]; then
		note "user adxl345 survives and predated the install"
	else
		note "user adxl345 was created by the postinst and survives the
         purge, which policy permits and no postrm undoes"
	fi
else
	note "user adxl345 is gone"
fi

summary
