SUMMARY = "Project 5: an IIO driver for the ADXL345, written from scratch"
DESCRIPTION = "The bench image plus Project 5's out-of-tree ADXL345 \
driver, the in-tree driver it is measured against, and the IIO tools from \
Project 10 that read either of them without knowing which is loaded."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    bench-iio \
    bench-adxl345-dt \
    kernel-module-bench-adxl345-core \
    kernel-module-bench-adxl345-i2c \
    kernel-module-bench-adxl345-spi \
    kernel-module-adxl345-i2c \
    kernel-module-adxl345-spi \
"

# THE MODULE LINES ARE THE POINT OF THIS FILE.
#
# Five of them, and every one is a package rather than a kernel option.
# adxl345.cfg compiles all five; naming them here is what puts them in the
# rootfs. Yocto packages one module per .ko and installs only what an
# image asks for, so a driver can be configured, built, packaged, cached
# and still absent from the card, with a device that never appears as the
# only symptom.
#
# This repository has paid for that twice. Project 1 lost a round to a
# wireless driver whose module package nobody named, and Project 8 lost a
# flash and a boot to spidev without its controller. Decision 75 is the
# write-up, and scripts/lint.py grew check_image_packages from it: the
# rule reads an image recipe's comments for kernel-module-* names and
# asserts they are installed. It can only see names somebody wrote down,
# which is the other half of why they are written down here.
#
# The first three are Project 5's own driver, built out of tree by
# meta-bench/recipes-bench/bench-adxl345. Three modules rather than one
# because the core is shared and each bus file loads on its own.
#
# The last two are mainline's. They are here so that the control is on the
# card rather than in a second image: this project's driver claims
# "bench,adxl345" and mainline's claims "adi,adxl345", so the overlay
# decides which one binds and swapping it is a reboot rather than a
# rebuild. An image that carried only one of them would make every
# comparison a two-build exercise, which is what Project 8 had to do and
# what this arrangement avoids.

# bench-iio is Project 10's tooling: iio-probe, iio-trigger, iio-rate and
# iio-decode. None of it knows anything about an ADXL345, which is the
# point of installing it here. iio-rate takes a device name, iio-decode
# reads scan_elements and computes offsets from the sysfs description, so
# both read this driver's buffer without a line of change. That is the
# dependency the repository README claims when it says Project 5 writes a
# driver Project 10 exercises, and installing the tools next to the driver
# is what turns the claim into something runnable.

# The overlay reaches the boot partition rather than the rootfs, because
# the firmware reads it before there is a rootfs. bench-adxl345-dt deploys
# it into overlays/ and this line copies it onto the card; the do_image
# dependency makes sure it was deployed before the image was assembled.
# Added Friday 9 October 2026, once the part had been read off the bus at
# 0x53 and the node could be written from a measurement rather than a
# guess. The same evening showed what the line in kas/bench-adxl345.yml
# that requests it is worth: scripts/check-overlays.sh runs at flash time
# and refuses a config.txt that names an overlay the card does not carry.
IMAGE_BOOT_FILES:append = " overlays/bench-adxl345.dtbo;overlays/bench-adxl345.dtbo"
do_image[depends] += "bench-adxl345-dt:do_deploy"
