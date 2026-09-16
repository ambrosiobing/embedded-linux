SUMMARY = "Device tree overlay for the X-NUCLEO-IKS4A1 sensor shield"
DESCRIPTION = "Binds the LSM6DSV16X, LIS2MDL, LPS22DF and SHT40 of an \
X-NUCLEO-IKS4A1 to their in-tree drivers on I2C1, with INT1 of the IMU on \
GPIO24 for FIFO watermark and data-ready events. Project 10."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bench-iks4a1-overlay.dts"

S = "${WORKDIR}"

# dtc, on the build host rather than in the image. The overlay is compiled
# once here and shipped as a .dtbo, instead of shipping the .dts and a
# compiler to the board. The board has no business compiling its own
# device tree, and the failure mode of doing it there is a boot that
# depends on a tool being installed.
DEPENDS = "dtc-native"

# allarch: a .dtbo is architecture independent in the sense that matters
# here, which is that nothing in it is compiled for a target ABI. The
# device tree is data.
inherit allarch deploy

do_compile() {
    # -@ keeps the symbol table, which is what lets an overlay reference
    # &i2c1 and &gpio by phandle at load time. Without it dtc emits a
    # .dtbo that dtoverlay refuses with "not a base or overlay", which
    # reads like a corrupt file rather than a missing flag.
    dtc -@ -I dts -O dtb \
        -o ${B}/bench-iks4a1.dtbo \
        ${S}/bench-iks4a1-overlay.dts
}

# The firmware loads overlays from an "overlays" directory on the boot
# partition, so the layout in DEPLOYDIR has to match the layout on the
# card. bench-iio-image.bb picks it up from here with IMAGE_BOOT_FILES and
# a do_image dependency on this task, because a file that is deployed
# after the image is assembled is a file the image does not contain.
do_deploy() {
    install -d ${DEPLOYDIR}/overlays
    install -m 0644 ${B}/bench-iks4a1.dtbo ${DEPLOYDIR}/overlays/
}

addtask deploy after do_compile before do_build

# Nothing is installed into the rootfs. The overlay lives on the FAT boot
# partition, which is not part of the rootfs at all, so this package is
# empty by design and Yocto is told so rather than warning about it.
ALLOW_EMPTY:${PN} = "1"
