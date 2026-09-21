SUMMARY = "A/B slot health policy, failsafe and mounts"
DESCRIPTION = "Everything Project 19 adds on the Linux side of an A/B \
update: a demonstration application with a heartbeat, the health check \
that decides whether the running slot is kept, a failsafe timer for a \
boot that reaches no verdict at all, the systemd watchdog setting, and \
the mount unit for the one partition that neither slot owns."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://bench-app \
    file://bench-health \
    file://bench-failsafe \
    file://bench-app.service \
    file://bench-app-broken.service \
    file://bench-health.service \
    file://bench-failsafe.service \
    file://bench-failsafe.timer \
    file://bench-watchdog.conf \
    file://boot.mount \
    file://fw_env.config \
    file://journald-persistent.conf \
    file://bench-ab.tmpfiles.conf \
    file://bench-slot-leds \
    file://bench-slot-leds.service \
    file://bench-rauc-pre-install \
    file://bench-rauc-post-install \
"

inherit systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

# Off everywhere except in the one kas file that builds the bundle for
# acceptance criterion 5. A default of "1" here would put a broken
# application in the card image itself, and the first boot of a fresh card
# would roll back to an empty slot B.
BENCH_AB_BREAK_APP ?= "0"

# The switch decides what is installed and bitbake cannot see that through
# a shell conditional. Without this line, flipping it would be served the
# previous package out of sstate: the build would report success, the
# bundle would carry a working application, and criterion 5 would fail to
# fail. A test that cannot fail is the most expensive kind here, because
# the whole project is the failure paths.
do_install[vardeps] += "BENCH_AB_BREAK_APP"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}", the same one line every other recipe in this layer
# will have to move.
S = "${WORKDIR}"

# Shell and units only, so nothing is compiled and nothing is architecture
# specific. The package is still not allarch: the unit files name
# /dev/mmcblk0 partitions, which is a property of this board's card, and an
# allarch package would claim to be reusable on a board where those names
# mean something else.

