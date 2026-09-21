/* SPDX-License-Identifier: MIT
 *
 * Test harness for metrics.c. Not shipped, not in any recipe.
 *
 * metrics.c is the only part of the HMI that can run without a
 * compositor, a GPU or a panel, because every function in it is a pure
 * read of a file and every path goes through a prefix that
 * BENCH_METRICS_ROOT can redirect. This harness is what turns that
 * property into a test: it prints the four readings in a form a shell
 * script can assert on, and nothing else.
 *
 * Output is one "key=value" per line, deliberately flat, so that the
 * test reads it with grep rather than with a parser that could itself
 * be wrong.
 *
 * Doubles are printed with %.3f rather than compared as floats in the
 * shell. The readers return -1.0 for a failed read, so the test looks
 * for exactly "-1.000" and there is no epsilon anywhere.
 */

#include "metrics.h"

#include <stdio.h>

int main(void)
{
	char word[BENCH_STATE_MAX];
	bench_state_t state;
	const char *root;
	const char *name;

	root = metrics_set_root_from_env();
	printf("root=%s\n", root && *root ? root : "(none)");

	printf("load=%.3f\n", metrics_loadavg());
	printf("temp=%.3f\n", metrics_soc_temp_c());
	printf("mem=%.3f\n", metrics_mem_used_percent());

	state = metrics_bench_state(word, sizeof word);
	switch (state) {
	case BENCH_STATE_OK:
		name = "OK";
		break;
	case BENCH_STATE_STARTING:
		name = "STARTING";
		break;
	case BENCH_STATE_FAILED:
		name = "FAILED";
		break;
	default:
		name = "UNKNOWN";
		break;
	}
	printf("state=%s\n", name);
	printf("word=%s\n", word);

	return 0;
}
