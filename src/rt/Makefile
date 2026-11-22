CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror $(shell $(PKG_CONFIG) --cflags libgpiod)
LDLIBS += $(shell $(PKG_CONFIG) --libs libgpiod)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin

SCRIPTS := rt-capture rt-analyze rt-compare rt-run rt-irq-affinity

.PHONY: all clean install

all: rt-toggle

rt-toggle: rt-toggle.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

install: rt-toggle $(SCRIPTS)
	install -Dm0755 rt-toggle $(DESTDIR)$(BINDIR)/rt-toggle
	for s in $(SCRIPTS); do install -Dm0755 $$s $(DESTDIR)$(BINDIR)/$$s; done

clean:
	rm -f rt-toggle
