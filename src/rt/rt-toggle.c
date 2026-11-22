/*
 * rt-toggle - a periodic real-time task that leaves a trace on a wire.
 *
 * It does the four things every real-time task on Linux has to do, and it
 * does them in this order for a reason:
 *
 *   1. pin itself to one CPU          before anything is measured
 *   2. raise policy and priority      SCHED_FIFO, so nothing normal preempts
 *   3. lock and pre-fault memory      a page fault in the loop is a
 *                                     millisecond, the whole budget
 *   4. sleep on an absolute timeline  so that a late wake-up does not push
 *                                     every later one out with it
 *
 * On every wake-up it flips one GPIO line through the character device and
 * records its own wake-up latency, meaning the difference between when the
 * kernel said it would run and when it actually did. That histogram is the
 * internal measurement, and it is the same quantity cyclictest reports.
 *
 * The external measurement is the wire. An MCC 118 samples the same pin on
 * its own clock, so the period it sees includes this program's wake-up
 * latency plus the cost of the ioctl that sets the line. The difference
 * between the two histograms is the point of the experiment, which is why
 * this program keeps its own numbers rather than trusting the DAQ alone.
 *
 * Deliberately absent from the loop: malloc, printf, and any syscall other
 * than clock_nanosleep, clock_gettime and the GPIO ioctl. The histogram is
 * a fixed array, and it is printed after the last edge.
 *
 * Written against the libgpiod v2 API.
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * _GNU_SOURCE, not _POSIX_C_SOURCE: cpu_set_t, CPU_SET and
 * sched_setaffinity are glibc extensions, and under a strict POSIX
 * feature test they are simply not declared. The error that produces is
 * "unknown type name cpu_set_t", which reads like a missing header and is
 * not one.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <gpiod.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define NSEC_PER_SEC   1000000000L
#define NSEC_PER_USEC  1000L

#define DEFAULT_CHIP      "/dev/gpiochip0"
#define DEFAULT_LINE      20       /* header pin 38, free on the MCC 118 */
#define DEFAULT_CPU       3
#define DEFAULT_PRIORITY  80
#define DEFAULT_PERIOD_US 1000     /* toggle interval: a 500 Hz square wave */
#define DEFAULT_SECONDS   60

/*
 * One microsecond per bin, two milliseconds of range. Anything past that is
 * counted in an overflow bucket and reported: a tail that falls off the end
 * of the histogram has to be visible as a number, not as a shorter tail.
 */
#define HIST_BINS 2000

/* 512 kB of stack touched once, so that no page in it faults later. */
#define PREFAULT_BYTES (512 * 1024)

struct config {
	const char *chip_path;
	const char *out_path;
	unsigned int line;
	int cpu;
	int priority;
	long period_us;
	long seconds;
};

static volatile sig_atomic_t stop_requested;

static void on_signal(int sig)
{
	(void)sig;
	stop_requested = 1;
}

static void add_ns(struct timespec *t, long ns)
{
	t->tv_nsec += ns;
	while (t->tv_nsec >= NSEC_PER_SEC) {
		t->tv_nsec -= NSEC_PER_SEC;
		t->tv_sec++;
	}
}

static long diff_ns(const struct timespec *a, const struct timespec *b)
{
	return (a->tv_sec - b->tv_sec) * NSEC_PER_SEC +
	       (a->tv_nsec - b->tv_nsec);
}

/*
 * mlockall(MCL_FUTURE) keeps pages resident once they exist. It does not
 * create the ones the stack has not grown into yet, and the first call deep
 * enough to need them takes the fault inside the measured loop. Touching
 * them here moves that cost to startup, where it does not matter.
 */
static void prefault_stack(void)
{
	char scratch[PREFAULT_BYTES];

	memset(scratch, 0, sizeof scratch);
	/*
	 * A write nobody reads is a write the compiler may delete. This
	 * barrier is cheaper than making the array volatile and changes
	 * nothing about the code generated around it.
	 */
	__asm__ __volatile__("" : : "r"(scratch) : "memory");
}

