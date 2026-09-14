SUMMARY = "Bench site configuration"
DESCRIPTION = "Settings that belong to this bench rather than to any one \
project: the console keymap, and later the network defaults. Kept as its \
own recipe so that the status daemon stays about status and this stays \
about the bench."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

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

FILES:${PN} += "${sysconfdir}/vconsole.conf"

CONFFILES:${PN} = "${sysconfdir}/vconsole.conf"

# systemd-vconsole-setup applies it, and the keymap data itself comes from
# the keymaps package that packagegroup-core-boot already pulls in.
RDEPENDS:${PN} += "keymaps kbd"
