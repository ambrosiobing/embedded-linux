/*
 * adxl-map - print live acceleration, one line per burst.
 *
 * A separate binary that links libadxl345 through its installed header
 * and nothing else. If this program ever needs something adxl.h does not
 * expose, that is a finding about the API rather than a reason to include
 * a file out of src/.
 *
 * SPDX-License-Identifier: MIT
 */

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <adxl.h>

/* FULL_RES fixes the scale at 3.9 mg per count at every range, which is
 * the reason the library always sets it. */
#define MILLI_G_PER_COUNT 39 /* tenths of a milli-g, to stay in integers */

/*
 * How long adxl_open took.
 *
 * Criterion 1 of this project is "adxl_open succeeds in under 100 ms at
 * 400 kHz", and until Sunday 4 October 2026 nothing in this tree could
 * produce that number. The criterion named a measurement and no
 * instrument existed to take it, which is the same shape as a blank left
 * looking like a gap: it would have been closed eventually by somebody
 * timing the whole process with a wristwatch and calling it the open.
 *
 * It is here rather than in the library on purpose. Criterion 4 pins the
 * library at exactly six exported symbols, so a seventh for timing would
 * close one criterion by breaking another. Timing a public call from
 * outside is also what a caller actually does.
 *
 * CLOCK_MONOTONIC rather than CLOCK_REALTIME: a clock step during the
 * open would otherwise be reported as the open taking it.
 */
static long long elapsed_us(const struct timespec *a, const struct timespec *b)
{
	return (long long)(b->tv_sec - a->tv_sec) * 1000000 +
	       (b->tv_nsec - a->tv_nsec) / 1000;
}

static volatile sig_atomic_t stop_requested;

static void on_signal(int sig)
{
	(void)sig;
	stop_requested = 1;
}

static void usage(const char *argv0)
{
	fprintf(stderr,
		"usage: %s [-d /dev/i2c-N] [-a 0x53|0x1d] [-i GPIO] "
		"[-r 2|4|8|16] [-f HZ] [-n COUNT]\n"
		"\n"
		"  -d  I2C bus. Default /dev/i2c-1, the Raspberry Pi header.\n"
		"  -a  address. 0x53 with SDO low, 0x1d with SDO high.\n"
		"      The DFRobot SEN0032 on this bench has SDO strapped to\n"
		"      GND and answered at 0x53 on Saturday 3 October 2026,\n"
		"      so the default is the measured one and not a guess.\n"
		"  -i  BCM offset of INT1. Omitted means not wired, and the\n"
		"      library polls instead. On this bench INT1 goes to\n"
		"      header pin 16, which is BCM 23, so: -i 23.\n"
		"  -r  range in g. Default 2.\n"
		"  -f  output data rate in Hz. Default 100.\n"
		"  -n  stop after COUNT bursts. Default 0, meaning run until\n"
		"      interrupted.\n",
		argv0);
}

