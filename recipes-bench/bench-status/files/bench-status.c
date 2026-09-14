/*
 * bench-status - mirror /run/bench/state onto three LEDs.
 *
 *   green   "ok"        every watched unit is active
 *   yellow  "starting"  the system is still coming up
 *   red     "failed"    a watched unit failed or was stopped
 *
 * The policy of what counts as healthy lives in systemd and in
 * bench-state(8), which writes one word into the state file. This program
 * owns the mechanism only: read a word, drive three lines. Splitting it
 * that way keeps the C short enough to read in one sitting and leaves unit
 * ordering, restart policy and logging where they belong.
 *
 * Line offsets and polarity come from /etc/bench/leds.conf, so rewiring the
 * breadboard does not mean rebuilding the image.
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

#define STATE_PATH     "/run/bench/state"
#define LEDS_CONF      "/etc/bench/leds.conf"
#define DEFAULT_LABEL  "pinctrl-bcm2711"   /* Raspberry Pi 4 SoC GPIO */
#define DEFAULT_PERIOD 1000                /* ms */
#define MAX_CHIPS      32

enum { GREEN, YELLOW, RED, LED_COUNT };

struct config {
	unsigned int offset[LED_COUNT];
	bool active_low;
	char chip_label[64];
	char chip_path[64];
	long period_ms;
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
	if (!strcmp(key, "green"))
		cfg->offset[GREEN] = (unsigned int)strtoul(value, NULL, 10);
	else if (!strcmp(key, "yellow"))
		cfg->offset[YELLOW] = (unsigned int)strtoul(value, NULL, 10);
	else if (!strcmp(key, "red"))
		cfg->offset[RED] = (unsigned int)strtoul(value, NULL, 10);
	else if (!strcmp(key, "active_low"))
		cfg->active_low = strtol(value, NULL, 10) != 0;
	else if (!strcmp(key, "period_ms"))
		cfg->period_ms = strtol(value, NULL, 10);
	else if (!strcmp(key, "chip_label"))
		snprintf(cfg->chip_label, sizeof cfg->chip_label, "%s", value);
	else if (!strcmp(key, "chip"))
		snprintf(cfg->chip_path, sizeof cfg->chip_path, "%s", value);
	else
		fprintf(stderr, "bench-status: ignoring unknown key %s\n", key);
}

/*
 * Defaults first, then the file, then the environment: the environment wins
 * so that a bring-up session can override without editing anything.
 */
static void load_config(struct config *cfg)
{
	const char *env;
	char line[160];
	FILE *f;

	cfg->offset[GREEN] = 17;
	cfg->offset[YELLOW] = 27;
	cfg->offset[RED] = 22;
	cfg->active_low = false;
	cfg->period_ms = DEFAULT_PERIOD;
	snprintf(cfg->chip_label, sizeof cfg->chip_label, "%s", DEFAULT_LABEL);
	cfg->chip_path[0] = '\0';

	f = fopen(LEDS_CONF, "r");
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
	env = getenv("BENCH_PERIOD_MS");
	if (env && *env)
		cfg->period_ms = strtol(env, NULL, 10);

	if (cfg->period_ms < 10 || cfg->period_ms > 60000)
		cfg->period_ms = DEFAULT_PERIOD;
}

static bool chip_is_wide_enough(struct gpiod_chip_info *info,
				const struct config *cfg)
{
	size_t lines = gpiod_chip_info_get_num_lines(info);
	int i;

	for (i = 0; i < LED_COUNT; i++)
		if (lines <= cfg->offset[i])
			return false;
	return true;
}

/*
 * Find the GPIO chip that carries the 40-pin header.
 *
 * /dev/gpiochip0 is the header on a Pi 4 but not on every board, and the
 * numbering moves when an expander is probed first. Matching the label is
 * stable across kernel versions; the width check is only a fallback so that
 * the daemon still starts on a board nobody has taught it about yet.
 */
static struct gpiod_chip *open_header_chip(const struct config *cfg)
{
	struct gpiod_chip *fallback = NULL;
	char path[32];
	int i;

