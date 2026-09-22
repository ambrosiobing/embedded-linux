/* SPDX-License-Identifier: MIT
 *
 * kbd-bridge: the physical keyboard on a USB-A port, replayed to the
 * host through the USB-C gadget as boot-protocol HID.
 *
 * The Pi sits between a keyboard and a PC. Everything typed on the
 * keyboard reaches the host, and a macro written to a FIFO is typed as
 * if it had come from the keyboard. That is how KVM-over-IP boxes and
 * hardware password managers work, and it is about 300 lines.
 *
 * FOUR THINGS ARE NOT OBVIOUS AND ARE THE REASON THIS FILE HAS COMMENTS
 *
 * 1. THE DAEMON NEVER SENDS A RELEASE. Boot-protocol HID has no press or
 *    release event: it carries STATE, eight bytes of it, and the host
 *    computes presses and releases by comparing consecutive reports. So
 *    the whole report goes out on every change, and a dropped report is
 *    a stuck key rather than a missed character.
 *
 * 2. GRABBING IS NOT OPTIONAL AND IT HAS A COST. EVIOCGRAB takes the
 *    keyboard away from everything else on the Pi, including its own
 *    console. Without the grab every keystroke would go to both the Pi
 *    and the host. With it, the USB/TTL serial console is the only way
 *    to type on the Pi, which is why that cable is in the parts list.
 *
 * 3. WRITING TO hidg0 FAILS NORMALLY. Until the host has issued
 *    SET_CONFIGURATION the endpoint is not live and write() returns
 *    ESHUTDOWN or EAGAIN. Unplugging the cable is an ordinary event, not
 *    a crash, so those two are counted and ignored rather than fatal.
 *
 * 4. AUTOREPEAT IS THE HOST'S JOB. evdev sends value 2 for repeats; the
 *    host generates its own from the held state. Forwarding them would
 *    produce two repeat rates fighting each other.
 */

/*
 * _DEFAULT_SOURCE before any include, and it is not decoration.
 *
 * usleep(3) and mkfifo(3) are POSIX, not ISO C, so under a strict
 * -std=c99 glibc does not declare them. The compiler then treats them as
 * implicitly declared functions returning int, which on a 64-bit target
 * is a real bug rather than a style warning, and with -Werror it is a
 * build failure whose message names the function and not the cause.
 *
 * Project 8 lost time to the same shape: _POSIX_C_SOURCE did not declare
 * cpu_set_t, and the fix was the feature test macro rather than the
 * code. Set here rather than in the build file so that the file compiles
 * the same way wherever it is built.
 */
#define _DEFAULT_SOURCE

#include "usage_table.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <libevdev/libevdev.h>

#define REPORT_LEN 8
#define KEY_SLOTS 6          /* bytes 2..7 of the boot report */
#define MACRO_MAX 512

/* The replay hotkey: right Ctrl plus M.
 *
 * Right Ctrl rather than left, because left Ctrl is half of most of the
 * shortcuts anybody actually types at the host and this key combination
 * has to be one the host never sees. When the hotkey fires, the M is
 * CONSUMED: it is not forwarded, so the host receives the macro and not
 * a stray letter in front of it.
 *
 * Bit 4 of byte 0 is right Ctrl, from the modifier order in the report
 * descriptor: usages 224 to 231 are left Ctrl, Shift, Alt, GUI then
 * right Ctrl, Shift, Alt, GUI.
 */
#define RIGHT_CTRL_BIT 4
#define HOTKEY_CODE KEY_M

/* Between characters of a macro. The host polls the interrupt endpoint
 * at bInterval, and a press and a release sent closer together than one
 * poll can be coalesced into nothing. 5 ms is comfortably more than the
 * 1 ms a high speed interrupt endpoint is usually given. */
#define MACRO_GAP_US 5000

static volatile sig_atomic_t stop;

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

/* ---------------------------------------------------------------- report */

struct report {
	uint8_t bytes[REPORT_LEN];
	unsigned long dropped_full;   /* a 7th key, no slot free */
	unsigned long dropped_unmapped;
	unsigned long write_not_live; /* host had not configured us */
};

static int modifier_bit(int code)
{
	switch (code) {
	case KEY_LEFTCTRL:   return 0;
	case KEY_LEFTSHIFT:  return 1;
	case KEY_LEFTALT:    return 2;
	case KEY_LEFTMETA:   return 3;
	case KEY_RIGHTCTRL:  return 4;
	case KEY_RIGHTSHIFT: return 5;
	case KEY_RIGHTALT:   return 6;
	case KEY_RIGHTMETA:  return 7;
	default:             return -1;
	}
}

