/*
 * user_ta_header_defines.h - what OP-TEE needs to know before it loads
 * this trusted application.
 *
 * The TA development kit compiles this into a header that is linked into
 * the .ta file, so every value here is fixed at build time and is visible
 * to OP-TEE before a single instruction of the TA runs.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef USER_TA_HEADER_DEFINES_H
#define USER_TA_HEADER_DEFINES_H

#include "bench_keystore_ta.h"

#define TA_UUID BENCH_KEYSTORE_UUID

/*
 * SINGLE_INSTANCE with MULTI_SESSION: one copy of the TA in memory, and
 * several clients may hold sessions to it at once.
 *
 * That combination is the one this design needs and it is worth being
 * explicit about why. The key lives in secure storage rather than in TA
 * memory, and no per-session state exists, so two clients signing at the
 * same time cannot interfere. The alternative, an instance per session,
 * would load and verify the TA binary once per client and multiply the
 * heap by the number of them, for no isolation this design uses.
 *
 * INSTANCE_KEEP_ALIVE is deliberately absent. Without it the instance is
 * destroyed when the last session closes, which means the next signature
 * pays for a TA load. With it the instance would stay resident for ever.
 * The gateway of Project 17 holds one session open for the life of the
 * process, so it pays that cost once either way, and a resident instance
 * on a board with 1 GB is memory spent on a convenience nobody measured.
 */
#define TA_FLAGS (TA_FLAG_SINGLE_INSTANCE | TA_FLAG_MULTI_SESSION)

/*
 * Stack and heap.
 *
 * The heap has to hold two persistent object handles, one transient HMAC
 * key object and one operation state, and the largest of those is the
 * HMAC context. 32 kB is the size the OP-TEE examples use for TAs of this
 * shape and it is a starting figure rather than a measurement: the TA
 * needs to run before anyone knows what it uses. docs/BRINGUP.md has the
 * command that reports it, CFG_WITH_STATS being already y in
 * plat-rpi3/conf.mk, and the journal records the number once it exists.
 *
 * The failure mode for a heap that is too small is TEE_ERROR_OUT_OF_MEMORY
 * from an allocation inside the TEE API, which surfaces in the client as a
 * signing call that fails with no message. That is worth knowing before
 * trimming this number.
 */
#define TA_STACK_SIZE (2 * 1024)
#define TA_DATA_SIZE (32 * 1024)

/* Shown by "xtest --list-ta" and in the OP-TEE log when the TA loads. */
#define TA_CURRENT_TA_EXT_PROPERTIES                                       \
	{ "gp.ta.description", USER_TA_PROP_TYPE_STRING,                   \
	  "bench keystore: HMAC-SHA256 over a message, key never leaves" }, \
	{ "gp.ta.version", USER_TA_PROP_TYPE_U32, &(const uint32_t){ 1 } }

#endif /* USER_TA_HEADER_DEFINES_H */
