/*
 * benchkey.c - the normal-world half, over the TEE Client API.
 *
 * Five TEEC calls do all of it: InitializeContext, OpenSession,
 * InvokeCommand, CloseSession, FinalizeContext. Everything else in this
 * file is parameter marshalling and the discipline of reporting which
 * layer said no.
 *
 * One process, one context, one session, held for the life of the
 * process. The state is file-static rather than in a handle the caller
 * passes around, and that is a real limitation stated rather than hidden:
 * a program that wanted two sessions to two TAs could not use this
 * library. Nothing on this bench wants that, and the alternative is a
 * handle in every signature for a case that does not exist.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <tee_client_api.h>

#include "benchkey.h"
#include "bench_keystore_ta.h"

static TEEC_Context ctx;
static TEEC_Session sess;
static int session_open;

static uint32_t last_result;
static uint32_t last_origin;

uint32_t benchkey_last_result(void)
{
	return last_result;
}

uint32_t benchkey_last_origin(void)
{
	return last_origin;
}

const char *benchkey_origin_name(uint32_t origin)
{
	switch (origin) {
	case TEEC_ORIGIN_API:
		return "API (libteec, before the call left this process)";
	case TEEC_ORIGIN_COMMS:
		return "COMMS (the driver or the SMC path)";
	case TEEC_ORIGIN_TEE:
		return "TEE (OP-TEE OS: loading, signature, dispatch)";
	case TEEC_ORIGIN_TRUSTED_APP:
		return "TRUSTED_APP (the TA ran and returned this)";
	default:
		return "unknown";
	}
}

int benchkey_open(void)
{
	const TEEC_UUID uuid = BENCH_KEYSTORE_UUID;
	TEEC_Result res;

	if (session_open)
		return BENCHKEY_OK;

	last_result = 0;
	last_origin = 0;

	res = TEEC_InitializeContext(NULL, &ctx);
	if (res != TEEC_SUCCESS) {
		/*
		 * There is no origin for this one: the context does not
		 * exist yet, so nothing could have told us where the
		 * failure was. It is almost always /dev/tee0 missing,
		 * which is the boot chain rather than the TEE.
		 */
		last_result = res;
		last_origin = TEEC_ORIGIN_API;
		return BENCHKEY_ERR_TEE;
	}

	res = TEEC_OpenSession(&ctx, &sess, &uuid, TEEC_LOGIN_PUBLIC,
			       NULL, NULL, &last_origin);
	if (res != TEEC_SUCCESS) {
		last_result = res;
		TEEC_FinalizeContext(&ctx);
		return BENCHKEY_ERR_TEE;
	}

	session_open = 1;
	return BENCHKEY_OK;
}

void benchkey_close(void)
{
	if (!session_open)
		return;
	TEEC_CloseSession(&sess);
	TEEC_FinalizeContext(&ctx);
	session_open = 0;
}

static int invoke(uint32_t cmd, TEEC_Operation *op)
{
	TEEC_Result res;

	if (!session_open)
		return BENCHKEY_ERR_NOT_OPEN;

	res = TEEC_InvokeCommand(&sess, cmd, op, &last_origin);
	last_result = res;
	return res == TEEC_SUCCESS ? BENCHKEY_OK : BENCHKEY_ERR_TEE;
}

int benchkey_generate(void)
{
	TEEC_Operation op;

	memset(&op, 0, sizeof(op));
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_NONE, TEEC_NONE,
					 TEEC_NONE, TEEC_NONE);
	return invoke(BENCH_CMD_GENERATE, &op);
}

int benchkey_sign(const void *msg, size_t len, uint8_t *mac, size_t mac_len)
{
	TEEC_Operation op;

	if (!msg || !mac || mac_len < BENCH_MAC_LEN)
		return BENCHKEY_ERR_ARGS;

	memset(&op, 0, sizeof(op));
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_INPUT,
					 TEEC_MEMREF_TEMP_OUTPUT,
					 TEEC_NONE, TEEC_NONE);
	/*
	 * A cast away from const, which libteec's own examples also do:
	 * the structure has one buffer field and it is not const-qualified
	 * even for an input reference. The TA declares the parameter
	 * MEMREF_INPUT, and OP-TEE enforces that, so the constness is lost
	 * in the type and kept in the protocol.
	 */
	op.params[0].tmpref.buffer = (void *)msg;
	op.params[0].tmpref.size = len;
	op.params[1].tmpref.buffer = mac;
	/*
	 * Set on every call, not once. The TA writes the produced length
	 * back into this field, and on TEE_ERROR_SHORT_BUFFER it writes
	 * the required length, so a caller that set it once would be
	 * passing the previous answer as the next request.
	 */
	op.params[1].tmpref.size = mac_len;

	return invoke(BENCH_CMD_SIGN, &op);
}

int benchkey_export_once(uint8_t *key, size_t key_len, size_t *out_len)
{
	TEEC_Operation op;
	int rc;

	if (!key || key_len < BENCH_KEY_LEN)
		return BENCHKEY_ERR_ARGS;

	memset(&op, 0, sizeof(op));
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE,
					 TEEC_NONE, TEEC_NONE);
	op.params[0].tmpref.buffer = key;
	op.params[0].tmpref.size = key_len;

	rc = invoke(BENCH_CMD_EXPORT_ONCE, &op);
	if (rc == BENCHKEY_OK && out_len)
		*out_len = op.params[0].tmpref.size;
	return rc;
}

/*
 * One datagram, best effort, never blocking.
 *
 * SOCK_DGRAM rather than SOCK_STREAM is the whole design. A stream
 * socket would need a connect(), which blocks when the listener's
 * backlog is full, and a connected peer that dies gives EPIPE and a
 * SIGPIPE to deal with. A datagram to a path with no socket fails
 * immediately with ENOENT, and that is the common case on a board with
 * no LEDs wired.
 *
 * SOCK_NONBLOCK on top of that covers the remaining case: a listener
 * that exists and is not reading. sendto then returns EAGAIN rather than
 * waiting, so a wedged LED daemon cannot slow down signing.
 *
 * Every return value is ignored on purpose, which is the one place in
 * this file where that is the right thing to do.
 */
void benchkey_notify(char event)
{
	struct sockaddr_un addr;
	int fd;

	fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return;

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, BENCHKEY_LED_SOCKET, sizeof(addr.sun_path) - 1);

	(void)sendto(fd, &event, 1, 0, (struct sockaddr *)&addr, sizeof(addr));
	close(fd);
}

int benchkey_status(int *has_key, int *locked)
{
	TEEC_Operation op;
	int rc;

	memset(&op, 0, sizeof(op));
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_OUTPUT, TEEC_NONE,
					 TEEC_NONE, TEEC_NONE);

	rc = invoke(BENCH_CMD_STATUS, &op);
	if (rc != BENCHKEY_OK)
		return rc;

	if (has_key)
		*has_key = op.params[0].value.a ? 1 : 0;
	if (locked)
		*locked = op.params[0].value.b ? 1 : 0;
	return BENCHKEY_OK;
}
