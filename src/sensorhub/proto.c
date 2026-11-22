/*
 * proto.c - framing, CRC and CBOR encoding for the sensor hub protocol.
 *
 * Compiled into the firmware and into sensorhubd. See proto.h for the
 * constraints and projects/12-sensor-hub/docs/PROTOCOL.md for the format.
 *
 * On encoding by hand rather than with a library, which is the one choice
 * here that looks lazy and is not:
 *
 * The five payloads are fixed in shape. A sample is always a four entry
 * map with integer keys, two three element arrays and two scalars. Writing
 * that out is forty lines with no dependency, no allocation and no code
 * size worth measuring, which matters on a part where tinycbor is a
 * noticeable fraction of the image.
 *
 * Decoding is the opposite case and is deliberately not done here.
 * Incoming bytes are untrusted, of unknown shape, and the daemon that
 * parses them runs on the system bus. That is a job for a hardened
 * library, so sensorhubd links libcbor. The asymmetry is the point:
 * encode a known shape by hand, decode an unknown one with a parser
 * somebody else has already fuzzed.
 *
 * SPDX-License-Identifier: MIT
 */

#include "proto.h"

#include <string.h>

uint16_t proto_crc16(const uint8_t *data, size_t len)
{
	uint16_t crc = 0xFFFFu;
	size_t i;
	int bit;

	for (i = 0; i < len; i++) {
		crc ^= (uint16_t)((uint16_t)data[i] << 8);
		for (bit = 0; bit < 8; bit++) {
			if (crc & 0x8000u)
				crc = (uint16_t)((uint16_t)(crc << 1) ^ 0x1021u);
			else
				crc = (uint16_t)(crc << 1);
		}
	}
	return crc;
}

int proto_frame(uint8_t *out, size_t out_size, uint8_t type,
		const uint8_t *payload, size_t payload_len)
{
	size_t total;
	uint16_t crc;

	if (payload_len > PROTO_MAX_PAYLOAD)
		return -1;
	total = PROTO_HEADER_LEN + payload_len + PROTO_CRC_LEN;
	if (out_size < total)
		return -1;

	out[0] = (uint8_t)PROTO_SOF;
	out[1] = (uint8_t)PROTO_VERSION;
	out[2] = type;
	out[3] = (uint8_t)(payload_len & 0xFFu);
	out[4] = (uint8_t)((payload_len >> 8) & 0xFFu);
	if (payload_len && payload)
		memcpy(out + PROTO_HEADER_LEN, payload, payload_len);

	/*
	 * The CRC covers everything except the SOF: bytes 1 to 4+n. The SOF
	 * is excluded on purpose. It is the resynchronisation marker, and a
	 * receiver that has just found one has not yet decided whether this
	 * is a frame, so it cannot be part of what proves that it is.
	 */
	crc = proto_crc16(out + 1, PROTO_HEADER_LEN - 1 + payload_len);
	out[total - 2] = (uint8_t)(crc & 0xFFu);
	out[total - 1] = (uint8_t)((crc >> 8) & 0xFFu);
	return (int)total;
}

/* ------------------------------------------------------------ CBOR out */

struct writer {
	uint8_t *buf;
	size_t size;
	size_t used;
	int overflow;
};

static void w_byte(struct writer *w, uint8_t b)
{
	if (w->used >= w->size) {
		w->overflow = 1;
		return;
	}
	w->buf[w->used++] = b;
}

static void w_bytes(struct writer *w, const uint8_t *p, size_t n)
{
	size_t i;

	for (i = 0; i < n; i++)
		w_byte(w, p[i]);
}

/*
 * A CBOR head is a three bit major type and a five bit argument. Values
 * below 24 live in the argument itself; larger ones spill into one, two,
 * four or eight following bytes, big endian. Always choosing the shortest
 * form is what RFC 8949 calls the preferred serialisation, and it is what
 * makes two independent encoders produce identical bytes, which is what
 * the cross-implementation test compares.
 */
static void w_head(struct writer *w, uint8_t major, uint64_t arg)
{
	uint8_t m = (uint8_t)(major << 5);
	int i;

	if (arg < 24u) {
		w_byte(w, (uint8_t)(m | (uint8_t)arg));
	} else if (arg <= 0xFFu) {
		w_byte(w, (uint8_t)(m | 24u));
		w_byte(w, (uint8_t)arg);
	} else if (arg <= 0xFFFFu) {
		w_byte(w, (uint8_t)(m | 25u));
		for (i = 1; i >= 0; i--)
			w_byte(w, (uint8_t)((arg >> (8 * i)) & 0xFFu));
	} else if (arg <= 0xFFFFFFFFu) {
		w_byte(w, (uint8_t)(m | 26u));
		for (i = 3; i >= 0; i--)
			w_byte(w, (uint8_t)((arg >> (8 * i)) & 0xFFu));
	} else {
		w_byte(w, (uint8_t)(m | 27u));
		for (i = 7; i >= 0; i--)
			w_byte(w, (uint8_t)((arg >> (8 * i)) & 0xFFu));
	}
}

static void w_uint(struct writer *w, uint64_t v)
{
	w_head(w, 0u, v);
}

static void w_array(struct writer *w, size_t n)
{
	w_head(w, 4u, (uint64_t)n);
}

static void w_map(struct writer *w, size_t n)
{
	w_head(w, 5u, (uint64_t)n);
}

static void w_text(struct writer *w, const char *s)
{
	size_t n = strlen(s);

	w_head(w, 3u, (uint64_t)n);
	w_bytes(w, (const uint8_t *)s, n);
}