/* Send the current state. Not fatal when the host is not listening. */
static void report_send(struct report *r, int hfd)
{
	ssize_t written = write(hfd, r->bytes, REPORT_LEN);

	if (written == REPORT_LEN)
		return;

	/*
	 * ESHUTDOWN: the gadget is not configured, so the cable is out or
	 * the host has not finished enumerating. EAGAIN: the endpoint
	 * queue is full. Both are ordinary and both are counted, because
	 * a bridge that exits on an unplugged cable is a bridge that has
	 * to be restarted by hand every time.
	 */
	if (errno == ESHUTDOWN || errno == EAGAIN || errno == ENODEV) {
		r->write_not_live++;
		return;
	}

	perror("kbd-bridge: write to hidg0");
}

/* Apply one evdev key event to the report. Returns 1 if it changed. */
static int report_apply(struct report *r, int code, int value)
{
	int bit = modifier_bit(code);
	uint8_t usage;
	int i;

	if (bit >= 0) {
		if (value)
			r->bytes[0] |= (uint8_t)(1u << bit);
		else
			r->bytes[0] &= (uint8_t)~(1u << bit);
		return 1;
	}

	if (code < 0 || code > KEYCODE_TO_USAGE_MAX) {
		r->dropped_unmapped++;
		return 0;
	}

	usage = keycode_to_usage[code];
	if (usage == 0) {
		/* Usage 0 is the reserved "no event" code, so a key with no
		 * mapping has to be dropped rather than sent as zero. */
		r->dropped_unmapped++;
		return 0;
	}

	if (value) {
		/* Already held? The host is edge-insensitive, but sending a
		 * usage twice in one report is malformed. */
		for (i = 2; i < REPORT_LEN; i++)
			if (r->bytes[i] == usage)
				return 0;
		for (i = 2; i < REPORT_LEN; i++) {
			if (r->bytes[i] == 0) {
				r->bytes[i] = usage;
				return 1;
			}
		}
		/*
		 * Seven keys at once. Boot protocol has six slots and no way
		 * to say "and one more", so the seventh is dropped. Counted
		 * rather than silent: the specification calls this out, and a
		 * count is the difference between a known limit and a mystery.
		 */
		r->dropped_full++;
		return 0;
	}

	for (i = 2; i < REPORT_LEN; i++) {
		if (r->bytes[i] == usage) {
			r->bytes[i] = 0;
			return 1;
		}
	}
	return 0;
}

/* ----------------------------------------------------------------- macro */

/*
 * ASCII to usage, for macros only. US layout.
 *
 * THIS IS A LAYOUT ASSUMPTION AND IT CANNOT BE AVOIDED HERE. The gadget
 * sends usages, not characters: usage 0x1d is "the key where z is on a
 * US keyboard", and on a Swiss or German host that key produces y. A
 * macro containing z therefore types y on such a host unless this table
 * is replaced with one for that layout.
 *
 * Said plainly rather than worked around, because the alternative is a
 * macro feature that works on the author's desk and mistypes on
 * somebody else's.
 */
struct ascii_key {
	uint8_t usage;
	uint8_t shift;
};

static struct ascii_key ascii_to_key(char c)
{
	struct ascii_key k = { 0, 0 };

