/*
 * bench_keystore_ta.h - the contract between the two worlds.
 *
 * One header, included by the trusted application and by the normal-world
 * library, and parsed by the Python binding and by the test suite. The
 * command ids and the parameter layouts live here and nowhere else,
 * because a mismatch between the two sides produces
 * TEE_ERROR_BAD_PARAMETERS with origin TRUSTED_APP, which reads as a bug
 * in the TA and is really a disagreement about a number.
 *
 * tests/keystore-header-test.sh reads this file and checks that the
 * Python binding still agrees with it. That is not paranoia: the binding
 * cannot include a C header, so it restates these values, and a restated
 * value is a value that drifts.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef BENCH_KEYSTORE_TA_H
#define BENCH_KEYSTORE_TA_H

/*
 * 7b53ed98-cbfb-42ec-92b6-fe56e7682c5c
 *
 * Generated once with uuidgen and fixed for ever after: it is the file
 * name of the TA on disk, the key OP-TEE dispatches on, and the value
 * the client asks for by. Changing it means a TA that loads and a client
 * that cannot find it.
 */
#define BENCH_KEYSTORE_UUID                                \
	{                                                  \
		0x7b53ed98, 0xcbfb, 0x42ec,                \
		{                                          \
			0x92, 0xb6, 0xfe, 0x56,            \
			0xe7, 0x68, 0x2c, 0x5c             \
		}                                          \
	}

#define BENCH_KEYSTORE_UUID_STR "7b53ed98-cbfb-42ec-92b6-fe56e7682c5c"

/*
 * Commands. The numbers are part of the contract; the order is not, and
 * a number is never reused for a different meaning even if a command is
 * withdrawn.
 *
 *  GENERATE      no parameters.
 *                Creates the HMAC key. Refuses if one exists, with
 *                TEE_ERROR_ACCESS_CONFLICT, so that a second run of a
 *                provisioning script cannot silently replace a key that
 *                a verifier already holds.
 *
 *  SIGN          p[0] MEMREF_INPUT   the message
 *                p[1] MEMREF_OUTPUT  at least 32 bytes, set to 32 on return
 *                Computes HMAC-SHA256 over p[0] with the stored key.
 *
 *  EXPORT_ONCE   p[0] MEMREF_OUTPUT  at least 32 bytes, set to the key length
 *                Returns the raw key exactly once, then writes a lock
 *                object. Every later call returns TEE_ERROR_ACCESS_DENIED
 *                and returns nothing.
 *
 *  STATUS        p[0] VALUE_OUTPUT
 *                  a = 1 if a key exists, 0 otherwise
 *                  b = 1 if export is locked, 0 otherwise
 *                The only command that is safe to call at any time and
 *                from anything, which is why the LED self-test uses it.
 */
#define BENCH_CMD_GENERATE    0
#define BENCH_CMD_SIGN        1
#define BENCH_CMD_EXPORT_ONCE 2
#define BENCH_CMD_STATUS      3

/* HMAC-SHA256. Both the MAC and the key are 32 bytes, and they are equal
 * by coincidence rather than by rule, so they have separate names.
 */
#define BENCH_MAC_LEN 32
#define BENCH_KEY_LEN 32
#define BENCH_KEY_BITS (BENCH_KEY_LEN * 8)

/*
 * Object identifiers inside TEE_STORAGE_PRIVATE. Two objects, and the
 * second one exists only to be present or absent: its content is never
 * read, so its meaning cannot drift.
 */
#define BENCH_OBJ_KEY  "bench.hmac-key"
#define BENCH_OBJ_LOCK "bench.export-lock"

#endif /* BENCH_KEYSTORE_TA_H */
