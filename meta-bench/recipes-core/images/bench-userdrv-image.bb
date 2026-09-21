SUMMARY = "Project 11: a userspace driver packaged as a library"
DESCRIPTION = "The bench image plus libadxl345, its tool and i2c-tools. \
There is no kernel module here: the ADXL345 is driven entirely from user \
space over i2c-dev, which is the whole point of the project."

require recipes-core/images/bench-image.bb

IMAGE_INSTALL:append = " \
    libadxl345 \
    libadxl345-tools \
    i2c-tools \
"

# THE IN-KERNEL ADXL345 DRIVER MUST NOT BE IN THIS IMAGE.
#
# Project 5 binds an in-kernel IIO driver to this same chip at this same
# address. Two drivers on one device is the first row of Project 11's
# ownership table because it is the only conflict on this bench that
# produces readings that are WRONG rather than absent: the kernel claims
# the address, i2c-dev may still be opened, and what comes back depends on
# which one last moved the register pointer.
#
# The two projects therefore never share an image. bench-image installs
# neither driver, so there is nothing to remove here; this comment is the
# guard, and tests/adxl345-build-test.sh asserts that no kernel-module
# line for the part appears in this file.
#
# If anyone adds one, the fix is a second image, not a shared one.

# i2c-tools for i2cdetect, which is the first thing to run when the part
# does not answer: it says whether anything is at 0x53 or 0x1d before the
# library is blamed. The library's own error message names the other
# strap address for the same reason.
