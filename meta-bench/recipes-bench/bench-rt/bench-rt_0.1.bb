SUMMARY = "Real-time latency lab: toggler, capture, analysis and matrix"
DESCRIPTION = "Project 8. A SCHED_FIFO task that toggles a GPIO line on an \
absolute schedule and keeps its own wake-up histogram, a capture script for \
the MCC 118 that watches the same line from outside the system, an analysis \
that recovers edge times below the sample period by interpolation, and the \
orchestration that applies one configuration at a time and refuses to \
label a run with a claim the kernel does not support."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://rt-toggle.c \
    file://rt-capture \
    file://rt-analyze \
    file://rt-compare \
    file://rt-run \
    file://rt-irq-affinity \
    file://rt.conf \
    file://rt.tmpfiles.conf \
"

DEPENDS = "libgpiod"

inherit pkgconfig

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}", the same one line bench-status and bench-lte move.
S = "${WORKDIR}"

# -Werror is not here, and that is deliberate rather than an oversight. A
# toolchain upgrade inside a three-hour image build is the worst place to
# discover a new warning, so the strict compile happens in CI and in
# scripts/host-check.sh against the host libgpiod, where it costs seconds.
CFLAGS:append = " -Wall -Wextra"

do_compile() {
    ${CC} ${CFLAGS} ${CPPFLAGS} $(pkg-config --cflags libgpiod) \
        ${S}/rt-toggle.c -o rt-toggle \
        ${LDFLAGS} $(pkg-config --libs libgpiod)
}

do_install() {
    install -Dm0755 rt-toggle ${D}${bindir}/rt-toggle
    install -Dm0755 ${S}/rt-capture ${D}${bindir}/rt-capture
    install -Dm0755 ${S}/rt-analyze ${D}${bindir}/rt-analyze
    install -Dm0755 ${S}/rt-compare ${D}${bindir}/rt-compare
    install -Dm0755 ${S}/rt-run ${D}${bindir}/rt-run
    install -Dm0755 ${S}/rt-irq-affinity ${D}${bindir}/rt-irq-affinity

    install -Dm0644 ${S}/rt.conf ${D}${sysconfdir}/bench/rt.conf
    install -Dm0644 ${S}/rt.tmpfiles.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/bench-rt.conf
}

FILES:${PN} += "\
    ${nonarch_libdir}/tmpfiles.d \
    ${sysconfdir}/bench \
"

CONFFILES:${PN} = "${sysconfdir}/bench/rt.conf"

# No systemd unit anywhere in this recipe, which is worth saying because
# every other bench recipe has one. These are laboratory instruments: they
# are started by hand, one configuration at a time, with a person watching.
# A timer that ran the matrix unattended would produce rows nobody could
# attach a thermal state or a jumper position to.

# rt-run reaches the board only through commands, which is what makes
# tests/rt-run-test.sh possible, and it is also why every one of them has
# to be named here. taskset missing at run time is not an error message,
# it is a run that quietly measured the wrong thing.
RDEPENDS:${PN} += "\
    libgpiod \
    util-linux-taskset \
    python3-core \
    python3-numpy \
    python3-daqhats \
    rt-tests \
    stress-ng \
"

# vcgencmd is in the Raspberry Pi userland and reports the throttle state.
# It is a recommendation rather than a dependency: the scripts degrade to
# recording "unknown" for the throttle columns on a board that has no such
# tool, which is the right behaviour when the same lab is repeated on
# hardware that is not a Pi.
RRECOMMENDS:${PN} += "userland"
