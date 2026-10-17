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
 * WHERE THIS STANDS
 *
 * This file first compiled on Friday 9 October 2026, against the 6.6.63
 * kernel of the bench image, after four edits for the difference between
 * that kernel and the v6.12 it was written from. The same night it bound
 * to the part on the bench through the overlay in bench-adxl345-dt, read
 * gravity, set and read back its rate, and took its interrupt once INT1
 * was wired. The project README's acceptance table says which criteria
 * are measured and which are still only configured.
 */

#include <linux/bitfield.h>
#include <linux/bits.h>
#include <linux/device.h>
#include <linux/interrupt.h>
#include <linux/math64.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/property.h>
#include <linux/regmap.h>

#include <linux/iio/buffer.h>
#include <linux/iio/events.h>
#include <linux/iio/iio.h>
#include <linux/iio/kfifo_buf.h>
#include <linux/iio/sysfs.h>
#include <linux/iio/trigger.h>
#include <linux/iio/trigger_consumer.h>

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
	 * The hardware watermark the next buffer enable will program,
	 * written through buffer/watermark by the IIO core's set_watermark
	 * hook. It started life as a fixed constant, and Project 10's
	 * iio-rate, which writes that attribute and then proves a hardware
	 * FIFO by the interrupt rate, would have measured a part that
	 * ignored it.
	 */
	unsigned int watermark;

	/*
	 * The sample period at the configured rate, in nanoseconds, kept
	 * here so the interrupt thread can spread a batch of FIFO samples
	 * back from the interrupt time without a bus read per interrupt.
	 * Set at probe from the part's reset rate and on every rate write.
	 */
	u64 period_ns;

	/*
	 * The buffer handed to iio_push_to_buffers_with_timestamp must be
	 * aligned for the timestamp it carries, so it is declared with the
	 * axes and the timestamp adjacent and the whole thing aligned to
	 * 8. Getting this wrong does not fail on arm64, it produces a
	 * timestamp that is occasionally torn, which is worse.
	 *
	 * Spelled as s64 with __aligned(8) rather than the aligned_s64
	 * typedef, because the typedef is newer than the 6.6 kernel this
	 * image carries and the first compile against that kernel, on
	 * Friday 9 October 2026, stopped on it. The in-tree drivers of
	 * 6.6 write it this way; the two forms mean the same thing.
	 */
	struct {
		s16 axis[BENCH_ADXL345_AXES];
		s64 timestamp __aligned(8);
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

/*
 * THE THREE EVENTS, AND WHY THEY SIT ON A CHANNEL OF THEIR OWN.
 *
 * The part reports a tap on whichever axis saw it, in ACT_TAP_STATUS,
 * and this driver does not read that register, so it reports the three
 * axes together: IIO_MOD_X_OR_Y_OR_Z, which is what the handler has
 * always pushed. An event code only reaches user space as a named
 * attribute if some channel declares it with the same modifier, so the
 * declaration has to carry that modifier too, and no scan channel does.
 * Hence a channel with no scan index: it adds nothing to the buffer and
 * exists to give the three events a home.
 *
 * If per-axis reporting is ever wanted, ACT_TAP_STATUS is the register
 * and the datasheet's page 16 carries the order it has to be read in:
 * before INT_SOURCE, because reading INT_SOURCE clears the event.
 *
 * Single tap carries the threshold, THRESH_TAP, which the part shares
 * between single and double tap, so double tap carries only its enable
 * rather than a second attribute writing the same register. Free fall
 * carries its own threshold, THRESH_FF.
 */
static const struct iio_event_spec bench_adxl345_events[] = {
	{
		.type = IIO_EV_TYPE_GESTURE,
		.dir = IIO_EV_DIR_SINGLETAP,
		.mask_separate = BIT(IIO_EV_INFO_ENABLE) |
				 BIT(IIO_EV_INFO_VALUE),
	}, {
		.type = IIO_EV_TYPE_GESTURE,
		.dir = IIO_EV_DIR_DOUBLETAP,
		.mask_separate = BIT(IIO_EV_INFO_ENABLE),
	}, {
		.type = IIO_EV_TYPE_THRESH,
		.dir = IIO_EV_DIR_FALLING,
		.mask_separate = BIT(IIO_EV_INFO_ENABLE) |
				 BIT(IIO_EV_INFO_VALUE),
	},
};

static const struct iio_chan_spec bench_adxl345_channels[] = {
	BENCH_ADXL345_CHANNEL(0, X),
	BENCH_ADXL345_CHANNEL(1, Y),
	BENCH_ADXL345_CHANNEL(2, Z),
	IIO_CHAN_SOFT_TIMESTAMP(3),
	{
		/*
		 * LAST ON PURPOSE. probe drops this channel when there is
		 * no interrupt, by registering one channel fewer, because
		 * an event attribute on a board whose INT1 is not wired
		 * can be enabled and will never fire.
		 */
		.type = IIO_ACCEL,
		.modified = 1,
		.channel2 = IIO_MOD_X_OR_Y_OR_Z,
		.scan_index = -1,
		.event_spec = bench_adxl345_events,
		.num_event_specs = ARRAY_SIZE(bench_adxl345_events),
	},
};

/*
 * The INT_ENABLE bit behind an event, or zero for a combination this
 * driver does not have. INT_ENABLE, INT_MAP and INT_SOURCE share one
 * layout, so the same bit enables the function, routes it and reads
 * back as its cause.
 */
static unsigned int bench_adxl345_event_bit(enum iio_event_type type,
					    enum iio_event_direction dir)
{
	if (type == IIO_EV_TYPE_GESTURE && dir == IIO_EV_DIR_SINGLETAP)
		return BENCH_ADXL345_INT_SINGLE_TAP;
	if (type == IIO_EV_TYPE_GESTURE && dir == IIO_EV_DIR_DOUBLETAP)
		return BENCH_ADXL345_INT_DOUBLE_TAP;
	if (type == IIO_EV_TYPE_THRESH && dir == IIO_EV_DIR_FALLING)
		return BENCH_ADXL345_INT_FREE_FALL;
	return 0;
}

/*
 * The threshold register behind an event's value, or zero for one that
 * has none. Zero is unambiguous as "none" here because register 0x00 is
 * DEVID and is not a threshold.
 */
static unsigned int bench_adxl345_event_value_reg(enum iio_event_type type,
						  enum iio_event_direction dir,
						  enum iio_event_info info)
{
	if (info != IIO_EV_INFO_VALUE)
		return 0;
	if (type == IIO_EV_TYPE_GESTURE && dir == IIO_EV_DIR_SINGLETAP)
		return BENCH_ADXL345_THRESH_TAP;
	if (type == IIO_EV_TYPE_THRESH && dir == IIO_EV_DIR_FALLING)
		return BENCH_ADXL345_THRESH_FF;
	return 0;
}

static int bench_adxl345_read_event_config(struct iio_dev *indio_dev,
					   const struct iio_chan_spec *chan,
					   enum iio_event_type type,
					   enum iio_event_direction dir)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	unsigned int bit, regval;
	int ret;

	bit = bench_adxl345_event_bit(type, dir);
	if (!bit)
		return -EINVAL;

	ret = regmap_read(st->regmap, BENCH_ADXL345_INT_ENABLE, &regval);
	if (ret)
		return ret;

	return !!(regval & bit);
}

