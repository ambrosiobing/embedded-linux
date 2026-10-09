SUMMARY = "Device tree overlay binding one ADXL345 to Project 5's driver"
DESCRIPTION = "One node on I2C1 at 0x53 with the compatible string \
bench,adxl345, which only Project 5's out-of-tree driver claims. Changing \
that one word to adi,adxl345 hands the same part to mainline's driver, \
which is how this project takes its control measurements."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bench-adxl345-overlay.dts"

S = "${WORKDIR}"

# dtc on the build host rather than in the image: the overlay is compiled
# once here and shipped as a .dtbo. The shape is bench-iks4a1's, which
# has booted on this bench, and it is copied rather than varied.
DEPENDS = "dtc-native"

# A .dtbo is data, compiled for no target ABI.
inherit allarch deploy

do_compile() {
    # -@ keeps the symbol table, which is what lets the overlay reference
    # &i2c1 by phandle at load time. Without it the firmware refuses the
    # file with a message that reads like corruption.
    dtc -@ -I dts -O dtb \
        -o ${B}/bench-adxl345.dtbo \
        ${S}/bench-adxl345-overlay.dts
}

# The firmware loads overlays from an "overlays" directory on the boot
# partition, so the layout here matches the card. bench-adxl345-image.bb
# copies it onto the card with IMAGE_BOOT_FILES and depends on this task
# from do_image, because a file deployed after the image is assembled is
# a file the image does not contain.
do_deploy() {
    install -d ${DEPLOYDIR}/overlays
    install -m 0644 ${B}/bench-adxl345.dtbo ${DEPLOYDIR}/overlays/
}

addtask deploy after do_compile before do_build

# Nothing goes into the rootfs: the overlay lives on the FAT boot
# partition. The package is empty by design and Yocto is told so.
ALLOW_EMPTY:${PN} = "1"
