CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror $(shell $(PKG_CONFIG) --cflags libgpiod)
LDLIBS += $(shell $(PKG_CONFIG) --libs libgpiod)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin

.PHONY: all clean install

all: bench-status

bench-status: bench-status.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

install: bench-status bench-state
	install -Dm0755 bench-status $(DESTDIR)$(BINDIR)/bench-status
	install -Dm0755 bench-state $(DESTDIR)$(BINDIR)/bench-state

clean:
	rm -f bench-status
