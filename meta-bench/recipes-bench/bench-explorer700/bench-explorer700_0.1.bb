SUMMARY = "Device tree overlay for the JOY-iT RB-Explorer700 HAT"
DESCRIPTION = "Binds eleven peripherals of an RB-Explorer700 to in-tree \
drivers on a Raspberry Pi 3: a DS3231, a PCF8574, a PCF8591 and a BMP280 on \
I2C1, an SSD1306 on SPI0, a DS18B20 on 1-Wire, an IR receiver, two LEDs, a \
buzzer and a five-way joystick. Project 6."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bench-explorer700-overlay.dts"

S = "${WORKDIR}"

# dtc on the build host, not in the image. The overlay is compiled once
# here and shipped as a .dtbo; a board that compiles its own device tree
# has a boot that depends on a tool being installed.
DEPENDS = "dtc-native"

# A .dtbo is data. Nothing in it is compiled for a target ABI.
inherit allarch deploy

do_compile() {
    # -@ keeps the symbol table, which is what lets the overlay resolve
    # &i2c1, &spi0, &spidev0 and &gpio by phandle at load time. Without it
    # dtoverlay refuses the file with "not a base or overlay", which reads
    # like corruption rather than a missing flag.
    #
    # This overlay references &spidev0, which exists only in the Raspberry
    # Pi device tree and not in mainline. That is fine: an overlay is
    # resolved against the base tree on the board, so the symbol has to
    # exist there and not here.
    dtc -@ -I dts -O dtb \
        -o ${B}/bench-explorer700.dtbo \
        ${S}/bench-explorer700-overlay.dts
}

# The firmware reads overlays from an "overlays" directory on the FAT boot
# partition, so the layout here has to match the layout on the card.
# bench-explorer-image picks it up with IMAGE_BOOT_FILES and a do_image
# dependency on this task, because a file deployed after the image is
# assembled is a file the image does not contain.
do_deploy() {
    install -d ${DEPLOYDIR}/overlays
    install -m 0644 ${B}/bench-explorer700.dtbo ${DEPLOYDIR}/overlays/
}

addtask deploy after do_compile before do_build

# Nothing reaches the rootfs. The overlay lives on the boot partition,
# which is not part of the rootfs at all, so this package is empty by
# design and Yocto is told so rather than warning about it.
ALLOW_EMPTY:${PN} = "1"
