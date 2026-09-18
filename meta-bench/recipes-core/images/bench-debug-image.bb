SUMMARY = "Bench image with the kernel debugging toolbox and a faulty module"
DESCRIPTION = "The bench image plus the tools Project 9 is about: trace-cmd \
and perf on the target, a kernel built with kgdb, ftrace, pstore, lockdep, \
kmemleak and KFENCE, and an out-of-tree module that misbehaves on request. \
It produces no product. It produces a notebook."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    kernel-module-buggy \
    trace-cmd \
    kmod \
"

# kernel-module-buggy, NOT bench-buggy.
#
# module.bbclass inherits the kernel module split class, which names the
# package after the .ko with a "kernel-module-" prefix. Asking for
# bench-buggy here would not fail: BitBake would build the recipe, find
# no package by that name to install, and produce an image without the
# module. The first sign would be a missing /sys/kernel/debug/buggy on a
# board that booted perfectly.

# perf is deliberately its own line, because it is the one package here
# that is not a normal target build: it compiles against the kernel
# source of THIS build, so it tracks the kernel rather than the distro,
# and it is the reason RM_WORK_EXCLUDE in the kas file keeps the kernel
# work directory.
IMAGE_INSTALL:append = " perf"

# trace-cmd comes from meta-oe, which kas/bench-rpi4.yml already has in
# the layer list. It brings libtraceevent and libtracefs with it.

# Room for a trace file written to disk rather than to /dev/shm, plus the
# module and the tools. Traces normally go to /dev/shm and leave over
# Ethernet, which is what the design document argues for, but a board
# that cannot write one anywhere is worse than a large image.
IMAGE_ROOTFS_EXTRA_SPACE = "262144"

# --- the second manager on /sys/fs/pstore -------------------------------
#
# systemd mounts pstore itself (src/shared/mount-setup.c has an entry for
# it), and then systemd-pstore.service ARCHIVES AND DELETES what it
# finds: Storage=external and Unlink=yes are the compile-time defaults,
# the unit is WantedBy=sysinit.target, and it runs Before=sysinit.target.
#
# So on a stock systemd image the sequence after a panic is:
#
#   reboot -> systemd mounts /sys/fs/pstore -> systemd-pstore.service
#   copies every record to /var/lib/systemd/pstore/ and unlinks it ->
#   you log in and /sys/fs/pstore is EMPTY.
#
# The crash is not lost, it has moved, but every instruction ever written
# about pstore says to look in /sys/fs/pstore, and an empty directory
# there reads as "ramoops is not working". The Raspberry Pi overlay
# README says the same thing in one line: "With systemd-pstore enabled
# (as it is on Raspberry Pi OS) the crash logs are moved to
# /var/lib/systemd/pstore/ on reboot."
#
# This image masks the unit. The reason is not that archiving is wrong,
# it is that a debugging lab wants ONE owner of that directory and wants
# the records to persist until the person reading them says otherwise.
# Clearing pstore after each capture is a step in the notebook, done by
# hand, so that an old record cannot be mistaken for a new one.
#
# To get the stock behaviour back, drop this and read
# /var/lib/systemd/pstore/ instead.
ROOTFS_POSTPROCESS_COMMAND += "mask_systemd_pstore; "

mask_systemd_pstore() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system
    ln -sf /dev/null \
        ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/systemd-pstore.service
}
