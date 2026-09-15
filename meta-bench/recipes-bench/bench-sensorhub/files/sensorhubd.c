/*
 * sensorhubd - republish a microcontroller's sensor stream on the system bus.
 *
 * One tty in, one D-Bus interface out. The daemon owns the serial port so
 * that nothing else has to: clients see org.bench.SensorHub1 and never a
 * device node, which is what makes the tty an implementation detail that
 * can be replaced by SPI, by a socket or by a second MCU without any
 * client changing.
 *
 * Structure, and why it is this shape:
 *
 *   one thread, one event loop     sd-event owns the tty fd, the bus and
 *                                  the timers. No locking anywhere,
 *                                  because there is nothing to lock.
 *   two reply strategies           SetRate blocks the loop for at most
 *                                  200 ms, because that is simple and the
 *                                  hub answers in microseconds. Calibrate
 *                                  takes seconds, so its reply is deferred
 *                                  and sent from the frame parser.
 *   decode with a library          proto.c encodes by hand because the
 *                                  shapes are fixed; this file decodes
 *                                  with libcbor because the input is
 *                                  untrusted and arrives from a wire.
 *   policy outside the daemon      who may call at all is the bus policy,
 *                                  who may calibrate is polkit. Neither
 *                                  question is answered by an if statement
 *                                  in here.
 *
 * Written against sd-bus, sd-event and libcbor 0.11.
 *
 * SPDX-License-Identifier: MIT
 */

#define _GNU_SOURCE

#include <cbor.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-daemon.h>
#include <systemd/sd-event.h>
#include <sys/epoll.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "proto.h"

#define IFACE "org.bench.SensorHub1"
#define OBJ   "/org/bench/SensorHub1"
#define POLKIT_CALIBRATE "org.bench.sensorhub.calibrate"

#define DEFAULT_TTY   "/dev/sensorhub"
#define DEFAULT_RATE  100u

#define SET_RATE_TIMEOUT_MS   200
#define CALIBRATE_TIMEOUT_US  (3 * 1000000ull)
#define SILENCE_TIMEOUT_US    (5 * 1000000ull)

#define RATE_MIN 1u
#define RATE_MAX 1000u

struct hub {
	sd_bus *bus;
	sd_event *event;
	int fd;

	struct proto_parser parser;

	uint32_t rate_hz;
	uint32_t wire_version;		/* what the hub last sent */
	uint32_t proto_minor;
	char *fw_version;

	bool version_complained;	/* log a mismatch once, not per frame */

	/* SetRate waits for this inline. */
	bool ack_seen;
	uint8_t ack_type;
	uint8_t ack_status;

	/* Calibrate replies later, from the frame parser. */
	sd_bus_message *calibrate_reply_to;
	sd_event_source *calibrate_timer;

	sd_event_source *silence_timer;
};

/* --------------------------------------------------------------- the tty */

/*
 * Raw, 921600 baud, no flow control, read returns as soon as one byte is
 * there. VMIN=1 VTIME=0 rather than a larger VMIN: this is a latency
 * project's neighbour, and a driver that waits for a full buffer adds
 * milliseconds that then look like they came from the hub.
 */
static int tty_open(const char *path)
{
	struct termios tio;
	int fd;

	fd = open(path, O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "sensorhubd: %s: %s\n", path, strerror(errno));
		return -errno;
	}

	if (tcgetattr(fd, &tio) < 0) {
		fprintf(stderr, "sensorhubd: %s is not a tty: %s\n", path,
			strerror(errno));
		close(fd);
		return -errno;
	}

	cfmakeraw(&tio);
	tio.c_cflag |= CLOCAL | CREAD;
	tio.c_cflag &= (tcflag_t)~CRTSCTS;
	tio.c_cc[VMIN] = 1;
	tio.c_cc[VTIME] = 0;
	if (cfsetispeed(&tio, B921600) < 0 || cfsetospeed(&tio, B921600) < 0) {
		fprintf(stderr, "sensorhubd: cannot set 921600 baud\n");
		close(fd);
		return -EINVAL;
	}
	if (tcsetattr(fd, TCSANOW, &tio) < 0) {
		fprintf(stderr, "sensorhubd: tcsetattr: %s\n", strerror(errno));
		close(fd);
		return -errno;
	}

	/*
	 * The ST-LINK buffers whatever the firmware printed before this
	 * process existed, including half a frame from before a reset.
	 * Throwing it away costs nothing and saves one CRC error per start
	 * that would otherwise have to be explained every time.
	 */
	tcflush(fd, TCIFLUSH);
	return fd;
}

