// SPDX-License-Identifier: GPL-2.0-only
/*
 * bench-adxl345-spi.c - the SPI half of the seam.
 *
 * The same shape as the I2C file, and the differences between them are
 * the entire reason the core does not care which one is loaded.
 *
 * Three things are SPI specific on this part, and all three are in the
 * regmap configuration below rather than anywhere the core can see:
 *
 *   read_flag_mask  bit 7 of the first byte means read
 *   the multi-byte bit  bit 6 must be set to read more than one register
 *                       in a burst, which the FIFO drain depends on
 *   the clock mode   the part is CPOL=1 CPHA=1, which the device tree
 *                    states with spi-cpol and spi-cpha rather than the
 *                    driver assuming it
 *
 * The 5 MHz ceiling is the part's maximum in 4 wire mode and is stated in
 * the device tree as spi-max-frequency, for the same reason: it is a
 * property of the board's wiring quality as much as of the chip.
 */

#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/regmap.h>
#include <linux/spi/spi.h>

#include "bench-adxl345.h"

#define BENCH_ADXL345_SPI_READ		BIT(7)
#define BENCH_ADXL345_SPI_MULTIBYTE	BIT(6)

static const struct regmap_config bench_adxl345_spi_regmap_config = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = BENCH_ADXL345_FIFO_STATUS,

	/*
	 * Both bits, not just the read bit. A single register read works
	 * without the multi-byte bit and the FIFO drain does not, so
	 * setting only READ here produces a driver whose sysfs values are
	 * correct and whose buffer is full of the same sample repeated.
	 * That is a difficult afternoon, and it is avoided by one constant.
	 */
	.read_flag_mask = BENCH_ADXL345_SPI_READ |
			  BENCH_ADXL345_SPI_MULTIBYTE,
};

static int bench_adxl345_spi_probe(struct spi_device *spi)
{
	struct regmap *regmap;

	regmap = devm_regmap_init_spi(spi,
				      &bench_adxl345_spi_regmap_config);
	if (IS_ERR(regmap))
		return dev_err_probe(&spi->dev, PTR_ERR(regmap),
				     "cannot initialise regmap\n");

	return bench_adxl345_core_probe(&spi->dev, regmap, "bench-adxl345");
}

/* See the same table in the I2C file for why this string and not adi's. */
static const struct of_device_id bench_adxl345_of_match[] = {
	{ .compatible = "bench,adxl345" },
	{ }
};
MODULE_DEVICE_TABLE(of, bench_adxl345_of_match);

static const struct spi_device_id bench_adxl345_spi_id[] = {
	{ "bench-adxl345" },
	{ }
};
MODULE_DEVICE_TABLE(spi, bench_adxl345_spi_id);

static struct spi_driver bench_adxl345_spi_driver = {
	.driver = {
		.name = "bench-adxl345-spi",
		.of_match_table = bench_adxl345_of_match,
	},
	.probe = bench_adxl345_spi_probe,
	.id_table = bench_adxl345_spi_id,
};
module_spi_driver(bench_adxl345_spi_driver);

MODULE_AUTHOR("Joseph Ambrose Pagaran");
MODULE_DESCRIPTION("ADXL345 over SPI, bench IIO driver");
MODULE_LICENSE("GPL");
MODULE_IMPORT_NS("BENCH_ADXL345");
