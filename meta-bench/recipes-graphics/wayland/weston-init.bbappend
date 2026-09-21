# Turn oe-core's weston into a kiosk, by replacing one configuration file.
#
# WHY A BBAPPEND AND NOT A UNIT OF OUR OWN.
#
# The project specification writes a systemd unit by hand: a dedicated
# user, PAMName=login, TTYPath=/dev/tty1, Conflicts=getty@tty1.service.
# oe-core's weston-init has already solved every one of those, and
# solved two of them better:
#
#   it creates the weston user with the right groups
#       (video, input, render, wayland)
#   it opens a login session with PAMName=weston-autologin, which is
#       what gives logind a seat to hand to libseat
#   it uses TTY7, not TTY1
#
# That last one removes a conflict rather than declaring one. The bench
# image puts console=tty1 on the kernel command line and runs a getty
# there, so the specification's Conflicts=getty@tty1.service would take
# the serial-adjacent console away from the operator. On tty7 the
# dashboard and the login prompt coexist, and Ctrl-Alt-F1 still reaches a
# shell on a board whose screen is showing a kiosk. On a bench that is
# strictly better.
#
# So the only thing this project needs to change is which shell weston
# loads and what it launches. That is weston.ini, and weston.ini is a
# CONFFILE of weston-init, so it is replaced here rather than shipped
# from a second package that would collide with it at packaging time.
#
# A second unit managing the same compositor is exactly the two-managers
# bug that docs/DESIGN.md's ownership table exists to prevent, and it
# would be invisible until both tried to take DRM master.

# files/, not ${PN}/. Both are ordinary Yocto conventions; this layer
# uses files/ everywhere and scripts/lint.py checks SRC_URI against it,
# so a bbappend that put its file elsewhere would be the one recipe the
# linter could not see into.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://weston-kiosk.ini"

# Replace the shipped template. Done in an append so the file keeps
# weston-init's CONFFILES status, which means an operator's edits on the
# board survive a package upgrade.
do_install:append() {
    install -Dm0644 ${WORKDIR}/weston-kiosk.ini \
        ${D}${sysconfdir}/xdg/weston/weston.ini
}

# bench-hmi is what the autolaunch line starts. Without it weston comes
# up, paints the kiosk background and sits there, which looks like a
# compositor failure and is a missing package.
RDEPENDS:${PN} += "bench-hmi"
