/*
 * bench_keystore_ta.c - the trusted application.
 *
 * Four commands, one key, and a rule for each of them that is a policy
 * rather than a mechanism:
 *
 *   generate      never overwrite an existing key
 *   sign          the key is loaded, used and freed without leaving here
 *   export-once   hand the key out exactly once, then refuse for ever
 *   status        say whether a key exists and whether export is locked
 *
 * The policy is what makes this worth testing, and it is modelled in
 * Python in tests/keystore_model.py and exercised by
 * tests/keystore-policy-test.sh. That model is written from the comments
 * in this file rather than from the code below it, so that the two are
 * independent statements of the same rules.
 *
 * What this file cannot do is protect anything on a Raspberry Pi 3. See
 * projects/20-optee-keystore/docs/THREAT-MODEL.md, which is the first
 * document to read and the last word on what this is for.
 *
 * SPDX-License-Identifier: MIT
 */

#include <string.h>
#include <tee_internal_api.h>
#include <tee_internal_api_extensions.h>

#include "bench_keystore_ta.h"

/*
 * Open a persistent object by name. Returns TEE_ERROR_ITEM_NOT_FOUND
 * when it does not exist, which is the answer every one of the four
 * commands is really asking for.
 */
static TEE_Result open_object(const char *id, uint32_t flags,
			      TEE_ObjectHandle *out)
{
	return TEE_OpenPersistentObject(TEE_STORAGE_PRIVATE,
					(void *)id, strlen(id), flags, out);
}

static bool object_exists(const char *id)
{
	TEE_ObjectHandle handle = TEE_HANDLE_NULL;
	TEE_Result res;

	res = open_object(id, TEE_DATA_FLAG_ACCESS_READ, &handle);
	if (res == TEE_SUCCESS) {
		TEE_CloseObject(handle);
		return true;
	}
	return false;
}

/*
 * CMD_GENERATE: create the key, or refuse.
 *
 * The refusal is the point. A provisioning script that is run twice, or
 * a board that is reprovisioned after the verifier already holds the
 * exported key, must not quietly end up with a new key: every record
 * signed afterwards would verify as BAD and the cause would look like a
 * transport fault.
 */
static TEE_Result cmd_generate(uint32_t types)
{
	const uint32_t expect = TEE_PARAM_TYPES(TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE);
	TEE_ObjectHandle key = TEE_HANDLE_NULL;
	TEE_ObjectHandle stored = TEE_HANDLE_NULL;
	TEE_Result res;

	if (types != expect)
		return TEE_ERROR_BAD_PARAMETERS;

	if (object_exists(BENCH_OBJ_KEY))
		return TEE_ERROR_ACCESS_CONFLICT;

	res = TEE_AllocateTransientObject(TEE_TYPE_HMAC_SHA256,
					  BENCH_KEY_BITS, &key);
	if (res != TEE_SUCCESS)
		return res;

	res = TEE_GenerateKey(key, BENCH_KEY_BITS, NULL, 0);
	if (res != TEE_SUCCESS)
		goto out;

	/*
	 * The key material is copied into the persistent object by
	 * TEE_CreatePersistentObject, so the transient one is freed
	 * immediately afterwards and the key exists in exactly one place.
	 */
	res = TEE_CreatePersistentObject(TEE_STORAGE_PRIVATE,
					 (void *)BENCH_OBJ_KEY,
					 strlen(BENCH_OBJ_KEY),
					 TEE_DATA_FLAG_ACCESS_READ |
					 TEE_DATA_FLAG_ACCESS_WRITE_META,
					 key, NULL, 0, &stored);
	if (res == TEE_SUCCESS)
		TEE_CloseObject(stored);

out:
	TEE_FreeTransientObject(key);
	return res;
}

/*
 * CMD_SIGN: HMAC-SHA256 over the input, with the stored key.
 *
 * Every allocation here is freed on every path, including the error
 * ones. A TA leaks into a heap that is a few tens of kilobytes and that
 * outlives the session, so a leak per call is a board that stops signing
 * after some number of records and gives no reason.
 */
static TEE_Result cmd_sign(uint32_t types, TEE_Param params[4])
{
	const uint32_t expect = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
						TEE_PARAM_TYPE_MEMREF_OUTPUT,
						TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE);
	TEE_ObjectHandle key = TEE_HANDLE_NULL;
	TEE_OperationHandle op = TEE_HANDLE_NULL;
	TEE_Result res;

	if (types != expect)
		return TEE_ERROR_BAD_PARAMETERS;
	if (params[1].memref.size < BENCH_MAC_LEN) {
		/*
		 * The caller is told how much it needs. This is the
		 * GlobalPlatform convention for a short output buffer and
		 * it is why the client sets the size before every call
		 * rather than once.
		 */
		params[1].memref.size = BENCH_MAC_LEN;
		return TEE_ERROR_SHORT_BUFFER;
	}

	res = open_object(BENCH_OBJ_KEY, TEE_DATA_FLAG_ACCESS_READ, &key);
	if (res != TEE_SUCCESS)
		return res;

	res = TEE_AllocateOperation(&op, TEE_ALG_HMAC_SHA256, TEE_MODE_MAC,
				    BENCH_KEY_BITS);
	if (res != TEE_SUCCESS)
		goto out_key;

	res = TEE_SetOperationKey(op, key);
	if (res != TEE_SUCCESS)
		goto out_op;

	TEE_MACInit(op, NULL, 0);
	res = TEE_MACComputeFinal(op, params[0].memref.buffer,
				  params[0].memref.size,
				  params[1].memref.buffer,
				  &params[1].memref.size);

