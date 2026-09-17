SUMMARY = "Verification and demonstration tools for the Explorer 700 HAT"
DESCRIPTION = "explorer-verify checks all eleven peripherals through their \
kernel subsystems and is the acceptance test for Project 6. explorer-oled \
writes text to the panel through the framebuffer, and explorer-beep sounds \
the buzzer through evdev. Neither touches an I2C or SPI register."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://explorer-verify \
           file://explorer-oled \
           file://explorer-beep \
           file://99-explorer700.rules \
           file://rc_keymap.toml"

S = "${WORKDIR}"

# Nothing is compiled. Two of these are Python and one is POSIX shell, and
# the interpreters are the only runtime dependency. python3-core rather
# than python3: explorer-oled and explorer-beep use os, sys, struct and
# time and nothing else, which is deliberate and is documented in each
# file's header.
RDEPENDS:${PN} = "python3-core"

# THE THREE LISTS MUST AGREE. Every file above appears below, and the
# package appears in bench-explorer-image's IMAGE_INSTALL. scripts/lint.py
# checks the first two of those; the third is checked by reading, which is
# why the image recipe says which packages it expects and why.
do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/explorer-verify ${D}${bindir}/explorer-verify
    install -m 0755 ${S}/explorer-oled ${D}${bindir}/explorer-oled
    install -m 0755 ${S}/explorer-beep ${D}${bindir}/explorer-beep

    # The udev rule gives the three input devices stable names. Without it
    # the event indices move between boots, because four of the joystick's
    # five lines arrive over I2C behind an expander with no fixed probe
    # order.
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${S}/99-explorer700.rules \
        ${D}${sysconfdir}/udev/rules.d/99-explorer700.rules

    # The IR keymap is an EXAMPLE and is installed as one. Its scancodes
    # came from the vendor manual's own output, not from a remote on this
    # bench, and the file says so at length. It is not wired into
    # /etc/rc_maps.cfg for the reason the bench uses everywhere: a line
    # there would be a claim about which remote is in the drawer, and the
    # image carries capability while the bench carries identity.
    install -m 0644 ${S}/rc_keymap.toml ${D}${sysconfdir}/rc_keymap.toml
}

FILES:${PN} += "${sysconfdir}/udev/rules.d/99-explorer700.rules \
                ${sysconfdir}/rc_keymap.toml"
