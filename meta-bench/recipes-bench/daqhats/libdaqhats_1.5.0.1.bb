SUMMARY = "MCC DAQ HAT library: C library, headers and board tools"
DESCRIPTION = "The vendor library for the Measurement Computing DAQ HAT \
family. It reads the HAT ID EEPROM to find the board and its calibration, \
and drives the converter over spidev. Project 8 uses the MCC 118 as the \
external instrument that measures the real-time task from outside the \
system under test."
HOMEPAGE = "https://github.com/mccdaq/daqhats"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=14d452bb31a1ae3c2fb70163065ffbc8"

# Pinned to the commit behind tag v1.5.0.1, not to the tag and not to the
# branch. Same rule the kas file applies to every Yocto layer: a tag can be
# moved by whoever owns the repository, a branch moves by design, and this
# recipe is one of the two instruments the results table depends on.
SRC_URI = "git://github.com/mccdaq/daqhats.git;protocol=https;branch=master"
SRCREV = "dc66583068372d95c87261eec8c6f9c2fd3c78bd"

S = "${WORKDIR}/git"

DEPENDS = "libgpiod"

inherit pkgconfig

# The vendor makefile is written for a build on the Pi itself, so three of
# its assumptions have to be replaced rather than accepted:
#
#   CC = gcc                      the host compiler, not the cross one
#   -I/usr/include                host headers ahead of the sysroot, which
#                                 is the classic way a cross build picks up
#                                 the wrong struct layout and fails at run
#                                 time rather than at compile time
#   -I/opt/vc/include -L/opt/vc/lib   the 32-bit Broadcom userland, which
#                                 does not exist on a 64-bit image
#
# Overriding on the make command line beats the assignments inside the
# makefile, so none of this needs a patch against the vendor tree. That
# matters for maintenance: a patch has to be rebased at every version bump
# and these three lines do not.
#
# What is deliberately kept: -fPIC, -DENABLE_LOCALES=Off, the soname, and
# the makefile's own choice between gpio.c and gpio_v2.c, which it makes
# from pkg-config --modversion libgpiod. inherit pkgconfig points that at
# the target sysroot, so the image's libgpiod v2 selects the v2 source and
# the decision stays the vendor's rather than being second-guessed here.
DAQHATS_SONAME = "libdaqhats.so.1"

do_compile() {
    oe_runmake -C ${S}/lib \
        CC="${CC}" \
        CFLAGS="${CFLAGS} -I${S}/include -fPIC -DENABLE_LOCALES=Off" \
        LDFLAGS="${LDFLAGS} -shared -pthread -Wl,-z,defs \
            -Wl,-soname,${DAQHATS_SONAME}"

    # The tools are linked with -ldaqhats, and that makes the linker look
    # for a file named exactly libdaqhats.so. What the build produces is
    # libdaqhats.so.1.5.0.1; the unversioned name is created by the same
    # vendor install step as the headers below:
    #
    #     ln -frs $(INSTALL_DIR)/$(TARGET_LIB) $(INSTALL_DIR)/lib$(NAME).so
    #
    # so it is missing here for the same reason and is made the same way.
    ln -sf libdaqhats.so.${PV} ${S}/lib/build/libdaqhats.so

    # The tools include their headers with a directory prefix:
    #
    #     daqhats_list_boards.c:3:  #include <daqhats/daqhats.h>
    #
    # and the headers live flat in include/. That prefix only resolves
    # after the vendor's own "make install" has copied them into
    # /usr/local/include/daqhats, because natively you build the library,
    # install it, and then build the tools against what was installed. A
    # recipe installs nothing on the build host, so that directory never
    # exists and -I${S}/include cannot help: the compiler is looking for
    # a daqhats/ subdirectory, not for the files inside it.
    #
    # Staging the same shape costs two lines and leaves the vendor tree
    # untouched. The alternative, a patch rewriting eleven include lines
    # across the tools, would need rebasing at every version bump to fix
    # something that is not broken upstream.
    #
    # Under ${S} rather than ${WORKDIR}, and that is not arbitrary. The
    # first version staged into ${WORKDIR}/staged-include and the build
    # succeeded with a QA warning:
    #
    #   File /usr/bin/.debug/daqhats_list_boards in package libdaqhats-dbg
    #   contains reference to TMPDIR [buildpaths]
    #
    # OE rewrites build paths out of debug information with prefix maps for
    # ${S}, recipe-sysroot and recipe-sysroot-native. A directory under
    # WORKDIR but outside all three is covered by none of them, so the
    # compiler command line recorded in the debug info kept an absolute
    # path from this machine. That costs byte-for-byte reproducibility,
    # which Project 1 has a criterion for, and leaks the builder's paths
    # into a shipped package. Staging under ${S} puts it inside the map
    # that already exists.
    install -d ${S}/staged-include/daqhats
    install -m 0644 ${S}/include/*.h ${S}/staged-include/daqhats/

    # Only the named tools. The makefile's "all" also recurses into
    # tools/applications, which builds the vendor's example programs and
    # their GUI; an example that fails to cross-compile is not a reason
    # for an image not to build.
    oe_runmake -C ${S}/tools \
        CC="${CC}" \
        CFLAGS="${CFLAGS} -I${S}/staged-include -I${S}/include \
            -I${S}/lib" \
        OFLAGS="${LDFLAGS} -L${S}/lib/build -ldaqhats" \
        daqhats_list_boards mcc118_firmware_update
}

do_install() {
    install -d ${D}${libdir}
    install -m 0755 ${S}/lib/build/libdaqhats.so.${PV} ${D}${libdir}/
    ln -sf libdaqhats.so.${PV} ${D}${libdir}/${DAQHATS_SONAME}
    ln -sf ${DAQHATS_SONAME} ${D}${libdir}/libdaqhats.so

    install -d ${D}${includedir}/daqhats
    install -m 0644 ${S}/include/*.h ${D}${includedir}/daqhats/

    install -d ${D}${bindir}
    install -m 0755 ${S}/tools/daqhats_list_boards ${D}${bindir}/
    install -m 0755 ${S}/tools/mcc118_firmware_update ${D}${bindir}/
}

# Two vendor tools are deliberately not installed, and the reason is worth
# writing down because "the vendor ships it" is not a justification.
#
# daqhats_version reads /usr/local/lib/libdaqhats.so, a path that exists on
# Raspberry Pi OS after install.sh and on no Yocto image. It would report
# "daqhats is not installed" next to a working library, which is worse than
# absent.
#
# daqhats_read_eeproms caches the ID EEPROM of boards 1 to 7 into
# /etc/mcc/hats. It needs the dtoverlay tool and the at24 driver from
# Raspberry Pi OS, and this project has exactly one HAT at address 0.
# lib/util.c reads address 0 from /proc/device-tree/hat, which the firmware
# fills in at boot from the same EEPROM, so the cache has nothing to add.
# A second HAT would change that, and then the honest fix is a recipe for
# the tool with the paths corrected, not a copy of this comment.

# The tools are a separate package because the library is a dependency of
# the capture script and the tools are a dependency of nothing. An image
# that wants only the former should not carry a firmware updater.
PACKAGES =+ "${PN}-tools"
FILES:${PN}-tools = "${bindir}"
RDEPENDS:${PN}-tools += "${PN}"
