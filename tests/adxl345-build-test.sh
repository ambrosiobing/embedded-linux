#!/bin/sh
#
# adxl345-build-test.sh - configure, build and run Project 11's library
# against its fake bus.
#
# This is a test rather than a CI step on purpose. The Tests loop runs
# every tests/*.sh, so putting it here means it runs in CI and for anyone
# typing ./go check, with one file instead of two lists that drift. That
# drift is not hypothetical: Project 7 added libdrm-dev to two package
# lists for a compile step that existed in neither, and nothing noticed
# until the run went red.
#
# What it proves, and it is the whole hardware-free half of Project 11:
# the library compiles with -Werror, the fake platform layer links in
# place of the real one, and every register the library writes is the one
# the datasheet asks for. No sensor, no bus, no kernel.
#
# It also asserts the two things the packaging depends on: exactly six
# exported symbols, and the soname. Those are acceptance criterion 4, and
# they are checkable here rather than only after a .deb exists.
#
#   sh tests/adxl345-build-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/libadxl345/files/adxl345-linux

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

[ -d "$SRC" ] || {
	echo "FAILED   the source tree is missing: $SRC"
	exit 1
}

echo "--- the tree the build needs"
for f in CMakeLists.txt cmake/adxl345.pc.in include/adxl.h src/adxl.c \
	src/platform.c src/platform.h apps/adxl-map.c tests/test_api.c \
	tests/fake_platform.c tests/fake_platform.h; do
	if [ -f "$SRC/$f" ]; then
		ok "$f"
	else
		no "missing: $f"
	fi
done
[ "$fail" -eq 0 ] || {
	echo
	echo "cannot build with files missing"
	exit 1
}

# ---------------------------------------------------------------- source
#
# Assertions that need no toolchain at all, so they run on the authoring
# laptop as well as on the runner. They are about agreement between files,
# which is the class of mistake a compiler cannot see.

echo
echo "--- the API surface the packaging pins"

exported=$(grep -c "^ADXL_API" "$SRC/include/adxl.h" || true)
if [ "$exported" -eq 6 ]; then
	ok "adxl.h declares exactly six exported functions"
else
	no "adxl.h declares $exported exported functions, not six" \
		"the symbols file and acceptance criterion 4 both say six"
fi

for fn in adxl_version adxl_open adxl_start adxl_read adxl_stop adxl_close; do
	if grep -q "^ADXL_API.*\b$fn\b" "$SRC/include/adxl.h" ||
		grep -q "ADXL_API.*$fn" "$SRC/include/adxl.h"; then
		ok "$fn is exported"
	else
		no "$fn is not marked ADXL_API"
	fi
done

if grep -q "C_VISIBILITY_PRESET hidden" "$SRC/CMakeLists.txt"; then
	ok "the build hides everything not marked ADXL_API"
else
	no "visibility is not hidden by default" \
		"without it every internal helper is part of the ABI"
fi

if grep -q "SOVERSION" "$SRC/CMakeLists.txt"; then
	ok "a soname is set"
else
	no "no SOVERSION, so the library has no soname"
fi

echo
echo "--- the seam between the library and the bus"

if grep -q "src/platform.c" "$SRC/CMakeLists.txt" &&
	! awk '/add_executable\(test_api/,/\)/' "$SRC/CMakeLists.txt" |
		grep -q "src/platform.c"; then
	ok "the test target does not link the real platform layer"
else
	no "the test target links src/platform.c" \
		"then the fake replaces nothing and the tests need a bus"
fi

if awk '/add_executable\(test_api/,/\)/' "$SRC/CMakeLists.txt" |
	grep -q "fake_platform.c"; then
	ok "the test target links the fake platform layer"
else
	no "the test target does not link tests/fake_platform.c"
fi

# Both implementations must offer the same six functions, or the link
# succeeds for one target and fails for the other, which is a confusing
# way to find a typo.
echo
echo "--- both platform implementations offer the same functions"
for fn in adxl_plat_open adxl_plat_close adxl_plat_write adxl_plat_read \
	adxl_plat_wait adxl_plat_sleep_ms; do
	real=$(grep -c "^[a-z].*$fn(" "$SRC/src/platform.c" || true)
	fake=$(grep -c "^[a-z].*$fn(" "$SRC/tests/fake_platform.c" || true)
	if [ "$real" -ge 1 ] && [ "$fake" -ge 1 ]; then
		ok "$fn is in both"
	else
		no "$fn is in real=$real fake=$fake" \
			"the two implementations have diverged"
	fi
