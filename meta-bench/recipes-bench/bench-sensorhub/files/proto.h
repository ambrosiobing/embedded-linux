/*
 * proto.h - the sensor hub wire protocol, one implementation for both ends.
 *
 * This file and proto.c are compiled twice: into the firmware on the
 * microcontroller and into sensorhubd on Linux. That is the whole point.
 * A protocol described in a document and implemented twice drifts; a
 * protocol implemented once and described in a document cannot.
 *
 * Constraints that shaped the interface, in the order they mattered:
 *
 *   no allocation      the firmware has no heap worth using, and the
 *                      daemon parses untrusted input
 *   no I/O             the caller owns the tty and the DMA engine; this
 *                      file only turns bytes into frames and back
 *   no floating point in the framing layer, only in the payloads that
 *                      need it, so a build without an FPU still links
 *   bounded everywhere every function takes the size of the buffer it
 *                      writes into and refuses rather than truncating
 *
 * The frame layout and the message catalogue are specified in
 * projects/12-sensor-hub/docs/PROTOCOL.md, which is the document this
 * file implements rather than the other way round.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef BENCH_PROTO_H
#define BENCH_PROTO_H

#include <stddef.h>
#include <stdint.h>

#define PROTO_SOF          0xA5u
#define PROTO_VERSION      1u     /* major; see PROTOCOL.md for the rules */
#define PROTO_MINOR        1u

#define PROTO_HEADER_LEN   5u     /* SOF, version, type, length lo, hi */
#define PROTO_CRC_LEN      2u
#define PROTO_MAX_PAYLOAD  512u
#define PROTO_MAX_FRAME    (PROTO_HEADER_LEN + PROTO_MAX_PAYLOAD + PROTO_CRC_LEN)

/* Message types. Hub to Pi below 0x10, Pi to hub from 0x10. */
#define PROTO_HELLO        0x01u
#define PROTO_SAMPLE       0x02u
#define PROTO_ACK          0x03u
#define PROTO_SET_RATE     0x10u
#define PROTO_CALIBRATE    0x11u

/* ACK status codes. */
#define PROTO_ACK_OK       0u
#define PROTO_ACK_RANGE    1u     /* understood, value out of range */
#define PROTO_ACK_BUSY     2u     /* understood, cannot do it now */
#define PROTO_ACK_UNKNOWN  3u     /* message type not understood */

/*
 * CRC-16/CCITT-FALSE: polynomial 0x1021, initial value 0xFFFF, no
 * reflection, no final xor. Its published check value is 0x29B1 for the
 * nine bytes "123456789", which is asserted by the tests on both sides.
 * Named rather than described because "CRC-16" alone identifies at least
 * six different functions.
 */
uint16_t proto_crc16(const uint8_t *data, size_t len);

/*
 * Wrap a payload into a frame. Returns the total frame length, or -1 if
 * the payload is too long or the output buffer is too small.
 */
int proto_frame(uint8_t *out, size_t out_size, uint8_t type,
		const uint8_t *payload, size_t payload_len);

/*
 * CBOR encoders for the five message payloads. Each returns the number of
 * bytes written, or -1 if the buffer is too small. They emit the canonical
 * shortest form for every integer, which keeps a sample at 45 bytes and
 * makes the encoding deterministic enough to compare byte for byte in a
 * test.
 */
int proto_encode_sample(uint8_t *out, size_t out_size, uint64_t t_us,
			const float accel_g[3], const float gyro_dps[3],
			float temp_c);
int proto_encode_hello(uint8_t *out, size_t out_size, uint32_t proto_minor,
		       const char *fw_version, const char *const *sensors,
		       size_t sensor_count);
int proto_encode_ack(uint8_t *out, size_t out_size, uint8_t acked_type,
		     uint8_t status);
int proto_encode_set_rate(uint8_t *out, size_t out_size, uint32_t rate_hz);
int proto_encode_calibrate(uint8_t *out, size_t out_size);

/*
 * The incremental parser.
 *
 * Bytes arrive from a tty in arbitrary chunks, so the parser has to hold a
 * partial frame across reads. It never allocates and never keeps more than
 * one frame.
 *
 * Note what it does NOT do: it does not check the version byte. A frame
 * from a firmware with a different major version is still a well formed
 * frame, and refusing it is a policy decision that belongs to the daemon,
 * which has somewhere to log it and a property to expose it in. A parser
 * that silently dropped those frames would make that failure look like a
 * dead cable.
 */
typedef void (*proto_frame_cb)(void *user, uint8_t version, uint8_t type,
			       const uint8_t *payload, size_t payload_len);

struct proto_parser {
	uint8_t buf[PROTO_MAX_FRAME];
	size_t len;
	uint64_t frames_ok;	/* CRC checked out */
	uint64_t frames_bad;	/* CRC failed, or the length field was absurd */
	uint64_t resyncs;	/* bytes discarded while hunting for a SOF */
};

void proto_parser_init(struct proto_parser *parser);
void proto_parser_push(struct proto_parser *parser, const uint8_t *data,
		       size_t len, proto_frame_cb cb, void *user);

#endif /* BENCH_PROTO_H */
