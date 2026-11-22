CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror $(shell $(PKG_CONFIG) --cflags libgpiod)
LDLIBS += $(shell $(PKG_CONFIG) --libs libgpiod)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin

SCRIPTS := lte-watchdog lte-exporter

.PHONY: all clean install

all: lte-gpio

lte-gpio: lte-gpio.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

install: lte-gpio $(SCRIPTS)
	install -Dm0755 lte-gpio $(DESTDIR)$(BINDIR)/lte-gpio
	for s in $(SCRIPTS); do install -Dm0755 $$s $(DESTDIR)$(BINDIR)/$$s; done

clean:
	rm -f lte-gpio