done

# ------------------------------------------------------------- packaging
#
# The two packagings share one CMakeLists.txt, so what can drift is the
# file lists: a binary installed by one and not the other, or a symbols
# file that no longer matches the header. Both are cheap to assert and
# neither needs dpkg.

echo
echo "--- the Debian packaging agrees with the library"

DEB=$SRC/debian
if [ ! -d "$DEB" ]; then
	no "missing: $DEB"
else
	for f in control rules changelog copyright source/format \
		libadxl345-1.symbols libadxl345-1.install \
		libadxl345-dev.install adxl345-tools.install; do
		if [ -f "$DEB/$f" ]; then
			ok "debian/$f"
		else
			no "missing: debian/$f"
		fi
	done

	# The symbols file is the ABI promise. If it and the header
	# disagree, dh_makeshlibs fails the package build, which is the
	# right place to find out and the wrong place to find out first.
	syms=$(grep -c "^ adxl_.*@Base" "$DEB/libadxl345-1.symbols" || true)
	if [ "$syms" -eq 6 ]; then
		ok "the symbols file pins six symbols"
	else
		no "the symbols file pins $syms symbols, not six" \
			"it must match the six ADXL_API functions in adxl.h"
	fi

	missing=""
	for fn in adxl_version adxl_open adxl_start adxl_read adxl_stop \
		adxl_close; do
		grep -q "^ $fn@Base" "$DEB/libadxl345-1.symbols" ||
			missing="$missing $fn"
	done
	if [ -z "$missing" ]; then
		ok "every exported function is in the symbols file"
	else
		no "not in the symbols file:$missing"
	fi

	# The soname and the project version have to agree on the major
	# number, or the package ships a library no dependency can resolve.
	# Compare the NUMBERS: an earlier version of this check only
	# confirmed that CMakeLists mentions SOVERSION at all, which passes
	# whatever the two numbers are.
	# awk rather than sed: a capture-group backslash in a sed script
	# does not survive every editing route, and a substitution that
	# loses its backreference prints an empty string that still
	# looks like a value. awk splits on the dot instead.
	cmajor=$(awk -F'VERSION ' '/^project/ {split($2, v, "."); print v[1]}' "$SRC/CMakeLists.txt" | head -n 1)
	smajor=$(awk '/^libadxl345.so./ {split($1, s, "."); print s[3]}' "$DEB/libadxl345-1.symbols" | head -n 1)
	if [ -n "$cmajor" ] && [ -n "$smajor" ] && [ "$cmajor" = "$smajor" ]
	then
		ok "the soname major agrees: CMake $cmajor, symbols $smajor"
	else
		no "soname mismatch: CMake '$cmajor', symbols '$smajor'"
	fi

	if grep -q "60-adxl345.rules" "$DEB/adxl345-tools.install"; then
		ok "the udev rule is installed by the tools package"
	else
		no "the udev rule is not installed, so reading needs root"
	fi
fi

# ------------------------------------------- the design against the code
#
# A document that describes a program is a claim about it and nothing
# tests it. This project has already shipped three artefacts named in the
# design and absent from the tree, and a figure naming a module that was
# actually a package. These are the claims cheap enough to check.

echo
echo "--- the design and the library agree"

DESIGN=$ROOT/projects/11-adxl345-userspace/docs/DESIGN.md
BRINGUP=$ROOT/projects/11-adxl345-userspace/docs/BRINGUP.md

if [ ! -f "$DESIGN" ]; then
	no "missing: $DESIGN"