static int tty_write_all(int fd, const uint8_t *data, size_t len)
{
	size_t done = 0;

	while (done < len) {
		ssize_t n = write(fd, data + done, len - done);

		if (n < 0) {
			if (errno == EINTR)
				continue;
			return -errno;
		}
		done += (size_t)n;
	}
	return 0;
}

static int send_command(struct hub *h, uint8_t type, const uint8_t *payload,
			size_t payload_len)
{
	uint8_t frame[PROTO_MAX_FRAME];
	int n = proto_frame(frame, sizeof frame, type, payload, payload_len);

	if (n < 0)
		return -EINVAL;
	return tty_write_all(h->fd, frame, (size_t)n);
}

/* ------------------------------------------------------------ CBOR input */

/*
 * Every accessor below is guarded. The bytes came off a wire from a device
 * that may be running any firmware at all, including a half flashed one,
 * and libcbor will happily hand back a map whose values are strings where
 * numbers were expected. A missing key is a malformed frame, not a zero.
 */
static const cbor_item_t *map_get(const cbor_item_t *map, uint64_t key)
{
	struct cbor_pair *pairs;
	size_t i, n;

	if (!cbor_isa_map(map))
		return NULL;
	n = cbor_map_size(map);
	pairs = cbor_map_handle(map);
	for (i = 0; i < n; i++) {
		if (cbor_isa_uint(pairs[i].key) &&
		    cbor_get_int(pairs[i].key) == key)
			return pairs[i].value;
	}
	return NULL;
}

static bool get_uint(const cbor_item_t *map, uint64_t key, uint64_t *out)
{
	const cbor_item_t *item = map_get(map, key);

	if (!item || !cbor_isa_uint(item))
		return false;
	*out = cbor_get_int(item);
	return true;
}

static bool get_float3(const cbor_item_t *map, uint64_t key, double out[3])
{
	const cbor_item_t *item = map_get(map, key);
	cbor_item_t **elements;
	size_t i;

	if (!item || !cbor_isa_array(item) || cbor_array_size(item) != 3)
		return false;
	elements = cbor_array_handle(item);
	for (i = 0; i < 3; i++) {
		if (!cbor_isa_float_ctrl(elements[i]))
			return false;
		out[i] = cbor_float_get_float(elements[i]);
	}
	return true;
}

static bool get_float(const cbor_item_t *map, uint64_t key, double *out)
{
	const cbor_item_t *item = map_get(map, key);

	if (!item || !cbor_isa_float_ctrl(item))
		return false;
	*out = cbor_float_get_float(item);
	return true;
}

static char *get_string(const cbor_item_t *map, uint64_t key)
{
	const cbor_item_t *item = map_get(map, key);
	size_t len;
	char *copy;

	if (!item || !cbor_isa_string(item))
		return NULL;
	len = cbor_string_length(item);
	copy = malloc(len + 1);
	if (!copy)
		return NULL;
	memcpy(copy, cbor_string_handle(item), len);
	copy[len] = '\0';
	return copy;
}

/* ------------------------------------------------------- the frame handler */

static void arm_silence_timer(struct hub *h);

static void finish_calibrate(struct hub *h, uint8_t status)
{
	sd_bus_message *reply_to = h->calibrate_reply_to;

	if (!reply_to)
		return;
	h->calibrate_reply_to = NULL;
	if (h->calibrate_timer)
		sd_event_source_set_enabled(h->calibrate_timer, SD_EVENT_OFF);

	if (status == PROTO_ACK_OK)
		sd_bus_reply_method_return(reply_to, "");
	else
		sd_bus_reply_method_errorf(reply_to, IFACE ".Error.Refused",
					   "the hub refused to calibrate, "
					   "status %u", (unsigned)status);
	sd_bus_message_unref(reply_to);
}