/*
 * Enabling an event enables the function, not merely its output pin.
 * The datasheet, Revision 0 page 17, says that of the eight bits in
 * INT_ENABLE only data ready, watermark and overrun "enable only the
 * interrupt output; the functions are always enabled". So with the tap
 * bit clear the part never detects a tap at all, which is the state
 * this driver shipped in until Friday 16 October 2026: three
 * iio_push_event calls that no hardware could ever reach.
 */
static int bench_adxl345_write_event_config(struct iio_dev *indio_dev,
					    const struct iio_chan_spec *chan,
					    enum iio_event_type type,
					    enum iio_event_direction dir,
					    int state)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	unsigned int bit;

	bit = bench_adxl345_event_bit(type, dir);
	if (!bit)
		return -EINVAL;

	return regmap_update_bits(st->regmap, BENCH_ADXL345_INT_ENABLE,
				  bit, state ? bit : 0);
}

/*
 * The thresholds are reported and taken in the part's own counts, not
 * in the channel's units, and that is a deliberate limit rather than an
 * oversight. THRESH_TAP and THRESH_FF are 62.5 mg per count while the
 * channel reads 3.9 mg per count in full resolution; converting would
 * mean a ratio of 16.03 that the datasheet does not bless, and a value
 * that reads back as something other than what was written. A count and
 * its scale factor are honest and are in the header beside the
 * register. The page is 15 in Revision 0.
 */
