SUMMARY = "Cellular watchdog, control lines and metrics"
DESCRIPTION = "The code half of the LTE router: a C tool that owns the \
modem's PWRKEY and FLIGHT lines, a watchdog that probes the bearer and \
escalates from a bearer restart through a modem reset to a power cycle, \
and a collector that writes the modem's state, signal and position as \
Prometheus text for a timer to refresh and a small server to hand out."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://lte-gpio.c \
    file://lte-watchdog \
    file://lte-exporter \
    file://lte.conf \
    file://lte-metrics.conf \
    file://lte.tmpfiles.conf \
    file://lte-watchdog.service \
    file://lte-flight.service \
    file://lte-exporter.service \
    file://lte-exporter.timer \
    file://lte-metrics.service \
"

DEPENDS = "libgpiod"

inherit systemd pkgconfig features_check

REQUIRED_DISTRO_FEATURES = "systemd"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}", the same one line bench-status has to move.
S = "${WORKDIR}"

CFLAGS:append = " -Wall -Wextra"

do_compile() {
    ${CC} ${CFLAGS} ${CPPFLAGS} $(pkg-config --cflags libgpiod) \
        ${S}/lte-gpio.c -o lte-gpio \
        ${LDFLAGS} $(pkg-config --libs libgpiod)
}

do_install() {
    install -Dm0755 lte-gpio ${D}${bindir}/lte-gpio
    install -Dm0755 ${S}/lte-watchdog ${D}${bindir}/lte-watchdog
    install -Dm0755 ${S}/lte-exporter ${D}${bindir}/lte-exporter

    install -Dm0644 ${S}/lte.conf ${D}${sysconfdir}/bench/lte.conf
    install -Dm0644 ${S}/lte-metrics.conf \
        ${D}${sysconfdir}/bench/lte-metrics.conf

    install -Dm0644 ${S}/lte.tmpfiles.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/lte.conf

    for unit in lte-watchdog.service lte-flight.service \
            lte-exporter.service lte-exporter.timer lte-metrics.service; do
        install -Dm0644 ${S}/$unit ${D}${systemd_system_unitdir}/$unit
    done
}

FILES:${PN} += "\
    ${systemd_system_unitdir} \
    ${nonarch_libdir}/tmpfiles.d \
    ${sysconfdir}/bench \
"

CONFFILES:${PN} = "\
    ${sysconfdir}/bench/lte.conf \
    ${sysconfdir}/bench/lte-metrics.conf \
"

# mmcli and nmcli are what the watchdog drives; ping and ip are what it
# probes with. python3-modules is the honest version of a dependency that
# should eventually be a measured list of the six modules these two scripts
# import. It is listed whole here because guessing at the OE python split
# and being wrong produces an image that boots and a watchdog that dies on
# its first import, which is the worst of both. Trim it once
# oe-pkgdata-util has been run against a built image; the size is recorded
# in projects/15-lte-router/README.md.
RDEPENDS:${PN} += "\
    libgpiod \
    modemmanager \
    networkmanager \
    iproute2 \
    iputils-ping \
    python3-core \
    python3-modules \
"

# lte-exporter.service is not listed: the timer pulls it, and enabling a
# oneshot service as well as its timer starts it once at boot for no reason.
SYSTEMD_SERVICE:${PN} = "\
    lte-flight.service \
    lte-watchdog.service \
    lte-exporter.timer \
    lte-metrics.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