/*
 * Single precision, major type 7 with argument 26, four bytes big endian.
 * float32 rather than float64 because the sensor delivers 16 bit raw
 * counts: a double would carry eleven digits of precision the instrument
 * does not have, at twice the bytes on a wire that has a budget.
 *
 * memcpy rather than a union or a cast through uint32_t *. Type punning
 * through a pointer is undefined and gcc does miscompile it at -O2 with
 * strict aliasing on; memcpy of four bytes compiles to the same single
 * instruction and is defined.
 */
static void w_float(struct writer *w, float value)
{
	uint32_t bits;
	int i;

	memcpy(&bits, &value, sizeof bits);
	w_byte(w, (uint8_t)((7u << 5) | 26u));
	for (i = 3; i >= 0; i--)
		w_byte(w, (uint8_t)((bits >> (8 * i)) & 0xFFu));
}

static int w_finish(const struct writer *w)
{
	return w->overflow ? -1 : (int)w->used;
}

int proto_encode_sample(uint8_t *out, size_t out_size, uint64_t t_us,
			const float accel_g[3], const float gyro_dps[3],
			float temp_c)
{
	struct writer w = { out, out_size, 0, 0 };
	int i;

	w_map(&w, 4);
	w_uint(&w, 0); w_uint(&w, t_us);
	w_uint(&w, 1); w_array(&w, 3);
	for (i = 0; i < 3; i++)
		w_float(&w, accel_g[i]);
	w_uint(&w, 2); w_array(&w, 3);
	for (i = 0; i < 3; i++)
		w_float(&w, gyro_dps[i]);
	w_uint(&w, 3); w_float(&w, temp_c);
	return w_finish(&w);
}

int proto_encode_hello(uint8_t *out, size_t out_size, uint32_t proto_minor,
		       const char *fw_version, const char *const *sensors,
		       size_t sensor_count)
{
	struct writer w = { out, out_size, 0, 0 };
	size_t i;

	w_map(&w, 3);
	w_uint(&w, 0); w_uint(&w, proto_minor);
	w_uint(&w, 1); w_text(&w, fw_version);
	w_uint(&w, 2); w_array(&w, sensor_count);
	for (i = 0; i < sensor_count; i++)
		w_text(&w, sensors[i]);
	return w_finish(&w);
}

int proto_encode_ack(uint8_t *out, size_t out_size, uint8_t acked_type,
		     uint8_t status)
{
	struct writer w = { out, out_size, 0, 0 };

	w_map(&w, 2);
	w_uint(&w, 0); w_uint(&w, acked_type);
	w_uint(&w, 1); w_uint(&w, status);
	return w_finish(&w);
}

int proto_encode_set_rate(uint8_t *out, size_t out_size, uint32_t rate_hz)
{
	struct writer w = { out, out_size, 0, 0 };

	w_map(&w, 1);
	w_uint(&w, 0); w_uint(&w, rate_hz);
	return w_finish(&w);
}

int proto_encode_calibrate(uint8_t *out, size_t out_size)
{
	struct writer w = { out, out_size, 0, 0 };

	w_map(&w, 0);
	return w_finish(&w);
}

/* ------------------------------------------------------------- parsing */

void proto_parser_init(struct proto_parser *parser)
{
	memset(parser, 0, sizeof *parser);
}

/* Drop the first byte and keep hunting. */
static void drop_one(struct proto_parser *p)
{
	if (p->len > 1)
		memmove(p->buf, p->buf + 1, p->len - 1);
	if (p->len)
		p->len--;
}

void proto_parser_push(struct proto_parser *parser, const uint8_t *data,
		       size_t len, proto_frame_cb cb, void *user)
{
	size_t i;

	for (i = 0; i < len; i++) {
		if (parser->len >= sizeof parser->buf) {
			/*
			 * Cannot happen: the loop below never lets the
			 * buffer grow past one complete frame. Handled
			 * anyway, because "cannot happen" in a parser that
			 * reads a wire is a sentence with a poor record.
			 */
			parser->len = 0;
		}
		parser->buf[parser->len++] = data[i];

		for (;;) {
			size_t payload_len, total;
			uint16_t want, got;

			if (parser->len == 0)
				break;

			if (parser->buf[0] != PROTO_SOF) {
				parser->resyncs++;
				drop_one(parser);
				continue;
			}
			if (parser->len < PROTO_HEADER_LEN)
				break;

			payload_len = (size_t)parser->buf[3] |
				      ((size_t)parser->buf[4] << 8);
			if (payload_len > PROTO_MAX_PAYLOAD) {
				/*
				 * A length this large is either corruption or
				 * a byte that only looked like a SOF. Either
				 * way the frame is lost, and the next attempt
				 * has to start at the byte after this one
				 * rather than skipping a length that cannot
				 * be trusted.
				 */
				parser->frames_bad++;
				drop_one(parser);
				continue;
			}

			total = PROTO_HEADER_LEN + payload_len + PROTO_CRC_LEN;
			if (parser->len < total)
				break;

			want = (uint16_t)parser->buf[total - 2] |
			       (uint16_t)((uint16_t)parser->buf[total - 1] << 8);
			got = proto_crc16(parser->buf + 1,
					  PROTO_HEADER_LEN - 1 + payload_len);
			if (want == got) {
				parser->frames_ok++;
				if (cb)
					cb(user, parser->buf[1], parser->buf[2],
					   parser->buf + PROTO_HEADER_LEN,
					   payload_len);
				if (parser->len > total)
					memmove(parser->buf,
						parser->buf + total,
						parser->len - total);
				parser->len -= total;
				continue;
			}

			/*
			 * Same reasoning as the length case, and the same
			 * one byte step. Skipping the claimed length here
			 * would be trusting a header that has just failed
			 * its own integrity check, and it is how a receiver
			 * ends up permanently one frame out of step after a
			 * single dropped byte.
			 */
			parser->frames_bad++;
			drop_one(parser);
		}
	}
}
