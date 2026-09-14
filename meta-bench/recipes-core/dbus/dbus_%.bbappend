# dbus is built with X11 autolaunch because the poky distro carries x11 in
# DISTRO_FEATURES. That feature starts a session bus by talking to an X
# display, which a headless bench board can never do, and it costs four
# packages in the rootfs: libx11, libxcb, libxau and libxdmcp.
#
# Removed here rather than by dropping x11 from DISTRO_FEATURES. Both would
# work, and the distro-wide change is arguably more correct for a headless
# image, but it invalidates shared-state signatures across the whole build
# for a four-package saving. This rebuilds one recipe. Project 13 will want
# graphics, and it wants Wayland rather than X11, so the distro feature is
# not being kept for its benefit either.
PACKAGECONFIG:remove = "x11"
