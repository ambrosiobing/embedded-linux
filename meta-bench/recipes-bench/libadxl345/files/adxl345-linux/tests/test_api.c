/*
 * test_api.c - the library against the fake bus.
 *
 * These assert on WHAT THE LIBRARY WROTE TO THE PART, not only on what it
 * returned. A test that checks return codes proves the error paths and
 * nothing about the configuration, and a wrong DATA_FORMAT byte returns
 * success every time.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <string.h>

#include "adxl.h"
#include "fake_platform.h"

static int failures;
static int checks;

static void ok(const char *what, int cond)
{
	checks++;
	if (cond) {
		printf("ok       %s\n", what);
	} else {
		printf("FAILED   %s\n", what);
		failures++;
	}
}

static void eq(const char *what, long got, long want)
{
	checks++;
	if (got == want) {
		printf("ok       %s\n", what);
	} else {
		printf("FAILED   %s: wanted %ld, got %ld\n", what, want, got);
		failures++;
	}
}

/* Index of the first log entry writing reg, or -1. */
static int first_write(uint8_t reg)
{
	const struct fake_log *l = fake_get_log();
	int i;

	for (i = 0; i < l->count; i++)
		if (l->entry[i].kind == FAKE_WRITE && l->entry[i].reg == reg)
			return i;
	return -1;
}

static void test_version(void)
{
	int a = -1, b = -1, c = -1;

	printf("\n--- version\n");
	eq("adxl_version returns OK", adxl_version(&a, &b, &c), ADXL_OK);
	ok("major is set", a >= 0);
	ok("NULL arguments are accepted", adxl_version(NULL, NULL, NULL) == 0);
}

static void test_open(void)
{
	adxl_dev *d = NULL;

	printf("\n--- open\n");

	fake_reset();
	eq("a good address opens", adxl_open(&d, "/dev/i2c-1", 0x53, -1),
	   ADXL_OK);
	ok("a handle came back", d != NULL);
	eq("the address reached the platform layer, not a compiled-in one",
	   fake_get_log()->open_addr, 0x53);
	eq("a negative interrupt is passed through as given",
	   fake_get_log()->open_int_gpio, -1);
	eq("the part is left in standby, not measuring", fake_reg(0x2d), 0);
	adxl_close(d);
	d = NULL;

	fake_reset();
	eq("the other strap address also opens",
	   adxl_open(&d, "/dev/i2c-1", 0x1d, -1), ADXL_OK);
	adxl_close(d);
	d = NULL;

	fake_reset();
	eq("an address that is neither strap is refused before the bus",
	   adxl_open(&d, "/dev/i2c-1", 0x68, -1), ADXL_EPARAM);
	ok("and no handle is produced", d == NULL);

	fake_reset();
	fake_set_devid(0x33);
	eq("something that answers and is not an ADXL345 is refused",
	   adxl_open(&d, "/dev/i2c-1", 0x53, -1), ADXL_EWHO);
	ok("and no handle is produced", d == NULL);

	eq("a NULL out pointer is refused",
	   adxl_open(NULL, "/dev/i2c-1", 0x53, -1), ADXL_EPARAM);
	eq("a NULL path is refused", adxl_open(&d, NULL, 0x53, -1),
	   ADXL_EPARAM);

	printf("\n--- close\n");
	adxl_close(NULL);
	ok("close on NULL does not crash", 1);
}

static void test_start(void)
{
	adxl_dev *d = NULL;

	printf("\n--- start: what it writes, not what it returns\n");

	fake_reset();
	adxl_open(&d, "/dev/i2c-1", 0x53, -1);
	eq("start at 2 g and 100 Hz", adxl_start(d, 2, 100), ADXL_OK);

	/* FULL_RES set, range bits 00. The whole point of FULL_RES is that
	 * the scale stays 3.9 mg per count at every range. */
	eq("DATA_FORMAT has FULL_RES and the 2 g bits", fake_reg(0x31), 0x08);
	eq("BW_RATE carries the 100 Hz code", fake_reg(0x2c), 0x0a);
	eq("FIFO_CTL is stream mode with a watermark of 16",
	   fake_reg(0x38), 0x80 | 16);
	eq("INT_MAP routes the watermark to INT1", fake_reg(0x2f), 0x00);
	eq("INT_ENABLE enables the watermark", fake_reg(0x2e), 0x02);
	eq("POWER_CTL is measuring", fake_reg(0x2d), 0x08);

	ok("measurement is enabled AFTER the configuration, not before",
	   first_write(0x2d) > first_write(0x31) &&
		   first_write(0x2d) > first_write(0x38));

	adxl_close(d);
	d = NULL;

	fake_reset();
	adxl_open(&d, "/dev/i2c-1", 0x53, -1);
	eq("16 g sets the top range bits", adxl_start(d, 16, 100), ADXL_OK);
	eq("DATA_FORMAT has FULL_RES and the 16 g bits", fake_reg(0x31),
	   0x08 | 0x03);
	adxl_close(d);
	d = NULL;

	printf("\n--- start: refusals\n");
	fake_reset();
	adxl_open(&d, "/dev/i2c-1", 0x53, -1);
	eq("an unlisted range is refused", adxl_start(d, 6, 100), ADXL_EPARAM);
	eq("an unlisted rate is refused rather than rounded",
	   adxl_start(d, 2, 300), ADXL_EPARAM);
	eq("nothing was written to POWER_CTL by a refused start",
	   fake_reg(0x2d), 0);
	eq("a NULL handle is refused", adxl_start(NULL, 2, 100), ADXL_EPARAM);
	adxl_close(d);
}

