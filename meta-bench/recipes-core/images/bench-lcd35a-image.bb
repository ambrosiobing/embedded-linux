SUMMARY = "Project 7: a 3.5 inch SPI panel as a DRM device with touch"
DESCRIPTION = "The bench image plus one overlay that binds a Waveshare 3.5 \
inch RPi LCD (A) to the in-tree ili9486 and ads7846 drivers, the three \
programs that exercise it, and the subsystem tools that check it. There is \
no vendor driver and no install script: the product is the hardware \
description and the kernel configuration behind it."

require recipes-core/images/bench-image.bb

IMAGE_INSTALL:append = " \
    bench-lcd35a \
    bench-lcd35a-overlay \
    libdrm-tests \
    evtest \
"

# NOT ONE kernel-module-* LINE, for the same reason bench-explorer-image
# has none.
#
# lcd35a.cfg builds everything in with =y, so there are no module packages
# to name and no way to get the list wrong. The reason it is worth buying
# that on this image and not everywhere is in the fragment's header, and
# the sharp end of it is this: the Raspberry Pi 3 defconfig builds
#
#     CONFIG_SPI_BCM2835=m
#
# so one forgotten kernel-module line here would not cost one driver. It
# would cost the SPI bus, and with it the panel and the touch controller at
# once, presenting as a board with nothing plugged into it.
#
# If a later change moves anything in lcd35a.cfg back to =m, this comment
# stops being true and a block of kernel-module-* lines has to appear
# below it. scripts/lint.py checks that any kernel-module-* named in an
# image recipe's comments is installed by some image; it cannot check the
# reverse, so this paragraph is the only guard.

# libdrm-tests AND NOT libdrm. poky's libdrm recipe splits its test
# programs into their own package, so libdrm-tests is what carries
# modetest, which is the tool acceptance criterion 3 is measured with.
# Installing libdrm alone gives the library that bench-lcd35a already
# links against and none of the tools.

# evtest is how the raw touch ranges are read for criterion 5. There is no
# way to calibrate without seeing what the controller actually reports at
# the four corners, and this is the tool that shows it.

# NOT INSTALLED, AND EACH FOR A REASON:
#
# tslib. ts_calibrate writes /etc/pointercal, which tslib programs read
# and nothing else does. This project puts calibration in a libinput
# property instead, because that is what a Wayland compositor applies and
# because it makes calibration data rather than a patched application.
# lcd35a-corners does the arithmetic that ts_calibrate would have done.
#
# libinput. The calibration matrix is consumed by whatever compositor
# eventually runs, and there is no compositor on this image: Project 13 is
# where a Wayland stack goes. libinput's own debug-events is useful during
# bring-up and is one "bitbake -c addto" away; it is not installed by
# default because an unused library in an image is the thing Project 3
# measures the cost of.
#
# fbtft. The specification offers fb_ili9486 with the vendor waveshare35a
# overlay as a fallback, and it is a fallback rather than the solution: it
# is a staging driver, it gives no /dev/dri node, and it refreshes on a
# timer instead of tracking damage. Documented in the project README as
# the comparison, not built here.

# The overlay reaches the FAT boot partition rather than the rootfs,
# because the firmware reads it before there is a rootfs to read from.
# bench-lcd35a-overlay deploys it into overlays/ and this is the line that
# copies it onto the card. The do_image dependency is what makes sure it
# was deployed before the image was assembled rather than after, which is
# the difference between a card that binds the panel and one that silently
# has no overlay at all.
#
# The pair is "source;destination" and both halves are the same path here,
# because the firmware looks for overlays in overlays/ and that is where
# do_deploy put it.
BENCH_LCD35A_DTBO = "overlays/bench-lcd35a.dtbo"
IMAGE_BOOT_FILES:append = " ${BENCH_LCD35A_DTBO};${BENCH_LCD35A_DTBO}"
do_image[depends] += "bench-lcd35a-overlay:do_deploy"

# bench-status IS NOT IN THIS IMAGE, and leaving it out is not an
# oversight.
#
# Project 1's status daemon holds GPIO17, GPIO22 and GPIO27. GPIO17 is
# this panel's pen-down interrupt, and ads7846 requests it at probe. Two
# drivers asking for one line is a probe failure on whichever loses, and
# the loser here would be the touch controller, which would look like a
# touch problem rather than a conflict.
#
# bench-image installs bench-status, so it is removed rather than simply
# not added. The ownership table in projects/07-lcd35-drm/docs/DESIGN.md
# is where this is written down as a rule rather than as one line.
IMAGE_INSTALL:remove = "bench-status"
