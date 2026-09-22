SUMMARY = "The broker half of Project 18: MQTT over TLS, certificates as identity"
DESCRIPTION = "Mosquitto with one TLS listener and no plaintext one, a \
private CA as the only thing it trusts, a revocation list it actually \
reads, and an access control list keyed on the certificate's common name. \
No certificate is in this repository; they are issued on the laptop by \
projects/18-edge-ap-mqtt/pki/bench-pki.sh and copied to the card."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://mosquitto.conf \
    file://mosquitto.acl \
    file://bench-broker.tmpfiles.conf \
    file://mosquitto-bench.conf \
    file://bench-broker-setup \
    file://bench-broker-setup.service \
"

inherit systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

S = "${WORKDIR}"

do_install() {
    install -Dm0755 ${S}/bench-broker-setup \
        ${D}${bindir}/bench-broker-setup
    install -Dm0644 ${S}/bench-broker-setup.service \
        ${D}${systemd_system_unitdir}/bench-broker-setup.service

    install -Dm0644 ${S}/mosquitto.conf \
        ${D}${sysconfdir}/bench/mosquitto.conf
    install -Dm0644 ${S}/mosquitto.acl \
        ${D}${sysconfdir}/bench/mosquitto.acl
    install -Dm0644 ${S}/bench-broker.tmpfiles.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/bench-broker.conf

    # The directory the certificates go into, created empty. The files
    # themselves arrive on the card after flashing, the same way the
    # wireless passphrase does: the image carries the capability and the
    # card carries the identity.
    install -d -m 0750 ${D}${sysconfdir}/bench/pki

    # A drop-in rather than a unit of its own, unlike the access point's
    # three. The mosquitto recipe already ships mosquitto.service and the
    # only thing this project changes is which configuration it reads.
    install -Dm0644 ${S}/mosquitto-bench.conf \
        ${D}${systemd_system_unitdir}/mosquitto.service.d/bench.conf
}

FILES:${PN} += "\
    ${systemd_system_unitdir} \
    ${nonarch_libdir}/tmpfiles.d \
    ${sysconfdir}/bench \
"

CONFFILES:${PN} = "\
    ${sysconfdir}/bench/mosquitto.conf \
    ${sysconfdir}/bench/mosquitto.acl \
"

# mosquitto-clients is mosquitto_pub and mosquitto_sub, and they are not a
# convenience here: acceptance criteria 5 through 8 are all statements
# about what the broker refuses, and the way to demonstrate a refusal is to
# attempt the thing and capture the error. A board that can only be tested
# from another machine cannot be tested at all when the other machine is
# the thing being debugged.
#
# openssl for s_client, which is criterion 4's evidence: the chain the
# client verified and the Verify return code line.
# The setup unit is enabled; mosquitto.service is not listed here because
# the mosquitto recipe already enables its own, and this project only adds
# a drop-in to it.
SYSTEMD_SERVICE:${PN} = "bench-broker-setup.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} += "\
    mosquitto \
    mosquitto-clients \
    openssl-bin \
"