	if (cfg->chip_path[0]) {
		struct gpiod_chip *chip = gpiod_chip_open(cfg->chip_path);

		if (!chip)
			fprintf(stderr, "bench-status: %s: %s\n",
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
		fprintf(stderr, "bench-status: no chip labelled %s, using the "
			"first wide enough chip\n", cfg->chip_label);
		return fallback;
	}

	fprintf(stderr, "bench-status: no usable GPIO chip found\n");
	return NULL;
}

static struct gpiod_line_request *request_leds(struct gpiod_chip *chip,
					       const struct config *cfg)
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
	/*
	 * The kernel inverts the line for us, so the rest of the program can
	 * talk about active and inactive and never about volts.
	 */
	gpiod_line_settings_set_active_low(settings, cfg->active_low);
	gpiod_line_settings_set_output_value(settings,
					     GPIOD_LINE_VALUE_INACTIVE);

	if (gpiod_line_config_add_line_settings(line_cfg, cfg->offset,
						LED_COUNT, settings))
		goto out;

	gpiod_request_config_set_consumer(req_cfg, "bench-status");

	request = gpiod_chip_request_lines(chip, req_cfg, line_cfg);
	if (!request)
		fprintf(stderr, "bench-status: requesting lines %u/%u/%u: %s\n",
			cfg->offset[GREEN], cfg->offset[YELLOW],
			cfg->offset[RED], strerror(errno));

out:
	if (req_cfg)
		gpiod_request_config_free(req_cfg);
	if (line_cfg)
		gpiod_line_config_free(line_cfg);
	if (settings)
		gpiod_line_settings_free(settings);
	return request;
}

/* Absent or unreadable state file means the system has not reported yet. */
static void read_state(char *buf, size_t len)
{
	FILE *f;

	snprintf(buf, len, "starting");

	f = fopen(STATE_PATH, "r");
	if (!f)
		return;

	if (fgets(buf, (int)len, f))
		buf[strcspn(buf, "\r\n")] = '\0';
	fclose(f);

	if (buf[0] == '\0')
		snprintf(buf, len, "starting");
}

int main(void)
{
	struct gpiod_line_request *request;
	struct gpiod_chip *chip;
	struct timespec interval;
	struct config cfg;
	int rc = 1;

	setvbuf(stdout, NULL, _IOLBF, 0);

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	load_config(&cfg);

	printf("bench-status: lines %u/%u/%u, active %s\n",
	       cfg.offset[GREEN], cfg.offset[YELLOW], cfg.offset[RED],
	       cfg.active_low ? "low" : "high");

	chip = open_header_chip(&cfg);
	if (!chip)
		return 1;

	request = request_leds(chip, &cfg);
	if (!request) {
		gpiod_chip_close(chip);
		return 1;
	}

	interval.tv_sec = cfg.period_ms / 1000;
	interval.tv_nsec = (cfg.period_ms % 1000) * 1000000L;

	while (!stop_requested) {
		enum gpiod_line_value values[LED_COUNT] = {
			GPIOD_LINE_VALUE_INACTIVE,
			GPIOD_LINE_VALUE_INACTIVE,
			GPIOD_LINE_VALUE_INACTIVE,
		};
		char state[32];

		read_state(state, sizeof state);

		if (!strcmp(state, "ok"))
			values[GREEN] = GPIOD_LINE_VALUE_ACTIVE;
		else if (!strcmp(state, "failed"))
			values[RED] = GPIOD_LINE_VALUE_ACTIVE;
		else
			values[YELLOW] = GPIOD_LINE_VALUE_ACTIVE;

		if (gpiod_line_request_set_values(request, values)) {
			fprintf(stderr, "bench-status: set_values: %s\n",
				strerror(errno));
			goto out;
		}

		nanosleep(&interval, NULL);
	}

	rc = 0;
out:
	/*
	 * Releasing the request returns the lines to input, so the LEDs go
	 * dark on a clean stop instead of freezing on the last colour.
	 */
	gpiod_line_request_release(request);
	gpiod_chip_close(chip);
	return rc;
}