out_op:
	TEE_FreeOperation(op);
out_key:
	TEE_CloseObject(key);
	return res;
}

/*
 * CMD_EXPORT_ONCE: the deliberate hole, and the lock that closes it.
 *
 * HMAC is symmetric, so the verifier needs the same secret. Rather than
 * generating the key somewhere else and installing it, the key is born
 * here and leaves exactly once, through a command that can be audited in
 * one place and that cannot be persuaded to run again.
 *
 * The lock is written *after* the key has been copied out, deliberately.
 * The other order loses the key on any failure between the two steps: a
 * board would be locked with nothing exported, and the only recovery is
 * to delete the storage and start again, which invalidates every record
 * already signed.
 */
static TEE_Result cmd_export_once(uint32_t types, TEE_Param params[4])
{
	const uint32_t expect = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_OUTPUT,
						TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE);
	TEE_ObjectHandle key = TEE_HANDLE_NULL;
	TEE_ObjectHandle lock = TEE_HANDLE_NULL;
	uint32_t size;
	TEE_Result res;

	if (types != expect)
		return TEE_ERROR_BAD_PARAMETERS;

	if (object_exists(BENCH_OBJ_LOCK))
		return TEE_ERROR_ACCESS_DENIED;

	if (params[0].memref.size < BENCH_KEY_LEN) {
		params[0].memref.size = BENCH_KEY_LEN;
		return TEE_ERROR_SHORT_BUFFER;
	}

	res = open_object(BENCH_OBJ_KEY, TEE_DATA_FLAG_ACCESS_READ, &key);
	if (res != TEE_SUCCESS)
		return res;

	size = params[0].memref.size;
	res = TEE_GetObjectBufferAttribute(key, TEE_ATTR_SECRET_VALUE,
					   params[0].memref.buffer, &size);
	TEE_CloseObject(key);
	if (res != TEE_SUCCESS)
		return res;
	params[0].memref.size = size;

	/*
	 * The lock object carries one byte and nobody ever reads it. Its
	 * content cannot drift because its content has no meaning; only
	 * its existence does.
	 */
	{
		const uint8_t marker = 1;

		res = TEE_CreatePersistentObject(TEE_STORAGE_PRIVATE,
						 (void *)BENCH_OBJ_LOCK,
						 strlen(BENCH_OBJ_LOCK),
						 TEE_DATA_FLAG_ACCESS_READ |
						 TEE_DATA_FLAG_ACCESS_WRITE_META,
						 TEE_HANDLE_NULL,
						 &marker, sizeof(marker),
						 &lock);
	}
	if (res == TEE_SUCCESS)
		TEE_CloseObject(lock);

	/*
	 * If the lock could not be written the key has already been
	 * copied into the caller's buffer, and saying TEE_SUCCESS would
	 * claim a lock that does not exist. Report the failure: the
	 * caller then knows the key is out and the board is not locked,
	 * which is a state a person has to resolve.
	 */
	return res;
}

static TEE_Result cmd_status(uint32_t types, TEE_Param params[4])
{
	const uint32_t expect = TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_OUTPUT,
						TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE,
						TEE_PARAM_TYPE_NONE);

	if (types != expect)
		return TEE_ERROR_BAD_PARAMETERS;

	params[0].value.a = object_exists(BENCH_OBJ_KEY) ? 1 : 0;
	params[0].value.b = object_exists(BENCH_OBJ_LOCK) ? 1 : 0;
	return TEE_SUCCESS;
}

/* ---------------------------------------------------------------- entry */

TEE_Result TA_CreateEntryPoint(void)
{
	return TEE_SUCCESS;
}

void TA_DestroyEntryPoint(void)
{
}

TEE_Result TA_OpenSessionEntryPoint(uint32_t types, TEE_Param params[4],
				    void **session)
{
	(void)types;
	(void)params;
	(void)session;

	/*
	 * No per-session state, which is why the parameter types are not
	 * checked here: nothing is done with them. A TA that keeps state
	 * per session would allocate it here and free it below, and would
	 * have to decide what two sessions from two processes mean.
	 */
	return TEE_SUCCESS;
}

void TA_CloseSessionEntryPoint(void *session)
{
	(void)session;
}

TEE_Result TA_InvokeCommandEntryPoint(void *session, uint32_t cmd,
				      uint32_t types, TEE_Param params[4])
{
	(void)session;

	switch (cmd) {
	case BENCH_CMD_GENERATE:
		return cmd_generate(types);
	case BENCH_CMD_SIGN:
		return cmd_sign(types, params);
	case BENCH_CMD_EXPORT_ONCE:
		return cmd_export_once(types, params);
	case BENCH_CMD_STATUS:
		return cmd_status(types, params);
	default:
		return TEE_ERROR_NOT_SUPPORTED;
	}
}
