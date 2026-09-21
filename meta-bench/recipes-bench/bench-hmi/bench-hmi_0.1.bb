SUMMARY = "Full screen LVGL dashboard as a Wayland client"
DESCRIPTION = "The bench HMI: load average, SoC temperature, memory use and \
the Project 1 status LED, drawn with LVGL into an xdg_toplevel surface and \
shown full screen by a kiosk compositor. It is the visible end of the \
bench: when bench-status writes failed, the screen goes red before anyone \
looks at the LEDs on the header."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

# LVGL is vendored rather than taken from meta-oe, and the reason is a
# silent no-op that would otherwise ship.
#
# meta-oe carries lvgl_9.1.0.bb. LVGL 9.1.0 HAS NO WAYLAND DRIVER: its
# src/drivers/ holds display, evdev, libinput, nuttx, sdl, windows and
# x11, and lv_conf_template.h at that revision contains no
# LV_USE_WAYLAND line at all. The Wayland driver arrives in 9.2.0.
#
# That matters more than a missing feature because of HOW meta-oe
# configures LVGL. lv-conf.inc sets options by running sed over
# lv_conf.h, and a sed whose pattern matches nothing changes nothing and
# reports success. Adding LV_USE_WAYLAND to a bbappend there would
# produce no error, no warning and no effect: the build would succeed and
# the binary would have no Wayland support. Project 9 found the same
# shape of failure in promptless Kconfig symbols; this is the sed
# version of it.
#
# Bumping meta-oe's recipe from a bbappend is not the answer either: it
# is pinned at 9.1.0 and carries three patches written against that
# revision, and every other consumer in the layer index would get them
# applied to a tree they do not fit.
#
# So this recipe fetches its own LVGL, exactly the way oe-core's own
# lvgl-demo-fb recipe fetches lv_port_linux_frame_buffer plus lvgl as two
# repositories. meta-oe's lvgl is left untouched.
SRC_URI = "\
    git://github.com/lvgl/lvgl;protocol=https;branch=master;name=lvgl;destsuffix=lvgl \
    file://CMakeLists.txt \
    file://main.c \
    file://dashboard.c \
    file://dashboard.h \
    file://metrics.c \
    file://metrics.h \
"

# v9.3.0. The license file changed between 9.1.0 and 9.3.0, so meta-oe's
# checksum for it does not apply here and is not copied:
#   9.1.0  bf1198c89ae87f043108cea62460b03a
#   9.3.0  4570b6241b4fced1d1d18eb691a0e083
SRCREV_lvgl = "c033a98afddd65aaafeebea625382a94020fe4a7"
LIC_FILES_CHKSUM += "file://${WORKDIR}/lvgl/LICENCE.txt;\
md5=4570b6241b4fced1d1d18eb691a0e083"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}"; it is the only line in the layer that has to move.
S = "${WORKDIR}"

# wayland-native is for wayland-scanner, which runs on the BUILD machine
# to turn xdg-shell.xml into C. wayland-protocols supplies that xml.
# Leaving either out produces link errors about xdg_wm_base symbols that
# name neither package, which the specification lists as a pitfall.
DEPENDS = "wayland wayland-native wayland-protocols libxkbcommon"

inherit cmake pkgconfig features_check

REQUIRED_DISTRO_FEATURES = "wayland"