static void on_frame(void *user, uint8_t version, uint8_t type,
		     const uint8_t *payload, size_t payload_len)
{
	struct hub *h = user;
	struct cbor_load_result result;
	cbor_item_t *item;
	uint64_t t_us = 0, acked = 0, status = 0, minor = 0;
	double accel[3] = { 0.0, 0.0, 0.0 };
	double gyro[3] = { 0.0, 0.0, 0.0 };
	double temp = 0.0;

	arm_silence_timer(h);

	if (version != h->wire_version) {
		h->wire_version = version;
		sd_bus_emit_properties_changed(h->bus, OBJ, IFACE,
					       "ProtocolVersion", NULL);
	}

	/*
	 * A major version the daemon was not written for is refused whole.
	 * Not silently: the property carries the number the hub is actually
	 * speaking, so a client can see the mismatch, and the log line
	 * appears once rather than at the sample rate.
	 */
	if (version != PROTO_VERSION) {
		if (!h->version_complained) {
			fprintf(stderr, SD_WARNING
				"sensorhubd: the hub speaks protocol major %u "
				"and this daemon implements %u; refusing the "
				"stream. Flash matching firmware, or install "
				"a daemon that serves %s%u.\n",
				(unsigned)version, (unsigned)PROTO_VERSION,
				IFACE, (unsigned)version);
			h->version_complained = true;
		}
		return;
	}

	item = cbor_load(payload, payload_len, &result);
	if (!item || result.read != payload_len) {
		if (item)
			cbor_decref(&item);
		/*
		 * A frame whose CRC was right and whose payload is not
		 * valid CBOR means the two ends disagree about the
		 * encoding rather than that the wire is noisy. Counted in
		 * the same place as a CRC failure, because to a client
		 * the distinction is "the hub is not being understood".
		 */
		h->parser.frames_bad++;
		return;
	}

	switch (type) {
	case PROTO_SAMPLE:
		/*
		 * The temperature is decoded and not published. The
		 * interface carries motion only, and validating the whole
		 * map anyway is deliberate: a firmware that stopped
		 * sending key 3 has changed the sample shape, which is a
		 * protocol change, and it should be noticed here rather
		 * than by a client wondering why a later key moved.
		 */
		if (!get_uint(item, 0, &t_us) || !get_float3(item, 1, accel) ||
		    !get_float3(item, 2, gyro) || !get_float(item, 3, &temp)) {
			h->parser.frames_bad++;
			break;
		}
		(void)temp;
		/*
		 * The array count is an int and the elements are doubles:
		 * see sd_bus_message_append(3), "an array is a count
		 * followed by the entries". Getting that wrong compiles
		 * cleanly and produces a signal nobody can decode.
		 */
		sd_bus_emit_signal(h->bus, OBJ, IFACE, "SampleReady", "tadad",
				   t_us,
				   3, accel[0], accel[1], accel[2],
				   3, gyro[0], gyro[1], gyro[2]);
		break;

	case PROTO_HELLO:
		if (get_uint(item, 0, &minor))
			h->proto_minor = (uint32_t)minor;
		free(h->fw_version);
		h->fw_version = get_string(item, 1);
		if (!h->fw_version)
			h->fw_version = strdup("unknown");
		fprintf(stderr, SD_INFO "sensorhubd: hub says protocol %u.%u, "
			"firmware %s\n", (unsigned)version, (unsigned)h->proto_minor,
			h->fw_version ? h->fw_version : "unknown");
		sd_bus_emit_properties_changed(h->bus, OBJ, IFACE,
					       "FirmwareVersion", NULL);
		break;

	case PROTO_ACK:
		if (!get_uint(item, 0, &acked) || !get_uint(item, 1, &status)) {
			h->parser.frames_bad++;
			break;
		}
		h->ack_seen = true;
		h->ack_type = (uint8_t)acked;
		h->ack_status = (uint8_t)status;
		if (acked == PROTO_CALIBRATE)
			finish_calibrate(h, (uint8_t)status);
		break;

	default:
		/*
		 * An unknown type from a matching major version is a minor
		 * version addition, and the rule in PROTOCOL.md is that
		 * the receiver ignores what it does not know. Not counted
		 * as an error: counting it would make a compatible
		 * firmware update look like a fault.
		 */
		break;
	}

	cbor_decref(&item);
}

/* Read whatever is available and feed the parser. */
static int pump(struct hub *h)
{
	uint8_t chunk[1024];
	ssize_t n;

	n = read(h->fd, chunk, sizeof chunk);
	if (n < 0) {
		if (errno == EINTR || errno == EAGAIN)
			return 0;
		return -errno;
	}
	if (n == 0)
		return -ENODEV;
	proto_parser_push(&h->parser, chunk, (size_t)n, on_frame, h);
	return 0;
}