	if (c >= 'a' && c <= 'z') {
		k.usage = (uint8_t)(0x04 + (c - 'a'));
	} else if (c >= 'A' && c <= 'Z') {
		k.usage = (uint8_t)(0x04 + (c - 'A'));
		k.shift = 1;
	} else if (c >= '1' && c <= '9') {
		k.usage = (uint8_t)(0x1e + (c - '1'));
	} else {
		switch (c) {
		case '0':  k.usage = 0x27; break;
		case '\n': k.usage = 0x28; break;
		case '\t': k.usage = 0x2b; break;
		case ' ':  k.usage = 0x2c; break;
		case '-':  k.usage = 0x2d; break;
		case '=':  k.usage = 0x2e; break;
		case '[':  k.usage = 0x2f; break;
		case ']':  k.usage = 0x30; break;
		case '\\': k.usage = 0x31; break;
		case ';':  k.usage = 0x33; break;
		case '\'': k.usage = 0x34; break;
		case '`':  k.usage = 0x35; break;
		case ',':  k.usage = 0x36; break;
		case '.':  k.usage = 0x37; break;
		case '/':  k.usage = 0x38; break;
		case '!':  k.usage = 0x1e; k.shift = 1; break;
		case '@':  k.usage = 0x1f; k.shift = 1; break;
		case '#':  k.usage = 0x20; k.shift = 1; break;
		case '$':  k.usage = 0x21; k.shift = 1; break;
		case '%':  k.usage = 0x22; k.shift = 1; break;
		case '^':  k.usage = 0x23; k.shift = 1; break;
		case '&':  k.usage = 0x24; k.shift = 1; break;
		case '*':  k.usage = 0x25; k.shift = 1; break;
		case '(':  k.usage = 0x26; k.shift = 1; break;
		case ')':  k.usage = 0x27; k.shift = 1; break;
		case '_':  k.usage = 0x2d; k.shift = 1; break;
		case '+':  k.usage = 0x2e; k.shift = 1; break;
		case '{':  k.usage = 0x2f; k.shift = 1; break;
		case '}':  k.usage = 0x30; k.shift = 1; break;
		case '|':  k.usage = 0x31; k.shift = 1; break;
		case ':':  k.usage = 0x33; k.shift = 1; break;
		case '"':  k.usage = 0x34; k.shift = 1; break;
		case '~':  k.usage = 0x35; k.shift = 1; break;
		case '<':  k.usage = 0x36; k.shift = 1; break;
		case '>':  k.usage = 0x37; k.shift = 1; break;
		case '?':  k.usage = 0x38; k.shift = 1; break;
		default:   break;
		}
	}
	return k;
}

/*
 * Type a string. Each character is one report with the key down and one
 * with everything up, because the host works out the press from the
 * difference and would see a repeated character as a single held key.
 *
 * The physical keyboard's own state is saved and restored around this,
 * so a macro fired while a modifier is held does not leave that
 * modifier stuck on the host.
 */
static unsigned long macro_type(struct report *r, int hfd, const char *text)
{
	uint8_t saved[REPORT_LEN];
	unsigned long typed = 0;
	size_t i;

	memcpy(saved, r->bytes, REPORT_LEN);
	memset(r->bytes, 0, REPORT_LEN);

	for (i = 0; text[i]; i++) {
		struct ascii_key k = ascii_to_key(text[i]);

		if (k.usage == 0) {
			r->dropped_unmapped++;
			continue;
		}

		r->bytes[0] = k.shift ? (uint8_t)(1u << 1) : 0u;  /* left shift */
		r->bytes[2] = k.usage;
		report_send(r, hfd);
		usleep(MACRO_GAP_US);

		memset(r->bytes, 0, REPORT_LEN);
		report_send(r, hfd);
		usleep(MACRO_GAP_US);
		typed++;
	}

	memcpy(r->bytes, saved, REPORT_LEN);
	report_send(r, hfd);
	return typed;
}

/* ------------------------------------------------------------------ main */

static void usage_message(const char *argv0)
{
	fprintf(stderr,
		"usage: %s [keyboard-device] [hid-device] [macro-fifo]\n"
		"  defaults: /dev/input/bench-kbd /dev/hidg0 "
		"/run/kbd-bridge/macro\n", argv0);
}

