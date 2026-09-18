# Kbuild for the out-of-tree faulty module.
#
# Shaped exactly like oe-core's meta-skeleton hello-mod Makefile, and
# that is deliberate rather than lazy. module.bbclass in scarthgap does
# NOT set MAKE_TARGETS, so module_do_compile runs oe_runmake with no
# target at all and gets whatever this file's first target is. Rename
# "all" to something else and the build fails with a make error about a
# missing target, which reads like a broken recipe rather than a renamed
# rule.
#
# KERNEL_SRC comes from module.bbclass:
#
#     EXTRA_OEMAKE += "KERNEL_SRC=${STAGING_KERNEL_DIR}"
#
# so it is set for a BitBake build and unset for a hand build. To build
# this by hand on the build laptop against a kernel tree:
#
#     make KERNEL_SRC=/lib/modules/$(uname -r)/build

obj-m := buggy.o

SRC := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC)

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC) modules_install

clean:
	rm -f *.o *~ core .depend .*.cmd *.ko *.mod *.mod.c
	rm -f Module.markers Module.symvers modules.order
	rm -rf .tmp_versions Modules.symvers
