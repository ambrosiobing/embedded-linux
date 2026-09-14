# Build with the SDK environment sourced:
#
#   . /opt/poky/5.0.x/environment-setup-cortexa72-poky-linux
#   make
#
# CC, CFLAGS, LDFLAGS and PKG_CONFIG_PATH all come from that script, which
# is the point: nothing here names a compiler or a sysroot.

CC      ?= cc
PKG_CONFIG ?= pkg-config

CFLAGS  += -Wall -Wextra -O2 $(shell $(PKG_CONFIG) --cflags libgpiod)
LDLIBS  += $(shell $(PKG_CONFIG) --libs libgpiod)

hello-gpiod: hello-gpiod.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

.PHONY: clean check
clean:
	rm -f hello-gpiod

# Refuse to ship a host binary by accident.
check: hello-gpiod
	@file hello-gpiod | grep -q aarch64 && echo "aarch64 binary: SDK is cross" || \
		{ echo "not an aarch64 binary; was the SDK environment sourced?"; exit 1; }
