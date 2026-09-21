SUMMARY = "Bench image that boots straight into a full screen touch dashboard"
DESCRIPTION = "The bench image plus the graphics stack of Project 13: weston \
with the kiosk shell, the LVGL dashboard it launches, and the tools that \
show each layer when one of them is wrong. It is the visible end of the \
bench: the Project 1 status word becomes a colour on a screen."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    weston \
    weston-init \
    bench-hmi \
    bench-kiosk \
    kernel-modules \
"

# --- kernel-modules, and why the whole set ------------------------------
#
# WITHOUT THIS LINE THIS IMAGE HAS NO GRAPHICS AT ALL. Not a degraded
# panel: no /dev/dri, no DRM device, no touch input device. weston fails
# to find an output and the screen stays black, which is the same symptom
# as a bad ribbon, a missing overlay and a brown-out.
#
# The reason is that every driver this project needs is a MODULE in the
# Raspberry Pi 4 defconfig, and core-image-minimal, which bench-image is
# built on, installs no kernel modules. Read out of
# arch/arm64/configs/bcm2711_defconfig at rpi-6.6.y:
#
#     CONFIG_DRM=m
#     CONFIG_DRM_VC4=m
#     CONFIG_DRM_V3D=m
#     CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=m
#     CONFIG_TOUCHSCREEN_EDT_FT5X06=m
#
# Project 6 met the same trap and answered it with a fragment full of =y,
# on the argument that nothing on that image is optional. THAT ANSWER
# DOES NOT WORK HERE, and the reason is worth writing down because it is
# invisible until a build:
#
#     config DRM_VC4
#         tristate "Broadcom VC4 Graphics"
#         ...
#         depends on SND && SND_SOC
#
# and the same defconfig has CONFIG_SND=m and CONFIG_SND_SOC=m. A
# tristate that depends on a module can itself be at most a module, so
# CONFIG_DRM_VC4=y is not merely unset by a fragment, it is UNREACHABLE.
# The fragment line would be dropped in silence, the build would succeed,
# and the board would have no display. Getting =y would mean pulling the
# entire ALSA and ASoC stack in built-in, to gain nothing that installing
# the modules does not already give.
#
# So the modules stay modules, which is also how Raspberry Pi OS ships
# them and what the firmware overlay flow expects, and the image installs
# them.
#
# WHY THE WHOLE SET rather than a list of names. Package names for
# modules are derived from the .ko basename with underscores turned into
# hyphens, so the touch driver's package is not spelled the way the
# Kconfig symbol or the source file is. That is easy to get subtly wrong,
# and a name that matches nothing is not an error: BitBake installs no
# package and says nothing, which lands back at a black screen with a
# different cause. The keyboard path needs the USB HID drivers as well,
# and those are not named in the defconfig at all. For an image whose
# entire product is a working display, the size of the module set is the
# cheaper risk.
#
# If this image ever needs to shrink, the safe way is to measure which
# modules actually load on a working board
# (lsmod > docs/evidence/lsmod.txt) and narrow to that list, rather than
# to guess names from the defconfig.

# weston-init is what carries the unit, the weston user and its groups,
# and the PAM session that gives logind a seat to hand out. The bbappend
# in meta-bench replaces its weston.ini with a kiosk one and adds the
# RDEPENDS on bench-hmi, so installing weston-init here is what pulls the
# whole session together.
#
# bench-hmi is listed anyway rather than left to that RDEPENDS, because
# an image should say what it contains: a reader checking whether the
# dashboard is in this image should not have to open a bbappend to find
# out.

# --- the tools that answer for each layer -------------------------------
#
# These are in the image on purpose, and the purpose is the project. The
# deliverable is knowing which tool shows which layer, and a tool that is
# not on the board when the screen is black is not a tool.
#
# libinput      libinput debug-events, list-devices
# wayland-utils wayland-info: what globals the compositor offers
# evtest        raw evdev, below libinput
IMAGE_INSTALL:append = " \
    libinput \
    wayland-utils \
"

# drm-info is NOT here, and that is a gap rather than a decision.
#
# It is the tool the specification reaches for first and the one
# docs/DESIGN.md's table names for the KMS layer, and there is no recipe
# for it in oe-core, meta-oe or meta-raspberrypi. bench-gfx covers the
# part that matters most (which card carries a connected connector, and
# the atomic state) by reading sysfs and debugfs directly, and says so
# when drm_info is absent rather than pretending the question was asked.
#
# Packaging drm_info is a small recipe and a reasonable follow-up; it is
# named in the project README under what is not done.

# evtest is likewise absent from the layers here. BusyBox has no
# equivalent, so the raw evdev layer is reachable only through
# bench-gfx's device listing and through libinput, which sits above it.
# Both gaps are in the acceptance table with their reason.

# LVGL vendors its own copy, the dashboard is one binary, and weston with
# the kiosk shell and Mesa is the bulk. Room for the compositor, the GPU
# driver and a font.
IMAGE_ROOTFS_EXTRA_SPACE = "262144"