static int set_realtime(const struct config *cfg)
{
	struct sched_param param;
	cpu_set_t set;

	CPU_ZERO(&set);
	CPU_SET(cfg->cpu, &set);
	if (sched_setaffinity(0, sizeof set, &set)) {
		fprintf(stderr, "rt-toggle: cannot pin to CPU %d: %s\n",
			cfg->cpu, strerror(errno));
		return -1;
	}

	memset(&param, 0, sizeof param);
	param.sched_priority = cfg->priority;
	if (sched_setscheduler(0, SCHED_FIFO, &param)) {
		fprintf(stderr,
			"rt-toggle: SCHED_FIFO priority %d refused: %s\n"
			"Run as root, or grant the binary the two\n"
			"capabilities it needs and nothing more:\n"
			"  setcap cap_sys_nice,cap_ipc_lock+ep rt-toggle\n",
			cfg->priority, strerror(errno));
		return -1;
	}

	if (mlockall(MCL_CURRENT | MCL_FUTURE)) {
		fprintf(stderr, "rt-toggle: mlockall: %s\n", strerror(errno));
		return -1;
	}
	prefault_stack();
	return 0;
}

static struct gpiod_line_request *request_line(struct gpiod_chip *chip,
					       const struct config *cfg)
{
	struct gpiod_request_config *req_cfg = NULL;
	struct gpiod_line_config *line_cfg = NULL;
	struct gpiod_line_settings *settings = NULL;
	struct gpiod_line_request *request = NULL;

	settings = gpiod_line_settings_new();
	line_cfg = gpiod_line_config_new();
	req_cfg = gpiod_request_config_new();
	if (!settings || !line_cfg || !req_cfg)
		goto out;

	gpiod_line_settings_set_direction(settings,
					  GPIOD_LINE_DIRECTION_OUTPUT);
	gpiod_line_settings_set_output_value(settings,
					     GPIOD_LINE_VALUE_INACTIVE);

	if (gpiod_line_config_add_line_settings(line_cfg, &cfg->line, 1,
						settings))
		goto out;

	gpiod_request_config_set_consumer(req_cfg, "rt-toggle");
	request = gpiod_chip_request_lines(chip, req_cfg, line_cfg);

out:
	if (req_cfg)
		gpiod_request_config_free(req_cfg);
	if (line_cfg)
		gpiod_line_config_free(line_cfg);
	if (settings)
		gpiod_line_settings_free(settings);
	return request;
}

/*
 * The percentile is read off the histogram rather than from a sorted list,
 * because sorting sixty thousand samples means allocating, in a program
 * that is not allowed to allocate. One microsecond of quantisation is well
 * below the differences this project is trying to resolve.
 */
static long percentile_us(const unsigned long *hist, unsigned long total,
			  unsigned long overflow, double fraction)
{
	unsigned long want = (unsigned long)(fraction * (double)total);
	unsigned long seen = 0;
	int i;

	if (total == 0)
		return -1;
	for (i = 0; i < HIST_BINS; i++) {
		seen += hist[i];
		if (seen >= want)
			return i;
	}
	return overflow ? HIST_BINS : HIST_BINS - 1;
}

struct summary {
	unsigned long total;
	unsigned long overflow;
	long min_ns;
	long max_ns;
	double sum_us;
};

static void report(FILE *out, const struct config *cfg,
		   const unsigned long *hist, const struct summary *s)
{
	int i;

	fprintf(out, "# rt-toggle\n");
	fprintf(out, "# chip %s line %u cpu %d priority %d\n",
		cfg->chip_path, cfg->line, cfg->cpu, cfg->priority);
	fprintf(out, "# toggle_us %ld edges %lu overflow %lu\n",
		cfg->period_us, s->total, s->overflow);
	if (s->total) {
		fprintf(out, "# min_us %.3f mean_us %.3f max_us %.3f\n",
			(double)s->min_ns / (double)NSEC_PER_USEC,
			s->sum_us / (double)s->total,
			(double)s->max_ns / (double)NSEC_PER_USEC);
		fprintf(out, "# p99_us %ld p999_us %ld\n",
			percentile_us(hist, s->total, s->overflow, 0.99),
			percentile_us(hist, s->total, s->overflow, 0.999));
	}
	fprintf(out, "# bin_us count\n");
	for (i = 0; i < HIST_BINS; i++)
		if (hist[i])
			fprintf(out, "%d %lu\n", i, hist[i]);
	if (s->overflow)
		fprintf(out, "%d %lu\n", HIST_BINS, s->overflow);
}

static void usage(void)
{
	fprintf(stderr,
		"usage: rt-toggle [-d seconds] [-c cpu] [-p priority]\n"
		"                 [-l line] [-C chip] [-t toggle_us]\n"
		"                 [-o file]\n"
		"\n"
		"Defaults: 60 s, CPU 3, priority 80, line 20 on\n"
		"/dev/gpiochip0, 1000 us per edge, histogram on stdout.\n");
}