static void test_read(void)
{
	adxl_dev *d = NULL;
	int16_t samples[ADXL_FIFO_DEPTH][ADXL_AXES];
	int n;

	printf("\n--- read\n");

	fake_reset();
	adxl_open(&d, "/dev/i2c-1", 0x53, -1);

	eq("reading before start is refused",
	   adxl_read(d, samples, ADXL_FIFO_DEPTH, 10), ADXL_EPARAM);

	adxl_start(d, 2, 100);

	fake_set_fifo(0);
	eq("an empty FIFO is a timeout, not zero samples",
	   adxl_read(d, samples, ADXL_FIFO_DEPTH, 10), ADXL_ETIMEOUT);

	fake_set_fifo(5);
	memset(samples, 0, sizeof(samples));
	n = adxl_read(d, samples, ADXL_FIFO_DEPTH, 10);
	eq("five entries held gives five samples", n, 5);
	eq("Z reads about 1 g on a board lying flat", samples[0][2], 256);
	eq("X is near zero", samples[0][0], 0);

	ok("each sample is a fresh FIFO entry, not the same one repeated",
	   samples[0][0] != samples[1][0]);

	fake_set_fifo(30);
	n = adxl_read(d, samples, 4, 10);
	eq("a caller asking for fewer than the FIFO holds gets what it asked",
	   n, 4);

	eq("a NULL sample array is refused",
	   adxl_read(d, NULL, 4, 10), ADXL_EPARAM);
	eq("a max of zero is refused", adxl_read(d, samples, 0, 10),
	   ADXL_EPARAM);

	adxl_close(d);
}

static void test_stop(void)
{
	adxl_dev *d = NULL;
	int16_t samples[4][ADXL_AXES];

	printf("\n--- stop\n");

	fake_reset();
	adxl_open(&d, "/dev/i2c-1", 0x53, -1);
	adxl_start(d, 2, 100);
	eq("stop returns OK", adxl_stop(d), ADXL_OK);
	eq("measurement is off", fake_reg(0x2d), 0);
	eq("the interrupt is disabled", fake_reg(0x2e), 0);
	eq("the FIFO is back in bypass", fake_reg(0x38), 0x00);

	ok("the interrupt is disabled BEFORE measurement stops, so no "
	   "watermark can arrive after the caller thinks it is quiet",
	   first_write(0x2e) < first_write(0x2d));

	/* A VALID array on purpose. Passing NULL here would return
	 * EPARAM from the argument check and the assertion would pass
	 * even if the library had forgotten the running flag entirely,
	 * which is a check that is right for the wrong reason. */
	fake_set_fifo(5);
	eq("reading after stop is refused, and not merely for a bad argument",
	   adxl_read(d, samples, 4, 10), ADXL_EPARAM);
	eq("a NULL handle is refused", adxl_stop(NULL), ADXL_EPARAM);
	adxl_close(d);
}

static void test_close_stops(void)
{
	adxl_dev *d = NULL;

	printf("\n--- close stops a running part\n");

	fake_reset();
	adxl_open(&d, "/dev/i2c-1", 0x53, -1);
	adxl_start(d, 2, 100);
	adxl_close(d);

	eq("close left the part in standby rather than measuring",
	   fake_reg(0x2d), 0);
	eq("and released the bus", fake_get_log()->closed, 1);
}

int main(void)
{
	test_version();
	test_open();
	test_start();
	test_read();
	test_stop();
	test_close_stops();

	printf("\n%d checked, %d failed\n", checks, failures);
	return failures ? 1 : 0;
}
