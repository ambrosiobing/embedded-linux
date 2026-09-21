SUMMARY = "OP-TEE keystore: a trusted application and its normal world"
DESCRIPTION = "Project 20. A trusted application that generates an HMAC \
key inside the secure world, keeps it in OP-TEE's secure storage and signs \
what the normal world hands it; a client library over the TEE Client API, \
a CLI, a Python binding whose canonical serialisation is shared with the \
verifier, a link-state LED daemon and a conformance check that runs once \
per boot."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://bench_keystore_ta.h \
    file://bench_keystore_ta.c \
    file://user_ta_header_defines.h \
    file://ta-Makefile \
    file://ta-sub.mk \
    file://benchkey.h \
    file://benchkey.c \
    file://benchkey-cli.c \
    file://benchkey.py \
    file://benchkey-verify \
    file://benchkey-leds \
    file://optee-selftest \
    file://benchkey-leds.service \
    file://optee-selftest.service \
    file://keystore.tmpfiles.conf \
"

# optee-os-tadevkit supplies the TA development kit, which is the
# compiler, the linker script, the signing step and the headers for the
# TEE Internal Core API. optee-client supplies libteec and its headers
# for the normal-world half.
DEPENDS = "optee-os-tadevkit optee-client"

inherit systemd useradd features_check python3-dir

REQUIRED_DISTRO_FEATURES = "systemd"

# scarthgap still unpacks into WORKDIR. On walnascar and later this
# becomes S = "${UNPACKDIR}", the same line every other bench recipe
# moves.
S = "${WORKDIR}"

# The TA is built by the dev kit's own makefile, which expects a
# directory of its own with a Makefile and a sub.mk in it. The files
# unpack flat, so do_configure arranges them.
#
# The alternative is a subdir= parameter on each SRC_URI entry, which
# BitBake supports. scripts/lint.py reads a URI up to whitespace, so it
# would take the parameter as part of the file name and report the file
# as missing. Teaching it about URI parameters is a change to a tool the
# whole repository depends on, to save five lines here; that trade is
# worth making when a second recipe needs it and not before.
#
# Writing that paragraph with the URI spelled out in it made the linter
# report the example as a missing file, which is a fair complaint about
# a checker that reads comments and a fair warning about writing
# configuration syntax into prose.
TA_UUID = "7b53ed98-cbfb-42ec-92b6-fe56e7682c5c"
TA_BUILD = "${S}/ta"

do_configure() {
    install -d ${TA_BUILD}
    install -m 0644 ${S}/bench_keystore_ta.c ${TA_BUILD}/
    install -m 0644 ${S}/bench_keystore_ta.h ${TA_BUILD}/
    install -m 0644 ${S}/user_ta_header_defines.h ${TA_BUILD}/
    install -m 0644 ${S}/ta-Makefile ${TA_BUILD}/Makefile
    install -m 0644 ${S}/ta-sub.mk ${TA_BUILD}/sub.mk
}

# --sysroot IN CFLAGS, WHICH LOOKS REDUNDANT AND IS NOT.
#
# ${CC} already carries --sysroot, and every normal-world compile below
# uses ${CC}, so this line changes nothing for them: the value is the same
# path twice. It exists for the trusted application, which never sees
# ${CC} at all.
#
# The TA dev kit's mk/gcc.mk builds its own compiler variable from
# CROSS_COMPILE and then destroys the inherited one on purpose:
#
#     CC$(sm)     := $(CROSS_COMPILE_$(sm))gcc
#     CC          := false    # "to discover accidental use"
#     libgcc$(sm) := $(shell $(CC$(sm)) $(CFLAGS$(arch-bits-$(sm))) \
#                            -print-libgcc-file-name)
#
# so libgcc is located by a bare aarch64-poky-linux-gcc plus CFLAGS64,
# and mk/ta_dev_kit.mk line 37 defines CFLAGS64 ?= $(CFLAGS), which
# oe_runmake takes from this recipe's environment. Without --sysroot
# there, the compiler answers the question with the two words "libgcc.a"
# and the link fails with:
#
#     aarch64-poky-linux-ld.bfd: cannot find libgcc.a
#
# Measured on Monday 21 September 2026 rather than reasoned about. With
# --sysroot the same compiler answers with an absolute path; the tune
# flags make no difference either way, which is worth recording because
# meta-arm passes LIBGCC_LOCATE_CFLAGS='${HOST_CC_ARCH}${TOOLCHAIN_OPTIONS}'
# and that variable is read only by mk/clang.mk. Passing it here would
# have looked like the fix and done nothing, since optee.inc pins
# TOOLCHAIN = "gcc".
#
# This is the same single line meta-arm's optee.inc uses for the same
# reason. That file is not required here because the rest of it is about
# building optee-os, not a TA against its dev kit.
CFLAGS += "--sysroot=${STAGING_DIR_HOST}"

