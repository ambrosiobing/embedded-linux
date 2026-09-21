# Project 19 supplies the target's system.conf and its verification
# certificate.
#
# rauc-conf.bb in meta-rauc ships an example system.conf and an example
# ca.cert.pem, and warns rather than fails when neither has been replaced.
# A warning in a BitBake log is not a guard: the build succeeds, the image
# boots, RAUC starts, and the device trusts a certificate whose private
# half is published on the internet. So this file replaces the first and
# refuses to build without the second.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# THE PRIVATE KEY IS NOT IN THIS REPOSITORY AND MUST NOT BE. What the
# image needs is the public certificate, and what signs a bundle is the key
# that stays on the build laptop. Neither is committed: the certificate is
# small and harmless but shipping one in the layer would mean every build
# of this project anywhere trusted the same bench CA, which is the habit
# rather than the file that causes trouble.
#
# Set this to an absolute path on the build machine, in local.conf or in
# the kas file's local_conf_header. docs/BRINGUP.md carries the openssl
# commands that produce the pair.
BENCH_RAUC_CA ??= ""

RAUC_KEYRING_FILE = "ca.cert.pem"

# Written as a plain variable reference rather than as inline python, and
# that is a lint decision as much as a style one. scripts/lint.py reads
# fetch URIs with a regex and skips any name that begins with ${, so this
# form is understood exactly. The inline python this replaced put a quote
# character straight after the scheme, and the linter dutifully reported a
# missing file whose name was a single apostrophe.
#
# The same regex reads prose. Writing the scheme in a comment with a comma
# after it makes the linter report a missing file named ",", which is how
# the first draft of this very comment failed. Mention the scheme in
# running text only with a space after it, or not at all.
RAUC_KEYRING_URI = "file://${BENCH_RAUC_CA}"

# Named so that scripts/lint.py can see that the system.conf in files/ is
# deliberate. It shadows the example of the same name in meta-rauc rather
# than adding to it; see the same note in the rpi-u-boot-scr bbappend.
SRC_URI += "file://system.conf"

# The refusal names what it wanted and where to put it, because a guard
# that only says no trains people to switch it off.
#
# IT HANGS OFF do_fetch RATHER THAN do_install, because by do_install the
# damage is already done: an empty BENCH_RAUC_CA makes the keyring URI the
# string "file://", and the fetcher fails first with a message about a file
# whose name is nothing, several hundred lines into a log. Checking before
# the fetch means the first error a reader sees is the one that explains
# itself.
#
# It is also not a __anonymous function, which would run while every recipe
# in the build is parsed and would stop builds that have nothing to do with
# RAUC.
python bench_check_rauc_ca() {
    if not d.getVar('BENCH_RAUC_CA'):
        bb.fatal("BENCH_RAUC_CA is empty, so this image would have no RAUC "
                 "keyring.\n"
                 "Set it to the absolute path of the bench CA certificate on "
                 "this build machine,\n"
                 "for example in kas/bench-rpi3-ab.yml:\n"
                 "    BENCH_RAUC_CA = \"/home/<user>/bench/keys/ca.cert.pem\"\n"
                 "The matching private key stays on that machine and is never "
                 "committed.\n"
                 "projects/19-rauc-ab/docs/BRINGUP.md has the openssl commands "
                 "that make the pair.")
}
do_fetch[prefuncs] += "bench_check_rauc_ca"

# The certificate path decides what gets installed, and bitbake cannot see
# that through a prefunc. Without this line a rebuild after pointing at a
# different CA would be served the old package out of sstate, and the
# device would go on trusting the previous certificate with nothing
# anywhere saying so.
do_install[vardeps] += "BENCH_RAUC_CA"

# Nothing here installs system.conf and nothing should: rauc-conf.bb in
# meta-rauc copies it to /etc/rauc, and this bbappend only changes which
# copy is found. scripts/lint.py asks that a recipe naming a file in its
# fetch list also mention it somewhere after the first build task, so that
# a file fetched and then forgotten cannot pass quietly. This sentence is
# that mention, and it is the honest version of it rather than a do_install
# line written to satisfy a check.
