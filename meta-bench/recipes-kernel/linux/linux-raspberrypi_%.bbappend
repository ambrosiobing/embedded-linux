# Kernel changes travel as a configuration fragment. A copied .config would
# pin this layer to one kernel version and hide which options the bench
# actually needs; a fragment survives the next rebase and reads as a list of
# reasons.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://bench.cfg"

# The router fragment is opt in, because it is a large change that only one
# image wants: built-in USB modem drivers and a built-in netfilter stack
# belong in Project 15's image and have no business in the boot time and
# the kernel size that Project 3 measures.
#
# The assignment is single quoted so that the expression inside can use
# double quotes. That matters for more than taste: scripts/lint.py reads
# SRC_URI to check that every file:// entry exists and that every file in
# files/ is referenced, and it stops a URI at a double quote. Written the
# other way round the fragment would look to the linter like a file named
# router.cfg' that does not exist.
BENCH_ROUTER_KERNEL ?= "0"
SRC_URI += '${@"file://router.cfg" if d.getVar("BENCH_ROUTER_KERNEL") == "1" else ""}'
