// SPDX-License-Identifier: GPL-2.0-only
/*
 * bench-adxl345-core.c - an IIO driver for the ADXL345, bus independent.
 *
 * Project 5 of embedded-linux-bench. This file knows registers, scales,
 * rates and interrupts. It does not know whether those registers are
 * reached over I2C or SPI, and that is the whole point: everything it
 * touches goes through one struct regmap *, which is the seam the
 * repository's walkthrough promised this driver would have before any of
 * it was written.
 *
 * WHY THIS EXISTS WHEN THE KERNEL ALREADY HAS ONE
 *
 * Linux has drivers/iio/accel/adxl345_core.c and it works. This is a
 * written-from-scratch exercise, and pretending the other does not exist
 * would be dishonest, so the two are arranged to coexist instead:
 *
 *   - the mainline driver claims "adi,adxl345" in its binding
 *   - this one claims "bench,adxl345" and nothing else
 *
 * Neither can bind to the other's node, so no load-order race exists and
 * both can be installed in the same image. The useful consequence is that
 * changing one word in the device tree overlay swaps which driver owns
 * the hardware, which makes mainline a control for every measurement this
 * project takes, on the same board and the same afternoon.
 *
 * WHAT IS NOT HERE YET
 *
 * This file has never been compiled. There is no kernel tree on the
 * machine it was written on, and no board has run it. The project README
 * says so in its acceptance table rather than leaving it to be assumed.
 */

#include <linux/bitfield.h>
#include <linux/bits.h>
#include <linux/device.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/regmap.h>

#include <linux/iio/buffer.h>
#include <linux/iio/events.h>
#include <linux/iio/iio.h>
#include <linux/iio/sysfs.h>

#include "bench-adxl345.h"

/*
 * The scale, derived here rather than copied, so the derivation can be
 * argued with.
 *
 * In FULL_RES mode the part keeps 3.9 mg per LSB at every range, which is
 * the mode this driver uses precisely so that the scale does not change
 * underneath userspace when the range does. IIO reports acceleration in
 * m/s^2, so:
 *
 *     3.9 mg/LSB  =  0.0039 g/LSB
 *     0.0039 g/LSB * 9.80665 m/s^2/g  =  0.038245935 m/s^2 per LSB
 *
 * Expressed as IIO_VAL_INT_PLUS_NANO that is 0 and 38245935 nano.
 *
 * tests/adxl345-driver-test.sh recomputes this from the two constants and
 * fails if the number below drifts from them, because a scale that is
 * wrong by a factor is the defect most likely to survive review: every
 * axis still moves, the signs are right, and gravity reads as the wrong
 * number only if somebody checks it against 9.81.
 */
#define BENCH_ADXL345_SCALE_NANO	38245935

struct bench_adxl345 {
	struct regmap *regmap;
	struct device *dev;
	const char *name;
	int irq;

	/*
	 * The buffer handed to iio_push_to_buffers_with_timestamp must be
	 * aligned for the timestamp it carries, so it is declared with the
	 * axes and the timestamp adjacent and the whole thing aligned to
	 * 8. Getting this wrong does not fail on arm64, it produces a
	 * timestamp that is occasionally torn, which is worse.
	 */
	struct {
		s16 axis[BENCH_ADXL345_AXES];
		aligned_s64 timestamp;
	} scan;
};

#define BENCH_ADXL345_CHANNEL(index, axis) {				\
	.type = IIO_ACCEL,						\
	.modified = 1,							\
	.channel2 = IIO_MOD_##axis,					\
	.info_mask_separate = BIT(IIO_CHAN_INFO_RAW),			\
	.info_mask_shared_by_type = BIT(IIO_CHAN_INFO_SCALE) |		\
				    BIT(IIO_CHAN_INFO_SAMP_FREQ),	\
	.scan_index = (index),						\
	.scan_type = {							\
		.sign = 's',						\
		.realbits = 13,						\
		.storagebits = 16,					\
		.endianness = IIO_LE,					\
	},								\
}

static const struct iio_chan_spec bench_adxl345_channels[] = {
	BENCH_ADXL345_CHANNEL(0, X),
	BENCH_ADXL345_CHANNEL(1, Y),
	BENCH_ADXL345_CHANNEL(2, Z),
	IIO_CHAN_SOFT_TIMESTAMP(3),
};

/*
 * The output data rate table, index into BW_RATE bits 3:0. Only the upper
 * half is offered: below 6.25 Hz the part has rates that exist and that
 * nothing on this bench wants, and offering them means testing them.
 */
