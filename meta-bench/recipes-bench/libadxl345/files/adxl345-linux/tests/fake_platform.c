/*
 * fake_platform.c - the same six functions as platform.c, over an
 * in-memory register map instead of a bus.
 *
 * Linked in place of src/platform.c by the test_api target. The library
 * cannot tell the difference, which is the point: every register write
 * adxl.c makes is exercised, and the test can then assert on what the
 * library actually wrote rather than on what it returned.
 *
 * It also records the transfer log, so a test can say "the interrupt was
 * disabled before measurement stopped" and have that be a statement about
 * ordering rather than about a return code.
 *
 * SPDX-License-Identifier: MIT
 */

#include "platform.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "fake_platform.h"

/* The ADXL345's register file is 0x00 to 0x39. */
#define FAKE_REGS 0x40

struct adxl_plat {
	int dummy;
};

/* One instance. The tests are single-threaded and a second handle is
 * itself something worth testing, so the state is file-scope and
 * fake_reset() clears it between cases. */
static struct adxl_plat the_plat;

static uint8_t regs[FAKE_REGS];
static struct fake_log log_state;

/* The synthetic burst the fake returns: a board lying flat, so Z reads
 * about 1 g and X and Y read about zero. 1 g is 256 counts at the
 * 3.9 mg per count that FULL_RES fixes. */
#define FAKE_Z_COUNTS 256

static int fifo_entries;
static int entries_read;

void fake_reset(void)
{
	memset(regs, 0, sizeof(regs));
	memset(&log_state, 0, sizeof(log_state));
	regs[0x00] = 0xe5; /* DEVID, so adxl_open identifies it */
	fifo_entries = 0;
	entries_read = 0;
}

void fake_set_devid(uint8_t v)
{
	regs[0x00] = v;
}

void fake_set_fifo(int entries)
{
	fifo_entries = entries;
	entries_read = 0;
	regs[0x39] = (uint8_t)(entries & 0x3f);
}

uint8_t fake_reg(uint8_t r)
{
	return r < FAKE_REGS ? regs[r] : 0;
}

const struct fake_log *fake_get_log(void)
{
	return &log_state;
}

static void log_event(int kind, uint8_t reg, uint8_t value)
{
	if (log_state.count >= FAKE_LOG_MAX)
		return;
	log_state.entry[log_state.count].kind = kind;
	log_state.entry[log_state.count].reg = reg;
	log_state.entry[log_state.count].value = value;
	log_state.count++;
}

int adxl_plat_open(adxl_plat **out, const char *path, int addr, int int_gpio)
{
	if (!out || !path)
		return -EINVAL;
	/* Recorded so a test can assert the library passed the address
	 * through rather than compiling one in. */
	log_state.open_addr = addr;
	log_state.open_int_gpio = int_gpio;
	*out = &the_plat;
	return 0;
}

void adxl_plat_close(adxl_plat *p)
{
	(void)p;
	log_state.closed++;
}

int adxl_plat_write(adxl_plat *p, uint8_t reg, const uint8_t *buf, int len)
{
	int i;

	(void)p;
	if (!buf || len < 0)
		return -EINVAL;
	for (i = 0; i < len; i++) {
		uint8_t r = (uint8_t)(reg + i);

		if (r < FAKE_REGS)
			regs[r] = buf[i];
		log_event(FAKE_WRITE, r, buf[i]);
	}
	return 0;
}

int adxl_plat_read(adxl_plat *p, uint8_t reg, uint8_t *buf, int len)
{
	int i;

	(void)p;
	if (!buf || len <= 0)
		return -EINVAL;

	/*
	 * Reading DATAX0 pops a FIFO entry, which is the behaviour the
	 * library depends on and the reason adxl_read issues one
	 * transaction per entry. Modelling it here is what makes the test
	 * able to catch a library that tried to read the whole FIFO in one
	 * burst: it would get the same entry repeated, exactly as the real
	 * part would deliver it.
	 */
	if (reg == 0x32) {
		int16_t x = 0, y = 0, z = FAKE_Z_COUNTS;

		if (entries_read < fifo_entries) {
			/* Make each entry distinguishable, so a test can
			 * tell a repeated entry from a fresh one. */
			x = (int16_t)entries_read;
			entries_read++;
			if (fifo_entries - entries_read >= 0)
				regs[0x39] = (uint8_t)
					((fifo_entries - entries_read) & 0x3f);
		}
		if (len >= 6) {
			buf[0] = (uint8_t)(x & 0xff);
			buf[1] = (uint8_t)((x >> 8) & 0xff);
			buf[2] = (uint8_t)(y & 0xff);
			buf[3] = (uint8_t)((y >> 8) & 0xff);
			buf[4] = (uint8_t)(z & 0xff);
			buf[5] = (uint8_t)((z >> 8) & 0xff);
		}
		log_event(FAKE_READ, reg, 0);
		return 0;
	}

	for (i = 0; i < len; i++) {
		uint8_t r = (uint8_t)(reg + i);

		buf[i] = r < FAKE_REGS ? regs[r] : 0;
		log_event(FAKE_READ, r, buf[i]);
	}
	return 0;
}

int adxl_plat_wait(adxl_plat *p, int timeout_ms)
{
	(void)p;
	(void)timeout_ms;
	log_state.waits++;
	/* Always reports "no edge", so the library takes its polling path.
	 * The FIFO status then decides whether anything arrived, which is
	 * the single code path the design claims. */
	return 0;
}

void adxl_plat_sleep_ms(int ms)
{
	(void)ms;
	/* Deliberately does nothing. A test that really slept would take
	 * as long as the timeouts it passes in, and the thing being tested
	 * is the logic rather than the clock. */
}
