SUMMARY = "Device tree overlay for the Waveshare 3.5 inch RPi LCD (A)"
DESCRIPTION = "Binds an ILI9486 panel on SPI0 CE0 to the in-tree ili9486 \
tiny DRM driver and an XPT2046 touch controller on SPI0 CE1 to ads7846, \
with the pen-down interrupt on GPIO17 and both spidev nodes disabled. \
Project 7."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bench-lcd35a-overlay.dts"

S = "${WORKDIR}"

# dtc on the build host, not in the image. The overlay is compiled once
# here and shipped as a .dtbo; a board that compiles its own device tree
# has a boot that depends on a tool being installed.
DEPENDS = "dtc-native"

# A .dtbo is data. Nothing in it is compiled for a target ABI.
inherit allarch deploy

do_compile() {
    # -@ keeps the symbol table, which is what lets the overlay resolve
    # &spi0, &spidev0, &spidev1 and &gpio by phandle at load time. Without
    # it dtoverlay refuses the file with "not a base or overlay", which
    # reads like corruption rather than a missing flag.
    #
    # &spidev0 and &spidev1 exist only in the Raspberry Pi device tree and
    # not in mainline. That is fine: an overlay is resolved against the
    # base tree on the board, so the symbol has to exist there and not
    # here.
    #
    # -Wno-unit_address_vs_reg is NOT passed. The two nodes are named
    # lcd35a@0 and lcd35a_ts@1 with matching reg properties, so the check
    # passes, and acceptance criterion 6 is that this compiles without
    # warnings. Silencing the checker would make that criterion vacuous.
    dtc -@ -I dts -O dtb \
        -o ${B}/bench-lcd35a.dtbo \
        ${S}/bench-lcd35a-overlay.dts
}

# The firmware reads overlays from an "overlays" directory on the FAT boot
# partition, so the layout here has to match the layout on the card.
# bench-lcd35a-image picks it up with IMAGE_BOOT_FILES and a do_image
# dependency on this task, because a file deployed after the image is
# assembled is a file the image does not contain.
do_deploy() {
    install -d ${DEPLOYDIR}/overlays
    install -m 0644 ${B}/bench-lcd35a.dtbo ${DEPLOYDIR}/overlays/
}

addtask deploy after do_compile before do_build

# Nothing reaches the rootfs. The overlay lives on the boot partition,
# which is not part of the rootfs at all, so this package is empty by
# design and Yocto is told so rather than warning about it.
ALLOW_EMPTY:${PN} = "1"
