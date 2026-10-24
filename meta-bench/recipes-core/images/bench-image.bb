SUMMARY = "Bench image for the embedded Linux projects"
DESCRIPTION = "core-image-minimal plus the five things every later bench \
project needs: a character-device GPIO stack, an I2C toolkit, a raw SPI \
and register toolkit for when a bus answers nothing, an SSH server and \
the bench status-LED daemon. Everything else is deliberately absent so \
that the package list stays short enough to justify line by line."

require recipes-core/images/core-image-minimal.bb

LICENSE = "MIT"

# ssh-server-openssh already pulls openssh-sshd, so the server is named once.
IMAGE_FEATURES += "ssh-server-openssh"

# debug-tweaks leaves the root account without a password. That is right for
# a bench board on an isolated network and wrong for anything else; drop this
# line and add an EXTRA_USERS_PARAMS entry before the board leaves the bench.
IMAGE_FEATURES += "debug-tweaks"

IMAGE_INSTALL:append = " \
    libgpiod \
    libgpiod-tools \
    i2c-tools \
    bench-provision \
    bench-net-wifi \
    linux-firmware-rpidistro-bcm43455 \
    kernel-module-brcmfmac \
    kernel-module-brcmfmac-wcc \
    wireless-regdb-static \
    bench-status \
    spitools \
    devmem2 \
    bench-diag \
"

# core-image-minimal installs no kernel modules at all, so the radio driver
# has to be named. Firmware without a driver is a radio that never probes:
# /lib/firmware/brcm was full and dmesg had no brcmfmac line anywhere.
# Yocto resolves module dependencies from the modules' own metadata, so this
# pulls brcmutil, cfg80211 and rfkill with it. Not mac80211: brcmfmac is a
# FullMAC driver, so the MAC layer runs in the chip's firmware and the host
# side speaks cfg80211 directly.
#
# The core driver is not enough on its own. Modern brcmfmac splits the
# vendor-specific part into its own module and asks for it by name at probe
# time. Without it the chip is detected, the firmware file is found, and
# attach fails at the last step:
#
#   brcmf_fwvid_request_module: mod=wcc: failed 256
#   brcmf_attach: brcmf_fwvid_attach failed
#
# wcc is the Cypress and Infineon variant, which is what the Pi 4 carries.
# bca is the other one and is not needed here.

# The third piece of the same chain is the regulatory database. Driver and
# firmware get the radio probing; without regulatory.db the kernel falls
# back to its built-in world domain, which is the conservative one: fewer
# channels and lower transmit power than the country actually permits.
# Observed on a Raspberry Pi 3 Model B Plus on Sunday 4 October 2026, on
# every boot:
#
#   platform regulatory.0: Direct firmware load for regulatory.db failed
#                          with error -2
#   cfg80211: failed to load regulatory.db
#
# THE PACKAGE IS NOT NAMED AFTER THE RECIPE. poky's wireless-regdb recipe
# declares PACKAGES = "${PN}-static ${PN}", and it is FILES:${PN}-static
# that holds regulatory.db and regulatory.db.p7s. Asking for
# "wireless-regdb" would build the recipe, install a package containing no
# database, and leave the two lines above exactly where they were. That is
# the same failure shape as asking for bench-buggy instead of
# kernel-module-buggy, which bench-debug-image.bb records for its own.
#
# The "static" in the name is about the database being a file rather than a
# CRDA lookup, not about linkage.

# The Pi 4 radio firmware is proprietary and binary-redistributable, so
# Yocto refuses to build it until the licence is accepted explicitly.
# That acceptance lives in the kas file next to the other policy,
# because it is a decision about this bench and not a property of the
# image.

