/*
 * lte-gpio - the two control lines of the SIM7600E-H HAT.
 *
 *   lte-gpio pwrkey [ms]   press the power key for ms (default from config)
 *   lte-gpio flight-hold   hold the FLIGHT line inactive until signalled
 *   lte-gpio info          print the chip and the offsets, then exit
 *
 * This is mechanism only. Whether the modem should be power-cycled, and
 * after how many failed probes, is policy and lives in lte-watchdog, which
 * runs this program. The split is the same one bench-status made in
 * Project 1 and it buys the same thing: the policy can be tested on a
 * laptop with no GPIO chip anywhere, because the only thing it does to the
 * hardware is run a command that a stub can replace.
 *
 * It also keeps a Python interpreter out of the GPIO path. The book's
 * version calls libgpiod through its Python bindings; those bindings are a
 * separate package whose name and availability differ between Yocto
 * releases, and a power-cycle path that fails to import is a power-cycle
 * path that does not exist.
 *
 * FLIGHT needs holding rather than pulsing. The HAT pulls the line up, and
 * a program that drives it low and exits gives the line straight back to
 * the kernel, which returns it to an input and lets the pull-up put the
 * radio into flight mode. So flight-hold blocks: the line is released when
 * the service stops, which is the correct coupling.
 *
 * Written against the libgpiod v2 API.
 *
 * SPDX-License-Identifier: MIT
 */

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <gpiod.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define LTE_CONF      "/etc/bench/lte.conf"
#define DEFAULT_LABEL "pinctrl-bcm2711"   /* Raspberry Pi 4 SoC GPIO */
#define MAX_CHIPS     32

struct config {
	unsigned int pwrkey;
	unsigned int flight;
	long press_ms;
	bool pwrkey_active_low;
	bool flight_active_low;
	char chip_label[64];
	char chip_path[64];
};

static volatile sig_atomic_t stop_requested;

static void on_signal(int sig)
{
	(void)sig;
	stop_requested = 1;
}

static void trim(char *s)
{
	char *end;

	while (*s == ' ' || *s == '\t')
		memmove(s, s + 1, strlen(s));
	end = s + strlen(s);
	while (end > s && (end[-1] == ' ' || end[-1] == '\t' ||
			   end[-1] == '\n' || end[-1] == '\r'))
		*--end = '\0';
}

static void set_option(struct config *cfg, const char *key, const char *value)
{
	if (!strcmp(key, "pwrkey"))
		cfg->pwrkey = (unsigned int)strtoul(value, NULL, 10);
	else if (!strcmp(key, "flight"))
		cfg->flight = (unsigned int)strtoul(value, NULL, 10);
	else if (!strcmp(key, "pwrkey_press_ms"))
		cfg->press_ms = strtol(value, NULL, 10);
	else if (!strcmp(key, "pwrkey_active_low"))
		cfg->pwrkey_active_low = strtol(value, NULL, 10) != 0;
	else if (!strcmp(key, "flight_active_low"))
		cfg->flight_active_low = strtol(value, NULL, 10) != 0;
	else if (!strcmp(key, "chip_label"))
		snprintf(cfg->chip_label, sizeof cfg->chip_label, "%s", value);
	else if (!strcmp(key, "chip"))
		snprintf(cfg->chip_path, sizeof cfg->chip_path, "%s", value);
	/* Keys this program does not own belong to lte-watchdog. */
}

/*
 * Defaults, then the file, then the environment. The defaults are the
 * Waveshare demo's jumper positions, which is a starting point and not a
 * promise: the HAT revision decides, and the config file is how a different
 * revision is accommodated without a rebuild.
 */
