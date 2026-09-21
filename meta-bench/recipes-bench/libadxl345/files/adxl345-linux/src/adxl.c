/*
 * adxl.c - the six public functions, over the four-function platform seam.
 *
 * Everything that knows a register number is in this file. platform.c
 * knows how to move bytes and nothing about what they mean; adxl.h knows
 * neither. That split is what lets the tests replace the bus wholesale
 * and still exercise every decision made here.
 *
 * SPDX-License-Identifier: MIT
 */

#include "adxl.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "platform.h"

/*
 * Set by CMake from the project version, so the number the library
 * reports and the number in the soname cannot drift apart. The fallback
 * exists so this file still compiles when somebody builds it by hand,
 * and it is deliberately 0.0.0 rather than a plausible version: a build
 * that reports 0.0.0 says "nobody told me", which is true.
 */
#ifndef ADXL_VERSION_MAJOR
#define ADXL_VERSION_MAJOR 0
#define ADXL_VERSION_MINOR 0
#define ADXL_VERSION_PATCH 0
#endif

/* Registers, from the ADXL345 datasheet. Named rather than inlined,
 * because a bare 0x31 in the middle of a function is unreviewable. */
#define REG_DEVID 0x00
#define REG_BW_RATE 0x2c
#define REG_POWER_CTL 0x2d
#define REG_INT_ENABLE 0x2e
#define REG_INT_MAP 0x2f
#define REG_DATA_FORMAT 0x31
#define REG_DATAX0 0x32
#define REG_FIFO_CTL 0x38
#define REG_FIFO_STATUS 0x39

#define DEVID_VALUE 0xe5

#define POWER_CTL_MEASURE 0x08

/* DATA_FORMAT: FULL_RES is bit 3, the range is bits 1:0. */
#define DATA_FORMAT_FULL_RES 0x08

/* INT_ENABLE and INT_SOURCE: the watermark bit. */
#define INT_WATERMARK 0x02

/*
 * REG_INT_SOURCE (0x30) IS DELIBERATELY NOT DEFINED OR READ, and this is
 * the note tests/adxl345_datasheet.py points at.
 *
 * On this part the watermark bit clears when the FIFO is read back below
 * the threshold, which adxl_read does as a side effect of taking the
 * samples. So the normal path needs no INT_SOURCE read.
 *
 * What that costs: the OVERRUN bit is only cleared by reading
 * INT_SOURCE. If the caller falls far enough behind that the FIFO
 * overruns, that latch stays set. With edge detection on INT1 the line
 * can then sit asserted, no further rising edge arrives, and
 * adxl_plat_wait times out every time.
 *
 * That is survivable rather than fatal, and only because of how the
 * polling fallback is written: a timeout is not an error, the code goes
 * on to read FIFO_STATUS anyway, and samples keep coming at the cost of
 * the interrupt being useless until something clears the latch.
 *
 * If this library ever grows an overrun count, or if the interrupt path
 * turns out to be the one that matters, the fix is to read 0x30 after a
 * timeout and report what it says. It is not done now because nothing
 * has run on hardware, and adding a register read to handle a condition
 * nobody has observed is how a driver grows paths that are never taken
 * and never tested.
 */

/* FIFO_CTL: stream mode is 0x80, the low five bits are the watermark. */
#define FIFO_CTL_STREAM 0x80
#define FIFO_CTL_BYPASS 0x00

/* FIFO_STATUS: the low six bits are the number of entries held. */
#define FIFO_STATUS_ENTRIES 0x3f

/* One FIFO entry is six bytes: X, Y, Z as little-endian int16. */
#define ENTRY_BYTES 6

struct adxl_dev {
	adxl_plat *plat;
	int watermark;
	int running;
};

