SUMMARY = "bench-tee-image with the OP-TEE driver as a loadable module"
DESCRIPTION = "The Project 20 image, identical to bench-tee-image except \
that the OP-TEE driver is a module rather than built in, and the module \
package is installed. It exists so that a driver which hangs at probe can \
be debugged from a board that finished booting."

require recipes-core/images/bench-tee-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    kernel-module-optee \
"

# kernel-module-optee is the package the kernel recipe produces for
# drivers/tee/optee/optee.ko once tee-modular.cfg has set CONFIG_OPTEE=m.
# Naming it here is not optional and not obvious: core-image-minimal
# installs no kernel modules at all, so without this line the build
# succeeds, the card boots, and "modprobe optee" says the module cannot
# be found. Project 1 lost two rounds to exactly that shape of mistake and
# scripts/lint.py has checked for it ever since.
#
# CONFIG_TEE stays =y, so the tee subsystem and /dev/tee0's class are in
# the kernel proper. There is no module package for the subsystem itself
# and none is wanted; only the OP-TEE backend moves.

# WHY THIS IMAGE EXISTS, and when it should stop existing.
#
# On Tuesday 22 September 2026 four boots narrowed a hang to the OP-TEE
# driver's own calls into the secure world, during optee_bus_scan, which
# runs once at probe. With the driver built in, the board dies while the
# kernel is still probing drivers: no shell, no login, and on a single-CPU
# boot not even a stall report, because the CPU that hangs is the only one
# there is to print with. Journal entries 20, 21 and 23 have the evidence.
#
# This image moves the failure to a moment of our choosing. It boots with
# TF-A and OP-TEE resident underneath it and the driver unloaded, reaches
# a login prompt, and then does whatever it does when somebody types
# modprobe, with dmesg, /proc and a console still available.
#
# Booting it requires modprobe.blacklist=optee on the kernel command line.
# Without that, udev matches the driver's OF table against /firmware/optee
# and autoloads it during boot, which reproduces the failure this image
# exists to escape. docs/BRINGUP.md says where the command line lives.
#
# When the hang is understood and fixed, this image and its fragment have
# no reason to survive. Delete both rather than leaving a second way to
# build Project 20 that nobody remembers the purpose of.
