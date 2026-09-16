SUMMARY = "Bench image with an OP-TEE normal world and a keystore TA"
DESCRIPTION = "The bench image with the Linux half of a trusted execution \
environment on it: the tee subsystem, the OP-TEE driver, tee-supplicant, \
the conformance suite, and a trusted application that generates an HMAC \
key inside the secure world and signs whatever the normal world hands it. \
The secure world's own boot image is not built here; see kas/bench-tee.yml."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    optee-client \
    optee-test \
    bench-keystore \
"

# optee-client is libteec and tee-supplicant. Nothing else in the image
# reaches the secure world without it: libteec opens /dev/tee0 for
# clients, and tee-supplicant owns /dev/teepriv0 and serves the remote
# procedure calls that the secure world makes back into Linux.
#
# That inversion is the thing to understand before debugging any of this.
# The secure world is more privileged and less capable: it has no block
# driver and no filesystem, so loading a TA and reading a persistent
# object are both requests it sends *outward*. Without the supplicant the
# first TEEC_OpenSession fails, and the error names neither the
# supplicant nor the file it could not read.
#
# One packaging detail that follows from meta-arm and costs a bring-up if
# it is missed: the unit is tee-supplicant@.service, a template. A
# template with no instance and no DefaultInstance starts nothing.
# bench-keystore ships the wants symlink that instantiates it, and says
# so in its own recipe.

# optee-test is xtest, the GlobalPlatform conformance suite. It is in the
# image rather than in a developer's pocket because it is the only thing
# that can say whether the secure world works *before* any of this
# project's own code is suspected. optee-selftest.service runs it once at
# boot for the same reason.
#
# It is not small. A build that wants the smallest possible image should
# drop it, and then has no way to distinguish a broken TA from a broken
# TEE, which on this platform is most of the debugging.

# python3-core is already in bench-image through other recipes; the
# keystore's ctypes binding and the verifier need nothing beyond it.

# Room for xtest, the TA, and a day of signed records.
IMAGE_ROOTFS_EXTRA_SPACE = "262144"
