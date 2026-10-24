SUMMARY = "Project 10: IIO in depth with the X-NUCLEO-IKS4A1"
DESCRIPTION = "The bench image plus four sensor drivers, the software \
triggers, libiio with its daemon and its command line programs, and the \
polling, a hrtimer trigger and the IMU's hardware FIFO."

require recipes-core/images/bench-image.bb

IMAGE_INSTALL:append = " \
    bench-iio \
    bench-iks4a1 \
    libiio \
    libiio-iiod \
    libiio-tests \
    python3-numpy \
    i2c-tools \
    lmsensors-sensors \
    kernel-module-st-lsm6dsx \
    kernel-module-st-lsm6dsx-i2c \
    kernel-module-st-magn \
    kernel-module-st-magn-i2c \
    kernel-module-st-pressure \
    kernel-module-st-pressure-i2c \
    kernel-module-sht4x \
    kernel-module-iio-trig-hrtimer \
    kernel-module-iio-trig-sysfs \
"

# THE MODULE LINES ARE THE POINT OF THIS FILE.
#
# Every driver in iio.cfg is =m, and a module that is configured in the
# kernel is not a module that is in the rootfs. Yocto packages one module
# per .ko and installs only what an image names, so a driver can be
# configured, compiled, deployed to the sstate feed, and absent from the
# card with nothing anywhere reporting it.
#
# Project 8 paid a flash and a boot for that distinction: its image asked
# for kernel-module-spidev and not for the SPI controller spidev attaches
# to, and the symptom on the board was a HAT that announced its own name
# out of its ID EEPROM and then could not be opened. See its journal entry
# 45, and decision 75.
#
# The names here are Yocto's, derived from the .ko with underscores turned
# into hyphens, and they are not guaranteed to match what this kernel
# version builds. ./go packages after a build lists what actually landed,
# and iio-probe on the board reports "no-driver-in-image" for anything that
# did not, which is the same fact seen from the other end.
#
# The two trigger modules are the reason bench.cfg is not enough on its
# own. CONFIG_IIO_SYSFS_TRIGGER is already there, and that is the kernel
# side; this is the rootfs side of the same symbol.

# libiio-iiod is the network daemon, and it is installed rather than
# enabled. iiod exposes every device with no authentication, so starting
# it is a decision taken on a bench with a known network rather than a
# default baked into an image. docs/BRINGUP.md says how, and why not to do
# it on anything but the bench LAN.
#
# libiio-TESTS is iio_info, iio_readdev and iio_attr, which are the
# reference implementations this project's own client is checked against.
#
# THE NAME IS THE TRAP AND IT COST A BUILD. This line said libiio-tools
# until Saturday 24 October 2026, because that is what those three
# programs are called by everyone including this comment. The recipe
# disagrees: meta-oe's libiio_0.25.bb declares
#
#     PACKAGES =+ "${PN}-iiod ${PN}-tests ${PN}-python3"
#     FILES:${PN}-tests = "${bindir}"
#
# so every binary it builds is swept into a package named after tests,
# and no package named libiio-tools exists at all. BitBake refused at
# parse with "Nothing RPROVIDES", which is the good direction: the
# alternative is an image that builds and has no tools in it.
#
# Not one package name in this file had ever been checked against a real
# build before that run, because the only job that builds an image is
# workflow_dispatch on a self-hosted runner and never runs on a push.
# Expect the next name to be wrong too, and expect it to cost forty
# seconds of parsing rather than a build.

# numpy is on the BOARD and not only on the PC, which is 30 MB of image for
# one reason: the claim this project makes is that the URI is the only
# difference between a local client and a remote one. That claim is not
# testable if the fusion program can only run on one side of it.

# lmsensors-sensors is for the SHT40, which is not an IIO device at all.
# It is a hwmon driver, so it appears in sensors(1) and never under
# /sys/bus/iio/devices, and an image that could not read it would leave the
# inventory table with a row nobody could check.

# The overlay reaches the boot partition rather than the rootfs, because
# the firmware reads it before there is a rootfs to read from. bench-iks4a1
# deploys it into overlays/ and this is the line that copies it onto the
# card; the do_image dependency is what makes sure it was deployed before
# the image was assembled rather than after.
IMAGE_BOOT_FILES:append = " overlays/bench-iks4a1.dtbo;overlays/bench-iks4a1.dtbo"
do_image[depends] += "bench-iks4a1:do_deploy"