static int on_tty_readable(sd_event_source *s, int fd, uint32_t revents,
			   void *userdata)
{
	struct hub *h = userdata;
	int r;

	(void)s;
	(void)fd;

	if (revents & (EPOLLHUP | EPOLLERR)) {
		fprintf(stderr, SD_WARNING
			"sensorhubd: the device went away; exiting so that "
			"systemd can restart on the next one.\n");
		return sd_event_exit(h->event, 0);
	}

	r = pump(h);
	if (r < 0) {
		fprintf(stderr, SD_ERR "sensorhubd: read: %s\n", strerror(-r));
		return sd_event_exit(h->event, 1);
	}
	return 0;
}

static int on_silence(sd_event_source *s, uint64_t usec, void *userdata)
{
	struct hub *h = userdata;

	(void)s;
	(void)usec;
	fprintf(stderr, SD_WARNING
		"sensorhubd: no frames for %llu s. The hub may be held in "
		"reset, or something else has the tty.\n",
		(unsigned long long)(SILENCE_TIMEOUT_US / 1000000ull));
	arm_silence_timer(h);
	return 0;
}

static void arm_silence_timer(struct hub *h)
{
	uint64_t now = 0;

	if (sd_event_now(h->event, CLOCK_MONOTONIC, &now) < 0)
		return;
	if (h->silence_timer) {
		sd_event_source_set_time(h->silence_timer,
					 now + SILENCE_TIMEOUT_US);
		sd_event_source_set_enabled(h->silence_timer, SD_EVENT_ONESHOT);
		return;
	}
	sd_event_add_time(h->event, &h->silence_timer, CLOCK_MONOTONIC,
			  now + SILENCE_TIMEOUT_US, 250000, on_silence, h);
}

/* ----------------------------------------------------------- the polkit ask */

/*
 * AllowUserInteraction is 0 on purpose, and it is the one argument in this
 * call worth arguing about.
 *
 * With 1, polkit may go and find an authentication agent and wait for a
 * human. This is a system service answering a bus call: the caller's
 * method call has a 25 s default timeout, and a handler that waits longer
 * makes every client of this daemon hang, which is the pitfall this
 * project warns about in its own README. With 0 the answer comes back
 * immediately, from the rules, and a caller who needs to authenticate gets
 * a clean denial rather than a hang.
 *
 * The consequence is deliberate: authorisation here is a property of the
 * caller's group, decided by 50-sensorhub.rules, not of somebody being at
 * a keyboard.
 */
static int polkit_allows(struct hub *h, sd_bus_message *m, const char *action,
			 sd_bus_error *err)
{
	sd_bus_message *reply = NULL;
	const char *sender;
	int authorized = 0, challenge = 0;
	int r;

	sender = sd_bus_message_get_sender(m);
	if (!sender)
		return sd_bus_error_set(err, SD_BUS_ERROR_ACCESS_DENIED,
					"the caller has no bus name");

	r = sd_bus_call_method(h->bus,
			       "org.freedesktop.PolicyKit1",
			       "/org/freedesktop/PolicyKit1/Authority",
			       "org.freedesktop.PolicyKit1.Authority",
			       "CheckAuthorization", err, &reply,
			       "(sa{sv})sa{ss}us",
			       "system-bus-name", 1, "name", "s", sender,
			       action,
			       0,
			       0,
			       "");
	if (r < 0)
		return r;

	r = sd_bus_message_enter_container(reply, 'r', "bba{ss}");
	if (r >= 0)
		r = sd_bus_message_read(reply, "bb", &authorized, &challenge);
	sd_bus_message_unref(reply);
	if (r < 0)
		return r;

	if (!authorized)
		return sd_bus_error_setf(err, SD_BUS_ERROR_ACCESS_DENIED,
					 "not authorised for %s", action);
	return 0;
}

/* ------------------------------------------------------------- the methods */

/*
 * Wait for an ACK without leaving the function. The event loop is not
 * running during this, which is the trade: 200 ms of unresponsiveness on
 * one call, against the machinery a deferred reply needs. Frames that
 * arrive meanwhile are still parsed and still emitted, because the wait
 * goes through the same parser as the event loop does.
 */