# TA_DEV_KIT_DIR comes from meta-arm's optee.inc as
# ${STAGING_INCDIR}/optee/export-user_ta, which is where
# optee-os-tadevkit installs it. It is set there but deliberately not
# added to EXTRA_OEMAKE, because doing so breaks the optee-os build
# itself, so it is passed here by hand.
#
# TEEC_EXPORT is the other half: the normal-world compile needs
# tee_client_api.h and libteec, and optee.inc points it at the sysroot.
# Neither of those variables reaches this recipe on its own.
do_compile() {
    oe_runmake -C ${TA_BUILD} \
        TA_DEV_KIT_DIR="${STAGING_INCDIR}/optee/export-user_ta" \
        CROSS_COMPILE="${HOST_PREFIX}" \
        O="${TA_BUILD}/out"

    # The library, then the CLI against it. -fPIC and a soname because
    # the Python binding loads it by name through ctypes and a versioned
    # library is what makes that name stable.
    ${CC} ${CFLAGS} ${CPPFLAGS} -fPIC -I${S} -c ${S}/benchkey.c \
        -o ${S}/benchkey.o
    ${CC} -shared -Wl,-soname,libbenchkey.so.1 ${LDFLAGS} \
        ${S}/benchkey.o -lteec -o ${S}/libbenchkey.so.1

    ${CC} ${CFLAGS} ${CPPFLAGS} -I${S} ${S}/benchkey-cli.c \
        -o ${S}/benchkey ${LDFLAGS} -L${S} -lbenchkey -lteec
}

do_install() {
    # The TA, named by its UUID because that is the name OP-TEE looks
    # for. /lib/optee_armtz is where tee-supplicant searches, and it is
    # a path in the supplicant rather than a convention this recipe may
    # choose.
    install -d ${D}${nonarch_base_libdir}/optee_armtz
    install -m 0444 ${TA_BUILD}/out/${TA_UUID}.ta \
        ${D}${nonarch_base_libdir}/optee_armtz/${TA_UUID}.ta

    install -d ${D}${libdir}
    install -m 0755 ${S}/libbenchkey.so.1 ${D}${libdir}/
    ln -sf libbenchkey.so.1 ${D}${libdir}/libbenchkey.so

    install -d ${D}${includedir}
    install -m 0644 ${S}/benchkey.h ${D}${includedir}/
    install -m 0644 ${S}/bench_keystore_ta.h ${D}${includedir}/

    install -Dm0755 ${S}/benchkey ${D}${bindir}/benchkey
    install -Dm0755 ${S}/benchkey-verify ${D}${bindir}/benchkey-verify
    install -Dm0755 ${S}/benchkey-leds ${D}${bindir}/benchkey-leds
    install -Dm0755 ${S}/optee-selftest ${D}${bindir}/optee-selftest

    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    install -m 0644 ${S}/benchkey.py ${D}${PYTHON_SITEPACKAGES_DIR}/

    install -Dm0644 ${S}/keystore.tmpfiles.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/bench-keystore.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/benchkey-leds.service \
        ${D}${systemd_system_unitdir}/
    install -m 0644 ${S}/optee-selftest.service \
        ${D}${systemd_system_unitdir}/

    # Instantiate the supplicant.
    #
    # meta-arm ships tee-supplicant@.service, a template, and sets
    # SYSTEMD_SERVICE to it. A template unit has no DefaultInstance here,
    # so nothing decides which instance to start and the answer at boot
    # is none. The symptom is the first pitfall in this project's notes:
    # TEEC_OpenSession fails with an error that names neither the
    # supplicant nor the file it could not read.
    #
    # This symlink is what "systemctl enable tee-supplicant@0" would
    # write. It is owned by this package rather than by optee-client
    # because it is this project that decided an instance should exist;
    # an image that wants the supplicant started some other way removes
    # this package and keeps optee-client.
    install -d ${D}${systemd_system_unitdir}/multi-user.target.wants
    ln -sf ../tee-supplicant@.service \
        ${D}${systemd_system_unitdir}/multi-user.target.wants/tee-supplicant@0.service
}

# The .ta is a signed binary for the secure world, not a normal-world
# executable, so the usual QA checks do not apply to it: it is not linked
# against the host libc, it has no RPATH and its architecture is checked
# by OP-TEE at load time rather than by the package manager.
INSANE_SKIP:${PN} += "arch libdir"

# The dev kit embeds its own build path in the TA, which OE's prefix maps
# do not cover. meta-arm's own optee-os-tadevkit recipe carries the same
# skip for the same reason, which is the tell that this is upstream
# behaviour rather than something this recipe caused.
INSANE_SKIP:${PN} += "buildpaths"

FILES:${PN} += "\
    ${nonarch_base_libdir}/optee_armtz \
    ${nonarch_libdir}/tmpfiles.d \
    ${systemd_system_unitdir} \
    ${PYTHON_SITEPACKAGES_DIR} \
    ${libdir}/libbenchkey.so.1 \
"
FILES:${PN}-dev = "${includedir} ${libdir}/libbenchkey.so"

# The LED daemon's user, and the group the GPIO character devices belong
# to. The gpio group is created by bench-stwin in Project 17; creating it
# in two recipes is not an error, useradd-staticids resolves it to one
# group, but the second recipe must agree about the name.
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-r gpio"
USERADD_PARAM:${PN} = "--system --no-create-home --groups gpio \
    --home-dir /var/lib/bench --shell /bin/false --user-group benchkey"

RDEPENDS:${PN} += "\
    optee-client \
    python3-core \
    python3-ctypes \
    python3-json \
    python3-gpiod \
"

# xtest is a recommendation, not a dependency. optee-selftest degrades to
# checking that a session opens when it is absent, and says so, which is
# the right behaviour for an image built deliberately without the
# conformance suite.
RRECOMMENDS:${PN} += "optee-test"

# Both units are enabled. Unlike the sensor hub of Project 12 there is no
# device to wait for and no socket to be activated by: the LEDs should
# come up with the board, and the conformance check has to run before
# anybody trusts a result from this image.
SYSTEMD_SERVICE:${PN} = "benchkey-leds.service optee-selftest.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
