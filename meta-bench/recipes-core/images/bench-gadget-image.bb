SUMMARY = "Bench image that is a USB device rather than a USB host"
DESCRIPTION = "The bench image with Project 14 on it: a composite USB gadget \
that the host sees as a network adapter, a serial port and a keyboard, and a \
daemon that bridges the Pi's own keyboard to the host. One cable carries all \
three functions and supplies the board."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    bench-gadget \
    bench-kbd-bridge \
    libevdev \
"

# --- no kernel-modules line here, and that is the finding ---------------
#
# Project 13's image needs "kernel-modules" because every graphics driver
# is =m in bcm2711_defconfig and core-image-minimal installs none. The
# same trap is set here and this image steps around it a different way:
#
#     CONFIG_USB_DWC2=m      in the defconfig
#     CONFIG_USB_CONFIGFS=m  in the defconfig
#
# but unlike DRM_VC4, which depends on SND and could therefore never be
# =y, both of these are reachable at =y and gadget.cfg sets them. So the
# controller and the configfs interface are in the kernel image and there
# is no module to install.
#
# Which way round to solve it is decided by the Kconfig and not by
# preference, and the two projects came out differently for that reason.
# See projects/14-usb-gadget/docs/DESIGN.md.

# --- the login on the gadget's serial port -------------------------------
#
# serial-getty@ttyGS0 is systemd's own template, instantiated for the
# tty the ACM function creates. Enabled HERE rather than in the
# bench-gadget recipe, because a getty on a tty that does not exist is a
# unit that fails at every boot, and ttyGS0 exists only on a board where
# this gadget is actually running.
SYSTEMD_DEFAULT_TARGET ?= "multi-user.target"

ROOTFS_POSTPROCESS_COMMAND += "enable_gadget_getty; "

enable_gadget_getty() {
    wants=${IMAGE_ROOTFS}${sysconfdir}/systemd/system/getty.target.wants
    install -d $wants
    ln -sf ${systemd_system_unitdir}/serial-getty@.service \
        $wants/serial-getty@ttyGS0.service
}

# --- the power budget is the constraint, so the image stays small --------
#
# Everything on this board is powered by the host's USB port: 500 mA on
# USB 2.0, 900 mA on USB 3, against a Pi 4 that idles near 550 mA and
# peaks above 1 A. There is no display, no HAT and no second supply, and
# that is a hardware fact rather than a packaging choice, but it is the
# reason nothing optional is added here.
IMAGE_ROOTFS_EXTRA_SPACE = "65536"
