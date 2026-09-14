SUMMARY = "Status LED daemon"
DESCRIPTION = "A daemon that mirrors one word from /run/bench/state onto \
three LEDs on the 40-pin header, and the systemd plumbing that writes that \
word: a polling timer, an OnFailure latch and the watch list of units whose \
health the LEDs report."
HOMEPAGE = "https://github.com/ambrosiobing/meta-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://bench-status.c \
    file://bench-state \
    file://bench-status.service \
    file://bench-state.service \
    file://bench-state.timer \
    file://bench-state-failed@.service \
    file://bench-onfailure.conf \
    file://bench-status.tmpfiles.conf \
    file://watch.conf \
    file://leds.conf \
"

DEPENDS = "libgpiod"

inherit systemd pkgconfig features_check

REQUIRED_DISTRO_FEATURES = "systemd"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}"; it is the only line in the layer that has to move.
S = "${WORKDIR}"

# -Werror is enforced in CI, not here: a toolchain upgrade should fail a
# pull request, not an image build on someone else's machine.
CFLAGS:append = " -Wall -Wextra"

do_compile() {
    ${CC} ${CFLAGS} ${CPPFLAGS} $(pkg-config --cflags libgpiod) \
        ${S}/bench-status.c -o bench-status \
        ${LDFLAGS} $(pkg-config --libs libgpiod)
}

do_install() {
    install -Dm0755 bench-status ${D}${bindir}/bench-status
    install -Dm0755 ${S}/bench-state ${D}${bindir}/bench-state

    install -Dm0644 ${S}/bench-status.service \
        ${D}${systemd_system_unitdir}/bench-status.service
    install -Dm0644 ${S}/bench-state.service \
        ${D}${systemd_system_unitdir}/bench-state.service
    install -Dm0644 ${S}/bench-state.timer \
        ${D}${systemd_system_unitdir}/bench-state.timer
    install -Dm0644 ${S}/bench-state-failed@.service \
        ${D}${systemd_system_unitdir}/bench-state-failed@.service

    # A vendor drop-in, so it lives next to the unit it extends rather than
    # in /etc where the administrator's own overrides belong.
    install -Dm0644 ${S}/bench-onfailure.conf \
        ${D}${systemd_system_unitdir}/sshd.socket.d/10-bench-onfailure.conf

    install -Dm0644 ${S}/bench-status.tmpfiles.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/bench-status.conf

    install -Dm0644 ${S}/watch.conf ${D}${sysconfdir}/bench/watch.conf
    install -Dm0644 ${S}/leds.conf ${D}${sysconfdir}/bench/leds.conf
}

FILES:${PN} += "\
    ${systemd_system_unitdir} \
    ${nonarch_libdir}/tmpfiles.d \
    ${sysconfdir}/bench \
"

CONFFILES:${PN} = "${sysconfdir}/bench/watch.conf ${sysconfdir}/bench/leds.conf"

# systemctl, and the tmpfiles handling that creates /run/bench.
RDEPENDS:${PN} += "systemd"

SYSTEMD_SERVICE:${PN} = "bench-status.service bench-state.timer"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
