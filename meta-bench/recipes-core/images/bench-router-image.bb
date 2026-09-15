SUMMARY = "Bench gateway: two uplinks, one LAN, cellular failover"
DESCRIPTION = "The bench image turned into the router of Project 15. It \
adds ModemManager and NetworkManager for the modem and the routing policy, \
nftables for the packet path, dnsmasq for the bench LAN, and the watchdog, \
control lines and metrics that make a cellular uplink something you can \
leave running unattended."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

# The wireless client profile has to go. bench-net-wifi configures wlan0 as
# a systemd-networkd DHCP client joining somebody else's access point;
# this image runs an access point on the same interface under
# NetworkManager. Two managers on one interface is not a conflict that
# resolves itself, it is an interface that flaps. The keymap and the rest
# of bench-provision stay, which is why that recipe was split in two.
IMAGE_INSTALL:remove = "bench-net-wifi"

IMAGE_INSTALL:append = " \
    networkmanager \
    networkmanager-wwan \
    modemmanager \
    libqmi \
    dnsmasq \
    nftables \
    usbutils \
    bench-router \
    bench-lte \
"

# networkmanager-wwan is the mobile broadband device plugin, and it is a
# separate package. Installing networkmanager alone gives a daemon that
# sees wwan0, logs "'wwan' plugin not available; creating generic device",
# and marks it unmanaged for ever. The profile is then valid, the modem is
# registered, and nothing connects. The package also has to be built, which
# is the PACKAGECONFIG line in kas/bench-router.yml.
#
# usbutils is here because this project's subject is a USB composite
# device. The first question on a board that shows no modem is what is on
# the bus, and the first bring-up answered it by reading sysfs by hand for
# want of lsusb.

# libqmi brings qmicli, which is how the QMI channel is inspected directly
# when the question is whether ModemManager is wrong or the modem is. It is
# a debugging tool on a box whose failure mode is "no connectivity", which
# is the one failure that makes installing a tool afterwards impossible.

# The modem drivers and the netfilter stack are built into the kernel
# rather than packaged as modules. See recipes-kernel/linux/files/router.cfg
# for why, and kas/bench-router.yml for the switch that turns the fragment
# on. An image built without that kas file boots and has no wwan0.

# NetworkManager, ModemManager, dnsmasq and a Python interpreter are a long
# way from core-image-minimal. Project 1's rule still applies: every
# package is justified in writing, and the justification for this jump is
# in projects/15-lte-router/README.md rather than here.
IMAGE_ROOTFS_EXTRA_SPACE = "262144"