static int wait_for_ack(struct hub *h, uint8_t type, int timeout_ms)
{
	struct pollfd pfd = { .fd = h->fd, .events = POLLIN };
	struct timespec start, now;

	h->ack_seen = false;
	clock_gettime(CLOCK_MONOTONIC, &start);

	for (;;) {
		long elapsed_ms;
		int remaining, r;

		/*
		 * The budget comes from the clock, not from counting
		 * iterations. At 100 Hz there are samples arriving the
		 * whole time, so poll returns immediately over and over and
		 * a loop that decremented a counter per iteration would
		 * expire in microseconds or never, depending on the rate.
		 */
		clock_gettime(CLOCK_MONOTONIC, &now);
		elapsed_ms = (long)(now.tv_sec - start.tv_sec) * 1000 +
			     (now.tv_nsec - start.tv_nsec) / 1000000L;
		remaining = timeout_ms - (int)elapsed_ms;
		if (remaining <= 0)
			return -ETIMEDOUT;

		r = poll(&pfd, 1, remaining);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			return -errno;
		}
		if (r == 0)
			return -ETIMEDOUT;
		if (pump(h) < 0)
			return -EIO;
		if (h->ack_seen && h->ack_type == type)
			return h->ack_status == PROTO_ACK_OK ? 0 : -EPERM;
	}
}

static int method_set_rate(sd_bus_message *m, void *userdata,
			   sd_bus_error *err)
{
	struct hub *h = userdata;
	uint8_t payload[16];
	uint32_t hz;
	int n, r;

	r = sd_bus_message_read(m, "u", &hz);
	if (r < 0)
		return r;

	if (hz < RATE_MIN || hz > RATE_MAX)
		return sd_bus_error_setf(err, SD_BUS_ERROR_INVALID_ARGS,
					 "rate %" PRIu32 " outside %u to %u Hz",
					 hz, RATE_MIN, RATE_MAX);

	n = proto_encode_set_rate(payload, sizeof payload, hz);
	if (n < 0)
		return -EINVAL;
	r = send_command(h, PROTO_SET_RATE, payload, (size_t)n);
	if (r < 0)
		return sd_bus_error_setf(err, IFACE ".Error.WriteFailed",
					 "cannot write to the hub: %s",
					 strerror(-r));

	r = wait_for_ack(h, PROTO_SET_RATE, SET_RATE_TIMEOUT_MS);
	if (r == -EPERM)
		return sd_bus_error_setf(err, IFACE ".Error.Refused",
					 "the hub refused the rate, status %u",
					 (unsigned)h->ack_status);
	if (r < 0)
		return sd_bus_error_setf(err, IFACE ".Error.NoAck",
					 "the hub did not acknowledge within "
					 "%d ms", SET_RATE_TIMEOUT_MS);

	/*
	 * The property changes here and not a line earlier. A client that
	 * reads RateHz after a successful SetRate sees the rate the hub
	 * confirmed, so the property describes the hardware rather than
	 * the last request somebody made of it.
	 */
	h->rate_hz = hz;
	sd_bus_emit_properties_changed(h->bus, OBJ, IFACE, "RateHz", NULL);
	return sd_bus_reply_method_return(m, "");
}

static int on_calibrate_timeout(sd_event_source *s, uint64_t usec,
				void *userdata)
{
	struct hub *h = userdata;
	sd_bus_message *reply_to = h->calibrate_reply_to;

	(void)s;
	(void)usec;
	if (!reply_to)
		return 0;
	h->calibrate_reply_to = NULL;
	sd_bus_reply_method_errorf(reply_to, IFACE ".Error.NoAck",
				   "the hub did not finish calibrating within "
				   "%llu s",
				   (unsigned long long)(CALIBRATE_TIMEOUT_US /
							1000000ull));
	sd_bus_message_unref(reply_to);
	return 0;
}