int main(int argc, char **argv)
{
	const char *kbd_path = argc > 1 ? argv[1] : "/dev/input/bench-kbd";
	const char *hid_path = argc > 2 ? argv[2] : "/dev/hidg0";
	const char *fifo_path = argc > 3 ? argv[3] : "/run/kbd-bridge/macro";
	struct libevdev *dev = NULL;
	struct report r;
	struct pollfd fds[2];
	/* The last macro sent, for the right Ctrl plus M hotkey. Kept
	 * here rather than in struct report because it is not part of the
	 * keyboard state: a replay does not change what is held down. */
	char last_macro[MACRO_MAX] = "";
	int kfd, hfd, ffd;
	int rc;

	if (argc > 4) {
		usage_message(argv[0]);
		return 2;
	}

	memset(&r, 0, sizeof r);

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	kfd = open(kbd_path, O_RDONLY | O_NONBLOCK);
	if (kfd < 0) {
		fprintf(stderr, "kbd-bridge: %s: %s\n", kbd_path, strerror(errno));
		fprintf(stderr, "  The udev rule creates this symlink when the "
				"keyboard is plugged in.\n");
		return 1;
	}

	hfd = open(hid_path, O_RDWR);
	if (hfd < 0) {
		fprintf(stderr, "kbd-bridge: %s: %s\n", hid_path, strerror(errno));
		fprintf(stderr, "  hidg0 appears only once bench-gadget has bound "
				"the UDC.\n  Check: bench-gadget status\n");
		close(kfd);
		return 1;
	}

	rc = libevdev_new_from_fd(kfd, &dev);
	if (rc < 0) {
		fprintf(stderr, "kbd-bridge: libevdev: %s\n", strerror(-rc));
		close(kfd);
		close(hfd);
		return 1;
	}

	/* The grab. Everything after this line is invisible to the Pi. */
	rc = libevdev_grab(dev, LIBEVDEV_GRAB);
	if (rc < 0) {
		fprintf(stderr, "kbd-bridge: cannot grab %s: %s\n",
			kbd_path, strerror(-rc));
		fprintf(stderr, "  Something else holds it. Only one process may "
				"grab a device.\n");
		libevdev_free(dev);
		close(kfd);
		close(hfd);
		return 1;
	}

	printf("kbd-bridge: %s -> %s\n", libevdev_get_name(dev), hid_path);
	printf("kbd-bridge: the keyboard is now invisible to this Pi; "
	       "use the serial console\n");
	fflush(stdout);

	/* The macro FIFO is optional: without it the bridge still mirrors
	 * the keyboard, which is the part that must not depend on anything
	 * else working. */
	ffd = -1;
	if (mkfifo(fifo_path, 0600) < 0 && errno != EEXIST)
		fprintf(stderr, "kbd-bridge: no macro fifo at %s: %s\n",
			fifo_path, strerror(errno));
	else
		ffd = open(fifo_path, O_RDONLY | O_NONBLOCK);

	fds[0].fd = kfd;
	fds[0].events = POLLIN;
	fds[1].fd = ffd;
	fds[1].events = POLLIN;

	while (!stop) {
		if (poll(fds, ffd >= 0 ? 2 : 1, -1) < 0) {
			if (errno == EINTR)
				continue;
			perror("kbd-bridge: poll");
			break;
		}

		if (fds[0].revents & POLLIN) {
			struct input_event ev;
			int status;

			for (;;) {
				status = libevdev_next_event(
					dev, LIBEVDEV_READ_FLAG_NORMAL, &ev);
				if (status != LIBEVDEV_READ_STATUS_SUCCESS)
					break;
				if (ev.type != EV_KEY)
					continue;
				if (ev.value == 2)   /* autorepeat: the host's job */
					continue;

				/*
				 * The replay hotkey, checked BEFORE the event
				 * reaches the report. Right Ctrl is already in
				 * byte 0 because its own press went through
				 * here first, so this reads the state rather
				 * than tracking it separately.
				 *
				 * The M is consumed either way: firing it and
				 * also forwarding it would type the letter in
				 * front of the macro.
				 */
				if (ev.code == HOTKEY_CODE && ev.value == 1 &&
				    (r.bytes[0] & (1u << RIGHT_CTRL_BIT))) {
					if (last_macro[0]) {
						macro_type(&r, hfd, last_macro);
					} else {
						fprintf(stderr, "kbd-bridge: "
							"hotkey pressed but no "
							"macro has been sent "
							"yet\n");
					}
					continue;
				}
				if (ev.code == HOTKEY_CODE && ev.value == 0 &&
				    (r.bytes[0] & (1u << RIGHT_CTRL_BIT)))
					continue;   /* swallow the release too */

				if (report_apply(&r, ev.code, ev.value))
					report_send(&r, hfd);
			}
		}

		if (ffd >= 0 && (fds[1].revents & POLLIN)) {
			char line[MACRO_MAX];
			ssize_t n = read(ffd, line, sizeof line - 1);

			if (n > 0) {
				line[n] = '\0';
				/* Remembered before it is typed, so the
				 * hotkey replays what was asked for even if
				 * the host was not listening at the time. */
				snprintf(last_macro, sizeof last_macro,
					 "%s", line);
				macro_type(&r, hfd, line);
			} else if (n == 0) {
				/* Every writer closed. Reopen so the next one is
				 * seen; without this the fifo reports readable
				 * forever and the loop spins. */
				close(ffd);
				ffd = open(fifo_path, O_RDONLY | O_NONBLOCK);
				fds[1].fd = ffd;
			}
		}
	}

	printf("kbd-bridge: stopping. dropped: %lu unmapped, %lu over six keys; "
	       "%lu writes while the host was not listening\n",
	       r.dropped_unmapped, r.dropped_full, r.write_not_live);

	libevdev_grab(dev, LIBEVDEV_UNGRAB);
	libevdev_free(dev);
	close(kfd);
	close(hfd);
	if (ffd >= 0)
		close(ffd);
	return 0;
}