static int bench_adxl345_read_event_value(struct iio_dev *indio_dev,
					  const struct iio_chan_spec *chan,
					  enum iio_event_type type,
					  enum iio_event_direction dir,
					  enum iio_event_info info,
					  int *val, int *val2)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	unsigned int reg, regval;
	int ret;

	reg = bench_adxl345_event_value_reg(type, dir, info);
	if (!reg)
		return -EINVAL;

	ret = regmap_read(st->regmap, reg, &regval);
	if (ret)
		return ret;

	*val = regval;
	return IIO_VAL_INT;
}

static int bench_adxl345_write_event_value(struct iio_dev *indio_dev,
					   const struct iio_chan_spec *chan,
					   enum iio_event_type type,
					   enum iio_event_direction dir,
					   enum iio_event_info info,
					   int val, int val2)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	unsigned int reg;

	reg = bench_adxl345_event_value_reg(type, dir, info);
	if (!reg)
		return -EINVAL;

	if (val < 0 || val > 0xff)
		return -EINVAL;

	return regmap_write(st->regmap, reg, val);
}

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

/*
 * The period of one table entry, in nanoseconds. The table carries the
 * rate as hertz plus microhertz so that 12.5 Hz has a row; one second
 * in femtoseconds over the rate in microhertz gives nanoseconds exactly
 * for every row: 100 Hz is 10 000 000 ns, 12.5 Hz is 80 000 000 ns.
 */
static u64 bench_adxl345_period_ns(int index)
{
	u64 uhz = (u64)bench_adxl345_rates[index][0] * 1000000ULL +
		  bench_adxl345_rates[index][1];

	return div64_u64(1000000000000000ULL, uhz);
}

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
	int i, ret;

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
		ret = regmap_update_bits(st->regmap,
					 BENCH_ADXL345_BW_RATE,
					 BENCH_ADXL345_BW_RATE_MASK,
					 i + BENCH_ADXL345_RATE_FIRST);
		if (ret)
			return ret;
		st->period_ns = bench_adxl345_period_ns(i);
		return 0;
	}

	return -EINVAL;
}

static int bench_adxl345_set_watermark(struct iio_dev *indio_dev,
				       unsigned int val);

/*
 * The watermark hook sits in iio_info, which is where this kernel's IIO
 * core looks when buffer/watermark is written; the buffer setup ops
 * below carry only the enable and disable halves. No hwfifo_* attributes
 * are provided; iio-rate looks for buffer/watermark second and uses it.
 */