static int method_calibrate(sd_bus_message *m, void *userdata,
			    sd_bus_error *err)
{
	struct hub *h = userdata;
	uint8_t payload[8];
	uint64_t now = 0;
	int n, r;

	r = polkit_allows(h, m, POLKIT_CALIBRATE, err);
	if (r < 0)
		return r;

	if (h->calibrate_reply_to)
		return sd_bus_error_set(err, IFACE ".Error.Busy",
					"a calibration is already running");

	n = proto_encode_calibrate(payload, sizeof payload);
	if (n < 0)
		return -EINVAL;
	r = send_command(h, PROTO_CALIBRATE, payload, (size_t)n);
	if (r < 0)
		return sd_bus_error_setf(err, IFACE ".Error.WriteFailed",
					 "cannot write to the hub: %s",
					 strerror(-r));

	/*
	 * Calibration takes about two seconds, which is eight times longer
	 * than SetRate is allowed to block. So the message is kept and the
	 * reply is sent from on_frame when the ACK arrives, or from the
	 * timer if it never does. Returning without replying is how a
	 * deferred reply is expressed in sd-bus: nothing is sent until
	 * somebody sends it.
	 */
	h->calibrate_reply_to = sd_bus_message_ref(m);

	if (sd_event_now(h->event, CLOCK_MONOTONIC, &now) >= 0) {
		if (h->calibrate_timer) {
			sd_event_source_set_time(h->calibrate_timer,
						 now + CALIBRATE_TIMEOUT_US);
			sd_event_source_set_enabled(h->calibrate_timer,
						    SD_EVENT_ONESHOT);
		} else {
			sd_event_add_time(h->event, &h->calibrate_timer,
					  CLOCK_MONOTONIC,
					  now + CALIBRATE_TIMEOUT_US, 100000,
					  on_calibrate_timeout, h);
		}
	}
	return 1;
}

/* ---------------------------------------------------------- the properties */

/*
 * Explicit getters rather than SD_BUS_PROPERTY with an offsetof. The
 * offset form is shorter and it is unchecked: a field whose C type does
 * not match the D-Bus signature compiles cleanly and produces a property
 * that reads the wrong bytes. Four lines each is a cheap price for the
 * compiler seeing the types.
 */
static int prop_rate(sd_bus *bus, const char *path, const char *iface,
		     const char *property, sd_bus_message *reply,
		     void *userdata, sd_bus_error *err)
{
	struct hub *h = userdata;

	(void)bus; (void)path; (void)iface; (void)property; (void)err;
	return sd_bus_message_append(reply, "u", h->rate_hz);
}

static int prop_protocol(sd_bus *bus, const char *path, const char *iface,
			 const char *property, sd_bus_message *reply,
			 void *userdata, sd_bus_error *err)
{
	struct hub *h = userdata;

	(void)bus; (void)path; (void)iface; (void)property; (void)err;
	/*
	 * The version the hub is speaking, not the one this daemon
	 * implements. On a match they are the same number and the property
	 * is uninteresting; on a mismatch it is the only place a client can
	 * see what went wrong.
	 */
	return sd_bus_message_append(reply, "u", h->wire_version);
}

static int prop_firmware(sd_bus *bus, const char *path, const char *iface,
			 const char *property, sd_bus_message *reply,
			 void *userdata, sd_bus_error *err)
{
	struct hub *h = userdata;

	(void)bus; (void)path; (void)iface; (void)property; (void)err;
	return sd_bus_message_append(reply, "s",
				     h->fw_version ? h->fw_version : "unknown");
}

static int prop_dropped(sd_bus *bus, const char *path, const char *iface,
			const char *property, sd_bus_message *reply,
			void *userdata, sd_bus_error *err)
{
	struct hub *h = userdata;

	(void)bus; (void)path; (void)iface; (void)property; (void)err;
	return sd_bus_message_append(reply, "t", h->parser.frames_bad);
}

/*
 * RateHz is read-only with a SetRate method beside it, rather than a
 * writable property. A property set is a one way assignment with no room
 * for "the hub refused" or "the hub did not answer", and both of those are
 * outcomes a client has to be able to distinguish. The method can return
 * a typed error; a property set can only fail.
 *
 * SD_BUS_VTABLE_UNPRIVILEGED on both methods is load bearing. Without it
 * sd-bus requires CAP_SYS_ADMIN from the caller before the handler runs at
 * all, and polkit never gets asked, which presents as a permission denial
 * that no polkit rule can fix.
 */