static const int bench_adxl345_rates[][2] = {
	{ 12, 500000 },		/* 0x7 */
	{ 25, 0 },		/* 0x8 */
	{ 50, 0 },		/* 0x9 */
	{ 100, 0 },		/* 0xa */
	{ 200, 0 },		/* 0xb */
	{ 400, 0 },		/* 0xc */
	{ 800, 0 },		/* 0xd */
	{ 1600, 0 },		/* 0xe */
	{ 3200, 0 },		/* 0xf */
};

#define BENCH_ADXL345_RATE_FIRST	0x7

static int bench_adxl345_read_axis(struct bench_adxl345 *st, int index,
				   int *val)
{
	__le16 raw;
	int ret;

	ret = regmap_bulk_read(st->regmap,
			       BENCH_ADXL345_DATAX0 + index * 2,
			       &raw, sizeof(raw));
	if (ret)
		return ret;

	/*
	 * 13 bits in a 16 bit word, left justified is OFF, so the value is
	 * already right aligned and sign extended by the part. sign_extend32
	 * is still correct and still necessary: le16_to_cpu gives an
	 * unsigned 16 bit quantity and assigning it to an int would make
	 * every negative reading a large positive one.
	 */
	*val = sign_extend32(le16_to_cpu(raw), 12);
	return 0;
}

static int bench_adxl345_read_raw(struct iio_dev *indio_dev,
				  struct iio_chan_spec const *chan,
				  int *val, int *val2, long mask)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	unsigned int regval;
	int ret, index;

	switch (mask) {
	case IIO_CHAN_INFO_RAW:
		ret = bench_adxl345_read_axis(st, chan->scan_index, val);
		if (ret)
			return ret;
		return IIO_VAL_INT;

	case IIO_CHAN_INFO_SCALE:
		*val = 0;
		*val2 = BENCH_ADXL345_SCALE_NANO;
		return IIO_VAL_INT_PLUS_NANO;

	case IIO_CHAN_INFO_SAMP_FREQ:
		ret = regmap_read(st->regmap, BENCH_ADXL345_BW_RATE, &regval);
		if (ret)
			return ret;
		index = FIELD_GET(BENCH_ADXL345_BW_RATE_MASK, regval);
		index -= BENCH_ADXL345_RATE_FIRST;
		if (index < 0 || index >= ARRAY_SIZE(bench_adxl345_rates))
			return -EINVAL;
		*val = bench_adxl345_rates[index][0];
		*val2 = bench_adxl345_rates[index][1];
		return IIO_VAL_INT_PLUS_MICRO;
	}

	return -EINVAL;
}

static int bench_adxl345_write_raw(struct iio_dev *indio_dev,
				   struct iio_chan_spec const *chan,
				   int val, int val2, long mask)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	int i;

	if (mask != IIO_CHAN_INFO_SAMP_FREQ)
		return -EINVAL;

	for (i = 0; i < ARRAY_SIZE(bench_adxl345_rates); i++) {
		if (bench_adxl345_rates[i][0] != val ||
		    bench_adxl345_rates[i][1] != val2)
			continue;

		/*
		 * update_bits rather than write: BW_RATE also carries the
		 * low power bit, and writing the byte would clear it
		 * without saying so.
		 */
		return regmap_update_bits(st->regmap,
					  BENCH_ADXL345_BW_RATE,
					  BENCH_ADXL345_BW_RATE_MASK,
					  i + BENCH_ADXL345_RATE_FIRST);
	}

	return -EINVAL;
}

static const struct iio_info bench_adxl345_info = {
	.read_raw = bench_adxl345_read_raw,
	.write_raw = bench_adxl345_write_raw,
};

/*
 * The threaded half of the interrupt. Everything here sleeps: regmap over
 * I2C is a bus transaction and cannot run in hard interrupt context,
 * which is the reason this driver uses a threaded IRQ at all rather than
 * the reason it is convenient to.
 */
