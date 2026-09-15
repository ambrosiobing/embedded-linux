SUMMARY = "Wireless client networking for the bench"
DESCRIPTION = "The half of the bench configuration that assumes this board \
joins somebody else's wireless network: a systemd-networkd profile for \
wlan0 and the first-boot step that reads SSID and PSK from the boot \
partition into a wpa_supplicant configuration. Images that run their own \
access point, or that are gateways rather than clients, leave this out."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://25-wireless.network \
    file://bench-wifi-setup \
    file://bench-wifi-setup.service \
"

inherit allarch systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd wifi"

S = "${WORKDIR}"

do_install() {
    install -Dm0644 ${S}/25-wireless.network \
        ${D}${nonarch_libdir}/systemd/network/25-wireless.network

    install -Dm0755 ${S}/bench-wifi-setup ${D}${bindir}/bench-wifi-setup

    install -Dm0644 ${S}/bench-wifi-setup.service \
        ${D}${systemd_system_unitdir}/bench-wifi-setup.service
}

FILES:${PN} += "\
    ${nonarch_libdir}/systemd/network \
    ${systemd_system_unitdir} \
"

# wpa-supplicant does the association; the firmware for the radio itself is
# named in the image recipe, where it can be justified alongside the rest.
RDEPENDS:${PN} += "wpa-supplicant"

SYSTEMD_SERVICE:${PN} = "bench-wifi-setup.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
