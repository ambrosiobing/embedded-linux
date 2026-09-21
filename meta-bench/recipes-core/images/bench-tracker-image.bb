SUMMARY = "Bench tracker: Cat-M and NB-IoT, driven by AT, asleep in between"
DESCRIPTION = "The bench image turned into the low-power tracker of \
Project 16. It adds the state machine, the power key and marker tool, and \
the two tools needed to find out what the modem actually is. It adds no \
modem manager, no network manager and no IP stack for the modem, because \
the CoAP datagram is built on the host and handed to the modem's own IP \
stack over the AT port."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    usbutils \
    bench-tracker \
"

# THE FIRST BUILD OF THIS IMAGE IS A RECONNAISSANCE BUILD, and that is the
# plan rather than a shortfall.
#
# There is no kernel fragment yet. Nothing in this repository records how a
# SIM7070G enumerates, so the USB serial driver it needs has not been
# written into a .cfg, and this image will very likely boot with the modem
# attached and no tty for it. That is the expected outcome of the first
# boot and it is still the fastest way forward: lsusb and dmesg report the
# device descriptor whether or not a driver bound to it, and the descriptor
# is exactly what has to be read before the fragment can be written
# honestly.
#
# Project 1 lost two rounds to a wlan0 that was assumed and Project 8 lost
# a flash to a spidev that was. Reading the part costs one boot.
#
# usbutils is here for that, and it is not a temporary addition. The first
# question on a board that shows no modem is what is on the bus, and
# Project 15's first bring-up answered it by reading sysfs by hand for want
# of lsusb. Its image recipe says the same thing in the same place.

# Deliberately absent, each for a reason that is the project rather than an
# oversight:
#
#   modemmanager      its job is to always know the modem's state, which it
#                     does by polling, and PSM is the modem being left
#                     alone for hours. Project 15's README already wrote
#                     the case for this project giving it up.
#   networkmanager    there is no network interface for the modem to be.
#   libqmi, ppp       the same. No QMI channel, no dial-up, no wwan0.
#   python3-modules   the tracker imports ten standard library modules and
#                     all ten are in python3-core. See bench-tracker_0.1.bb
#                     for the list and for how the guess would fail loudly.
#
# bench-net-wifi STAYS, and it is worth saying why rather than leaving it
# looking like an oversight in a low-power image. A wireless client on the
# Pi is how the board is reached at all while it is being brought up, and
# it does not contaminate the measurement: the PPK2 goes on the modem's
# supply rail, not the system's, because a Pi 3 idles in the hundreds of
# milliamps and the instrument stops at 1 A. The number this project
# publishes is the modem's charge per report, so what the processor's own
# radio is doing sits outside the measurement entirely. Measuring the
# processor's draw is a separate question and this image does not answer
# it.

# Smaller than Project 15's by design, so the extra space it asks for is
# smaller too. This is not core-image-minimal either: Project 1's rule
# still applies and the justification for every package above is written
# here or in projects/16-nbiot-tracker/README.md rather than assumed.
IMAGE_ROOTFS_EXTRA_SPACE = "65536"
