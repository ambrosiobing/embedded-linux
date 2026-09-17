SUMMARY = "Project 6: the Explorer 700, bound by one device tree overlay"
DESCRIPTION = "The bench image plus one overlay that binds eleven \
peripherals of a JOY-iT RB-Explorer700 to in-tree drivers, the subsystem \
tools that check each of them, and nothing else. There is no vendor library \
and no application: the product is the hardware description."

require recipes-core/images/bench-image.bb

IMAGE_INSTALL:append = " \
    bench-explorer \
    bench-explorer700 \
    ir-keytable \
    evtest \
    lmsensors-sensors \
"

# NOT ONE kernel-module-* LINE, AND THAT IS THE POINT OF THIS FILE.
#
# Every other image in this repository carries a block of them, and two of
# this bench's expensive failures were a module that was configured,
# compiled, and absent from the rootfs with nothing anywhere reporting it.
# bench-iio-image has nine such lines and a long comment about why.
#
# explorer.cfg builds all eleven drivers in with =y instead, so there are
# no module packages to name and no way to get the list wrong. That is a
# larger kernel on one image, bought deliberately, and the reason it is
# worth buying here rather than everywhere is in the fragment's header:
# the Raspberry Pi 3 defconfig makes the two BUS CONTROLLERS modules
#
#     CONFIG_I2C_BCM2835=m
#     CONFIG_SPI_BCM2835=m
#
# so the cost of one forgotten line on this board is not one missing
# driver. It is the whole I2C bus, and with it four of the five addressed
# parts at once, presenting as a HAT that is not there.
#
# If a later change moves anything in explorer.cfg back to =m, this comment
# stops being true and a block of kernel-module-* lines has to appear
# below it. scripts/lint.py checks that any kernel-module-* named in an
# image recipe's comments is installed by some image; it cannot check the
# reverse, so this paragraph is the only guard and it is addressed to
# whoever edits that fragment.

# ir-keytable AND NOT v4l-utils. The v4l-utils recipe does
# "PACKAGES =+ media-ctl ir-keytable rc-keymaps ...", so ir-keytable is its
# own package and FILES:ir-keytable claims ${bindir}/ir-keytable before the
# catch-all sees it. Installing v4l-utils would give every other binary in
# that recipe and not the one tool this project needs. rc-keymaps arrives
# with it through RDEPENDS:ir-keytable, which is what makes
# "ir-keytable -p nec" able to name a protocol.

# evtest is how acceptance criteria 3 and 4 are met: it is the only way to
# see which joystick direction a contact really is, and the manual's block
# diagram is read off a rendered page rather than a net list. See
# projects/06-explorer700/docs/pin-map.md.

# lmsensors-sensors is for the PCF8591, which is a hwmon device and never
# appears under /sys/bus/iio. Its four inputs leave this board through a
# screw terminal and therefore float, so "sensors" here shows four
# unterminated channels; explorer-verify reports that rather than printing
# the numbers as though they were measurements.

# The overlay reaches the FAT boot partition rather than the rootfs,
# because the firmware reads it before there is a rootfs to read from.
# bench-explorer700 deploys it into overlays/ and this is the line that
# copies it onto the card. The do_image dependency is what makes sure it
# was deployed before the image was assembled rather than after, which is
# the difference between a card that boots the HAT and one that silently
# has no overlay at all.
#
# The pair is "source;destination" and both halves are the same path here,
# because the firmware looks for overlays in overlays/ and that is where
# do_deploy put it.
BENCH_EXPLORER_DTBO = "overlays/bench-explorer700.dtbo"
IMAGE_BOOT_FILES:append = " ${BENCH_EXPLORER_DTBO};${BENCH_EXPLORER_DTBO}"
do_image[depends] += "bench-explorer700:do_deploy"
