CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror $(shell $(PKG_CONFIG) --cflags libgpiod)
LDLIBS += $(shell $(PKG_CONFIG) --libs libgpiod)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin

.PHONY: all clean install

all: tracker-gpio

tracker-gpio: tracker-gpio.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

install: tracker-gpio tracker
	install -Dm0755 tracker-gpio $(DESTDIR)$(BINDIR)/tracker-gpio
	install -Dm0755 tracker $(DESTDIR)$(BINDIR)/tracker

clean:
	rm -f tracker-gpio
