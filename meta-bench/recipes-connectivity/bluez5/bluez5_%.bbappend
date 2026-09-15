# bluetoothd's configuration, which this image would otherwise not have.
#
# poky's bluez5 recipe installs network.conf and input.conf into
# /etc/bluetooth and nothing else: there is no main.conf on the image at
# all, so bluetoothd runs entirely on the defaults compiled into it. That
# is worth knowing before copying instructions written for a distribution,
# where the file exists and is mostly comments.
#
# A new file rather than an edit to somebody else's, so there is no
# packaging conflict and no sed against a version-specific layout. Every
# key in main.conf is optional, which means a short file that contains only
# the decisions reads better than a long one with three lines uncommented.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://main.conf"

# WORKDIR, not S: S is the bluez source tree here, and a file:// entry is
# unpacked beside it. On walnascar and later this becomes UNPACKDIR, the
# same one line every other recipe in this layer has to move.
do_install:append() {
    install -d ${D}${sysconfdir}/bluetooth
    install -m 0644 ${WORKDIR}/main.conf ${D}${sysconfdir}/bluetooth/main.conf
}

CONFFILES:${PN} += "${sysconfdir}/bluetooth/main.conf"
