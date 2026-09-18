SUMMARY = "ADXL345 accelerometer, an IIO driver written from scratch"
DESCRIPTION = "Project 5's out-of-tree IIO driver for the ADXL345: a core \
that speaks only regmap, an I2C bus file and an SPI bus file. It claims \
the compatible bench,adxl345 rather than the mainline adi,adxl345, so that \
both drivers can be installed at once, neither can bind to the other's \
node, and swapping one word in the device tree overlay makes the in-tree \
driver a control for this one."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;\
md5=801f80980d171dd6425610833a22dbe6"

SRC_URI = "\
    file://bench-adxl345.h \
    file://bench-adxl345-core.c \
    file://bench-adxl345-i2c.c \
    file://bench-adxl345-spi.c \
    file://Makefile \
"

# THE FIRST RECIPE IN THIS LAYER THAT COMPILES KERNEL CODE.
#
# module.bbclass is what makes that work: it builds against the kernel
# this image is assembling rather than against the host's headers, and it
# packages each .ko it finds into its own kernel-module-* package.
#
# That packaging is the trap, and this repository has paid for it twice.
# Yocto installs only what an image names, so a module can be compiled,
# packaged, deployed into the sstate cache and still be absent from the
# rootfs, with a device that never probes as the only sign. See decision
# 75, and the comment in bench-adxl345-image.bb which names all three
# packages for exactly this reason.
inherit module

# The licence is GPL-2.0-only rather than the MIT the rest of this layer
# uses, and that is not a preference. A kernel module that links against
# GPL-only exported symbols is a derived work of the kernel, and this one
# does: EXPORT_SYMBOL_NS_GPL on the core's own probe, and the IIO and
# regmap interfaces underneath it. MODULE_LICENSE("GPL") in the sources
# says the same thing to modpost, which refuses the link otherwise.
S = "${WORKDIR}"

EXTRA_OEMAKE = "KDIR=${STAGING_KERNEL_DIR}"

# One package per .ko, named by module.bbclass from the file name. They
# are listed here so that the image recipe's IMAGE_INSTALL can be checked
# against something, and so that a reader does not have to run the build
# to learn what this produces:
#
#   kernel-module-bench-adxl345-core
#   kernel-module-bench-adxl345-i2c
#   kernel-module-bench-adxl345-spi
#
# Nothing autoloads. KERNEL_MODULE_AUTOLOAD would insert these at boot
# whether or not the device tree describes the part, and a driver loaded
# with nothing to bind to is indistinguishable from a driver that failed
# to bind. The overlay describes the node, the bus matches it, and the
# module is loaded on demand by udev.