static const struct iio_info bench_adxl345_info = {
	.read_raw = bench_adxl345_read_raw,
	.write_raw = bench_adxl345_write_raw,
	.hwfifo_set_watermark = bench_adxl345_set_watermark,
	.read_event_config = bench_adxl345_read_event_config,
	.write_event_config = bench_adxl345_write_event_config,
	.read_event_value = bench_adxl345_read_event_value,
	.write_event_value = bench_adxl345_write_event_value,
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

		/*
		 * The FIFO holds entries samples taken one period apart,
		 * the newest at the interrupt. Each is pushed with the
		 * time it was taken, counted back from the interrupt time
		 * at the configured rate, which is what docs/DESIGN.md
		 * promised for the FIFO path and what the first capture on
		 * Friday 9 October 2026 showed was not happening: every
		 * sample in a batch carried the interrupt time and the
		 * timestamp spread came out as the batch period. These are
		 * assigned times, not measured ones; iio-rate labels the
		 * column accordingly.
		 */
		iio_push_to_buffers_with_timestamp(indio_dev, &st->scan,
			timestamp - (s64)(entries - 1 - i) * st->period_ns);

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

/*
 * THE TRIGGERED PATH, WHICH IS THE SECOND WAY OUT OF THIS PART AND NOT A
 * VARIANT OF THE FIRST.
 *
 * Here something else decides when a sample is taken: an hrtimer trigger
 * at a rate of its own, or the sysfs trigger when a test wants one scan
 * at a time. The core calls this function once per trigger, it reads the
 * current output registers, and one scan goes into the same kfifo the
 * watermark path fills.
 *
 * Three differences from the FIFO path, all of them the point of having
 * both:
 *
 *   - the timestamp is taken in the core at the moment the trigger
 *     fired, not computed. pf->timestamp holds it because
 *     iio_pollfunc_store_time is this pollfunc's hard-irq half; with a
 *     NULL half the field is never written and every sample would carry
 *     whatever was there before.
 *   - one bus transaction per sample rather than one per batch, so this
 *     path costs the most CPU per sample of the three and is the reason
 *     the part has a FIFO at all.
 *   - the trigger rate and the part's output rate are independent, and
 *     nothing here enforces a relationship between them. Trigger faster
 *     than BW_RATE and the same conversion is read twice; slower and
 *     conversions are skipped. Neither is an error and neither is
 *     reported, which makes it a thing to measure rather than a thing to
 *     guard: Project 10's iio-rate reads back in_accel_sampling_frequency
 *     and the trigger's own rate, and the comparison is only meaningful
 *     when it prints both.
 *
 * st->scan is shared with the interrupt thread, which is safe because
 * the two paths are mutually exclusive: the core runs one buffer mode at
 * a time and picks it at enable, see the postenable below.
 *
 * All six data bytes are read whatever the scan mask says. That is the
 * part's requirement rather than a shortcut, since DATAX0 through DATAZ1
 * have to be read in one transaction to be one sample; a scan mask with
 * fewer axes is handled by the core's demux on the way into the buffer.
 */
static irqreturn_t bench_adxl345_trigger_handler(int irq, void *p)
{
	struct iio_poll_func *pf = p;
	struct iio_dev *indio_dev = pf->indio_dev;
	struct bench_adxl345 *st = iio_priv(indio_dev);
	int ret;

	ret = regmap_bulk_read(st->regmap, BENCH_ADXL345_DATAX0,
			       st->scan.axis, BENCH_ADXL345_SAMPLE_BYTES);
	if (!ret)
		iio_push_to_buffers_with_timestamp(indio_dev, &st->scan,
						   pf->timestamp);

	/*
	 * Unconditionally, including after a failed read. The trigger
	 * counts its consumers and will not fire again until every one of
	 * them has said it is done, so an early return on error stops the
	 * path for good rather than dropping one sample.
	 */
	iio_trigger_notify_done(indio_dev->trig);

	return IRQ_HANDLED;
}

static void bench_adxl345_free_pollfunc(void *data)
{
	iio_dealloc_pollfunc(data);
}

static int bench_adxl345_buffer_postenable(struct iio_dev *indio_dev)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	int ret;

	/*
	 * WHICH OF THE TWO BUFFER PATHS THIS ENABLE IS FOR.
	 *
	 * The core decides, in iio_verify_update, and its condition is
	 * that the device declares INDIO_BUFFER_TRIGGERED and has a
	 * trigger attached; failing that it falls back to
	 * INDIO_BUFFER_SOFTWARE, which is this driver's FIFO path. So a
	 * trigger in current_trigger means the pollfunc above is about to
	 * run and the part's own FIFO must stay in bypass with its
	 * watermark interrupt off, or both paths would fill the same
	 * buffer and the capture would carry twice as many samples as
	 * either path produced.
	 *
	 * This branch mirrors the core's condition rather than reading
	 * its decision, because the mode itself is not a public field of
	 * struct iio_dev in this kernel. If the two ever disagree the
	 * symptom is doubled samples or none, so the condition is named
	 * here and asserted in tests/adxl345-driver-test.sh.
	 */
	if (indio_dev->trig)
		return 0;

	ret = regmap_write(st->regmap, BENCH_ADXL345_FIFO_CTL,
			   FIELD_PREP(BENCH_ADXL345_FIFO_CTL_MODE,
				      BENCH_ADXL345_FIFO_STREAM) |
			   FIELD_PREP(BENCH_ADXL345_FIFO_CTL_SAMPLES,
				      st->watermark));
	if (ret)
		return ret;

	return regmap_update_bits(st->regmap, BENCH_ADXL345_INT_ENABLE,
				  BENCH_ADXL345_INT_WATERMARK,
				  BENCH_ADXL345_INT_WATERMARK);
}

