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

# --- the second claimant on GPIO17 --------------------------------------
#
# bench-image installs bench-status, Project 12's LED daemon, which drives
# GPIO 17, 27 and 22 through libgpiod and gives them a health meaning:
# green healthy, yellow starting, red failed. kas/bench-debug.yml declares
# a gpio-led overlay on 17 for the kernel's heartbeat trigger, and
# docs/DESIGN.md's ownership table gives that line to ledtrig-heartbeat.
#
# Two claimants, and only one can win. leds-gpio takes the line from the
# device tree during probe, so bench-status asks for 17, 27 and 22 in a
# single all or nothing libgpiod request, gets EBUSY and exits 1. Measured
# on Sunday 4 October 2026, with systemd restarting it 301 times before it
# was stopped by hand:
#
#     bench-status: requesting lines 17/27/22: Device or resource busy
#
# bench-ab-image.bb and bench-lcd35a-image.bb already resolve this the same
# way for the same reason. This image had not, and the reason it had never
# shown is worth recording: until that evening gpio-led.dtbo was not
# deployed to any card, so leds-gpio never competed and nothing ever
# failed. The conflict was always here; only the evidence was missing.
#
# The heartbeat wins rather than the health indicator, and the reason is
# specific to this project. The LED is the instrument that still reports
# once the kernel has stopped, and a userspace daemon cannot do that: it
# would freeze lit, and a frozen lit lamp is indistinguishable from a
# healthy one.
IMAGE_INSTALL:remove = "bench-status"

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
#
# MEASURED ON THE BOARD, Monday 5 October 2026, and it corrects the block
# above. None of that sequence happens on this image, because neither half
# of it is present:
#
#   /usr/lib/systemd/system/systemd-pstore.service   does not exist
#   journalctl -b | grep -i pstore                   only the kernel's own
#                                                    two lines, so systemd
#                                                    never tried to mount
#                                                    it and never logged a
#                                                    failure
#
# This systemd was built without its pstore component. The mask above is
# therefore a symlink to /dev/null for a unit that is not here. It is kept
# as insurance, because a later layer or PACKAGECONFIG change could bring
# the service in and the argument for masking it would hold again. What it
# is not, and what the block above implies it is, is a guard against
# something currently happening.
#
# The real problem is the opposite one. Nothing mounts the filesystem, so a
# crash record sits in the backend while /sys/fs/pstore is an empty
# directory, which reads exactly like the failure the block above was
# written to prevent. docs/BRINGUP.md step 6 runs `mount | grep pstore` and
# expects a mount; without the unit below that step is a false negative
# every time, and it was one on Sunday 4 October 2026.
#
# The unit directory is /usr/lib/systemd/system, read off the running board
# rather than assumed: it is where bench-status.service was loaded from
# before that daemon was removed from this image.
ROOTFS_POSTPROCESS_COMMAND += "mask_systemd_pstore; mount_pstore; "

mask_systemd_pstore() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system
    ln -sf /dev/null \
        ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/systemd-pstore.service
}

mount_pstore() {
    unitdir=${IMAGE_ROOTFS}/usr/lib/systemd/system
    wants=${IMAGE_ROOTFS}${sysconfdir}/systemd/system/sysinit.target.wants
    install -d "$unitdir" "$wants"
    cat > "$unitdir/sys-fs-pstore.mount" <<'UNIT'
[Unit]
Description=Persistent Store File System
Documentation=https://github.com/ambrosiobing/embedded-linux
DefaultDependencies=no
ConditionPathExists=/sys/fs/pstore
Before=sysinit.target

[Mount]
What=pstore
Where=/sys/fs/pstore
Type=pstore
Options=nosuid,nodev,noexec

[Install]
WantedBy=sysinit.target
UNIT
    ln -sf /usr/lib/systemd/system/sys-fs-pstore.mount "$wants/sys-fs-pstore.mount"
}
