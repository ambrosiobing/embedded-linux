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

# The real-time fragment is opt in for the same reason and with the same
# mechanism. It is a larger change than the router one: PREEMPT_RT replaces
# the locking primitives of the whole kernel, so every other image in this
# repository would stop being comparable to stock the moment it was on by
# default. Project 8 needs exactly one variable to differ between its two
# rows, and this is that variable.
#
# Turning it on is not sufficient by itself. PREEMPT_RT depends on
# ARCH_SUPPORTS_RT, which arm64 gained in 6.12, and the BSP default on
# scarthgap is 6.6. kas/bench-rt.yml therefore sets both this switch and
# PREFERRED_VERSION_linux-raspberrypi; setting only this one produces a
# kernel that builds, boots, and is not preemptible.
BENCH_RT_KERNEL ?= "0"
SRC_URI += '${@"file://rt.cfg" if d.getVar("BENCH_RT_KERNEL") == "1" else ""}'

# And the Bluetooth fragment, on the same switch pattern. Project 17 runs a
# BLE gateway on a Raspberry Pi 3B+, where the radio is on a UART rather
# than on USB, so the transport has to be built into the kernel. The cost
# is a larger image for anything that does not use a radio, which is why it
# is not in bench.cfg.
BENCH_BLE_KERNEL ?= "0"
SRC_URI += '${@"file://ble.cfg" if d.getVar("BENCH_BLE_KERNEL") == "1" else ""}'

# And the netboot fragment, same pattern again. Project 4's device under
# test has no SD card at all and mounts its root over NFS, which needs the
# NFS client, kernel IP autoconfiguration and the Ethernet driver all built
# in rather than modular. None of that belongs in an image that boots from
# a card: it is kernel size for a capability nothing else uses, and Project
# 3 measures both.
BENCH_NETBOOT_KERNEL ?= "0"
SRC_URI += '${@"file://netboot.cfg" if d.getVar("BENCH_NETBOOT_KERNEL") == "1" else ""}'