/*
 * Called by the IIO core when buffer/watermark is written. The value is
 * remembered and programmed at the next enable rather than written to
 * FIFO_CTL here, because FIFO_CTL also carries the mode and a write
 * while streaming would restart the FIFO under the reader.
 *
 * Clamped to the FIFO's depth less one: a watermark of 32 on a 32-deep
 * FIFO leaves no room to service the interrupt before an overrun, which
 * is the reason the default sits at 24. Zero would never interrupt, so
 * the floor is one. Added Friday 9 October 2026, the night the FIFO
 * path first ran, so that the rate iio-rate asks for is the rate the
 * part is given, and a watermark of 8 interrupts three times as often as
 * one of 24 rather than exactly as often.
 */
static int bench_adxl345_set_watermark(struct iio_dev *indio_dev,
				       unsigned int val)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);

	st->watermark = clamp_val(val, 1U, BENCH_ADXL345_FIFO_DEPTH - 1U);
	return 0;
}

static int bench_adxl345_buffer_predisable(struct iio_dev *indio_dev)
{
	struct bench_adxl345 *st = iio_priv(indio_dev);
	int ret;

	/*
	 * The same condition as the postenable, for symmetry rather than
	 * for safety: the two writes below are idempotent and would do no
	 * harm on the triggered path. A trigger cannot be attached or
	 * detached while a buffer is enabled, so the mode this sees is
	 * the mode the postenable saw.
	 */
	if (indio_dev->trig)
		return 0;

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

/*
 * Thresholds and timings, written once at probe. The values and the
 * reasoning behind each are in bench-adxl345.h beside the registers.
 */
static int bench_adxl345_setup_events(struct regmap *regmap)
{
	static const struct {
		unsigned int reg;
		unsigned int val;
	} setup[] = {
		{ BENCH_ADXL345_TAP_AXES, BENCH_ADXL345_TAP_AXES_XYZ },
		{ BENCH_ADXL345_THRESH_TAP, BENCH_ADXL345_THRESH_TAP_DEFAULT },
		{ BENCH_ADXL345_DUR, BENCH_ADXL345_DUR_DEFAULT },
		{ BENCH_ADXL345_LATENT, BENCH_ADXL345_LATENT_DEFAULT },
		{ BENCH_ADXL345_WINDOW, BENCH_ADXL345_WINDOW_DEFAULT },
		{ BENCH_ADXL345_THRESH_FF, BENCH_ADXL345_THRESH_FF_DEFAULT },
		{ BENCH_ADXL345_TIME_FF, BENCH_ADXL345_TIME_FF_DEFAULT },
	};
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(setup); i++) {
		ret = regmap_write(regmap, setup[i].reg, setup[i].val);
		if (ret)
			return ret;
	}

	return 0;
}

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
	st->watermark = BENCH_ADXL345_WATERMARK_DEFAULT;
	/* Set further down, from the rate this probe writes rather than
	 * from the reset value it used to assume. */
	st->period_ns = 0;

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
	 * EVERY BIT OF EVERY REGISTER THIS DRIVER DEPENDS ON, WRITTEN
	 * RATHER THAN MERGED, and the reason is the part itself.
	 *
	 * The ADXL345 has no reset pin and no software reset. Its
	 * registers keep their values across a warm reboot and across a
	 * driver unbind: only removing power returns them to the
	 * datasheet's defaults. So whatever any earlier session left
	 * behind is what this probe inherits, and an update_bits over a
	 * partial mask leaves all of it in place.
	 *
	 * Read off the bench on Friday 16 October 2026, after an evening
	 * in which several writes had failed mid-transfer on a marginal
	 * bus, the part held:
	 *
	 *   DATA_FORMAT  0xaf   SELF_TEST set, INT_INVERT set, Justify set
	 *   OFSX/Y/Z     0xa9 0xba 0x7a   up to 1.9 g of trim, from nowhere
	 *   BW_RATE      0x07   12.5 Hz, while this driver assumed 100
	 *   INT_ENABLE   0xba   data ready, activity and inactivity on
	 *
	 * Each of those produces readings that look like data. Justify
	 * left-aligns the word, so every value is eight times too large;
	 * SELF_TEST applies an electrostatic force that deflects the beam;
	 * the offset registers add a trim at 15.6 mg a count; INT_INVERT
	 * makes the interrupt active low while the device tree asks for
	 * level high. Nothing in the driver could have noticed any of it.
	 *
	 * The fix is not cleverness, it is coverage: write the whole byte
	 * wherever the configuration matters, so that probe puts the part
	 * in a known state from any starting state.
	 */
	ret = regmap_write(regmap, BENCH_ADXL345_DATA_FORMAT,
			   BENCH_ADXL345_DATA_FORMAT_FULL_RES |
			   FIELD_PREP(BENCH_ADXL345_DATA_FORMAT_RANGE,
				      BENCH_ADXL345_RANGE_16G));
	if (ret)
		return dev_err_probe(dev, ret, "cannot set DATA_FORMAT\n");

	/*
	 * The user offset trim, back to zero. These three are the ones
	 * that cost the most to find, because a constant added to an axis
	 * is indistinguishable from a part that is sitting at an angle.
	 */
	ret = regmap_write(regmap, BENCH_ADXL345_OFSX, 0);
	if (!ret)
		ret = regmap_write(regmap, BENCH_ADXL345_OFSY, 0);
	if (!ret)
		ret = regmap_write(regmap, BENCH_ADXL345_OFSZ, 0);
	if (ret)
		return dev_err_probe(dev, ret, "cannot clear the offsets\n");

	/*
	 * The output data rate, written rather than assumed, and the
	 * cached period set from the same constant so the two cannot
	 * drift apart.
	 */
	ret = regmap_write(regmap, BENCH_ADXL345_BW_RATE,
			   BENCH_ADXL345_RATE_DEFAULT);
	if (ret)
		return dev_err_probe(dev, ret, "cannot set the output rate\n");

	st->period_ns = bench_adxl345_period_ns(BENCH_ADXL345_RATE_DEFAULT -
						BENCH_ADXL345_RATE_FIRST);

	/*
	 * Every interrupt off. What the buffer needs is enabled in
	 * postenable and what an event needs is enabled from sysfs, so
	 * anything set here is something nobody asked for.
	 */
	ret = regmap_write(regmap, BENCH_ADXL345_INT_ENABLE, 0);
	if (ret)
		return dev_err_probe(dev, ret, "cannot clear INT_ENABLE\n");

	ret = regmap_write(regmap, BENCH_ADXL345_FIFO_CTL,
			   FIELD_PREP(BENCH_ADXL345_FIFO_CTL_MODE,
				      BENCH_ADXL345_FIFO_BYPASS));
	if (ret)
		return dev_err_probe(dev, ret, "cannot reset the FIFO\n");

	/*
	 * The event parameters, so that enabling an event from sysfs is
	 * enough to make it fire. Two of these registers reset to zero
	 * and zero is not a neutral value for either: DUR of zero
	 * disables tap detection outright, and Latent or Window of zero
	 * disables double tap, which the datasheet says on page 15 of
	 * Revision 0. Nothing here touches INT_ENABLE, so no event is
	 * armed until userspace asks for one.
	 */
	ret = bench_adxl345_setup_events(regmap);
	if (ret)
		return dev_err_probe(dev, ret,
				     "cannot set the event parameters\n");

	/*
	 * Measurement on and every other bit off, written whole for the
	 * reason given above: the link and wakeup bits were set on the
	 * bench with nothing in this driver having written them.
	 */
	ret = regmap_write(regmap, BENCH_ADXL345_POWER_CTL,
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

	/*
	 * No interrupt, no events. The event channel is last in the
	 * array, so registering one channel fewer drops the three event
	 * attributes with it. Leaving them visible on a board whose INT1
	 * is not wired would offer an enable that writes a register and
	 * then waits for a line nothing drives, which is the failure the
	 * overlay in bench-adxl345-dt refuses for the same pin.
	 */
	if (st->irq <= 0)
		indio_dev->num_channels--;

	/*
	 * ONE BUFFER, TWO PATHS INTO IT.
	 *
	 * The kfifo is attached whatever is wired, because the triggered
	 * path needs it and does not need the part's interrupt. Until
	 * Saturday 17 October 2026 this call sat inside the branch below
	 * and a board with no INT1 had no buffer at all, which is what
	 * docs/DESIGN.md described as the sysfs-only case.
	 *
	 * The helper declares INDIO_BUFFER_SOFTWARE as it attaches the
	 * buffer, which is this driver's name for the FIFO path, so with
	 * no interrupt that mode is taken back again below: a reader who
	 * enabled it would wait on a buffer nothing can push into, with
	 * no error anywhere to say why.
	 */
	ret = devm_iio_kfifo_buffer_setup(dev, indio_dev,
					  &bench_adxl345_buffer_ops);
	if (ret)
		return ret;

	/*
	 * And the triggered path, built from the three exported functions
	 * rather than from iio_triggered_buffer_setup, which is the
	 * helper every in-tree driver uses for this.
	 *
	 * The helper lives behind CONFIG_IIO_TRIGGERED_BUFFER, which has
	 * no prompt in drivers/iio/Kconfig and is reached only by an
	 * in-tree "select". A configuration fragment asking for it
	 * directly is a line kconfig drops without a word, and this
	 * module is out of tree and can select nothing. Depending on
	 * some unrelated in-tree driver to select it would make this
	 * driver's buffer a side effect of another driver's presence.
	 *
	 * What it does is attach a kfifo, allocate a pollfunc and set the
	 * mode bit. The kfifo is above, and the other two are here.
	 * CONFIG_IIO_TRIGGER is all this needs, it is =y in bench.cfg for
	 * every image in this repository, and ./go ksym is where that
	 * claim is checked.
	 *
	 * The name is the thread name the trigger's consumer runs under
	 * and shows up in ps; in-tree spells it with iio_device_id, and
	 * dev_name is already unique per instance.
	 */
	indio_dev->pollfunc = iio_alloc_pollfunc(iio_pollfunc_store_time,
						 bench_adxl345_trigger_handler,
						 IRQF_ONESHOT, indio_dev,
						 "%s_consumer", dev_name(dev));
	if (!indio_dev->pollfunc)
		return -ENOMEM;

	ret = devm_add_action_or_reset(dev, bench_adxl345_free_pollfunc,
				       indio_dev->pollfunc);
	if (ret)
		return ret;

	indio_dev->modes |= INDIO_BUFFER_TRIGGERED;

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
						indio_dev->name, indio_dev);
		if (ret)
			return dev_err_probe(dev, ret,
					     "cannot request irq %d\n",
					     st->irq);
	} else {
		/*
		 * No interrupt in the device tree costs the events and the
		 * part's own FIFO, and leaves the polled and triggered
		 * paths working. Said once at probe so that a buffer which
		 * only fills when a trigger is attached is explained
		 * rather than mysterious.
		 */
		indio_dev->modes &= ~INDIO_BUFFER_SOFTWARE;
		dev_info(dev,
			 "no interrupt: no events, no fifo, buffer needs a trigger\n");
	}

	return devm_iio_device_register(dev, indio_dev);
}
/*
 * The namespace is an identifier, not a string. Kernels from 6.13 take a
 * quoted string here; 6.6, which this image carries, stringifies the
 * argument itself, so a quoted spelling would have made the quotes part
 * of the namespace name on both the export and the two imports. The
 * bus files spell it the same way for the same reason.
 */
EXPORT_SYMBOL_NS_GPL(bench_adxl345_core_probe, BENCH_ADXL345);

MODULE_AUTHOR("Joseph Ambrose Pagaran");
MODULE_DESCRIPTION("ADXL345 three axis accelerometer, bench IIO driver");
MODULE_LICENSE("GPL");
