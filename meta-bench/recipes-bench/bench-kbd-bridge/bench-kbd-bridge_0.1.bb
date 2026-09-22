SUMMARY = "Bridge the Pi's own keyboard to the host as a USB HID keyboard"
DESCRIPTION = "Grabs the physical keyboard with evdev and replays every key \
to the host as boot-protocol HID reports through the gadget, so the Pi sits \
between a keyboard and a PC. A FIFO accepts macros, which are typed as if \
they had come from the keyboard. The keycode to HID usage table is generated \
from the kernel's own hid-input.c rather than typed."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://kbd_bridge.c \
    file://usage_table.h \
    file://gen-usage-table.py \
    file://kbd-bridge.service \
    file://80-bench-kbd.rules \
"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}"; it is the only line in the layer that has to move.
S = "${WORKDIR}"

DEPENDS = "libevdev"

inherit systemd pkgconfig features_check

REQUIRED_DISTRO_FEATURES = "systemd"

SYSTEMD_SERVICE:${PN} = "kbd-bridge.service"

# The service is started by udev when the keyboard appears, through
# ENV{SYSTEMD_WANTS} in the rule, not at boot. Enabling it at boot would
# give a unit that fails on every board where the keyboard is not plugged
# in yet, which is most boots.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

# -Werror here and not in the image build. The rule this layer follows is
# that a toolchain upgrade should fail a pull request, not somebody's
# image build; CI compiles this file with the same flags.
CFLAGS:append = " -Wall -Wextra"

do_compile() {
    ${CC} ${CFLAGS} ${CPPFLAGS} $(pkg-config --cflags libevdev) \
        ${S}/kbd_bridge.c -o kbd-bridge \
        ${LDFLAGS} $(pkg-config --libs libevdev)
}

do_install() {
    install -Dm0755 kbd-bridge ${D}${bindir}/kbd-bridge

    install -Dm0644 ${S}/kbd-bridge.service \
        ${D}${systemd_system_unitdir}/kbd-bridge.service

    install -Dm0644 ${S}/80-bench-kbd.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/80-bench-kbd.rules

    # The generator is installed beside nothing and used by nobody at
    # run time. It is here so that a board carries the thing that
    # produced its own usage table, which is the difference between a
    # generated file and a magic one.
    install -Dm0755 ${S}/gen-usage-table.py \
        ${D}${datadir}/bench-kbd-bridge/gen-usage-table.py
}

FILES:${PN} += "\
    ${nonarch_base_libdir}/udev/rules.d \
    ${datadir}/bench-kbd-bridge \
"

# usage_table.h is a build input, compiled into kbd-bridge and not
# installed. Named here because scripts/lint.py asks every SRC_URI entry
# to appear in the build tasks, and a file that is genuinely only an
# input has to say so rather than be silently exempt.
#
# It is CHECKED IN rather than generated during the build, and that is
# deliberate. Generating it here would make the recipe depend on the
# kernel source being unpacked, which couples a userspace recipe to a
# kernel build for a table that changes about once a decade. The
# generator ships beside it and the header records which revision it came
# from, so regenerating is one command and reviewing the diff is possible.
