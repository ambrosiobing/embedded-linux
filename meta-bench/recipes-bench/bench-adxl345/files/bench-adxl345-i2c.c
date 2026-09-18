// SPDX-License-Identifier: GPL-2.0-only
/*
 * bench-adxl345-i2c.c - the I2C half of the seam.
 *
 * Everything bus specific about this part on I2C is in this file, and it
 * is almost nothing: a regmap configuration and a driver registration.
 * That is the measure of whether the split worked. If this file grows
 * logic about ranges or rates, the logic is in the wrong place.
 *
 * The part answers at 0x53 with its SDO pin low and 0x1d with it high.
 * Neither address is assumed here: the address comes from the device tree
 * node's reg property, which is where it belongs, and the overlay in this
 * project records which one this bench's board is strapped to.
 */

#include <linux/i2c.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/regmap.h>

#include "bench-adxl345.h"

static const struct regmap_config bench_adxl345_i2c_regmap_config = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = BENCH_ADXL345_FIFO_STATUS,
};

static int bench_adxl345_i2c_probe(struct i2c_client *client)
{
	struct regmap *regmap;

	regmap = devm_regmap_init_i2c(client,
				      &bench_adxl345_i2c_regmap_config);
	if (IS_ERR(regmap))
		return dev_err_probe(&client->dev, PTR_ERR(regmap),
				     "cannot initialise regmap\n");

	return bench_adxl345_core_probe(&client->dev, regmap, "bench-adxl345");
}

/*
 * "bench,adxl345" and nothing else, deliberately.
 *
 * The in-tree driver claims "adi,adxl345". If this table claimed it too,
 * two drivers would match one node and which one bound would depend on
 * module load order: both probe, both register an IIO device, and the
 * readings look plausible either way, so the wrong answer would not
 * announce itself. With separate strings the overlay names which driver
 * it wants, and swapping one word in the overlay turns mainline into a
 * control for this one.
 */
static const struct of_device_id bench_adxl345_of_match[] = {
	{ .compatible = "bench,adxl345" },
	{ }
};
MODULE_DEVICE_TABLE(of, bench_adxl345_of_match);

static const struct i2c_device_id bench_adxl345_i2c_id[] = {
	{ "bench-adxl345" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, bench_adxl345_i2c_id);

static struct i2c_driver bench_adxl345_i2c_driver = {
	.driver = {
		.name = "bench-adxl345-i2c",
		.of_match_table = bench_adxl345_of_match,
	},
	.probe = bench_adxl345_i2c_probe,
	.id_table = bench_adxl345_i2c_id,
};
module_i2c_driver(bench_adxl345_i2c_driver);

MODULE_AUTHOR("Joseph Ambrose Pagaran");
MODULE_DESCRIPTION("ADXL345 over I2C, bench IIO driver");
MODULE_LICENSE("GPL");
MODULE_IMPORT_NS("BENCH_ADXL345");