# --- the configuration, and a check that it actually took ---------------
#
# Same mechanism meta-oe uses: start from the upstream template and set
# the handful of options that differ. The difference is the last block.
do_configure:prepend() {
    cp -f "${WORKDIR}/lvgl/lv_conf_template.h" "${S}/lv_conf.h"

    # Upstream's template ships every option inside an "#if 0" block.
    sed -r -i -e "s|#if 0 (.*Set it to \"1\" to enable content.*)|#if 1 \1|" \
        "${S}/lv_conf.h"

    # One option per call, rather than a wall of -e expressions.
    #
    # The replacement is "\1 VALUE", with the capture ending BEFORE the
    # whitespace so that the space in the replacement separates them.
    # Writing it meta-oe's way, with the whitespace inside the capture,
    # produces "\11" for a value of 1: a backreference followed by a
    # digit, which relies on GNU sed guessing that there is no group 11.
    # It works there and it is not worth inheriting.
    #
    # $1 and $2, not ${name}: inside a BitBake shell function ${...} is
    # expanded by BitBake at parse time, so a shell variable written that
    # way is gone before the shell ever runs.
    set_conf() {
        sed -r -i \
            -e "s|^([[:space:]]*#define[[:space:]]+$1)[[:space:]]+.*|\1 $2|" \
            "${S}/lv_conf.h"
    }

    set_conf LV_USE_WAYLAND                 1
    set_conf LV_WAYLAND_WINDOW_DECORATIONS  0
    set_conf LV_WAYLAND_WL_SHELL            0
    set_conf LV_COLOR_DEPTH                 32
    set_conf LV_USE_LOG                     1
    set_conf LV_LOG_LEVEL                   LV_LOG_LEVEL_WARN
    set_conf LV_USE_LED                     1
    set_conf LV_USE_BAR                     1

    # THE CHECK THIS RECIPE EXISTS TO CARRY.
    #
    # Every line above is a sed, and a sed that matches nothing succeeds.
    # If upstream renames a symbol, moves it behind an #if, or changes
    # the spacing, the configuration silently reverts to the template
    # default and the build produces a binary with no Wayland support and
    # no complaint. That is precisely the failure this recipe exists to
    # avoid, so it is asserted rather than assumed.
    #
    # Checked by reading the file back, not by trusting the exit status.
    #
    # Positional parameters, not ${name}: inside a BitBake shell function
    # ${...} is expanded by BitBake at parse time, so a shell variable
    # written that way is replaced with an empty string long before the
    # shell runs. $1 and $2 are invisible to it.
    check_conf() {
        if grep -qE "^[[:space:]]*#define[[:space:]]+$1[[:space:]]+$2([[:space:]]|$)" \
                "${S}/lv_conf.h"; then
            return 0
        fi
        bberror "lv_conf.h: $1 is not $2 after configuration."
        bberror "The sed above matched nothing, which means upstream has"
        bberror "changed the spelling of this option. What the file says:"
        grep -nE "define[[:space:]]+$1" "${S}/lv_conf.h" >&2 ||
            bberror "  (the symbol is not in the file at all)"
        bbfatal "refusing to build an HMI with no Wayland support"
    }

    # Three of the nine, chosen because each one fails differently:
    # without WAYLAND there is no backend at all, without COLOR_DEPTH 32
    # the buffer format disagrees with the compositor, and LED is the
    # widget the Project 1 state drives. The other six are cosmetic and
    # a wrong value there is visible on the screen.
    check_conf LV_USE_WAYLAND 1
    check_conf LV_COLOR_DEPTH 32
    check_conf LV_USE_LED 1
}

EXTRA_OECMAKE = "\
    -DLV_CONF_PATH=${S}/lv_conf.h \
    -DLV_CONF_BUILD_DISABLE_EXAMPLES=ON \
    -DLV_CONF_BUILD_DISABLE_DEMOS=ON \
"

do_install() {
    install -Dm0755 ${B}/bench-hmi ${D}${bindir}/bench-hmi
}

# CMakeLists.txt is a build input, consumed by cmake.bbclass, and is not
# installed. Named here because scripts/lint.py asks every SRC_URI entry
# to appear somewhere in the build tasks, and a file that is genuinely
# only an input has to say so rather than be silently exempt. The same
# rule caught a first-boot template that really had been dropped.

FILES:${PN} = "${bindir}/bench-hmi"

# The dashboard reads /run/bench/state, which bench-status writes. It is
# an RRECOMMENDS rather than an RDEPENDS on purpose: the HMI runs without
# it and shows "unknown" in yellow, which is the honest display for a
# board where nothing is reporting. A hard dependency would mean the
# screen could not come up to tell you that.
RRECOMMENDS:${PN} = "bench-status"