int main(int argc, char **argv)
{
	const char *path = "/dev/i2c-1";
	int addr = 0x53;
	int int_gpio = -1;
	int range = 2;
	int rate = 100;
	long bursts = 0;
	long done = 0;
	adxl_dev *d = NULL;
	int16_t samples[ADXL_FIFO_DEPTH][ADXL_AXES];
	/*
	 * Both initialised, and the "did it work" kept in its own flag
	 * rather than smuggled into tv_sec. With the flag folded into the
	 * value, -Wmaybe-uninitialized cannot prove t1 is never read on the
	 * path where reading the clock failed, and this project builds with
	 * -Werror, so the compiler's doubt would be a red CI run.
	 */
	struct timespec t0 = { .tv_sec = 0, .tv_nsec = 0 };
	struct timespec t1 = { .tv_sec = 0, .tv_nsec = 0 };
	int timed = 1;
	int rc, i;

	for (i = 1; i < argc; i++) {
		const char *a = argv[i];
		const char *v = (i + 1 < argc) ? argv[i + 1] : NULL;

		if (strcmp(a, "-h") == 0) {
			usage(argv[0]);
			return 0;
		}
		if (!v) {
			usage(argv[0]);
			return 2;
		}
		if (strcmp(a, "-d") == 0)
			path = v;
		else if (strcmp(a, "-a") == 0)
			addr = (int)strtol(v, NULL, 0);
		else if (strcmp(a, "-i") == 0)
			int_gpio = (int)strtol(v, NULL, 0);
		else if (strcmp(a, "-r") == 0)
			range = (int)strtol(v, NULL, 0);
		else if (strcmp(a, "-f") == 0)
			rate = (int)strtol(v, NULL, 0);
		else if (strcmp(a, "-n") == 0)
			bursts = strtol(v, NULL, 0);
		else {
			usage(argv[0]);
			return 2;
		}
		i++;
	}

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	/*
	 * Timed whether or not anyone asked, because a measurement behind a
	 * flag is a measurement nobody has. It goes to stderr, so stdout
	 * stays a column of numbers something else can read.
	 */
	if (clock_gettime(CLOCK_MONOTONIC, &t0) != 0)
		timed = 0;
	rc = adxl_open(&d, path, addr, int_gpio);
	if (clock_gettime(CLOCK_MONOTONIC, &t1) != 0)
		timed = 0;

	if (timed) {
		long long us = elapsed_us(&t0, &t1);

		/*
		 * Which path was taken is part of the number. With -i the
		 * open also opens a gpiochip and requests a line, and that
		 * is the slow half; reporting a time without saying which
		 * of the two was measured invites the faster one to be
		 * quoted for both.
		 */
		fprintf(stderr,
			"%s: adxl_open %s after %lld.%03lld ms (%lld us), "
			"%s, CLOCK_MONOTONIC\n",
			argv[0], rc == ADXL_OK ? "returned" : "failed",
			us / 1000, us % 1000, us,
			int_gpio < 0 ? "no interrupt line requested"
				     : "interrupt line requested");
	} else {
		/* Say that the question could not be asked, rather than
		 * printing a zero that reads like a fast open. */
		fprintf(stderr,
			"%s: the monotonic clock could not be read, so how "
			"long adxl_open took is not reported\n",
			argv[0]);
	}

	if (rc != ADXL_OK) {
		/*
		 * Name the likely cause rather than printing a number. A
		 * refusal without evidence cannot be argued with, and the
		 * two common causes here are a permission problem and the
		 * other strap address.
		 */
		switch (rc) {
		case ADXL_EWHO:
			fprintf(stderr,
				"%s: something answered at 0x%02x and it is "
				"not an ADXL345.\nTry the other strap "
				"address: %s -a 0x%02x\n",
				argv[0], addr, argv[0],
				addr == 0x53 ? 0x1d : 0x53);
			break;
		case ADXL_EIO:
			fprintf(stderr,
				"%s: cannot use %s.\nIf this is a permission "
				"error, add yourself to the i2c group and log "
				"in again; this program needs no root.\n",
				argv[0], path);
			break;
		default:
			fprintf(stderr, "%s: open failed (%d)\n", argv[0], rc);
		}
		return 1;
	}

	if (int_gpio < 0)
		fprintf(stderr,
			"%s: no interrupt line given, polling instead. "
			"Pass -i with the INT1 offset once it is known.\n",
			argv[0]);

	if (adxl_start(d, range, rate) != ADXL_OK) {
		fprintf(stderr,
			"%s: range %d g or rate %d Hz is not one the part "
			"offers.\nRanges: 2 4 8 16. Rates: 12 25 50 100 200 "
			"400 800 1600 3200.\n",
			argv[0], range, rate);
		adxl_close(d);
		return 2;
	}

	printf("#      x_mg      y_mg      z_mg   samples\n");

	while (!stop_requested && (bursts == 0 || done < bursts)) {
		long sx = 0, sy = 0, sz = 0;

		rc = adxl_read(d, samples, ADXL_FIFO_DEPTH, 200);
		if (rc == ADXL_ETIMEOUT)
			continue;
		if (rc < 0) {
			fprintf(stderr, "%s: read failed (%d)\n", argv[0], rc);
			break;
		}

		/*
		 * The mean of the burst rather than the last sample. A
		 * single sample at 100 Hz is noisy enough that a board
		 * sitting still looks like it is moving, and averaging the
		 * burst is free because the samples are already here.
		 */
		for (i = 0; i < rc; i++) {
			sx += samples[i][0];
			sy += samples[i][1];
			sz += samples[i][2];
		}

		printf("%10ld%10ld%10ld%10d\n",
		       sx * MILLI_G_PER_COUNT / rc / 10,
		       sy * MILLI_G_PER_COUNT / rc / 10,
		       sz * MILLI_G_PER_COUNT / rc / 10, rc);
		fflush(stdout);
		done++;
	}

	adxl_close(d);
	return 0;
}
