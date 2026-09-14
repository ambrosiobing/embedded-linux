SUMMARY = "Bench image with the debugging tooling"
DESCRIPTION = "bench-image plus the debug and profile image features, which \
bring gdbserver, strace and perf. Kept as a separate target so that the \
image under test and the image being measured are never the same artefact."

require recipes-core/images/bench-image.bb

# tools-debug is gdb, gdbserver and strace; tools-profile is perf and the
# profiling helpers. Naming the features rather than the packages keeps this
# correct when poky moves a tool between them.
IMAGE_FEATURES += "tools-debug tools-profile"

IMAGE_ROOTFS_EXTRA_SPACE = "262144"
