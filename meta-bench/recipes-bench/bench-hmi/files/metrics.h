/* SPDX-License-Identifier: MIT
 *
 * Reading the numbers the dashboard shows.
 *
 * Kept apart from the widgets on purpose: every function here is a pure
 * read of a file under /proc, /sys or /run, which means the whole module
 * can be tested on a laptop by pointing BENCH_METRICS_ROOT at a directory
 * of fake files. tests/hmi-metrics-test.sh does exactly that, and it is
 * the only part of this project that can be tested without a panel.
 */

#ifndef BENCH_METRICS_H
#define BENCH_METRICS_H

/* Longest state word bench-status writes, plus room for a terminator. */
#define BENCH_STATE_MAX 32

/* What /run/bench/state said, as a small enumeration rather than a
 * string comparison scattered through the widget code.
 *
 * THREE words, not two. bench-state(8) of Project 1 writes ok, starting
 * or failed, and its write_state() refuses anything else. The project
 * specification's example code for this dashboard only handled ok and
 * failed and painted everything else yellow, which would have shown a
 * booting board in the same colour as an unreadable file. They are
 * different conditions and the screen should not merge them:
 *
 *   ok        green
 *   starting  yellow, and it is going to change on its own
 *   failed    red
 *   unknown   yellow, and it is NOT going to change on its own
 */
typedef enum {
	BENCH_STATE_OK,
	BENCH_STATE_STARTING,
	BENCH_STATE_FAILED,
	BENCH_STATE_UNKNOWN
} bench_state_t;

/* One second of load average, from /proc/loadavg.
 * Returns -1.0 when the file cannot be read, which the caller shows
 * rather than hides: a dashboard that displays 0.00 for a failed read is
 * lying, and 0.00 is a plausible load. */
double metrics_loadavg(void);

/* SoC temperature in degrees Celsius, from the thermal zone.
 * The kernel reports millidegrees. Returns -1.0 on failure, for the same
 * reason: 0.0 C is not a plausible SoC temperature but it is a plausible
 * NUMBER, and a reader would believe it. */
double metrics_soc_temp_c(void);

/* Used memory as a percentage of total, from /proc/meminfo, computed as
 * (MemTotal - MemAvailable) / MemTotal.
 *
 * MemAvailable, not MemFree. MemFree on a healthy Linux box is small
 * because the page cache is doing its job, so a bar driven by MemFree
 * sits near 100 percent on an idle board and tells you nothing. This is
 * the single most common way to draw a misleading memory widget.
 *
 * Returns -1.0 on failure. */
double metrics_mem_used_percent(void);

/* The Project 1 status word from /run/bench/state.
 *
 * out must hold at least BENCH_STATE_MAX bytes and always receives a
 * terminated string, including on failure, where it receives "unknown".
 * The return value is the same thing as an enumeration for the LED. */
bench_state_t metrics_bench_state(char *out, unsigned long out_size);

/* The directory the four readers above treat as the filesystem root.
 *
 * Empty in production, so the paths are absolute and ordinary. Set from
 * BENCH_METRICS_ROOT at startup so the test suite can supply a tree of
 * fake files. Returns the prefix in use, for the startup log line. */
const char *metrics_set_root_from_env(void);

#endif /* BENCH_METRICS_H */
