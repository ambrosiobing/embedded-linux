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
    bench-status \
"

# Enough room for the SDK-built binaries of the later projects.
IMAGE_ROOTFS_EXTRA_SPACE = "131072"