int main(int argc, char **argv)
{
	static unsigned long hist[HIST_BINS];

	struct config cfg = {
		.chip_path = DEFAULT_CHIP,
		.out_path = NULL,
		.line = DEFAULT_LINE,
		.cpu = DEFAULT_CPU,
		.priority = DEFAULT_PRIORITY,
		.period_us = DEFAULT_PERIOD_US,
		.seconds = DEFAULT_SECONDS,
	};
	struct summary s = { 0, 0, -1, 0, 0.0 };
	struct gpiod_line_request *request;
	struct gpiod_chip *chip;
	struct sigaction sa;
	struct timespec next, now;
	long edges, i;
	FILE *out = stdout;
	int opt;

	while ((opt = getopt(argc, argv, "d:c:p:l:C:t:o:h")) != -1) {
		switch (opt) {
		case 'd': cfg.seconds = atol(optarg); break;
		case 'c': cfg.cpu = atoi(optarg); break;
		case 'p': cfg.priority = atoi(optarg); break;
		case 'l': cfg.line = (unsigned int)strtoul(optarg, NULL, 10);
			break;
		case 'C': cfg.chip_path = optarg; break;
		case 't': cfg.period_us = atol(optarg); break;
		case 'o': cfg.out_path = optarg; break;
		default: usage(); return opt == 'h' ? 0 : 2;
		}
	}

	if (cfg.seconds <= 0 || cfg.period_us <= 0 || cfg.period_us > 1000000L) {
		usage();
		return 2;
	}
	edges = cfg.seconds * (1000000L / cfg.period_us);

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_signal;
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	chip = gpiod_chip_open(cfg.chip_path);
	if (!chip) {
		fprintf(stderr, "rt-toggle: %s: %s\n", cfg.chip_path,
			strerror(errno));
		return 1;
	}

	request = request_line(chip, &cfg);
	if (!request) {
		fprintf(stderr, "rt-toggle: cannot request line %u on %s: %s\n",
			cfg.line, cfg.chip_path, strerror(errno));
		gpiod_chip_close(chip);
		return 1;
	}

	if (cfg.out_path) {
		out = fopen(cfg.out_path, "w");
		if (!out) {
			fprintf(stderr, "rt-toggle: %s: %s\n", cfg.out_path,
				strerror(errno));
			gpiod_line_request_release(request);
			gpiod_chip_close(chip);
			return 1;
		}
	}

	/*
	 * Everything that can fail has failed by now. Going real-time last
	 * means a mistake in the arguments is reported by an ordinary
	 * process, rather than by one that can starve the shell it was
	 * typed into on a single-core board.
	 */
	if (set_realtime(&cfg)) {
		gpiod_line_request_release(request);
		gpiod_chip_close(chip);
		if (out != stdout)
			fclose(out);
		return 1;
	}

	clock_gettime(CLOCK_MONOTONIC, &next);
	for (i = 0; i < edges && !stop_requested; i++) {
		long late_ns, bin;
		int rc;

		add_ns(&next, cfg.period_us * NSEC_PER_USEC);
		do {
			rc = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME,
					     &next, NULL);
		} while (rc == EINTR && !stop_requested);

		gpiod_line_request_set_value(request, cfg.line,
					     (i & 1) ? GPIOD_LINE_VALUE_ACTIVE
						     : GPIOD_LINE_VALUE_INACTIVE);

		clock_gettime(CLOCK_MONOTONIC, &now);
		late_ns = diff_ns(&now, &next);
		if (late_ns < 0)
			late_ns = 0;
		if (s.min_ns < 0 || late_ns < s.min_ns)
			s.min_ns = late_ns;
		if (late_ns > s.max_ns)
			s.max_ns = late_ns;
		s.sum_us += (double)late_ns / (double)NSEC_PER_USEC;

		bin = late_ns / NSEC_PER_USEC;
		if (bin < HIST_BINS)
			hist[bin]++;
		else
			s.overflow++;
		s.total++;
	}

	gpiod_line_request_set_value(request, cfg.line,
				     GPIOD_LINE_VALUE_INACTIVE);
	gpiod_line_request_release(request);
	gpiod_chip_close(chip);

	if (s.min_ns < 0)
		s.min_ns = 0;
	report(out, &cfg, hist, &s);
	if (out != stdout)
		fclose(out);
	return 0;
}