static irqreturn_t bench_adxl345_irq_thread(int irq, void *private)
{
	struct iio_dev *indio_dev = private;
	struct bench_adxl345 *st = iio_priv(indio_dev);
	unsigned int source, status;
	int entries, i, ret;
	s64 timestamp;

	ret = regmap_read(st->regmap, BENCH_ADXL345_INT_SOURCE, &source);
	if (ret)
		return IRQ_NONE;

	timestamp = iio_get_time_ns(indio_dev);

	if (source & BENCH_ADXL345_INT_SINGLE_TAP)
		iio_push_event(indio_dev,
			       IIO_MOD_EVENT_CODE(IIO_ACCEL, 0,
						  IIO_MOD_X_OR_Y_OR_Z,
						  IIO_EV_TYPE_GESTURE,
						  IIO_EV_DIR_SINGLETAP),
			       timestamp);

	if (source & BENCH_ADXL345_INT_DOUBLE_TAP)
		iio_push_event(indio_dev,
			       IIO_MOD_EVENT_CODE(IIO_ACCEL, 0,
						  IIO_MOD_X_OR_Y_OR_Z,
						  IIO_EV_TYPE_GESTURE,
						  IIO_EV_DIR_DOUBLETAP),
			       timestamp);

	if (source & BENCH_ADXL345_INT_FREE_FALL)
		iio_push_event(indio_dev,
			       IIO_MOD_EVENT_CODE(IIO_ACCEL, 0,
						  IIO_MOD_X_OR_Y_OR_Z,
						  IIO_EV_TYPE_THRESH,
						  IIO_EV_DIR_FALLING),
			       timestamp);

	if (!(source & BENCH_ADXL345_INT_WATERMARK))
		return IRQ_HANDLED;

	/*
	 * Drain what the part says it holds, not what the watermark was
	 * set to. Those differ whenever the thread was late, and reading
	 * the watermark count instead would leave samples behind on every
	 * busy system until an overrun threw them away.
	 */
	ret = regmap_read(st->regmap, BENCH_ADXL345_FIFO_STATUS, &status);
	if (ret)
		return IRQ_HANDLED;

	entries = FIELD_GET(BENCH_ADXL345_FIFO_STATUS_ENTRIES, status);

	for (i = 0; i < entries; i++) {
		ret = regmap_bulk_read(st->regmap, BENCH_ADXL345_DATAX0,
				       st->scan.axis,
				       BENCH_ADXL345_SAMPLE_BYTES);
		if (ret)
			break;

		iio_push_to_buffers_with_timestamp(indio_dev, &st->scan,
						   timestamp);

		/*
		 * The datasheet asks for at least 5 us between reads of
		 * the FIFO so that the next sample is presented. On a
		 * 400 kHz I2C bus a six byte burst already takes longer
		 * than that, so this is only load bearing on SPI.
		 */
		udelay(5);
	}

	return IRQ_HANDLED;
}

static int bench_adxl345_buffer_postenable(struct iio_dev *indio_dev)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	int ret;

	ret = regmap_write(st->regmap, BENCH_ADXL345_FIFO_CTL,
			   FIELD_PREP(BENCH_ADXL345_FIFO_CTL_MODE,
				      BENCH_ADXL345_FIFO_STREAM) |
			   FIELD_PREP(BENCH_ADXL345_FIFO_CTL_SAMPLES,
				      BENCH_ADXL345_WATERMARK_DEFAULT));
	if (ret)
		return ret;

	return regmap_update_bits(st->regmap, BENCH_ADXL345_INT_ENABLE,
				  BENCH_ADXL345_INT_WATERMARK,
				  BENCH_ADXL345_INT_WATERMARK);
}

static int bench_adxl345_buffer_predisable(struct iio_dev *indio_dev)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	int ret;

	ret = regmap_update_bits(st->regmap, BENCH_ADXL345_INT_ENABLE,
				 BENCH_ADXL345_INT_WATERMARK, 0);
	if (ret)
		return ret;

	/*
	 * Back to bypass, which also empties the FIFO. Without this a
	 * second capture starts by reading samples from the first one,
	 * timestamped as if they had just arrived.
	 */
	return regmap_write(st->regmap, BENCH_ADXL345_FIFO_CTL,
			    FIELD_PREP(BENCH_ADXL345_FIFO_CTL_MODE,
				       BENCH_ADXL345_FIFO_BYPASS));
}

static const struct iio_buffer_setup_ops bench_adxl345_buffer_ops = {
	.postenable = bench_adxl345_buffer_postenable,
	.predisable = bench_adxl345_buffer_predisable,
};

static void bench_adxl345_powerdown(void *data)
{
	struct regmap *regmap = data;

	regmap_update_bits(regmap, BENCH_ADXL345_POWER_CTL,
			   BENCH_ADXL345_POWER_CTL_MEASURE, 0);
}

