/*
 * hello-gpiod - the smallest program that proves the SDK is real.
 *
 * It links against libgpiod from the target sysroot, so building it with
 * the SDK environment and running the result on the board exercises the
 * whole chain: cross compiler, sysroot headers, shared library ABI and
 * kernel interface. If this runs, the other nineteen projects can be
 * cross-compiled on the host.
 *
 * SPDX-License-Identifier: MIT
 */

#include <gpiod.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
	char path[32];
	int found = 0;
	int i;

	printf("hello-gpiod, libgpiod %s\n", gpiod_api_version());

	for (i = 0; i < 32; i++) {
		struct gpiod_chip_info *info;
		struct gpiod_chip *chip;

		snprintf(path, sizeof path, "/dev/gpiochip%d", i);
		if (!gpiod_is_gpiochip_device(path))
			continue;

		chip = gpiod_chip_open(path);
		if (!chip)
			continue;

		info = gpiod_chip_get_info(chip);
		if (info) {
			printf("  %-18s %-20s %zu lines\n", path,
			       gpiod_chip_info_get_label(info),
			       gpiod_chip_info_get_num_lines(info));
			gpiod_chip_info_free(info);
			found++;
		}
		gpiod_chip_close(chip);
	}

	if (!found) {
		fprintf(stderr, "no GPIO chips: is this the target?\n");
		return 1;
	}

	return 0;
}
