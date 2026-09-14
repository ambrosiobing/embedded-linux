SUMMARY = "Bench site configuration"
DESCRIPTION = "Settings that belong to this bench rather than to any one \
project: the console keymap, the wireless network file, and the first-boot \
step that reads WiFi credentials from the boot partition. Kept as its own \
recipe so that the status daemon stays about status and this stays about \
the bench."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://vconsole.conf \
    file://25-wireless.network \
    file://bench-wifi-setup \
    file://bench-wifi-setup.service \
"

inherit allarch systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd wifi"

S = "${WORKDIR}"

do_install() {
    install -Dm0644 ${S}/vconsole.conf ${D}${sysconfdir}/vconsole.conf

    install -Dm0644 ${S}/25-wireless.network \
        ${D}${nonarch_libdir}/systemd/network/25-wireless.network

    install -Dm0755 ${S}/bench-wifi-setup ${D}${bindir}/bench-wifi-setup

    install -Dm0644 ${S}/bench-wifi-setup.service \
        ${D}${systemd_system_unitdir}/bench-wifi-setup.service
}

FILES:${PN} += "\
    ${sysconfdir}/vconsole.conf \
    ${nonarch_libdir}/systemd/network \
    ${systemd_system_unitdir} \
"

CONFFILES:${PN} = "${sysconfdir}/vconsole.conf"

# keymaps and kbd carry the keymap data that systemd-vconsole-setup applies.
# wpa-supplicant does the association; the firmware for the radio itself is
# named in the image recipe, where it can be justified alongside the rest.
RDEPENDS:${PN} += "keymaps kbd wpa-supplicant"

SYSTEMD_SERVICE:${PN} = "bench-wifi-setup.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
