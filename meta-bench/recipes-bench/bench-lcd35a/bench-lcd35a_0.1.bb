SUMMARY = "Project 7: the userspace side of the 3.5 inch DRM panel"
DESCRIPTION = "Three programs for a Waveshare 3.5 inch RPi LCD (A) bound \
as a DRM device: drmfill, which paints a gradient through plain libdrm and \
finds the panel by driver name rather than by card number; lcd35a-corners, \
which turns four raw corner readings into a libinput calibration matrix; \
and lcd35a-verify, which reports what can be checked from the board and \
names what cannot."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://drmfill.c \
           file://lcd35a-corners \
           file://lcd35a-verify"

S = "${WORKDIR}"

# libdrm and nothing else. This program deliberately uses only public
# libdrm and ioctl interfaces: it exists to show what a compositor does,
# and a compositor has no vendor library either.
DEPENDS = "libdrm"

inherit pkgconfig

do_compile() {
    # Same flags as the rest of the C in this repository. -Werror is not
    # decoration: this program is compiled on the CI host as well, against
    # the host libdrm, which is how a mistake in it is found without a
    # board.
    ${CC} ${CFLAGS} ${LDFLAGS} -Wall -Wextra -Werror -O2 \
        `pkg-config --cflags libdrm` \
        ${S}/drmfill.c -o ${B}/drmfill \
        `pkg-config --libs libdrm`
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/drmfill ${D}${bindir}/drmfill
    install -m 0755 ${S}/lcd35a-corners ${D}${bindir}/lcd35a-corners
    install -m 0755 ${S}/lcd35a-verify ${D}${bindir}/lcd35a-verify
}

# NO UDEV RULE IS SHIPPED, AND THAT IS DELIBERATE.
#
# The calibration matrix is a property of one panel and one rotation, not
# of this software. Shipping a rule with the identity matrix in it would
# change nothing, because libinput already defaults to the identity, and
# would leave a file that looks like calibration and is not. Shipping a
# matrix measured on some other panel would be worse.
#
# So lcd35a-corners prints the rule and the bring-up notes say where to put
# it. This is the same rule as everywhere else on this bench: the image
# carries capability, the card carries identity.

RDEPENDS:${PN} = "libdrm-tests evtest"
