SUMMARY = "Bench image for a device under test that has no card in it"
DESCRIPTION = "The bench image, arranged to be served rather than flashed. \
Project 4's lab boots this over TFTP and NFS on a Raspberry Pi 3B+ with an \
empty card slot, so the output that matters is a root filesystem tarball \
rather than a disk image."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

# A disk image is the wrong shape for this. An NFS export is a directory
# tree, so the deploy step extracts a tarball into it; a .wic would have to
# be loop-mounted and copied out of, which is the same work done twice and
# needs root on the server.
#
# The boot files are deployed separately from the same directory, which is
# why wic is not needed at all here.
IMAGE_FSTYPES = "tar.bz2"

# The wireless client profile goes. This board is wired, its root
# filesystem is on that wire, and a supplicant hunting for an access point
# on a board with no credentials is noise in the one log anyone reads.
IMAGE_INSTALL:remove = "bench-net-wifi"

IMAGE_INSTALL:append = " \
    bench-netboot \
"

# The kernel needs NFS, IP autoconfiguration and the 3B+ Ethernet driver
# built in. That is BENCH_NETBOOT_KERNEL in kas/bench-netboot.yml, and an
# image built without it boots as far as "unable to mount root".

# An fstab that names a card this board does not have.
#
# core-image-minimal's fstab carries entries for the boot partition, and on
# a netbooted board those are mounts of a device that never appears. The
# result is a failed mount unit at every boot, which is harmless and which
# makes "systemctl --failed" useless, and this lab's first test asserts
# that "systemctl --failed" is empty. A check that has to be read past is a
# check nobody reads.
ROOTFS_POSTPROCESS_COMMAND += "bench_netboot_fstab; "

bench_netboot_fstab() {
    if [ -f ${IMAGE_ROOTFS}${sysconfdir}/fstab ]; then
        sed -i -e '/mmcblk/s/^/# netboot: no card in this board. /' \
            ${IMAGE_ROOTFS}${sysconfdir}/fstab
    fi
}
