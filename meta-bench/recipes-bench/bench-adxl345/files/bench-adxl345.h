/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * bench-adxl345.h - registers, and the one thing the bus files share.
 *
 * Every register here is from the ADXL345 datasheet, Analog Devices
 * Rev. E, the register map table. The values are transcribed once, in one
 * place, because a register constant written twice is a register constant
 * that will disagree with itself eventually. tests/adxl345-driver-test.sh
 * asserts that every register the core uses is defined here.
 *
 * The core file includes this and nothing about a bus. If it ever needs
 * i2c.h or spi.h, the split has failed.
 */

#ifndef BENCH_ADXL345_H
#define BENCH_ADXL345_H

#include <linux/regmap.h>
#include <linux/types.h>

#define BENCH_ADXL345_DEVID		0x00
#define BENCH_ADXL345_THRESH_TAP	0x1d
#define BENCH_ADXL345_OFSX		0x1e
#define BENCH_ADXL345_OFSY		0x1f
#define BENCH_ADXL345_OFSZ		0x20
#define BENCH_ADXL345_DUR		0x21
#define BENCH_ADXL345_LATENT		0x22
#define BENCH_ADXL345_WINDOW		0x23
#define BENCH_ADXL345_THRESH_ACT	0x24
#define BENCH_ADXL345_THRESH_INACT	0x25
#define BENCH_ADXL345_TIME_INACT	0x26
#define BENCH_ADXL345_ACT_INACT_CTL	0x27
#define BENCH_ADXL345_THRESH_FF		0x28
#define BENCH_ADXL345_TIME_FF		0x29
#define BENCH_ADXL345_TAP_AXES		0x2a
#define BENCH_ADXL345_ACT_TAP_STATUS	0x2b
#define BENCH_ADXL345_BW_RATE		0x2c
#define BENCH_ADXL345_POWER_CTL		0x2d
#define BENCH_ADXL345_INT_ENABLE	0x2e
#define BENCH_ADXL345_INT_MAP		0x2f
#define BENCH_ADXL345_INT_SOURCE	0x30
#define BENCH_ADXL345_DATA_FORMAT	0x31
#define BENCH_ADXL345_DATAX0		0x32
#define BENCH_ADXL345_FIFO_CTL		0x38
#define BENCH_ADXL345_FIFO_STATUS	0x39

/*
 * The value DEVID always reads. It is a fixed 0xe5 and it is the only
 * cheap way to tell "the part is there and talking" from "the bus
 * acknowledged an address because something else lives there". Probe
 * refuses on a mismatch rather than continuing and reporting zeros.
 */
#define BENCH_ADXL345_DEVID_VALUE	0xe5

/* POWER_CTL. Measurement is off after reset, which catches everyone once. */
#define BENCH_ADXL345_POWER_CTL_MEASURE	BIT(3)
#define BENCH_ADXL345_POWER_CTL_SLEEP	BIT(2)

/*
 * DATA_FORMAT. Two fields matter and they are adjacent, which is why
 * they are masked rather than written whole: the range is bits 1:0 and
 * FULL_RES is bit 3, and writing the byte to set one of them silently
 * clears INT_INVERT and the SPI wire-count bit that sit in the same
 * register.
 */
#define BENCH_ADXL345_DATA_FORMAT_RANGE	GENMASK(1, 0)
#define BENCH_ADXL345_DATA_FORMAT_FULL_RES	BIT(3)
#define BENCH_ADXL345_DATA_FORMAT_SPI_3WIRE	BIT(6)

#define BENCH_ADXL345_RANGE_2G		0
#define BENCH_ADXL345_RANGE_4G		1
#define BENCH_ADXL345_RANGE_8G		2
#define BENCH_ADXL345_RANGE_16G		3

/* BW_RATE. The output data rate is bits 3:0; bit 4 is the low power bit. */
#define BENCH_ADXL345_BW_RATE_MASK	GENMASK(3, 0)

/*
 * INT_ENABLE, INT_MAP and INT_SOURCE share one bit layout, which is a
 * convenience of the part worth naming: the same mask enables an
 * interrupt, routes it to INT1 or INT2, and reads back as its cause.
 */
#define BENCH_ADXL345_INT_DATA_READY	BIT(7)
#define BENCH_ADXL345_INT_SINGLE_TAP	BIT(6)
#define BENCH_ADXL345_INT_DOUBLE_TAP	BIT(5)
#define BENCH_ADXL345_INT_ACTIVITY	BIT(4)
#define BENCH_ADXL345_INT_INACTIVITY	BIT(3)
#define BENCH_ADXL345_INT_FREE_FALL	BIT(2)
#define BENCH_ADXL345_INT_WATERMARK	BIT(1)
#define BENCH_ADXL345_INT_OVERRUN	BIT(0)

/* FIFO_CTL. Mode is bits 7:6, the watermark is bits 4:0. */
#define BENCH_ADXL345_FIFO_CTL_MODE	GENMASK(7, 6)
#define BENCH_ADXL345_FIFO_CTL_SAMPLES	GENMASK(4, 0)

#define BENCH_ADXL345_FIFO_BYPASS	0
#define BENCH_ADXL345_FIFO_FIFO		1
#define BENCH_ADXL345_FIFO_STREAM	2
#define BENCH_ADXL345_FIFO_TRIGGER	3

/* FIFO_STATUS. Entries currently held is bits 5:0, so 0 to 33. */
#define BENCH_ADXL345_FIFO_STATUS_ENTRIES	GENMASK(5, 0)

/*
 * The FIFO is 32 samples deep. The watermark is set below that on
 * purpose: a watermark of 32 leaves no room to service the interrupt
 * before the 33rd sample overruns, and an overrun is a silently short
 * buffer rather than an error anybody sees.
 */
#define BENCH_ADXL345_FIFO_DEPTH	32
#define BENCH_ADXL345_WATERMARK_DEFAULT	24

/* Three axes, two bytes each, read as one burst from DATAX0. */
#define BENCH_ADXL345_AXES		3
#define BENCH_ADXL345_SAMPLE_BYTES	(BENCH_ADXL345_AXES * 2)

int bench_adxl345_core_probe(struct device *dev, struct regmap *regmap,
			     const char *name);

#endif /* BENCH_ADXL345_H */
