# Project 19 replaces the boot script, and only for Project 19.
#
# THE GUARD IS THE POINT OF THIS FILE. rpi-u-boot-scr builds the boot.scr
# that every Raspberry Pi image in this repository boots from, and a
# bbappend that prepended its files directory unconditionally would hand
# the A/B script to Projects 1, 3, 5, 6, 7, 8, 17 and 20 as well. Those
# images have one root partition and no uboot.env counters, so the script
# would choose slot A, decrement a counter nothing ever resets, and
# ext4load a kernel from a path their rootfs does not have. Three boots
# later every one of them would be reading the "no slot has attempts left"
# message.
#
# That is precisely the failure class this project is about: one resource,
# two owners, and no mechanism to notice. It would have been introduced by
# the project whose design document contains the ownership table.
#
# THIS_DIR IS READ THROUGH d.getVar RATHER THAN WRITTEN AS ${THISDIR}. An
# inline python expression is expanded once and its result is not expanded
# again, so "${THISDIR}/files:" returned from python would reach
# FILESEXTRAPATHS as those characters rather than as a path, the override
# would silently do nothing, and the stock script would be used with no
# error anywhere. Asking bitbake for the value inside the expression keeps
# it a path.
FILESEXTRAPATHS:prepend := "${@d.getVar('THISDIR') + '/files:' if d.getVar('BENCH_AB_BOOTSCRIPT') == '1' else ''}"

# Set to "1" by kas/bench-rpi3-ab.yml and by nothing else. Default off, so
# a stray build of any other image in this layer gets the BSP's script.
BENCH_AB_BOOTSCRIPT ?= "0"

# The file is named here as well, and it is worth saying why, because the
# override above is what actually selects it and this line changes nothing
# about which file is used.
#
# scripts/lint.py checks that every file in a recipe's files/ directory is
# referenced from that recipe, because a file sitting in files/ and named
# by nobody is the shape of a fetch that was removed and a file that was
# forgotten. A bbappend that replaces an upstream file by shadowing it is
# the one legitimate case where that is not true, and the honest fix is to
# say out loud that this bbappend ships a boot.cmd.in, rather than to
# widen a rule that has caught real mistakes.
#
# The single quotes around the assignment are not style. The linter reads
# SRC_URI with a regex that stops a URI at a double quote, so written the
# other way round the entry would look to it like a file named
# boot.cmd.in' that does not exist. The same trap is documented at length
# in the kernel bbappend.
SRC_URI += '${@"file://boot.cmd.in" if d.getVar("BENCH_AB_BOOTSCRIPT") == "1" else ""}'

# The upstream recipe does not put the switch in the task signature, so
# bitbake would happily reuse a boot.scr built with the other setting from
# sstate. The two scripts are entirely different files and the difference
# is invisible until a board boots, which is the most expensive place in
# this project to discover anything.
do_compile[vardeps] += "BENCH_AB_BOOTSCRIPT"
