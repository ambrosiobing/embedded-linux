SUMMARY = "Bench image with two root slots and RAUC"
DESCRIPTION = "The bench image built to be updated rather than reflashed. \
The root filesystem is read-only and lives in one of two fixed, equal \
partitions; /etc is an overlay on a third; RAUC writes whichever slot is \
not running and U-Boot decides which one to try, by a counter it \
decrements and a health check resets."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    bench-ab \
    rauc \
    kernel-image-image \
"

# THE THREE LEDS HAVE TWO CLAIMANTS AND ONLY ONE CAN WIN.
#
# bench-image installs bench-status, Project 12's LED daemon, which drives
# GPIO 17, 27 and 22 through libgpiod and gives them a health meaning:
# green healthy, yellow starting, red failed. Figure 3 of this project's
# design gives the same three lines entirely different meanings: which slot
# booted, and whether it has been confirmed.
#
# This is not a preference between two schemes. The gpio-led overlays in
# kas/bench-rpi3-ab.yml claim those lines in the device tree, so libgpiod
# cannot open them at all, and
# bench-status would fail at start on a board where nothing is wrong. The
# conflict is resolved here, once, rather than left to whichever starts
# first.
#
# Teaching bench-state two more words was the alternative and was rejected:
# it would leave a yellow LED meaning either "a watched unit is starting"
# or "you are on slot B" depending on which image was flashed, and an
# indicator that needs the image name to interpret is not an indicator.
IMAGE_INSTALL:remove = "bench-status"

# The LEDs themselves are declared in kas/bench-rpi3-ab.yml and NOT here.
#
# RPI_EXTRA_CONFIG is read by rpi-config_git.bb when it writes config.txt,
# so it has to be set where that recipe can see it, which means local.conf.
# An assignment in this image recipe is scoped to this recipe, would be
# read by nothing, and would produce a card with no LED devices and no
# error anywhere. It was written here first, for exactly that reason.

# kernel-image-image IS NOT DECORATION AND IS THE EASIEST LINE HERE TO
# DELETE BY MISTAKE.
#
# On a Raspberry Pi the kernel normally lives only on the FAT partition and
# the firmware loads it directly. meta-raspberrypi is built that way, so
# the rootfs has no kernel in it at all, and that is fine for every other
# image in this repository.
#
# It is fatal here. A shared kernel on p1 is a kernel no bundle can
# replace, so the whole point of a per-slot root filesystem is lost: an
# update could change userspace and never the thing most likely to need
# changing. So boot.cmd.in ext4loads /boot/Image out of the slot it chose,
# and this line is what puts a /boot/Image in the slot for it to find.
#
# Without it the build succeeds, the image flashes, the card boots, U-Boot
# prints its slot decision, the load fails, and the board resets. Three
# times, then the other slot, which is empty, then back again. The symptom
# is a reboot loop with a correct-looking boot log.
#
# The package name follows KERNEL_IMAGETYPE, which is Image on arm64.
# Changing that variable renames this package and nothing points that out.

# A read-only root is the premise, not a hardening measure. RAUC writes a
# whole filesystem image into the inactive slot and compares it against
# what it wrote; a root that anything can modify is a root whose contents
# stop matching the bundle that produced them, and then a rollback restores
# something nobody has ever tested.
#
# overlayfs-etc is what makes that survivable. /etc has to be writable for
# a device to be configurable at all, so it becomes an overlay with the
# image's copy as the read-only lower layer and persistent storage as the
# upper.
IMAGE_FEATURES += "read-only-rootfs overlayfs-etc"

# THE SINGLE PLACE p4 IS MOUNTED. The class generates a preinit that mounts
# this device before /sbin/init runs, because /etc must be an overlay
# before the process that reads /etc starts. bench-ab therefore ships no
# data.mount: a second unit for this device would be two owners of one
# resource, which is the fault the design document's ownership table
# exists to prevent.
OVERLAYFS_ETC_DEVICE = "/dev/mmcblk0p4"
OVERLAYFS_ETC_MOUNT_POINT = "/data"
OVERLAYFS_ETC_FSTYPE = "ext4"
OVERLAYFS_ETC_MOUNT_OPTIONS = "rw,noatime"

# THE HAZARD THE OVERLAY BUYS, recorded here because it is invisible on a
# working board and permanent once it happens. A file edited on slot A
# lands in the upper layer, and the upper layer persists across every
# update. From then on it shadows whatever slot B ships as that file's new
# default, forever, with nothing reporting a conflict. The policy is that
# the overlay is for operator configuration and that anything the image
# owns is never edited in place. A policy is all it is: nothing enforces
# it, which is why it is written in three places.

# /var/log IS A REAL DIRECTORY, NOT A SYMLINK INTO TMPFS.
#
# poky's default with a read-only root is VOLATILE_LOG_DIR = "yes", which
# makes /var/log a symlink to /var/volatile/log and therefore erases the
# journal at every reboot. In most read-only designs that is the right
# trade. Here it destroys the project's own evidence: every interesting
# event in an A/B system is followed immediately by a reboot, so the log
# saying why a slot was rejected is deleted by the rejection.
#
# With this set to "no", bench-ab can put a symlink at /var/log/journal
# pointing onto the shared data partition, and the record survives both
# the reboot and the rollback. The journald settings that go with it, and
# the size cap that keeps the journal from filling the partition RAUC
# needs, are in that recipe.
VOLATILE_LOG_DIR = "no"

# ext4 for the slot image, wic for the card.
#
# The two are for different jobs and both are needed. The wic image is a
# whole card, written once from a laptop, and carries all four partitions.
# The ext4 image is one root filesystem and is what a bundle contains,
# because RAUC writes a filesystem into a partition rather than a card into
# a reader.
IMAGE_FSTYPES = "wic.bz2 wic.bmap ext4"

# A slot is 1024 MiB in bench-ab.wks and both slots are fixed at that size,
# so this is the figure that decides whether a bundle can be installed at
# all. It is set here rather than left to grow with the rootfs for the same
# reason the partitions are fixed: an image that quietly exceeds the slot
# fails at install time on a device in the field rather than at build time
# on a desk.
#
# 800 MiB of image against a 1024 MiB slot leaves room for the filesystem's
# own overhead and for growth, and is small enough that the failure comes
# early.
IMAGE_ROOTFS_MAXSIZE = "819200"

# The rootfs is read-only, so the usual reason for spare space does not
# apply: nothing on the running system can use it. What this covers is the
# difference between the populated filesystem and the image RAUC writes,
# which has to be identical in size on both slots.
IMAGE_ROOTFS_EXTRA_SPACE = "0"
