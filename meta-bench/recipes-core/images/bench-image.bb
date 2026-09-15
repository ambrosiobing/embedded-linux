SUMMARY = "Bench image for the embedded Linux projects"
DESCRIPTION = "core-image-minimal plus the four things every later bench \
project needs: a character-device GPIO stack, an I2C toolkit, an SSH \
server and the bench status-LED daemon. Everything else is deliberately \
absent so that the package list stays short enough to justify line by line."

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
    linux-firmware-rpidistro-bcm43455 \
    kernel-module-brcmfmac \
    kernel-module-brcmfmac-wcc \
    bench-status \
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

# The Pi 4 radio firmware is proprietary and binary-redistributable, so
# Yocto refuses to build it until the licence is accepted explicitly.
# That acceptance lives in the kas file next to the other policy,
# because it is a decision about this bench and not a property of the
# image.

# Enough room for the SDK-built binaries of the later projects.
IMAGE_ROOTFS_EXTRA_SPACE = "131072"
