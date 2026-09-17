SUMMARY = "Bench site identity"
DESCRIPTION = "Settings that describe this workshop rather than any one \
project or any one network: at present the console keymap. Kept separate \
from bench-net-wifi so that an image which manages its own networking, such \
as the router image of Project 15, can take the keyboard without also \
taking a wpa_supplicant client profile for wlan0."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://vconsole.conf"

inherit allarch features_check

REQUIRED_DISTRO_FEATURES = "systemd"

S = "${WORKDIR}"

do_install() {
    install -Dm0644 ${S}/vconsole.conf ${D}${sysconfdir}/vconsole.conf
}

CONFFILES:${PN} = "${sysconfdir}/vconsole.conf"

# keymaps and kbd carry the keymap data that systemd-vconsole-setup applies.
RDEPENDS:${PN} += "keymaps kbd"
