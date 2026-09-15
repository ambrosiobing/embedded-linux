SUMMARY = "Bench image with a BLE central and the STWIN.box gateway"
DESCRIPTION = "The bench image with the Bluetooth stack underneath it and \
the gateway of Project 17 on top: bluetoothd owning ATT and GATT, a Python \
client that subscribes to a sensor peripheral's notifications and forwards \
them to a CSV file and an MQTT topic, and the tools that make a radio \
debuggable from the board itself."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    bluez5 \
    bluez-firmware-rpidistro-bcm4345c0-hcd \
    python3-bleak \
    python3-paho-mqtt \
    python3-gpiod \
    mosquitto \
    mosquitto-clients \
    bench-stwin \
"

# bluez5 is bluetoothd, bluetoothctl, btmon and hciconfig in one package,
# and on a Raspberry Pi machine it brings pi-bluetooth with it: the
# meta-raspberrypi bbappend adds "RDEPENDS:${PN}:append:rpi = pi-bluetooth",
# which is what installs hciuart.service and bthelper@.service. Those are
# what attach the UART to the kernel and make hci0 exist at all. Nothing
# here has to name them, and naming them anyway would suggest they are a
# choice made here rather than a property of the BSP.
#
# hciconfig is deprecated and is in the image on purpose: bthelper calls
# it, and meta-raspberrypi carries a patch just to correct its path. It
# arrives because poky's default PACKAGECONFIG for bluez5 includes both
# "deprecated" and "tools"; if a future release drops either, hci0 comes up
# and bthelper fails in a way that reads like a radio fault.
#
# The firmware is the one piece with no automatic dependency at all. The
# CYW43455 has no flash: the kernel loads its patch RAM from
# /lib/firmware/brcm/BCM4345C0.hcd on every boot, and that file is not in
# poky's linux-firmware, which carries only BCM-0bb4-0306.hcd. It comes
# from meta-raspberrypi's bluez-firmware-rpidistro recipe, which packages
# the Cypress blobs RPi-Distro ships and upstream does not. Without it the
# adapter appears, hciattach times out, and hci0 never reaches UP RUNNING.
# This is the Bluetooth twin of the linux-firmware-rpidistro-bcm43455 line
# in bench-image.bb, and it is a different package: one is the WiFi
# firmware, this is the Bluetooth patch RAM.

# Mosquitto is here so that the pipeline can be proven end to end on one
# board with nothing else on the bench. Project 18 replaces it with a
# broker that has TLS and a private CA; this one listens on localhost and
# is a test fixture, not a product decision.

# Enough room for a day of CSV at the demo firmware's notification rate,
# plus the btsnoop traces that the bring-up notes ask for.
IMAGE_ROOTFS_EXTRA_SPACE = "262144"
