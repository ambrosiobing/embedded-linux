SUMMARY = "RAUC update bundle for the A/B bench board"
DESCRIPTION = "One signed bundle containing one root filesystem. This is \
what an update is: a file that is verified before anything is written, \
written into whichever slot is not running, and then either confirmed by a \
health check or forgotten about by a boot counter."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit bundle

# THIS STRING IS COMPARED, NOT DISPLAYED, and it must be identical to the
# one in the system.conf beside this file, at
# ../rauc/files/system.conf. RAUC refuses a bundle whose compatible
# differs from the running system's, before it writes anything, which is
# the check that stops a Pi 4 image reaching this card.
#
# Nothing in the build compares these two strings. They are in different
# files, read by different programs, at different times, and the only
# report of a mismatch is a device in the field refusing every update it is
# offered. tests/ab-config-test.sh asserts they are equal, which is the
# cheapest place this can possibly be caught.
BENCH_AB_COMPATIBLE ?= "bench-rpi3"
RAUC_BUNDLE_COMPATIBLE = "${BENCH_AB_COMPATIBLE}"

# The indirection exists for one reason: acceptance criterion 7 needs a
# bundle carrying the WRONG string, so that the refusal can be shown rather
# than asserted. kas/bench-ab-bundle-wrong.yml overrides the variable and
# nothing else, which is what makes the resulting refusal attributable to
# the compatible check and not to some other difference between two builds.
#
# It is written with ?= so that overriding it is possible, and read through
# a second name so that the default stays greppable. A plain override of
# RAUC_BUNDLE_COMPATIBLE in local.conf would not work: the class reads it
# per recipe, and a recipe assignment with = wins over local.conf.

# A date and a commit rather than a semantic version. What a reader of
# "rauc status" needs to answer is which build is on the board, and this
# project has no release cadence for a number to track.
RAUC_BUNDLE_VERSION = "${@d.getVar('DATE')}-${@d.getVar('BENCH_BUNDLE_TAG') or 'dev'}"
RAUC_BUNDLE_VERSION[vardepsexclude] = "DATE"
BENCH_BUNDLE_TAG ??= ""

# verity, matching bundle-formats in system.conf. The payload is a
# dm-verity image and the signature covers its root hash, so the bundle can
# be verified as it is read rather than only once it is completely
# downloaded. The older plain format hashes the whole file, which makes a
# truncated transfer indistinguishable from a tampered one until the last
# byte lands.
RAUC_BUNDLE_FORMAT = "verity"

# ONE SLOT, AND THAT IS THE INTERESTING PART OF THIS FILE.
#
# The class supports separate kernel, dtb and bootloader slots, and the
# obvious reading of figure 1 is that this bundle needs a kernel slot too.
# It does not, because the kernel is inside the root filesystem:
# bench-ab-image.bb installs kernel-image-image, and boot.cmd.in ext4loads
# /boot/Image out of whichever slot it chose. Kernel and userspace are
# therefore replaced together, atomically, by one write, and can never be
# a mismatched pair.
#
# The device tree is genuinely absent rather than forgotten. It is on the
# shared FAT partition, loaded by the GPU firmware before any ARM core
# runs, and no bundle can reach it. That is the design's main limitation
# and it is stated in three places on purpose.
RAUC_BUNDLE_SLOTS = "rootfs"
RAUC_SLOT_rootfs = "bench-ab-image"
RAUC_SLOT_rootfs[fstype] = "ext4"

# THE PRIVATE KEY NEVER ENTERS THIS REPOSITORY. Both of these are absolute
# paths on the build machine, set in the kas file or local.conf, and the
# class reads them as paths rather than as names fetched into WORKDIR.
BENCH_RAUC_KEY ??= ""
BENCH_RAUC_CERT ??= ""
RAUC_KEY_FILE = "${BENCH_RAUC_KEY}"
RAUC_CERT_FILE = "${BENCH_RAUC_CERT}"

# ONE VARIABLE NAME, TWO MEANINGS, AND THIS IS THE TRAP IN THIS FILE.
#
# bundle.bbclass reads RAUC_KEYRING_FILE as a path on the build machine,
# and uses it to verify the bundle it has just signed. rauc-conf.bb reads a
# variable of the same name as a bare filename inside WORKDIR, and installs
# it to /etc/rauc on the target. The two are not interchangeable.
#
# Setting it once in local.conf, which is the natural thing to do because
# it looks like a global, breaks whichever of the two was not being thought
# about: an absolute path makes rauc-conf install a file whose name is a
# path, and a bare name makes this class look for a keyring in the build
# directory. Both are set per recipe here, and neither is set globally.
RAUC_KEYRING_FILE = "${BENCH_RAUC_CERT}"

# The refusal names what it wanted, and it runs before the work rather
# than after it. Signing is the last step of a long build, so a missing key
# discovered at signing time costs the whole build.
python bench_check_rauc_signing() {
    missing = [name for name in ('BENCH_RAUC_KEY', 'BENCH_RAUC_CERT')
               if not d.getVar(name)]
    if missing:
        bb.fatal("Cannot sign a bundle: %s not set.\n"
                 "These are absolute paths on this build machine. The private\n"
                 "key never leaves it and is never committed. Set them beside\n"
                 "BENCH_RAUC_CA in kas/bench-rpi3-ab.yml, for example:\n"
                 "    BENCH_RAUC_KEY  = \"/home/<user>/bench/keys/dev.key.pem\"\n"
                 "    BENCH_RAUC_CERT = \"/home/<user>/bench/keys/dev.cert.pem\"\n"
                 "projects/19-rauc-ab/docs/BRINGUP.md has the openssl commands."
                 % ", ".join(missing))
}
do_configure[prefuncs] += "bench_check_rauc_signing"

# The bundle is named for the board and the build, and the class appends a
# timestamp of its own. The link name is the stable path to hand to a
# person: it always points at the most recent bundle for this machine.
#
# THE NAME IS OVERRIDABLE BECAUSE THREE BUNDLES EXIST AND TWO ARE MEANT TO
# FAIL. The deliberately broken one and the wrong-compatible one land in
# the same deploy directory as the good one, and a set of files
# distinguished only by timestamp is a set nobody can tell apart on a
# board. Each variant names itself, so the filename says which failure is
# being demonstrated and a log quoting it is self-explaining.
BENCH_AB_BUNDLE_NAME ?= "bench-ab"
BUNDLE_BASENAME = "${BENCH_AB_BUNDLE_NAME}"
