SUMMARY = "A Cat-M and NB-IoT position tracker, driven by AT commands"
DESCRIPTION = "The code half of Project 16: a state machine that powers a \
modem, locks it to LTE, attaches, sends one CoAP report through the \
modem's own IP stack and lets it sleep, plus the tool that owns the power \
key and the instrument marker the current trace is integrated between. \
Deliberately without ModemManager, because a daemon whose job is to always \
know the modem's state is the opposite of a device that sleeps."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://tracker \
    file://tracker-gpio.c \
    file://tracker.conf \
    file://78-sim7070.rules \
    file://tracker.service \
    file://tracker.timer \
"

DEPENDS = "libgpiod"

inherit systemd pkgconfig features_check

REQUIRED_DISTRO_FEATURES = "systemd"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}", the same one line bench-status and bench-lte have to
# move when this repository moves release.
S = "${WORKDIR}"

CFLAGS:append = " -Wall -Wextra"

do_compile() {
    ${CC} ${CFLAGS} ${CPPFLAGS} $(pkg-config --cflags libgpiod) \
        ${S}/tracker-gpio.c -o tracker-gpio \
        ${LDFLAGS} $(pkg-config --libs libgpiod)
}

do_install() {
    install -Dm0755 tracker-gpio ${D}${bindir}/tracker-gpio
    install -Dm0755 ${S}/tracker ${D}${bindir}/tracker

    install -Dm0644 ${S}/tracker.conf ${D}${sysconfdir}/bench/tracker.conf

    install -Dm0644 ${S}/78-sim7070.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/78-sim7070.rules

    install -Dm0644 ${S}/tracker.service \
        ${D}${systemd_system_unitdir}/tracker.service
    install -Dm0644 ${S}/tracker.timer \
        ${D}${systemd_system_unitdir}/tracker.timer
}

FILES:${PN} += "\
    ${systemd_system_unitdir} \
    ${nonarch_base_libdir}/udev/rules.d \
    ${sysconfdir}/bench \
"

# Preserved across an upgrade, because the APN, the server and the two GPIO
# offsets are written into it after flashing and exist nowhere else. An
# image update that overwrote this file would silently unconfigure the
# board, and the symptom would be a tracker that refuses to drive a GPIO it
# drove yesterday.
CONFFILES:${PN} = "${sysconfdir}/bench/tracker.conf"

# python3-core and not python3-modules, which is what Project 15 installs.
# That recipe says plainly that the whole split is the honest version of a
# dependency nobody had measured, and this program is small enough to
# measure: it imports argparse, errno, os, random, re, select, struct,
# subprocess, sys and time, and every one of those is in python3-core.
# Nothing here imports json, urllib, ssl or logging, which is most of what
# the modules package is for.
#
# If that turns out to be wrong the symptom is precise and immediate: the
# unit fails on its first run with an ImportError naming the module. Run
# oe-pkgdata-util find-path against a built image before changing it.
#
# No modemmanager, no networkmanager, no iproute2 and no ping. This image
# has no network interface at all: the CoAP datagram is built in the
# tracker and handed to the modem over the AT port, so there is nothing for
# ip or ping to look at. That absence is the project, not an omission.
RDEPENDS:${PN} += "\
    libgpiod \
    python3-core \
"

# The timer is enabled and the service is not. Enabling a oneshot service
# as well as its timer runs it once at boot for no reason, which here means
# an attach and a report before the board has finished coming up. Project
# 15's recipe leaves lte-exporter.service out of its list for exactly this
# reason and says so.
SYSTEMD_SERVICE:${PN} = "tracker.timer"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
