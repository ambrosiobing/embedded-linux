CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror $(shell $(PKG_CONFIG) --cflags libdrm)
LDLIBS += $(shell $(PKG_CONFIG) --libs libdrm)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin

.PHONY: all clean install

all: drmfill

drmfill: drmfill.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

install: drmfill lcd35a-corners lcd35a-verify
	install -Dm0755 drmfill $(DESTDIR)$(BINDIR)/drmfill
	install -Dm0755 lcd35a-corners $(DESTDIR)$(BINDIR)/lcd35a-corners
	install -Dm0755 lcd35a-verify $(DESTDIR)$(BINDIR)/lcd35a-verify

clean:
	rm -f drmfill
