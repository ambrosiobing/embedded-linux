SUMMARY = "Bench image with the sensor hub service and its clients"
DESCRIPTION = "The bench image plus Project 12: the daemon that owns the \
serial link to a sensor hub microcontroller and republishes it on the \
system bus, the system bus itself, polkit to decide who may calibrate, a \
Python client that knows nothing about the wire format, and OpenOCD so \
that the firmware can be reflashed from the board rather than from a desk."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    bench-sensorhub \
    dbus \
    dbus-tools \
    polkit \
    libcbor \
    python3-dbus-next \
    openocd \
    kernel-module-cdc-acm \
"

# dbus and dbus-tools are named rather than assumed. core-image-minimal
# with systemd does not install the system bus, and busctl comes from
# systemd while dbus-send and dbus-monitor come from dbus-tools; the
# bring-up notes use busctl, but the first thing anybody reaches for when
# a bus question gets strange is dbus-monitor.
#
# kernel-module-cdc-acm for the same reason the RT image names
# kernel-module-spidev and the first image had to name the radio driver:
# core-image-minimal installs no kernel modules at all, so the driver that
# turns the ST-LINK's virtual COM port into /dev/ttyACM0 has to be asked
# for. Without it the device enumerates, dmesg shows the USB descriptor,
# and no tty ever appears.
#
# openocd is 30 MB and it is here on purpose. Flashing the hub from the
# board that talks to it is the update path a product would use: a CI job
# builds the firmware, copies the ELF to the Pi, and the Pi programs it
# over the same USB cable it already reads frames from. A bench that needs
# a laptop and a debugger on the desk has no such path.

# The daemon is not started at boot. It is started by the device appearing
# or by a client calling, which is the point of Project 12 and is why
# nothing here enables a unit.

IMAGE_ROOTFS_EXTRA_SPACE = "262144"
