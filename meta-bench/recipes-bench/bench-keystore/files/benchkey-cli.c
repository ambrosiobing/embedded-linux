/*
 * benchkey-cli.c - the four commands, from a shell.
 *
 *   benchkey generate
 *   benchkey sign FILE          hex MAC on stdout, or - for stdin
 *   benchkey export-once        hex key on stdout, exactly once ever
 *   benchkey status             key: yes/no  locked: yes/no
 *
 * Installed as /usr/bin/benchkey. Every failure prints the TEE result and
 * its origin, because those two together are the only thing that says
 * which half of the board refused.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "benchkey.h"
#include "bench_keystore_ta.h"

/* 1 MiB. A signed record is a few hundred bytes; this is a limit chosen
 * so that "benchkey sign /dev/zero" ends rather than filling memory.
 */
#define MAX_INPUT (1024 * 1024)

static void print_hex(const uint8_t *buf, size_t len)
{
	size_t i;

	for (i = 0; i < len; i++)
		printf("%02x", buf[i]);
	printf("\n");
}

static void report(const char *what)
{
	uint32_t result = benchkey_last_result();
	uint32_t origin = benchkey_last_origin();

	fprintf(stderr, "benchkey: %s failed: 0x%08x, origin %s\n",
		what, result, benchkey_origin_name(origin));

	/*
	 * The four results worth translating, because each one sends you to
	 * a different place and the numbers are not memorable.
	 *
	 * The values are from lib/libutee/include/tee_api_defines.h in
	 * optee_os, read rather than recalled. The first version of this
	 * table had ACCESS_CONFLICT as 0xffff000c, which is
	 * TEE_ERROR_OUT_OF_MEMORY: a full TA heap would have been reported
	 * as "a key already exists", which is a wrong diagnosis pointing at
	 * a wrong fix, and the real conflict would have printed nothing.
	 */
	switch (result) {
	case 0xffff0001: /* TEE_ERROR_ACCESS_DENIED */
		fprintf(stderr, "  the export lock is set: this device has "
				"already exported its key, once.\n");
		break;
	case 0xffff0003: /* TEE_ERROR_ACCESS_CONFLICT */
		fprintf(stderr, "  a key already exists, and this command "
				"will not replace one.\n");
		break;
	case 0xffff0008: /* TEE_ERROR_ITEM_NOT_FOUND */
		if (origin == 2 /* TEEC_ORIGIN_TEE */)
			fprintf(stderr, "  OP-TEE could not load the TA. Is "
					"%s.ta in /lib/optee_armtz, and is "
					"tee-supplicant running?\n",
				BENCH_KEYSTORE_UUID_STR);
		else
			fprintf(stderr, "  no key. Run: benchkey generate\n");
		break;
	case 0xffff000c: /* TEE_ERROR_OUT_OF_MEMORY */
		fprintf(stderr, "  the TA ran out of heap. TA_DATA_SIZE in "
				"user_ta_header_defines.h is the number to "
				"raise.\n");
		break;
	default:
		break;
	}
}

static int read_all(const char *path, uint8_t **out, size_t *out_len)
{
	FILE *fh = strcmp(path, "-") ? fopen(path, "rb") : stdin;
	uint8_t *buf;
	size_t len;

	if (!fh) {
		fprintf(stderr, "benchkey: cannot open %s\n", path);
		return -1;
	}

	buf = malloc(MAX_INPUT);
	if (!buf) {
		if (fh != stdin)
			fclose(fh);
		return -1;
	}

	len = fread(buf, 1, MAX_INPUT, fh);
	if (fh != stdin)
		fclose(fh);

	*out = buf;
	*out_len = len;
	return 0;
}

static int do_sign(const char *path)
{
	uint8_t mac[BENCH_MAC_LEN];
	uint8_t *msg = NULL;
	size_t len = 0;
	int rc;

	if (read_all(path, &msg, &len))
		return 1;

	rc = benchkey_sign(msg, len, mac, sizeof(mac));
	free(msg);
	if (rc) {
		report("sign");
		benchkey_notify(BENCHKEY_EVENT_ERROR);
		return 1;
	}

	benchkey_notify(BENCHKEY_EVENT_SIGNED);
	print_hex(mac, sizeof(mac));
	return 0;
}

static int do_export_once(void)
{
	uint8_t key[BENCH_KEY_LEN];
	size_t len = 0;

	if (benchkey_export_once(key, sizeof(key), &len)) {
		report("export-once");
		benchkey_notify(BENCHKEY_EVENT_ERROR);
		return 1;
	}

	/*
	 * On stdout, and only here. The provisioning procedure redirects
	 * this into the verifier's key file on the console, and the
	 * warning goes to stderr so that the redirect stays clean.
	 */
	fprintf(stderr, "benchkey: this is the only time this key can be "
			"read. Keep it, or the device has to be reprovisioned "
			"and every record it already signed becomes "
			"unverifiable.\n");
	print_hex(key, len);
	return 0;
}

static int do_status(void)
{
	int has_key = 0;
	int locked = 0;

	if (benchkey_status(&has_key, &locked)) {
		report("status");
		return 1;
	}

	printf("key: %s\n", has_key ? "yes" : "no");
	printf("locked: %s\n", locked ? "yes" : "no");

	/*
	 * A key that exists and is not locked is a device half way
	 * through provisioning, which is a state that should not survive
	 * the bench. Saying so costs one line and saves the reading.
	 */
	if (has_key && !locked)
		printf("note: provisioned but not locked; the key can still "
		       "be exported\n");
	return 0;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: benchkey generate | sign FILE | export-once | status\n"
		"\n"
		"  FILE may be - for standard input.\n"
		"  The TA is %s\n",
		BENCH_KEYSTORE_UUID_STR);
}

int main(int argc, char **argv)
{
	int rc;

	if (argc < 2) {
		usage();
		return 2;
	}

	if (benchkey_open()) {
		report("open");
		benchkey_notify(BENCHKEY_EVENT_ERROR);
		return 1;
	}

	if (!strcmp(argv[1], "generate")) {
		rc = benchkey_generate();
		if (rc) {
			report("generate");
			benchkey_notify(BENCHKEY_EVENT_ERROR);
			rc = 1;
		} else {
			printf("key generated\n");
		}
	} else if (!strcmp(argv[1], "sign")) {
		if (argc < 3) {
			usage();
			rc = 2;
		} else {
			rc = do_sign(argv[2]);
		}
	} else if (!strcmp(argv[1], "export-once")) {
		rc = do_export_once();
	} else if (!strcmp(argv[1], "status")) {
		rc = do_status();
	} else {
		usage();
		rc = 2;
	}

	benchkey_close();
	return rc;
}
