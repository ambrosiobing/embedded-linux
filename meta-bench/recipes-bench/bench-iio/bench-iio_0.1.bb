SUMMARY = "IIO bring-up, rate comparison and libiio client for Project 10"
DESCRIPTION = "Four tools for the X-NUCLEO-IKS4A1: an honest sensor \
inventory, software trigger management through configfs, the three-path \
rate comparison, a scan decoder that reads the layout the kernel declares, \
and a libiio client whose only difference between local and remote is the \
context URI."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux-bench"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://iio-probe \
    file://iio-trigger \
    file://iio-rate \
    file://iio-decode \
    file://iio-stream.c \
    file://ahrs.py \
"

S = "${WORKDIR}"

# libiio, for the C client. The version matters and is pinned by whatever
# meta-oe ships for this release: libiio 1.0 replaced buffers with blocks
# and iio_buffer_refill no longer exists, so iio-stream.c is 0.x code and
# says so in its own comments. A build against 1.0 fails at compile time,
# which is the right place for it to fail.
DEPENDS = "libiio"

do_compile() {
    # pkg-config rather than -liio, because libiio's dependencies differ
    # between builds: a libiio with the network backend pulls in libxml2
    # and avahi, and one without does not. Naming the library by hand
    # works on the machine it was tried on.
    ${CC} ${CFLAGS} ${LDFLAGS} \
        -o ${B}/iio-stream ${S}/iio-stream.c \
        `pkg-config --cflags --libs libiio`
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/iio-probe ${D}${bindir}/iio-probe
    install -m 0755 ${S}/iio-trigger ${D}${bindir}/iio-trigger
    install -m 0755 ${S}/iio-rate ${D}${bindir}/iio-rate
    install -m 0755 ${S}/iio-decode ${D}${bindir}/iio-decode
    install -m 0755 ${B}/iio-stream ${D}${bindir}/iio-stream

    # Installed without its .py, because it is a program here rather than a
    # module to import. Its own selftest is reachable on the board as
    # "ahrs --selftest", which is the check that the filter's sign
    # conventions survived being packaged.
    install -m 0755 ${S}/ahrs.py ${D}${bindir}/ahrs
}

# What each tool actually needs at run time, named rather than assumed.
#
# i2c-tools is for iio-probe's i2cdetect, and it is the one that would be
# missed: the inventory is the first thing run on the board, and without
# it every row would read "absent" and point at the wiring.
#
# kmod supplies modinfo, which is how iio-probe distinguishes a module
# that is installed from one that is missing, which is the distinction
# Project 8 paid a flash and a boot to learn.
#
# python3-core is for iio-decode. Only the core: it uses struct, re, argparse
# and pathlib, all of which are in it, and pulling python3 whole would add
# tens of megabytes for nothing.
RDEPENDS:${PN} = "\
    libiio \
    i2c-tools \
    kmod \
    python3-core \
"