int bench_adxl345_core_probe(struct device *dev, struct regmap *regmap,
			     const char *name)
{
	struct bench_adxl345 *st;
	struct iio_dev *indio_dev;
	unsigned int devid;
	int ret;

	indio_dev = devm_iio_device_alloc(dev, sizeof(*st));
	if (!indio_dev)
		return -ENOMEM;

	st = iio_priv(indio_dev);
	st->regmap = regmap;
	st->dev = dev;
	st->name = name;
	st->irq = fwnode_irq_get(dev_fwnode(dev), 0);

	/*
	 * Ask the part who it is before configuring anything. An I2C
	 * address that acknowledges is not the same as the part being
	 * there, and without this the driver probes cleanly against
	 * whatever else answers at 0x53 and then reports plausible zeros.
	 */
	ret = regmap_read(regmap, BENCH_ADXL345_DEVID, &devid);
	if (ret)
		return dev_err_probe(dev, ret, "cannot read DEVID\n");

	if (devid != BENCH_ADXL345_DEVID_VALUE)
		return dev_err_probe(dev, -ENODEV,
				     "DEVID is 0x%02x, expected 0x%02x\n",
				     devid, BENCH_ADXL345_DEVID_VALUE);

	/*
	 * FULL_RES at the widest range. Full resolution keeps 3.9 mg/LSB
	 * whatever the range, so the reported scale stays constant and the
	 * range becomes a choice about clipping rather than about
	 * precision.
	 */
	ret = regmap_update_bits(regmap, BENCH_ADXL345_DATA_FORMAT,
				 BENCH_ADXL345_DATA_FORMAT_RANGE |
				 BENCH_ADXL345_DATA_FORMAT_FULL_RES,
				 BENCH_ADXL345_DATA_FORMAT_FULL_RES |
				 FIELD_PREP(BENCH_ADXL345_DATA_FORMAT_RANGE,
					    BENCH_ADXL345_RANGE_16G));
	if (ret)
		return dev_err_probe(dev, ret, "cannot set DATA_FORMAT\n");

	ret = regmap_write(regmap, BENCH_ADXL345_FIFO_CTL,
			   FIELD_PREP(BENCH_ADXL345_FIFO_CTL_MODE,
				      BENCH_ADXL345_FIFO_BYPASS));
	if (ret)
		return dev_err_probe(dev, ret, "cannot reset the FIFO\n");

	ret = regmap_update_bits(regmap, BENCH_ADXL345_POWER_CTL,
				 BENCH_ADXL345_POWER_CTL_MEASURE,
				 BENCH_ADXL345_POWER_CTL_MEASURE);
	if (ret)
		return dev_err_probe(dev, ret, "cannot start measuring\n");

	ret = devm_add_action_or_reset(dev, bench_adxl345_powerdown, regmap);
	if (ret)
		return ret;

	indio_dev->name = name;
	indio_dev->info = &bench_adxl345_info;
	indio_dev->modes = INDIO_DIRECT_MODE;
	indio_dev->channels = bench_adxl345_channels;
	indio_dev->num_channels = ARRAY_SIZE(bench_adxl345_channels);

	if (st->irq > 0) {
		/*
		 * Route the interrupts this driver handles to INT1 and
		 * leave the rest on INT2, which is where they are after
		 * reset. A zero bit in INT_MAP means INT1.
		 */
		ret = regmap_write(regmap, BENCH_ADXL345_INT_MAP, 0);
		if (ret)
			return dev_err_probe(dev, ret,
					     "cannot route interrupts\n");

		ret = devm_request_threaded_irq(dev, st->irq, NULL,
						bench_adxl345_irq_thread,
						IRQF_ONESHOT,
						dev_name(dev), indio_dev);
		if (ret)
			return dev_err_probe(dev, ret,
					     "cannot request irq %d\n",
					     st->irq);

		ret = devm_iio_kfifo_buffer_setup(dev, indio_dev,
						  &bench_adxl345_buffer_ops);
		if (ret)
			return ret;
	} else {
		/*
		 * No interrupt in the device tree is a usable driver with
		 * no buffer, not a failure. Said once at probe so that a
		 * missing buffer directory later is explained rather than
		 * mysterious.
		 */
		dev_info(dev, "no interrupt, so sysfs only and no buffer\n");
	}

	return devm_iio_device_register(dev, indio_dev);
}
EXPORT_SYMBOL_NS_GPL(bench_adxl345_core_probe, "BENCH_ADXL345");

MODULE_AUTHOR("Joseph Ambrose Pagaran");
MODULE_DESCRIPTION("ADXL345 three axis accelerometer, bench IIO driver");
MODULE_LICENSE("GPL");