static void load_config(struct config *cfg)
{
	const char *env;
	char line[160];
	FILE *f;

	cfg->pwrkey = 6;
	cfg->flight = 4;
	cfg->press_ms = 1200;
	cfg->pwrkey_active_low = false;
	cfg->flight_active_low = false;
	snprintf(cfg->chip_label, sizeof cfg->chip_label, "%s", DEFAULT_LABEL);
	cfg->chip_path[0] = '\0';

	f = fopen(LTE_CONF, "r");
	if (f) {
		while (fgets(line, sizeof line, f)) {
			char *hash = strchr(line, '#');
			char *eq;

			if (hash)
				*hash = '\0';
			eq = strchr(line, '=');
			if (!eq)
				continue;
			*eq = '\0';
			trim(line);
			trim(eq + 1);
			if (line[0] && eq[1])
				set_option(cfg, line, eq + 1);
		}
		fclose(f);
	}

	env = getenv("BENCH_GPIOCHIP");
	if (env && *env)
		snprintf(cfg->chip_path, sizeof cfg->chip_path, "%s", env);
	env = getenv("BENCH_CHIP_LABEL");
	if (env && *env)
		snprintf(cfg->chip_label, sizeof cfg->chip_label, "%s", env);

	if (cfg->press_ms < 50 || cfg->press_ms > 10000)
		cfg->press_ms = 1200;
}

static bool chip_is_wide_enough(struct gpiod_chip_info *info,
				const struct config *cfg)
{
	size_t lines = gpiod_chip_info_get_num_lines(info);

	return lines > cfg->pwrkey && lines > cfg->flight;
}

/*
 * The same search bench-status does: match the label, fall back to the
 * first chip wide enough. /dev/gpiochip0 is the header on a Pi 4 and is not
 * on every board, and the numbering moves when an expander probes first.
 */
static struct gpiod_chip *open_header_chip(const struct config *cfg)
{
	struct gpiod_chip *fallback = NULL;
	char path[32];
	int i;

	if (cfg->chip_path[0]) {
		struct gpiod_chip *chip = gpiod_chip_open(cfg->chip_path);

		if (!chip)
			fprintf(stderr, "lte-gpio: %s: %s\n",
				cfg->chip_path, strerror(errno));
		return chip;
	}

	for (i = 0; i < MAX_CHIPS; i++) {
		struct gpiod_chip_info *info;
		struct gpiod_chip *chip;
		bool matched;

		snprintf(path, sizeof path, "/dev/gpiochip%d", i);
		if (!gpiod_is_gpiochip_device(path))
			continue;

		chip = gpiod_chip_open(path);
		if (!chip)
			continue;

		info = gpiod_chip_get_info(chip);
		if (!info) {
			gpiod_chip_close(chip);
			continue;
		}

		matched = !strcmp(gpiod_chip_info_get_label(info),
				  cfg->chip_label);

		if (!matched && !fallback && chip_is_wide_enough(info, cfg)) {
			gpiod_chip_info_free(info);
			fallback = chip;
			continue;
		}

		gpiod_chip_info_free(info);

		if (matched) {
			if (fallback)
				gpiod_chip_close(fallback);
			return chip;
		}

		gpiod_chip_close(chip);
	}

	if (fallback) {
		fprintf(stderr, "lte-gpio: no chip labelled %s, using the "
			"first wide enough chip\n", cfg->chip_label);
		return fallback;
	}

	fprintf(stderr, "lte-gpio: no usable GPIO chip found\n");
	return NULL;
}

