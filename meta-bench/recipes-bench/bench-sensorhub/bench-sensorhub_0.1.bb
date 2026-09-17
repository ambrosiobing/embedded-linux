SUMMARY = "Sensor hub D-Bus service, its policy and a client"
DESCRIPTION = "Project 12. A daemon that owns the serial link to a sensor \
hub microcontroller, validates its framed CBOR stream and republishes it \
as org.bench.SensorHub1 on the system bus, with the bus policy that says \
who may talk to it, the polkit action that says who may calibrate it, the \
two activation paths that start it, and a client that knows none of the \
wire format."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://proto.c \
    file://proto.h \
    file://sensorhubd.c \
    file://hubctl \
    file://org.bench.SensorHub1.conf \
    file://org.bench.SensorHub1.service \
    file://org.bench.sensorhub.policy \
    file://50-sensorhub.rules \
    file://80-sensorhub.rules \
    file://sensorhubd.service \
"

# polkit-group-rule.inc is meta-oe's own idiom for a recipe that ships a
# polkit rule: it pulls in polkit, requires the distro feature, creates
# /etc/polkit-1/rules.d with the ownership polkit insists on, and prepends
# the polkitd user to USERADD_PARAM so that the chown has somebody to
# chown to. Requiring it from another layer works the same way this
# repository already requires core-image-minimal.bb from poky: the path is
# relative to a BBPATH entry, and every layer root is one.
require recipes-extended/polkit/polkit-group-rule.inc

DEPENDS += "systemd libcbor"

inherit systemd pkgconfig features_check

# polkit comes from the .inc above; systemd is this recipe's own, because
# sd-bus, sd-event and the unit all assume it.
REQUIRED_DISTRO_FEATURES = "systemd polkit"

# scarthgap still unpacks into WORKDIR. On walnascar and later this
# becomes S = "${UNPACKDIR}", the same one line every other bench recipe
# has to move.
S = "${WORKDIR}"

CFLAGS:append = " -Wall -Wextra"

do_compile() {
    ${CC} ${CFLAGS} ${CPPFLAGS} -I${S} \
        $(pkg-config --cflags libsystemd libcbor) \
        ${S}/sensorhubd.c ${S}/proto.c -o sensorhubd \
        ${LDFLAGS} $(pkg-config --libs libsystemd libcbor)
}

do_install() {
    install -Dm0755 sensorhubd ${D}${bindir}/sensorhubd
    install -Dm0755 ${S}/hubctl ${D}${bindir}/hubctl

    # The bus policy goes in ${datadir}, not ${sysconfdir}. A package
    # ships its policy; /etc/dbus-1/system.d is where an administrator
    # overrides it, and nothing in this repository is the administrator.
    install -Dm0644 ${S}/org.bench.SensorHub1.conf \
        ${D}${datadir}/dbus-1/system.d/org.bench.SensorHub1.conf

    # The activation file: a client call starts the daemon.
    install -Dm0644 ${S}/org.bench.SensorHub1.service \
        ${D}${datadir}/dbus-1/system-services/org.bench.SensorHub1.service

    install -Dm0644 ${S}/org.bench.sensorhub.policy \
        ${D}${datadir}/polkit-1/actions/org.bench.sensorhub.policy

    # The rules directory was created and chowned by the .inc's
    # do_install:prepend. The rule itself is 0644: it is read by polkitd,
    # and the 0700 that matters is on the directory.
    install -m0644 ${S}/50-sensorhub.rules \
        ${D}${sysconfdir}/polkit-1/rules.d/50-sensorhub.rules

    # The other activation path: a device plug starts the daemon.
    install -Dm0644 ${S}/80-sensorhub.rules \
        ${D}${sysconfdir}/udev/rules.d/80-sensorhub.rules

    install -Dm0644 ${S}/sensorhubd.service \
        ${D}${systemd_system_unitdir}/sensorhubd.service
}

FILES:${PN} += "\
    ${systemd_system_unitdir} \
    ${datadir}/dbus-1 \
    ${datadir}/polkit-1 \
    ${sysconfdir}/polkit-1 \
    ${sysconfdir}/udev/rules.d \
"

# The daemon's own user, and the group the polkit rule names. Neither is
# created by hand on the board: a user that exists only because somebody
# ran useradd once is a user that will be missing on the next image.
#
# dialout is a supplementary group rather than the primary one, because
# the tty is the only thing it unlocks and the daemon should not own files
# as a group that every serial user is in.
USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "--system --no-create-home --user-group \
--home-dir / --shell /bin/nologin --groups dialout sensorhub"
GROUPADD_PARAM:${PN} = "--system bench"

# The unit is NOT enabled here, and that is the point of the project.
# Two activation paths cover the two situations: udev starts it when the
# device appears, and the bus starts it when a client calls. A unit
# enabled at boot would start before either, fail because there is no
# device, and spend its RestartSec budget before the Nucleo is plugged in.
SYSTEMD_SERVICE:${PN} = "sensorhubd.service"
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

RDEPENDS:${PN} += "\
    libcbor \
    dbus \
    polkit \
    python3-core \
    python3-asyncio \
    python3-dbus-next \
"
