SUMMARY = "Composite USB gadget: CDC Ethernet, CDC ACM and a HID keyboard"
DESCRIPTION = "Turns the Raspberry Pi 4 into a USB device rather than a host. \
A configfs tree built by a shell script becomes one composite device that the \
host sees as a network adapter, a serial port and a keyboard, with no driver \
to install on either side. The HID report descriptor is checked in as \
annotated hex and assembled at build time."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://bench-gadget \
    file://bench-gadget.service \
    file://hid-keyboard.desc \
    file://20-usb0.network \
"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}"; it is the only line in the layer that has to move.
S = "${WORKDIR}"

inherit systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

SYSTEMD_SERVICE:${PN} = "bench-gadget.service"

# --- the report descriptor, assembled here rather than on the board ------
#
# The specification converts the annotated hex on the target with
#
#     xxd -r -p
#
# which assumes xxd is on the board. On a BusyBox image that is not safe,
# and the failure lands at the very last step of bringing the gadget up,
# after everything else has looked correct.
#
# So it is assembled at build time, where python3 certainly exists, and
# the board gets bytes. The annotated hex is still what is checked in,
# which is the property the specification actually cares about: the
# structure of a HID descriptor is the thing worth reading, and a .bin in
# a repository is 63 bytes nobody will look at again.
# A python task rather than a shell one calling python3. BitBake runs on
# python already, so this needs nothing from the host that is not
# guaranteed, and bb.fatal puts the reason in the build log in the place
# a reader is already looking.
python do_compile() {
    import os
    import re

    source = os.path.join(d.getVar("S"), "hid-keyboard.desc")
    target = os.path.join(d.getVar("B"), "hid-keyboard.bin")

    octets = []
    with open(source, "r") as handle:
        for line in handle:
            # Everything after a # is a comment, and stripping it FIRST
            # matters: the comments contain hex-looking words such as
            # "Usage Minimum (224)" and the page numbers, and a converter
            # that did not strip them would assemble a longer descriptor
            # that is still syntactically plausible.
            code = line.split("#", 1)[0]
            octets += re.findall(r"\b[0-9a-fA-F]{2}\b", code)

    data = bytes(int(octet, 16) for octet in octets)

    # THE ASSERTION THIS STEP EXISTS FOR.
    #
    # The boot keyboard descriptor from HID 1.11 is exactly 63 bytes. A
    # descriptor short or long by one byte is not a syntax error: it is a
    # tree the host parses differently, and the symptom is a keyboard
    # that enumerates cleanly and types nothing. That is a long way from
    # the cause, on the far side of a flash and a reboot.
    if len(data) != 63:
        bb.fatal("hid-keyboard.desc assembled to %d bytes, expected 63. "
                 "A dropped or added octet changes how the host parses "
                 "the whole descriptor." % len(data))

    # Two structural checks, cheap and specific enough to name what is
    # wrong rather than only that something is.
    if data[0:2] != b"\x05\x01":
        bb.fatal("descriptor does not begin with Usage Page (Generic "
                 "Desktop); first two bytes are %02x %02x"
                 % (data[0], data[1]))
    if data[-1] != 0xC0:
        bb.fatal("descriptor does not end with End Collection (0xc0); "
                 "last byte is %02x" % data[-1])

    with open(target, "wb") as handle:
        handle.write(data)

    bb.note("hid-keyboard.bin: %d bytes" % len(data))
}

do_install() {
    install -Dm0755 ${S}/bench-gadget ${D}${sbindir}/bench-gadget

    install -Dm0644 ${B}/hid-keyboard.bin \
        ${D}${datadir}/bench-gadget/hid-keyboard.bin

    # hid-keyboard.desc is the source of that binary and is installed too,
    # beside it, so that a board carries the annotated version of what it
    # is actually using. It is 2 kB and it is the only place the
    # descriptor is explained.
    install -Dm0644 ${S}/hid-keyboard.desc \
        ${D}${datadir}/bench-gadget/hid-keyboard.desc

    install -Dm0644 ${S}/bench-gadget.service \
        ${D}${systemd_system_unitdir}/bench-gadget.service

    install -Dm0644 ${S}/20-usb0.network \
        ${D}${nonarch_libdir}/systemd/network/20-usb0.network
}

FILES:${PN} += "\
    ${datadir}/bench-gadget \
    ${nonarch_libdir}/systemd/network \
"

# The script reads /sys/class/udc and writes configfs; neither needs a
# package. What it does need is a login on the gadget's serial port,
# which is systemd's own template unit, and that is enabled by the image
# rather than here: serial-getty@ttyGS0 only makes sense on a board where
# this gadget is actually running, and enabling a getty on a tty that
# does not exist is a unit that fails at every boot.
