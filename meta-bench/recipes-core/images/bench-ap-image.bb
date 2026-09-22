SUMMARY = "Bench island: an access point and a broker nobody can join by accident"
DESCRIPTION = "The bench image turned into Project 18's edge access point. \
hostapd owns wlan0, dnsmasq hands out addresses and answers no DNS, and \
Mosquitto listens on 8883 with a private CA as the only thing it trusts. \
There is no uplink, no plaintext listener and no path onto the board other \
than its own network and the serial console."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

# THE WIRELESS CLIENT PROFILE HAS TO GO, AND THIS IS THE SAME REMOVAL
# PROJECT 15 MAKES FOR THE SAME REASON.
#
# bench-net-wifi configures wlan0 as a systemd-networkd DHCP client joining
# somebody else's access point, driven by wpa_supplicant. This image runs
# hostapd on that interface and assigns it a static address. Two managers
# on one interface is not a conflict that resolves itself, it is an
# interface that flaps, and here it would flap between being an access
# point and being a station.
#
# The keymap and the rest of bench-provision stay, which is why that recipe
# was split in two.
IMAGE_INSTALL:remove = "bench-net-wifi"

IMAGE_INSTALL:append = " \
    bench-ap \
    bench-broker \
"

# bench-ap pulls hostapd, dnsmasq, iw and wireless-regdb; bench-broker
# pulls mosquitto, mosquitto-clients and openssl-bin. Both recipes say in
# their own comments why each one is there, which is where a reader looking
# at a package will go.

# NOTHING ELSE. In particular, no NetworkManager and no ModemManager: this
# image has one interface, it is configured by two files, and a daemon
# whose job is to decide what to do with interfaces would have an opinion
# about the one thing here that must not change.

# THE FIRST BUILD IS EXPECTED TO BE INCOMPLETE, AND THE REASON IS ON THE
# CARD RATHER THAN IN THE IMAGE.
#
# Two things arrive after flashing, both of them identity rather than
# capability, and neither is in this repository:
#
#   /boot/ap.conf              SSID and passphrase, read at every boot
#   /etc/bench/pki/            the broker's certificate, key and the CA
#
# Without the first, bench-ap-setup refuses with a message naming the file
# and the board comes up with no network at all. Without the second,
# mosquitto refuses to start. Both refusals are loud and both are correct:
# an access point with a default passphrase and a broker with a certificate
# somebody else also has are worse than a board that will not come up.
#
# projects/18-edge-ap-mqtt/docs/evidence/README.md has the bring-up order.

# THE RADIO FIRMWARE IS AN OPEN QUESTION ON THIS BOARD, NOT A SETTLED ONE.
#
# bench-image installs linux-firmware-rpidistro-bcm43455, which is the
# Pi 3B+ and Pi 4 part. A plain Raspberry Pi 3 carries a BCM43438 and wants
# brcmfmac43430-sdio.bin, which nothing in this repository installs. Which
# board this project runs on decides whether a line has to be added here,
# and one line of dmesg on the first boot settles it. It is not guessed at:
# Project 1 lost two rounds to a radio whose firmware was assumed.

# Smaller than the router's. hostapd and dnsmasq are small, mosquitto is
# small, and the CA lives on a laptop. Project 1's rule still applies:
# every package is justified in writing, and the justification is in the
# two recipes and in projects/18-edge-ap-mqtt/README.md.
IMAGE_ROOTFS_EXTRA_SPACE = "65536"
