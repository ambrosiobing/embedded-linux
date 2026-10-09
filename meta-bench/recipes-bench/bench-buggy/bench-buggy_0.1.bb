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

# This line is what gets the recipe scheduled, not a convenience, and the
# earlier version of this comment said otherwise. kernel-module-buggy
# exists only after do_package runs the module split, so at parse time no
# recipe declares it and BitBake falls back to PACKAGES_DYNAMIC patterns.
# The kernel declares the same kernel-module-.* pattern as this recipe and
# is the preferred provider of virtual/kernel, so without an exact
# RPROVIDES the name resolves to the kernel, this recipe is never built,
# and the image fails at do_rootfs. Project 5's bench-adxl345 lacked the
# line and did exactly that on Friday 9 October 2026; the comment there
# has the full mechanism. scripts/lint.py check_module_rprovides now
# requires the line in every module recipe.
RPROVIDES:${PN} += "kernel-module-buggy"

# The module is useless without somewhere to put its trigger file, and
# debugfs not being mounted is a plausible state on an image that did not
# come from this project. Nothing here can enforce that, so it is said in
# the module's own load message and in the bring-up notes rather than
# pretended about in a dependency.
#
# What CAN be stated is the kernel side: debug.cfg sets CONFIG_DEBUG_FS,
# and ./go kconfig checks it against the built kernel.
