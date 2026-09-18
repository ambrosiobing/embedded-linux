SUMMARY = "Four deliberate kernel faults behind one debugfs trigger"
DESCRIPTION = "An out-of-tree kernel module that misbehaves on request: a \
NULL dereference, a spinlock held with interrupts off, a use after free and \
a leak. It is the subject of Project 9, whose point is that only the first \
of those four announces itself, so the tool that finds each of the other \
three has to be in place before the fault rather than after it."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;\
md5=801f80980d171dd6425610833a22dbe6"

# The first recipe in this layer that builds a kernel module rather than
# userspace, and it behaves differently from its neighbours in three ways
# that are each worth a line.
#
# ONE. The package is not named after the recipe. module.bbclass inherits
# kernel-module-split.bbclass, which names the package after the .ko with
# a "kernel-module-" prefix, so this recipe produces kernel-module-buggy.
# An image with IMAGE_INSTALL += "bench-buggy" gets nothing, and BitBake
# does not consider that an error: the recipe built, and nothing asked
# for its output. See bench-debug-image.bb, which installs the right one.
#
# TWO. There is no do_compile here. module.bbclass provides one, and it
# runs oe_runmake with NO target, so files/Makefile has to answer to its
# default rule. That file says the same thing at greater length.
#
# THREE. The module is not auto-loaded. KERNEL_MODULE_AUTOLOAD is
# deliberately not set: this module exists to break the kernel, and a
# fault injector that loads itself on every boot is one typo away from a
# board that panics before the console is up. It is loaded by hand, from
# a notebook entry that says why.
inherit module

SRC_URI = "\
    file://Makefile \
    file://buggy.c \
"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}"; it is the only line in the layer that has to move.
S = "${WORKDIR}"

# So that an image or another recipe can depend on the capability by a
# name that does not change if the .ko is ever renamed, and so the name
# appears in "bitbake -e" next to the real package rather than only in
# the kernel-module-split output.
RPROVIDES:${PN} += "kernel-module-buggy"

# The module is useless without somewhere to put its trigger file, and
# debugfs not being mounted is a plausible state on an image that did not
# come from this project. Nothing here can enforce that, so it is said in
# the module's own load message and in the bring-up notes rather than
# pretended about in a dependency.
#
# What CAN be stated is the kernel side: debug.cfg sets CONFIG_DEBUG_FS,
# and ./go kconfig checks it against the built kernel.
