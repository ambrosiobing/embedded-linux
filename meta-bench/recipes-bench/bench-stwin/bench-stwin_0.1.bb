SUMMARY = "BLE gateway for a BlueST sensor peripheral"
DESCRIPTION = "Project 17. A D-Bus client that finds a BlueST peripheral \
through bluetoothd, subscribes to its notifying characteristics, decodes \
the frames against a feature-mask table, and forwards them to a daily CSV \
file, an MQTT topic and three link-state LEDs. It reconnects on its own \
with bounded back-off, and it notices a link that is still up and has \
stopped delivering, which a supervision timeout cannot."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://__init__.py \
    file://bluest.py \
    file://sinks.py \
    file://supervisor.py \
    file://blelink.py \
    file://stwin-gw \
    file://stwin.conf \
    file://stwin-gw.service \
    file://99-bench-gpio.rules \
"

inherit systemd useradd features_check python3-dir

REQUIRED_DISTRO_FEATURES = "systemd bluetooth"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}", the same one line the other bench recipes move.
S = "${WORKDIR}"

# The service user, and the group the udev rule hands the GPIO character
# devices to. Two separate things: the user exists so that the gateway is
# not root, and the group exists so that a non-root process can still
# drive an LED.
#
# No "bluetooth" group is created or joined. Upstream BlueZ's D-Bus policy
# allows the default context to talk to org.bluez; the group every
# tutorial mentions is Debian's patch to that file and does not exist
# here. See the comment in stwin-gw.service.
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-r gpio"
USERADD_PARAM:${PN} = "--system --no-create-home --groups gpio \
    --home-dir /var/lib/stwin-gw --shell /bin/false --user-group stwingw"

# A package rather than four loose modules, because three of them import
# the fourth and a flat install would put bluest.py on the path of every
# Python program on the image. The executable in ${bindir} is the only
# thing outside it.
STWIN_PKGDIR = "${PYTHON_SITEPACKAGES_DIR}/bench_stwin"

do_install() {
    install -d ${D}${STWIN_PKGDIR}
    for module in __init__.py bluest.py sinks.py supervisor.py blelink.py; do
        install -m 0644 ${S}/$module ${D}${STWIN_PKGDIR}/$module
    done

    install -Dm0755 ${S}/stwin-gw ${D}${bindir}/stwin-gw

    install -Dm0644 ${S}/stwin.conf ${D}${sysconfdir}/bench/stwin.conf
    install -Dm0644 ${S}/99-bench-gpio.rules \
        ${D}${sysconfdir}/udev/rules.d/99-bench-gpio.rules

    install -Dm0644 ${S}/stwin-gw.service \
        ${D}${systemd_system_unitdir}/stwin-gw.service
}

FILES:${PN} += "\
    ${STWIN_PKGDIR} \
    ${systemd_system_unitdir} \
    ${sysconfdir}/bench \
    ${sysconfdir}/udev/rules.d \
"

CONFFILES:${PN} = "${sysconfdir}/bench/stwin.conf"

# bleak is the BLE client and pulls dbus-fast with it; paho-mqtt is the
# broker side; python3-gpiod is the libgpiod v2 Python binding, version
# 2.1.3, which is the same library version the C daemons in this layer are
# compiled against.
#
# python3-asyncio is named because the OE Python split puts it in its own
# package, and the gateway is an asyncio program from its first line. An
# image that boots and a service that dies on "import asyncio" is a
# failure this repository has already paid for once, with kernel modules.
RDEPENDS:${PN} += "\
    python3-core \
    python3-asyncio \
    python3-json \
    python3-logging \
    python3-bleak \
    python3-paho-mqtt \
    python3-gpiod \
    bluez5 \
"

# Enabled at boot. Unlike the sensor hub of Project 12, there is no device
# to wait for: the peripheral is a radio that may be out of range, and
# being out of range is a state this service is built to sit in.
SYSTEMD_SERVICE:${PN} = "stwin-gw.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