static int rate_code(int hz)
{
	/*
	 * The ADXL345's output data rates are a fixed ladder and the
	 * register takes a code, not a frequency. An unlisted rate is an
	 * error rather than a silent round to the nearest, because a caller
	 * that asked for 300 Hz and silently got 400 has a sample interval
	 * that is wrong by a third and nothing anywhere says so.
	 */
	switch (hz) {
	case 12:
		return 0x07;
	case 25:
		return 0x08;
	case 50:
		return 0x09;
	case 100:
		return 0x0a;
	case 200:
		return 0x0b;
	case 400:
		return 0x0c;
	case 800:
		return 0x0d;
	case 1600:
		return 0x0e;
	case 3200:
		return 0x0f;
	default:
		return -1;
	}
}

static int range_bits(int g)
{
	switch (g) {
	case 2:
		return 0x00;
	case 4:
		return 0x01;
	case 8:
		return 0x02;
	case 16:
		return 0x03;
	default:
		return -1;
	}
}

static int write_reg(adxl_dev *d, uint8_t reg, uint8_t value)
{
	return adxl_plat_write(d->plat, reg, &value, 1) < 0 ? ADXL_EIO
							    : ADXL_OK;
}

int adxl_version(int *major, int *minor, int *patch)
{
	if (major)
		*major = ADXL_VERSION_MAJOR;
	if (minor)
		*minor = ADXL_VERSION_MINOR;
	if (patch)
		*patch = ADXL_VERSION_PATCH;
	return ADXL_OK;
}

int adxl_open(adxl_dev **out, const char *i2c_path, int addr, int int_gpio)
{
	adxl_dev *d;
	uint8_t devid = 0;
	int rc;

	if (!out || !i2c_path)
		return ADXL_EPARAM;
	/* The only two straps the part has. Anything else is a typo that
	 * would otherwise reach the bus and return EIO from a long way
	 * away from the mistake. */
	if (addr != 0x53 && addr != 0x1d)
		return ADXL_EPARAM;

	d = calloc(1, sizeof(*d));
	if (!d)
		return ADXL_ENOMEM;

	rc = adxl_plat_open(&d->plat, i2c_path, addr, int_gpio);
	if (rc < 0) {
		free(d);
		return ADXL_EIO;
	}

	/*
	 * Identify before trusting anything. A wrong address on a busy bus
	 * often finds some other chip that answers, and every later read
	 * then returns numbers that look like acceleration and are not.
	 * This is the cheapest guard in the library and the one that turns
	 * a wrong strap into a clear message.
	 */
	if (adxl_plat_read(d->plat, REG_DEVID, &devid, 1) < 0) {
		adxl_plat_close(d->plat);
		free(d);
		return ADXL_EIO;
	}
	if (devid != DEVID_VALUE) {
		adxl_plat_close(d->plat);
		free(d);
		return ADXL_EWHO;
	}

	/* Leave it in standby until adxl_start. Opening a handle should
	 * not start the part drawing measurement current. */
	if (write_reg(d, REG_POWER_CTL, 0) != ADXL_OK) {
		adxl_plat_close(d->plat);
		free(d);
		return ADXL_EIO;
	}

	*out = d;
	return ADXL_OK;
}

int adxl_start(adxl_dev *d, int range_g, int rate_hz)
{
	int rbits, rcode;

	if (!d)
		return ADXL_EPARAM;

	rbits = range_bits(range_g);
	rcode = rate_code(rate_hz);
	if (rbits < 0 || rcode < 0)
		return ADXL_EPARAM;

	/*
	 * FULL_RES is always set, so the scale stays 3.9 mg per count at
	 * every range and only the clipping point moves. Without it the
	 * scale changes with the range and every stored sample needs to
	 * carry the range it was taken at to be interpretable later.
	 */
	if (write_reg(d, REG_DATA_FORMAT,
		      (uint8_t)(DATA_FORMAT_FULL_RES | rbits)) != ADXL_OK)
		return ADXL_EIO;

	if (write_reg(d, REG_BW_RATE, (uint8_t)rcode) != ADXL_OK)
		return ADXL_EIO;

	/*
	 * Stream mode with a watermark of 16, which is half the FIFO. Deep
	 * enough that a caller scheduled late does not lose samples, and
	 * shallow enough that it has half a FIFO of slack to catch up in.
	 */
	d->watermark = 16;
	if (write_reg(d, REG_FIFO_CTL,
		      (uint8_t)(FIFO_CTL_STREAM | d->watermark)) != ADXL_OK)
		return ADXL_EIO;

	/* Watermark on INT1. INT_MAP bit clear means INT1 rather than
	 * INT2, and INT2 is not wired on this bench. */
	if (write_reg(d, REG_INT_MAP, 0) != ADXL_OK)
		return ADXL_EIO;
	if (write_reg(d, REG_INT_ENABLE, INT_WATERMARK) != ADXL_OK)
		return ADXL_EIO;

	if (write_reg(d, REG_POWER_CTL, POWER_CTL_MEASURE) != ADXL_OK)
		return ADXL_EIO;

	d->running = 1;
	return ADXL_OK;
}