# --- spitools and devmem2, and why they are in the BASE image -----------
#
# THE REASON IS THAT A DIAGNOSTIC TOOL ARRIVING BY REFLASH IS TOO LATE.
#
# Tuesday 21 October 2026. The ADXL345 answered nothing on either bus:
# i2cdetect found no address at all, the SPI arm read DEVID as 0x00, and
# the question that mattered was whether the part was being addressed and
# saying nothing or never being addressed. That is one raw transfer away
# from an answer, and the card could not make one. No spidev_test, no
# compiler, and this image's python3 is installed by bench-iio as
# python3-core alone, which has neither fcntl nor ctypes, so there is no
# ioctl from any language on the board.
#
# The remedy was available the whole time and cost a rebuild and a
# reflash, which is why it was not taken: the state under investigation
# was six friction contacts on an unsoldered breakout, where any one can
# open at any moment, so pulling the card destroys the thing being
# measured. A tool that can only be fetched by disturbing the fault is
# not a diagnostic tool. Hence the base image rather than
# bench-debug-image, which is where a first instinct put them.
#
# spitools gives spi-config and spi-pipe. spi-pipe does a full-duplex
# transfer on a /dev/spidevB.C from stdin to stdout, which is the exact
# capability that was missing: writing 0x80 and reading one byte back is
# the ADXL345's DEVID register with no driver in the way, and it
# separates a bus fault from a binding fault in one command. spi-config
# reads and sets mode, bits and speed on the same node, so the CPOL and
# CPHA the overlay asked for can be read off the device rather than
# inferred from the .dts.
#
# devmem2 reads a physical address. On a Pi that is how GPFSEL is read,
# which is the register holding the pin mux, and the mux is the one thing
# in this whole class of failure that gets INFERRED every time: whether
# a pin is I2C, SPI or plain GPIO is a two-bit field somebody can look
# at. On that Tuesday the mux state of GPIO2 and GPIO3 was argued from
# what gpioinfo does not print. gpioinfo cannot show it; this can.
#
# WHAT THEY COST. Both are small C programs with no library beyond libc,
# tens of kilobytes together, and neither pulls an interpreter or a
# toolchain. That is the whole reason this pair is affordable in the base
# image while the two Python extension modules that would do the same job
# are not: those pull python3-core into eleven images that have no
# interpreter today. Where python3 is already present the modules are
# named by that image instead, which bench-adxl345-image.bb does.
#
# bench-diag is the third line and the one that replaces an instrument
# rather than a utility. A GPIO configured as an input is a one-bit
# voltmeter with a threshold near 1.3 V, and reading a line under both
# bias settings tells a driven line from a floating one, which a single
# reading cannot. Doing that by hand is what found the fault on Tuesday
# 21 October 2026, at twelve commands and a paragraph of arithmetic per
# answer, so the method is a program now:
#
#   bench-diag level      gpiochip0 23      driven high, low, or floating
#   bench-diag rail       gpiochip0 24      is a supply present on this net
#   bench-diag ground     gpiochip0 24      is this net tied to ground
#   bench-diag continuity gpiochip0 24 25   does a lead between pins conduct
#   bench-diag watch      gpiochip0 23      the same reading once a second
#   bench-diag scan       gpiochip0         every unused line on the chip
#
# "watch" is the one that matters at the bench, because it turns an
# adjustment into a closed loop: work the hardware and read the verdict
# changing, rather than adjust, run a command, and infer.
#
# It drives a line in exactly one subcommand and that one carries three
# refusals, the important one being that the sense line must read
# FLOATING before anything is driven into it. A ground pin reads
# DRIVEN-LOW, and an output into a ground pin sources far more than a pin
# is rated for, which is the one way this tool could damage a board.

# NEITHER IS A SUBSTITUTE FOR AN INSTRUMENT. There is no voltmeter on
# this bench and these do not make one. What they do is make the board
# able to answer questions about its own buses and registers, which on
# Tuesday 21 October 2026 was answered instead by reading GPIO23 under
# two opposite bias settings through libgpiod and reasoning about an ESD
# clamp diode. That worked and it should not have been the only route.

# Enough room for the SDK-built binaries of the later projects.
IMAGE_ROOTFS_EXTRA_SPACE = "131072"
