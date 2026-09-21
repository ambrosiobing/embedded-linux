SUMMARY = "Kiosk plumbing: the graphics diagnostic and the touch rule"
DESCRIPTION = "What Project 13 needs on the board besides the compositor and \
the dashboard: bench-gfx, which walks the graphics stack one layer at a time \
and names what it could not ask, and a udev calibration rule shipped \
disabled because enabling it on a correctly rotated panel rotates the touch \
surface twice."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://bench-gfx \
    file://99-bench-touch.rules \
"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}"; it is the only line in the layer that has to move.
S = "${WORKDIR}"

# No compositor unit here, deliberately. oe-core's weston-init owns that,
# and meta-bench/recipes-graphics/wayland/weston-init.bbappend changes
# the one file that makes it a kiosk. A second unit managing the same
# compositor is the two-managers bug the design document's ownership
# table exists to prevent, and it would stay invisible until both tried
# to take DRM master.

do_install() {
    install -Dm0755 ${S}/bench-gfx ${D}${bindir}/bench-gfx

    # NOT into /etc/udev/rules.d. The rule is shipped as documentation
    # with a matrix in it, and putting it where udev reads it would arm
    # a correction that is wrong on a board whose rotation already
    # works. The operator copies it after measuring with
    # "libinput debug-events", which is the measurement the file itself
    # opens by asking for.
    #
    # This is the same discipline as the recovery rung in Project 15: a
    # hardware property the software cannot verify is armed by hand,
    # and the un-armed state is visible rather than silent.
    install -Dm0644 ${S}/99-bench-touch.rules \
        ${D}${docdir}/${BPN}/99-bench-touch.rules
}

FILES:${PN} = "${bindir}/bench-gfx"
FILES:${PN}-doc = "${docdir}/${BPN}"

# bench-gfx reads what these produce. None is a hard requirement: the
# script names every question it could not ask, so a board without
# libinput still gets the evdev half rather than a silent skip.
RRECOMMENDS:${PN} = "libinput wayland-utils"