int adxl_read(adxl_dev *d, int16_t samples[][ADXL_AXES], int max,
	      int timeout_ms)
{
	uint8_t status = 0;
	int held, count, i;

	if (!d || !samples || max <= 0)
		return ADXL_EPARAM;
	if (!d->running)
		return ADXL_EPARAM;

	/*
	 * Wait for the watermark interrupt if one is wired. With no
	 * interrupt this sleeps for the timeout and returns 0, and the
	 * FIFO_STATUS read below then decides whether anything arrived, so
	 * there is one code path rather than two.
	 */
	if (adxl_plat_wait(d->plat, timeout_ms) < 0)
		return ADXL_EIO;

	if (adxl_plat_read(d->plat, REG_FIFO_STATUS, &status, 1) < 0)
		return ADXL_EIO;

	held = status & FIFO_STATUS_ENTRIES;
	if (held == 0)
		return ADXL_ETIMEOUT;

	count = held < max ? held : max;

	for (i = 0; i < count; i++) {
		uint8_t raw[ENTRY_BYTES];

		/*
		 * One entry per transaction, and that is a real cost: 16
		 * entries is 16 round trips. It is written this way because
		 * the FIFO is read through a single register that pops an
		 * entry per burst, so a longer read does NOT fetch more
		 * entries, it re-reads the same one.
		 */
		if (adxl_plat_read(d->plat, REG_DATAX0, raw, ENTRY_BYTES) < 0)
			return ADXL_EIO;

		samples[i][0] = (int16_t)((uint16_t)raw[0] |
					  ((uint16_t)raw[1] << 8));
		samples[i][1] = (int16_t)((uint16_t)raw[2] |
					  ((uint16_t)raw[3] << 8));
		samples[i][2] = (int16_t)((uint16_t)raw[4] |
					  ((uint16_t)raw[5] << 8));

		/*
		 * The datasheet asks for at least 5 us between FIFO reads.
		 * The platform sleep has millisecond resolution, which is
		 * far coarser than needed, so it is not used: the ioctl
		 * round trip through the kernel already costs more than 5 us
		 * and is the reason this loop is safe without an explicit
		 * delay. Stated here because it is an assumption rather than
		 * a measurement, and it is the first thing to suspect if
		 * bursts come back with repeated entries.
		 */
	}

	return count;
}

int adxl_stop(adxl_dev *d)
{
	if (!d)
		return ADXL_EPARAM;

	/* Order matters: stop the interrupt before stopping measurement,
	 * or a watermark interrupt can arrive after the caller believes
	 * the part is quiet. */
	if (write_reg(d, REG_INT_ENABLE, 0) != ADXL_OK)
		return ADXL_EIO;
	if (write_reg(d, REG_FIFO_CTL, FIFO_CTL_BYPASS) != ADXL_OK)
		return ADXL_EIO;
	if (write_reg(d, REG_POWER_CTL, 0) != ADXL_OK)
		return ADXL_EIO;

	d->running = 0;
	return ADXL_OK;
}

void adxl_close(adxl_dev *d)
{
	if (!d)
		return;
	if (d->running)
		adxl_stop(d);
	adxl_plat_close(d->plat);
	free(d);
}
