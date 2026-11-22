CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra -Werror -I. $(shell $(PKG_CONFIG) --cflags libsystemd libcbor)
LDLIBS += $(shell $(PKG_CONFIG) --libs libsystemd libcbor)

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin

.PHONY: all clean install

all: sensorhubd

sensorhubd: sensorhubd.c proto.c proto.h
	$(CC) $(CFLAGS) $(CPPFLAGS) sensorhubd.c proto.c -o $@ $(LDFLAGS) $(LDLIBS)

install: sensorhubd hubctl
	install -Dm0755 sensorhubd $(DESTDIR)$(BINDIR)/sensorhubd
	install -Dm0755 hubctl $(DESTDIR)$(BINDIR)/hubctl

clean:
	rm -f sensorhubd
