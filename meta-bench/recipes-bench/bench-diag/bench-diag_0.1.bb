SUMMARY = "Voltmeter, logic probe and continuity tester from GPIO lines"
DESCRIPTION = "There is no multimeter on this bench. A GPIO configured as \
an input is a one-bit voltmeter with a threshold near 1.3 V, and reading \
one line under both bias settings distinguishes a driven line from a \
floating one, which one reading cannot. This is that method as a program, \
plus a continuity test that drives one line and senses another."
HOMEPAGE = "https://github.com/ambrosiobing/meta-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bench-diag.c"

DEPENDS = "libgpiod"

inherit pkgconfig

# NO features_check AND NO systemd, UNLIKE EVERY OTHER bench-* RECIPE.
#
# This is deliberate and it is the point of the thing. It is one static
# binary with libgpiod and libc behind it, no unit, no configuration file
# and no distro feature required, so it installs into any image including
# ones with no init system worth speaking of. A diagnostic that declines
# to install on the image you are trying to diagnose is no use at all.

# scarthgap still unpacks into WORKDIR. On walnascar and later this
# becomes S = "${UNPACKDIR}"; the same line moves in bench-status.
S = "${WORKDIR}"

# -Werror is enforced in CI, not here, matching bench-status: a toolchain
# upgrade should fail a pull request rather than someone else's image
# build. scripts/host-check.sh compiles this with -Werror on the host.
CFLAGS:append = " -Wall -Wextra"

do_compile() {
    ${CC} ${CFLAGS} ${CPPFLAGS} $(pkg-config --cflags libgpiod) \
        ${S}/bench-diag.c -o bench-diag \
        ${LDFLAGS} $(pkg-config --libs libgpiod)
}

do_install() {
    install -Dm0755 bench-diag ${D}${bindir}/bench-diag
}

# libgpiod-tools gives gpioget and gpioset, which do the same readings by
# hand and are what this was written from. They are a runtime
# recommendation rather than a dependency: this program needs neither, and
# anyone debugging the program itself will want them.
RRECOMMENDS:${PN} = "libgpiod-tools"