do_install() {
    install -Dm0755 ${S}/bench-app ${D}${bindir}/bench-app
    install -Dm0755 ${S}/bench-health ${D}${bindir}/bench-health
    install -Dm0755 ${S}/bench-failsafe ${D}${bindir}/bench-failsafe
    install -Dm0755 ${S}/bench-slot-leds ${D}${bindir}/bench-slot-leds

    # RAUC's handlers take no arguments, so these are two one-line wrappers
    # rather than one script with a parameter. system.conf names them by
    # absolute path; moving either one silently disables that handler,
    # because a handler RAUC cannot execute is reported once in a log
    # nobody reads during an install.
    install -Dm0755 ${S}/bench-rauc-pre-install \
        ${D}${bindir}/bench-rauc-pre-install
    install -Dm0755 ${S}/bench-rauc-post-install \
        ${D}${bindir}/bench-rauc-post-install

    # ACCEPTANCE CRITERION 5 IS PROVOKED HERE, at build time, and not on the
    # board. The specification asks for a bundle whose bench-app.service
    # runs /bin/false. Editing that unit by hand on a running board would
    # prove nothing about the update path: the interesting claim is that a
    # BUNDLE carrying a broken application installs successfully, boots,
    # fails three times and is abandoned. The fault has to travel the whole
    # mechanism for this to be a test of the mechanism.
    #
    # Both units are always fetched, so the two builds differ by which one
    # is installed under the name systemd looks for, and by nothing else.
    # Only kas/bench-ab-bundle-broken.yml sets the switch.
    if [ "${BENCH_AB_BREAK_APP}" = "1" ]; then
        install -Dm0644 ${S}/bench-app-broken.service \
            ${D}${systemd_system_unitdir}/bench-app.service
    else
        install -Dm0644 ${S}/bench-app.service \
            ${D}${systemd_system_unitdir}/bench-app.service
    fi
    install -Dm0644 ${S}/bench-health.service \
        ${D}${systemd_system_unitdir}/bench-health.service
    install -Dm0644 ${S}/bench-failsafe.service \
        ${D}${systemd_system_unitdir}/bench-failsafe.service
    install -Dm0644 ${S}/bench-failsafe.timer \
        ${D}${systemd_system_unitdir}/bench-failsafe.timer
    install -Dm0644 ${S}/bench-slot-leds.service \
        ${D}${systemd_system_unitdir}/bench-slot-leds.service

    # A mount unit's filename has to match the path it mounts, with the
    # separators turned into dashes. systemd will not load boot.mount for
    # any path but /boot, and renaming this file produces a unit that is
    # parsed, ignored, and reported by nothing.
    #
    # THERE IS NO data.mount, AND THAT IS DELIBERATE. p4 is mounted by the
    # overlayfs-etc preinit before systemd exists, because /etc has to be
    # an overlay before the thing that reads /etc starts. A mount unit for
    # the same device would be a second owner of it, which is the exact
    # fault class the ownership table in docs/DESIGN.md was written to
    # catch. The options for that mount are decided in one place,
    # OVERLAYFS_ETC_MOUNT_OPTIONS in bench-ab-image.bb.
    install -Dm0644 ${S}/boot.mount ${D}${systemd_system_unitdir}/boot.mount

    # The manager's own configuration, in the vendor directory rather than
    # in /etc. That matters more here than usual: /etc is an overlay whose
    # upper layer persists across updates, so a watchdog setting placed
    # there would be shadowed by whatever the first slot wrote and could
    # never be changed by a bundle again.
    install -Dm0644 ${S}/bench-watchdog.conf \
        ${D}${nonarch_libdir}/systemd/system.conf.d/10-bench-watchdog.conf

    # fw_setenv reads this from /etc by default and has no other way to be
    # told where the environment is.
    install -Dm0644 ${S}/fw_env.config ${D}${sysconfdir}/fw_env.config

    install -Dm0644 ${S}/journald-persistent.conf \
        ${D}${nonarch_libdir}/systemd/journald.conf.d/10-bench-persistent.conf
    install -Dm0644 ${S}/bench-ab.tmpfiles.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/bench-ab.conf

    # The journal's home, as a symlink made at build time because a
    # read-only root cannot make one at boot.
    #
    # This is why bench-ab-image.bb sets VOLATILE_LOG_DIR = "no". With the
    # default, /var/log is itself a symlink into tmpfs and this symlink
    # would be created inside a directory that is replaced at every boot,
    # so it would work on the build machine and exist nowhere on the board.
    install -d ${D}${localstatedir}/log
    ln -sf /data/journal ${D}${localstatedir}/log/journal

    # The mount point itself. A mount unit whose target directory does not
    # exist fails at boot, and on a read-only root nothing can create it
    # afterwards. /data is not created here: OVERLAYFS_ETC_CREATE_MOUNT_DIRS
    # defaults to 1 and the class makes it, so creating it here as well
    # would put one directory in two packages.
    install -d ${D}/boot
}

FILES:${PN} += "\
    ${systemd_system_unitdir} \
    ${nonarch_libdir}/systemd/system.conf.d \
    ${nonarch_libdir}/systemd/journald.conf.d \
    ${nonarch_libdir}/tmpfiles.d \
    ${localstatedir}/log/journal \
    /boot \
"

CONFFILES:${PN} = "${sysconfdir}/fw_env.config"

# rauc is what this package exists to serve, and u-boot-fw-utils is what
# writes the boot counters. rauc-target.inc adds the second automatically
# when the bootloader provider contains u-boot, but this package uses
# fw_setenv through its own fw_env.config and would be broken by an image
# that installed it without RAUC, so it asks for both itself.
RDEPENDS:${PN} += "rauc u-boot-fw-utils systemd"

# bench-failsafe.service is deliberately absent from this list: it is
# started by its timer, and enabling it as well would run the failsafe once
# at boot, immediately, before any health check could have written the
# marker it looks for. That would reboot every slot on its first boot,
# forever, and the reboot loop would look exactly like a hardware fault.
SYSTEMD_SERVICE:${PN} = "\
    bench-app.service \
    bench-slot-leds.service \
    bench-health.service \
    bench-failsafe.timer \
    boot.mount \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