else
	# Both strap addresses appear in the design, in the bring-up notes
	# and in the library's own argument check. If the library ever
	# accepts a third, or drops one, the documents become wrong
	# silently.
	for addr in 0x53 0x1d; do
		ind=$(grep -ci "$addr" "$DESIGN" || true)
		inc=$(grep -c "$addr" "$SRC/src/adxl.c" || true)
		if [ "$ind" -ge 1 ] && [ "$inc" -ge 1 ]; then
			ok "$addr is in the design and enforced in the code"
		else
			no "$addr: design=$ind code=$inc" 				"the documents and the argument check disagree"
		fi
	done

	# The six functions the design lists must be the six the header
	# exports. The design names them in its API section.
	missing=""
	for fn in adxl_version adxl_open adxl_start adxl_read adxl_stop 		adxl_close; do
		grep -q "$fn" "$DESIGN" || missing="$missing $fn"
	done
	if [ -z "$missing" ]; then
		ok "every exported function appears in the design"
	else
		no "the design does not mention:$missing"
	fi

	# The design says FULL_RES is always on, which is what fixes the
	# scale at every range. If the code stops setting it, the design's
	# explanation of why a stored sample needs no range tag is wrong.
	if grep -q "FULL_RES" "$DESIGN" &&
		grep -q "DATA_FORMAT_FULL_RES |" "$SRC/src/adxl.c"; then
		ok "FULL_RES is claimed in the design and set in the code"
	else
		no "the design's fixed-scale claim is not what the code does"
	fi
fi

if [ ! -f "$BRINGUP" ]; then
	no "missing: $BRINGUP"
else
	ok "the bring-up notes exist"
	# The notes tell a reader to power from 3V3 rather than 5 V. That
	# is the one instruction in this project that prevents damage
	# rather than confusion.
	if grep -q "3V3" "$BRINGUP"; then
		ok "the bring-up notes name the supply that cannot destroy a pin"
	else
		no "the bring-up notes do not state the supply" 			"a part at 5 V driving INT1 into a Pi GPIO destroys it"
	fi
fi

# ----------------------------------------------------- the Yocto recipe
#
# Three defects lived here at once and every one of them builds a package
# that installs and then does not work, which is the class this bench
# keeps paying for.

echo
echo "--- the Yocto recipe ships what CMake installs"

REC=$ROOT/meta-bench/recipes-bench/libadxl345/libadxl345_1.0.0.bb
if [ ! -f "$REC" ]; then
	no "missing: $REC"
else
	# EXTRA_OECMAKE assigned twice means the second discards the first,
	# silently. It happened here: a "+=" for the python directory
	# followed by a "=" for the build type.
	n=$(grep -c "^EXTRA_OECMAKE" "$REC" || true)
	if [ "$n" -eq 1 ]; then
		ok "EXTRA_OECMAKE is assigned exactly once"
	else
		no "EXTRA_OECMAKE is assigned $n times" 			"the last assignment silently discards the others"
	fi

	# Without the override the bindings install to Debian's path inside
	# a Yocto image: present on disk, never importable.
	if grep -q "ADXL_PYDIR" "$REC"; then
		ok "the recipe overrides the python directory"
	else
		no "the recipe does not set ADXL_PYDIR" 			"CMake would use Debian's dist-packages inside the image"
	fi

	# Anything CMake installs and no package claims is an unpackaged
	# file, which Yocto treats as an error rather than a warning.
	# In the FILES block, not anywhere in the recipe: the comments name
	# these programs too, so a plain grep passes with the package list
	# emptied. That version of this check was written first and proved
	# nothing, which is the second time in this suite.
	files=$(awk '/^FILES:/,/"$/' "$REC")
	for prog in adxl-map adxl-motion; do
		if printf '%s' "$files" | grep -q "$prog"; then
			ok "the recipe packages $prog"
		else
			no "$prog is installed by CMake and packaged by nobody"
		fi
	done

	if printf '%s' "$files" | grep -q "SITEPACKAGES_DIR}/adxl345"; then
		ok "the recipe packages the python bindings"
	else
		no "the bindings are installed and not packaged"
	fi

	if grep -q "RDEPENDS.*python3" "$REC"; then
		ok "the tools package depends on an interpreter"
	else
		no "adxl-motion is Python and nothing pulls python3 in" 			"the image would carry a program whose first line fails"
	fi
fi

echo
echo "--- the systemd unit is named so debhelper installs it"

# With three binary packages, debhelper only finds a unit named
# <package>.<unit>.service. Named adxl-motion.service it is ignored, the
# package builds, installs, and the service does not exist.
if [ -f "$DEB/adxl345-tools.adxl-motion.service" ]; then
	ok "the unit carries its package prefix"
