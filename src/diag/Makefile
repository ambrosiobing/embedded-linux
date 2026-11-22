CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror $(shell $(PKG_CONFIG) --cflags libgpiod)
LDLIBS += $(shell $(PKG_CONFIG) --libs libgpiod)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin

.PHONY: all clean install

all: bench-diag

bench-diag: bench-diag.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

install: bench-diag
	install -Dm0755 bench-diag $(DESTDIR)$(BINDIR)/bench-diag

clean:
	rm -f bench-diag
