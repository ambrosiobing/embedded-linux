/*
 * benchkey.h - the normal-world API, four calls wide.
 *
 * Wraps the TEE Client API so that a caller needs to know about neither
 * TEEC_Operation nor parameter types. The ctypes binding in benchkey.py
 * calls exactly these symbols, so this header is also the contract with
 * the Python side.
 *
 * Every function returns 0 on success and a negative number on failure,
 * with the exception noted on benchkey_last_origin(): a TEE error is not
 * an errno and the two must not be confused by a caller that prints
 * strerror() on it.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef BENCHKEY_H
#define BENCHKEY_H

#include <stddef.h>
#include <stdint.h>

#define BENCHKEY_OK               0
#define BENCHKEY_ERR_NOT_OPEN    -1
#define BENCHKEY_ERR_TEE         -2
#define BENCHKEY_ERR_ARGS        -3

/*
 * Open a context and a session, and keep both.
 *
 * Held open deliberately. Every TEEC_OpenSession costs a TA load through
 * tee-supplicant, which is a file read and a signature check; holding the
 * session makes the per-signature cost one SMC round trip instead. A
 * process that signs once should still call this, because the cost is
 * the same either way and the error handling is in one place.
 */
int benchkey_open(void);

void benchkey_close(void);

/* HMAC-SHA256 over msg, into mac. mac must have room for 32 bytes. */
int benchkey_sign(const void *msg, size_t len, uint8_t *mac, size_t mac_len);

/* Create the key. Fails if one exists; see the TA for why that matters. */
int benchkey_generate(void);

/*
 * Export the key, exactly once in the life of the device. Fails with
 * BENCHKEY_ERR_TEE afterwards, and benchkey_last_result() is then
 * TEE_ERROR_ACCESS_DENIED, 0xffff0001.
 */
int benchkey_export_once(uint8_t *key, size_t key_len, size_t *out_len);

/* has_key and locked are set to 0 or 1. */
int benchkey_status(int *has_key, int *locked);

/*
 * The last TEE result and where it came from.
 *
 * origin is the part people forget, and it is the difference between
 * "the TA said no" and "the TA was never reached". TEEC_ORIGIN_TEE with
 * TEEC_ERROR_ITEM_NOT_FOUND is a missing or unsigned .ta file;
 * TEEC_ORIGIN_TRUSTED_APP with the same number would be the TA saying it
 * has no key. Same value, different half of the board.
 */
uint32_t benchkey_last_result(void);
uint32_t benchkey_last_origin(void);
const char *benchkey_origin_name(uint32_t origin);

/*
 * Tell the LED daemon that something happened. 'S' for a signature, 'E'
 * for an error.
 *
 * This cannot fail, cannot block, and returns nothing, and all three are
 * requirements rather than conveniences. It is a datagram to an AF_UNIX
 * path: sendto() on a SOCK_DGRAM socket to a path with no listener
 * returns ENOENT immediately rather than blocking, and a full receive
 * queue gives EAGAIN rather than waiting. So a dead LED daemon, a
 * missing socket and a wrongly wired board all cost one failed syscall.
 *
 * It is a separate call rather than something the signing path does by
 * itself, because a library that opens sockets behind the caller's back
 * is a library that surprises a caller who is holding a lock. The CLI
 * and the Python binding call it; the gateway of Project 17 can choose
 * not to.
 */
#define BENCHKEY_LED_SOCKET "/run/benchkey-leds.sock"
#define BENCHKEY_EVENT_SIGNED 'S'
#define BENCHKEY_EVENT_ERROR 'E'

void benchkey_notify(char event);

#endif /* BENCHKEY_H */
