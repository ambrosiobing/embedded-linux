/* SPDX-License-Identifier: MIT
 *
 * The numbers behind the dashboard. See metrics.h for why this is a
 * separate module: it is the only part of the HMI that can be tested
 * without a panel, a compositor or a GPU.
 *
 * Two decisions run through the whole file.
 *
 * A FAILED READ RETURNS -1, NOT ZERO. Every reader here can fail, and
 * for three of the four a zero is a perfectly plausible reading: load
 * 0.00 is an idle board, 0 percent memory is nonsense but looks like a
 * number, and only the temperature is obviously wrong at 0. A dashboard
 * that prints 0.00 for a file it could not open is not degraded, it is
 * lying, and the reader has no way to tell. The widgets render -1 as
 * "n/a".
 *
 * EVERY PATH GOES THROUGH prefix_path(). In production the prefix is
 * empty and the paths are the absolute ones you would expect. Under the
 * test suite it points at a directory of fake files. That indirection is
 * the entire reason this module has a test at all, and it costs one
 * function.
 */

#include "metrics.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Long enough for any of the paths below under a test root. */
#define PATH_MAX_LEN 512

static char metrics_root[PATH_MAX_LEN] = "";

const char *metrics_set_root_from_env(void)
{
	const char *env = getenv("BENCH_METRICS_ROOT");

	if (env && *env) {
		snprintf(metrics_root, sizeof metrics_root, "%s", env);
	} else {
		metrics_root[0] = '\0';
	}
	return metrics_root;
}

static const char *prefix_path(const char *path, char *buf, unsigned long size)
{
	if (metrics_root[0] == '\0')
		return path;

	snprintf(buf, size, "%s%s", metrics_root, path);
	return buf;
}

double metrics_loadavg(void)
{
	char buf[PATH_MAX_LEN];
	const char *path = prefix_path("/proc/loadavg", buf, sizeof buf);
	FILE *f = fopen(path, "r");
	double value = 0.0;
	int got;

	if (!f)
		return -1.0;

	got = fscanf(f, "%lf", &value);
	fclose(f);

	return got == 1 ? value : -1.0;
}

double metrics_soc_temp_c(void)
{
	char buf[PATH_MAX_LEN];
	const char *path = prefix_path(
		"/sys/class/thermal/thermal_zone0/temp", buf, sizeof buf);
	FILE *f = fopen(path, "r");
	double milli = 0.0;
	int got;

	if (!f)
		return -1.0;

	got = fscanf(f, "%lf", &milli);
	fclose(f);

	/* The kernel reports millidegrees. */
	return got == 1 ? milli / 1000.0 : -1.0;
}

double metrics_mem_used_percent(void)
{
	char buf[PATH_MAX_LEN];
	const char *path = prefix_path("/proc/meminfo", buf, sizeof buf);
	FILE *f = fopen(path, "r");
	char line[256];
	double total = -1.0;
	double available = -1.0;

	if (!f)
		return -1.0;

	while (fgets(line, sizeof line, f)) {
		double value;

		if (sscanf(line, "MemTotal: %lf kB", &value) == 1)
			total = value;
		else if (sscanf(line, "MemAvailable: %lf kB", &value) == 1)
			available = value;
	}
	fclose(f);

	/*
	 * MemAvailable, not MemFree. On a healthy Linux system MemFree is
	 * small because the page cache is doing its job, so a bar driven
	 * by MemFree sits near 100 percent on a completely idle board.
	 * That is the commonest way to draw a memory widget that is always
	 * alarming and never informative.
	 *
	 * MemAvailable has been in /proc/meminfo since 3.14 and is the
	 * kernel's own estimate of what a new allocation could get.
	 */
	if (total <= 0.0 || available < 0.0)
		return -1.0;

	if (available > total)
		available = total;

	return (total - available) / total * 100.0;
}

bench_state_t metrics_bench_state(char *out, unsigned long out_size)
{
	char buf[PATH_MAX_LEN];
	const char *path = prefix_path("/run/bench/state", buf, sizeof buf);
	char word[BENCH_STATE_MAX];
	FILE *f;

	if (out && out_size)
		snprintf(out, out_size, "unknown");

	f = fopen(path, "r");
	if (!f)
		return BENCH_STATE_UNKNOWN;

	if (!fgets(word, sizeof word, f)) {
		fclose(f);
		return BENCH_STATE_UNKNOWN;
	}
	fclose(f);

	/* bench-status writes one word and a newline. */
	word[strcspn(word, "\r\n")] = '\0';

	if (word[0] == '\0')
		return BENCH_STATE_UNKNOWN;

	if (out && out_size)
		snprintf(out, out_size, "%s", word);

	/*
	 * The three words bench-state(8) actually writes. Read out of
	 * meta-bench/recipes-bench/bench-status/files/bench-state, whose
	 * write_state() refuses anything outside this set, rather than
	 * taken from the project specification, which listed only two.
	 */
	if (strcmp(word, "ok") == 0)
		return BENCH_STATE_OK;
	if (strcmp(word, "starting") == 0)
		return BENCH_STATE_STARTING;
	if (strcmp(word, "failed") == 0)
		return BENCH_STATE_FAILED;

	/*
	 * A fourth word is reported as unknown rather than as a failure.
	 * bench-state may grow one, and a dashboard that painted every
	 * unrecognised word red would cry wolf on the day that happens.
	 * The word itself is still displayed, so the screen shows what it
	 * actually read rather than what this function made of it.
	 */
	return BENCH_STATE_UNKNOWN;
}