static const sd_bus_vtable hub_vtable[] = {
	SD_BUS_VTABLE_START(0),

	SD_BUS_METHOD_WITH_ARGS("SetRate",
				SD_BUS_ARGS("u", rate_hz),
				SD_BUS_NO_RESULT,
				method_set_rate,
				SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD_WITH_ARGS("Calibrate",
				SD_BUS_NO_ARGS,
				SD_BUS_NO_RESULT,
				method_calibrate,
				SD_BUS_VTABLE_UNPRIVILEGED),

	SD_BUS_PROPERTY("RateHz", "u", prop_rate, 0,
			SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
	SD_BUS_PROPERTY("ProtocolVersion", "u", prop_protocol, 0,
			SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
	SD_BUS_PROPERTY("FirmwareVersion", "s", prop_firmware, 0,
			SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
	SD_BUS_PROPERTY("FramesDropped", "t", prop_dropped, 0, 0),

	SD_BUS_SIGNAL_WITH_ARGS("SampleReady",
				SD_BUS_ARGS("t", t_us, "ad", accel_g,
					    "ad", gyro_dps),
				0),

	SD_BUS_VTABLE_END
};

/* ---------------------------------------------------------------- startup */

static void hub_close(struct hub *h)
{
	if (h->calibrate_reply_to)
		sd_bus_message_unref(h->calibrate_reply_to);
	if (h->calibrate_timer)
		sd_event_source_unref(h->calibrate_timer);
	if (h->silence_timer)
		sd_event_source_unref(h->silence_timer);
	if (h->bus)
		sd_bus_flush_close_unref(h->bus);
	if (h->event)
		sd_event_unref(h->event);
	if (h->fd >= 0)
		close(h->fd);
	free(h->fw_version);
}

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : DEFAULT_TTY;
	struct hub h;
	sigset_t mask;
	int r;

	memset(&h, 0, sizeof h);
	h.fd = -1;
	h.rate_hz = DEFAULT_RATE;
	/*
	 * Zero until a frame says otherwise. Starting at PROTO_VERSION
	 * would have the property assert what the hub speaks before the
	 * hub has spoken, which is the one moment a client most wants a
	 * truthful answer.
	 */
	h.wire_version = 0;
	h.proto_minor = PROTO_MINOR;
	proto_parser_init(&h.parser);

	r = sd_event_default(&h.event);
	if (r < 0) {
		fprintf(stderr, "sensorhubd: sd_event_default: %s\n",
			strerror(-r));
		goto fail;
	}

	/*
	 * sd-event delivers signals through signalfd, which only works if
	 * the ordinary delivery is blocked first. A NULL handler means
	 * "leave the loop", which is what both of these should do: systemd
	 * sends SIGTERM on stop and on the device going away.
	 */
	sigemptyset(&mask);
	sigaddset(&mask, SIGTERM);
	sigaddset(&mask, SIGINT);
	sigprocmask(SIG_BLOCK, &mask, NULL);
	sd_event_add_signal(h.event, NULL, SIGTERM, NULL, NULL);
	sd_event_add_signal(h.event, NULL, SIGINT, NULL, NULL);

	r = sd_bus_open_system(&h.bus);
	if (r < 0) {
		fprintf(stderr, "sensorhubd: no system bus: %s\n",
			strerror(-r));
		goto fail;
	}

	r = sd_bus_add_object_vtable(h.bus, NULL, OBJ, IFACE, hub_vtable, &h);
	if (r < 0) {
		fprintf(stderr, "sensorhubd: cannot export %s: %s\n", OBJ,
			strerror(-r));
		goto fail;
	}

	/*
	 * The name is requested after the object exists. A client that is
	 * activating this service is already waiting for the name to
	 * appear, and it will call the moment it does; exporting second
	 * would leave a window in which that call finds nothing.
	 */
	r = sd_bus_request_name(h.bus, IFACE, 0);
	if (r < 0) {
		fprintf(stderr, "sensorhubd: cannot own %s: %s\n"
			"Is /usr/share/dbus-1/system.d/%s.conf installed, and "
			"is this process running as the user it names?\n",
			IFACE, strerror(-r), IFACE);
		goto fail;
	}

	r = sd_bus_attach_event(h.bus, h.event, SD_EVENT_PRIORITY_NORMAL);
	if (r < 0)
		goto fail;

	h.fd = tty_open(path);
	if (h.fd < 0) {
		r = h.fd;
		h.fd = -1;
		goto fail;
	}

	r = sd_event_add_io(h.event, NULL, h.fd, EPOLLIN, on_tty_readable, &h);
	if (r < 0)
		goto fail;

	arm_silence_timer(&h);

	fprintf(stderr, SD_INFO "sensorhubd: serving %s on %s from %s\n",
		IFACE, OBJ, path);
	sd_notify(0, "READY=1");

	r = sd_event_loop(h.event);
	sd_notify(0, "STOPPING=1");
	hub_close(&h);
	return r < 0 ? 1 : 0;

fail:
	hub_close(&h);
	return 1;
}