static struct gpiod_line_request *request_line(struct gpiod_chip *chip,
					       unsigned int offset,
					       bool active_low,
					       const char *consumer)
{
	struct gpiod_request_config *req_cfg = NULL;
	struct gpiod_line_config *line_cfg = NULL;
	struct gpiod_line_settings *settings = NULL;
	struct gpiod_line_request *request = NULL;

	settings = gpiod_line_settings_new();
	line_cfg = gpiod_line_config_new();
	req_cfg = gpiod_request_config_new();
	if (!settings || !line_cfg || !req_cfg)
		goto out;

	gpiod_line_settings_set_direction(settings,
					  GPIOD_LINE_DIRECTION_OUTPUT);
	gpiod_line_settings_set_active_low(settings, active_low);
	gpiod_line_settings_set_output_value(settings,
					     GPIOD_LINE_VALUE_INACTIVE);

	if (gpiod_line_config_add_line_settings(line_cfg, &offset, 1, settings))
		goto out;

	gpiod_request_config_set_consumer(req_cfg, consumer);
	request = gpiod_chip_request_lines(chip, req_cfg, line_cfg);
	if (!request)
		fprintf(stderr, "lte-gpio: cannot request line %u: %s\n",
			offset, strerror(errno));

out:
	if (req_cfg)
		gpiod_request_config_free(req_cfg);
	if (line_cfg)
		gpiod_line_config_free(line_cfg);
	if (settings)
		gpiod_line_settings_free(settings);
	return request;
}

static void sleep_ms(long ms)
{
	struct timespec ts;

	ts.tv_sec = ms / 1000;
	ts.tv_nsec = (ms % 1000) * 1000000L;
	while (nanosleep(&ts, &ts) == -1 && errno == EINTR && !stop_requested)
		;
}

static int do_pwrkey(struct gpiod_chip *chip, const struct config *cfg,
		     long press_ms)
{
	struct gpiod_line_request *request;

	request = request_line(chip, cfg->pwrkey, cfg->pwrkey_active_low,
			       "lte-gpio-pwrkey");
	if (!request)
		return 1;

	printf("lte-gpio: pressing PWRKEY on offset %u for %ld ms\n",
	       cfg->pwrkey, press_ms);

	if (gpiod_line_request_set_value(request, cfg->pwrkey,
					 GPIOD_LINE_VALUE_ACTIVE)) {
		fprintf(stderr, "lte-gpio: set failed: %s\n", strerror(errno));
		gpiod_line_request_release(request);
		return 1;
	}

	sleep_ms(press_ms);

	gpiod_line_request_set_value(request, cfg->pwrkey,
				     GPIOD_LINE_VALUE_INACTIVE);
	gpiod_line_request_release(request);
	return 0;
}

static int do_flight_hold(struct gpiod_chip *chip, const struct config *cfg)
{
	struct gpiod_line_request *request;

	request = request_line(chip, cfg->flight, cfg->flight_active_low,
			       "lte-gpio-flight");
	if (!request)
		return 1;

	printf("lte-gpio: holding FLIGHT inactive on offset %u\n", cfg->flight);
	fflush(stdout);

	while (!stop_requested)
		pause();

	gpiod_line_request_release(request);
	return 0;
}

static void usage(void)
{
	fprintf(stderr, "usage: lte-gpio pwrkey [ms] | flight-hold | info\n");
}

int main(int argc, char **argv)
{
	struct sigaction sa;
	struct config cfg;
	struct gpiod_chip *chip;
	int status;

	if (argc < 2) {
		usage();
		return 2;
	}

	load_config(&cfg);

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_signal;
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	chip = open_header_chip(&cfg);
	if (!chip)
		return 1;

	if (!strcmp(argv[1], "info")) {
		struct gpiod_chip_info *info = gpiod_chip_get_info(chip);

		printf("chip %s, pwrkey offset %u, flight offset %u\n",
		       info ? gpiod_chip_info_get_label(info) : "unknown",
		       cfg.pwrkey, cfg.flight);
		if (info)
			gpiod_chip_info_free(info);
		status = 0;
	} else if (!strcmp(argv[1], "pwrkey")) {
		long ms = argc > 2 ? strtol(argv[2], NULL, 10) : cfg.press_ms;

		if (ms < 50 || ms > 10000)
			ms = cfg.press_ms;
		status = do_pwrkey(chip, &cfg, ms);
	} else if (!strcmp(argv[1], "flight-hold")) {
		status = do_flight_hold(chip, &cfg);
	} else {
		usage();
		status = 2;
	}

	gpiod_chip_close(chip);
	return status;
}
