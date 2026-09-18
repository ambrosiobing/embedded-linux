# SPDX-License-Identifier: GPL-2.0-only
#
# Kbuild for the bench ADXL345 driver.
#
# Three modules rather than one, which is the packaging consequence of the
# seam: the core is shared and each bus file is loadable on its own, so a
# board with only I2C never loads the SPI half. The core exports its probe
# in the BENCH_ADXL345 namespace and each bus module imports it, so
# loading a bus module without the core is a modprobe error rather than an
# unresolved symbol at insert time.
#
# KDIR and the module install path come from Yocto's module.bbclass, which
# sets both. The defaults below are for building by hand against a running
# kernel, which is how this is tested on a workstation before it is
# committed to a three hour image build.

obj-m += bench-adxl345-core.o
obj-m += bench-adxl345-i2c.o
obj-m += bench-adxl345-spi.o

SRC := $(shell pwd)
KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(SRC) modules

modules_install:
	$(MAKE) -C $(KDIR) M=$(SRC) modules_install

clean:
	$(MAKE) -C $(KDIR) M=$(SRC) clean

.PHONY: all modules_install clean