elif [ -f "$DEB/adxl-motion.service" ]; then
	no "the unit has no package prefix" 		"debhelper ignores it and the package ships no service"
else
	no "there is no adxl-motion unit at all"
fi

# --------------------------------------------------- the two-driver hazard
#
# Project 5 binds an in-kernel IIO driver to this same chip at this same
# address. Two drivers on one device is the only conflict on this bench
# that produces readings that are WRONG rather than absent, so the two
# projects never share an image. bench-userdrv-image says so in a comment
# and this is the assertion behind that comment.

echo
echo "--- project 5's driver must not be in project 11's image"

IMG=$ROOT/meta-bench/recipes-core/images/bench-userdrv-image.bb
if [ ! -f "$IMG" ]; then
	no "missing: $IMG"
elif grep -qE '^[^#]*kernel-module-.*adxl' "$IMG"; then
	no "the image installs an in-kernel adxl driver" \
		"two drivers on one device give readings that are wrong"
else
	ok "no in-kernel adxl driver is installed"
fi

# In the IMAGE_INSTALL block, not anywhere in the file: the DESCRIPTION
# names the library too, so a plain grep passes even with the package
# removed. That version of this check was written first and proved
# nothing.
if [ -f "$IMG" ] && awk '/^IMAGE_INSTALL/,/^"/' "$IMG" |
	grep -qE '^[[:space:]]*libadxl345[[:space:]]'; then
	ok "the image installs the userspace library"
else
	no "IMAGE_INSTALL does not name libadxl345"
fi

KAS=$ROOT/kas/bench-userdrv.yml
if [ -f "$KAS" ] && grep -q 'ENABLE_I2C = "1"' "$KAS"; then
	ok "the bus the library needs is enabled in config.txt"
else
	no "ENABLE_I2C is not set, so there is no /dev/i2c-1 to open"
fi

# --------------------------------------------------------------- toolchain

echo
echo "--- compile and run"

if ! command -v cmake >/dev/null 2>&1; then
	skipped "cmake is absent on this host, so nothing was compiled.
         CI installs cmake and does compile it, so this is a gap on this
         machine and not in the suite."
elif ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
	skipped "no C compiler on this host, so nothing was compiled."
elif ! pkg-config --exists libgpiod 2>/dev/null; then
	skipped "libgpiod development files are absent, so the library half
         was not built. The fake-bus test needs no libgpiod but the
         shared library does, and CMake configures both together."
else
	WORK=$(mktemp -d)
	trap 'rm -rf "$WORK"' EXIT

	if cmake -S "$SRC" -B "$WORK/b" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
		>"$WORK/cfg.log" 2>&1; then
		ok "cmake configures"
	else
		no "cmake refused to configure" "$(tail -5 "$WORK/cfg.log")"
	fi

	if [ -d "$WORK/b" ] && cmake --build "$WORK/b" -j2 \
		>"$WORK/build.log" 2>&1; then
		ok "everything builds with -Werror"
	else
		no "the build failed" "$(tail -12 "$WORK/build.log")"
	fi

	if [ -x "$WORK/b/test_api" ]; then
		if "$WORK/b/test_api" >"$WORK/test.log" 2>&1; then
			n=$(grep -oE "[0-9]+ checked" "$WORK/test.log" |
				head -n 1)
			ok "the fake-bus suite passes ($n)"
		else
			no "the fake-bus suite failed" \
				"$(grep FAILED "$WORK/test.log" | head -5)"
		fi
	else
		no "test_api was not built"
	fi

	# Acceptance criterion 4, measured rather than asserted, on any host
	# that can build the library.
	lib=$(find "$WORK/b" -name "libadxl345.so.1*" -type f 2>/dev/null |
		head -n 1)
	if [ -n "$lib" ] && command -v nm >/dev/null 2>&1; then
		count=$(nm -D --defined-only "$lib" 2>/dev/null |
			grep -c " T adxl_" || true)
		if [ "$count" -eq 6 ]; then
			ok "the built library exports exactly six symbols"
		else
			no "the built library exports $count adxl_ symbols" \
				"$(nm -D --defined-only "$lib" | grep ' T ')"
		fi
	else
		skipped "nm or the built library is absent, so the exported
         symbol count was not measured here."
	fi
fi

echo
printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
