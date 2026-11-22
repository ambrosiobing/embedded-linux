CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror -I. $(shell $(PKG_CONFIG) --cflags libevdev)
LDLIBS += $(shell $(PKG_CONFIG) --libs libevdev)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share

.PHONY: all clean install

all: kbd-bridge

kbd-bridge: kbd_bridge.c usage_table.h
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

install: kbd-bridge gen-usage-table.py
	install -Dm0755 kbd-bridge $(DESTDIR)$(BINDIR)/kbd-bridge
	install -Dm0755 gen-usage-table.py $(DESTDIR)$(DATADIR)/bench-kbd-bridge/gen-usage-table.py

clean:
	rm -f kbd-bridge
