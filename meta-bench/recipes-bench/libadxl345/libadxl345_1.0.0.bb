SUMMARY = "Userspace driver for the ADXL345, as a versioned shared library"
DESCRIPTION = "libadxl345 drives a DFRobot SEN0032 over i2c-dev with an \
opaque six-function C API, a soname and hidden visibility. The same CMake \
project is packaged for Debian in projects/11-adxl345-userspace/debian, so \
the two packagings cannot drift. Project 11."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

# One directory rather than a list of files. The tree inside it is a
# complete CMake project that also builds outside Yocto, which is the
# point: a developer runs cmake on it, debhelper runs cmake on it, and
# this recipe runs cmake on it. Three consumers, one build definition.
SRC_URI = "file://adxl345-linux"

S = "${WORKDIR}/adxl345-linux"

DEPENDS = "libgpiod"

# python3-dir gives PYTHON_SITEPACKAGES_DIR, which is where this
# distribution's interpreter actually looks. CMake defaults ADXL_PYDIR to
# Debian's dist-packages, and installing there inside a Yocto image
# produces the worst kind of failure: the file is plainly present and the
# module is not importable.
inherit cmake pkgconfig python3-dir

# Where this distribution's interpreter actually looks, without the
# leading slash that CMake's DESTINATION must not have.
PYDIR = "${@d.getVar('PYTHON_SITEPACKAGES_DIR').lstrip('/')}"

# The tests are built by default and are not shipped. They link the fake
# platform layer instead of the real one, so the test binary cannot talk
# to a bus even if somebody installed it.
#
# NOT run under qemu: these are aarch64 binaries and the build host is
# x86_64. ctest would report every case as a failure to execute, which is
# a red build for the wrong reason. The fake-bus suite runs natively in CI
# through tests/adxl345-build-test.sh, which is where it belongs.
#
# ONE ASSIGNMENT, and that is deliberate. This was briefly written as a
# "+=" for the python directory followed by a "=" for the build type,
# and the second silently discarded the first: the bindings would have
# installed to Debian's path inside a Yocto image, present on disk and
# not importable. The same shape as two PACKAGECONFIG:remove lines, which
# this repository's notes already warn about.
EXTRA_OECMAKE = "-DCMAKE_BUILD_TYPE=RelWithDebInfo \
                 -DADXL_PYDIR=${PYDIR}"

# The library and the tool are split the way any distribution splits them:
# the runtime library in the main package, the header and the pkg-config
# file in -dev, the application in -tools. Yocto does the first two on its
# own; the third needs saying.
PACKAGES =+ "${PN}-tools"
FILES:${PN}-tools = "${bindir}/adxl-map ${bindir}/adxl-motion \
                     ${PYTHON_SITEPACKAGES_DIR}/adxl345"

# adxl-motion is Python and imports the bindings, so the package has to
# pull in an interpreter. Without this the image installs a program whose
# first line fails, which looks like a broken program rather than a
# missing dependency.
RDEPENDS:${PN}-tools += "python3-core python3-ctypes"

# The udev rule and the group are NOT here.
#
# On Debian this project ships a rule putting /dev/i2c-* in group i2c,
# because a plain Debian has none. The bench images have root with no
# password from debug-tweaks, so a group rule here would be ceremony that
# changes nothing, and it would be the kind of ceremony that looks like
# security. The Debian packaging carries it because there it does work.
# See the project README.
