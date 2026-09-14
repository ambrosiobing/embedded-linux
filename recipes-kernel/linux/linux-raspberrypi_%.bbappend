# Kernel changes travel as a configuration fragment. A copied .config would
# pin this layer to one kernel version and hide which options the bench
# actually needs; a fragment survives the next rebase and reads as a list of
# reasons.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://bench.cfg"
