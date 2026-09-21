/* SPDX-License-Identifier: MIT
 *
 * The dashboard: four readings and a status LED, refreshed twice a
 * second.
 *
 * Nothing here opens a device. The widgets receive touch and keyboard
 * through LVGL's Wayland input devices, and the numbers come from
 * metrics.c, which reads files. If this file ever grows an open() on
 * /dev/input, the design has gone wrong and the compositor is being
 * bypassed.
 *
 * THE RENDERING RULE THAT MATTERS: a reading that could not be taken is
 * drawn as "n/a", never as a number. metrics.c returns -1 for a failed
 * read precisely so that this file can tell the difference between "the
 * load is 0.00" and "there is no /proc/loadavg", which look identical
 * once a zero has been formatted into a label.
 */

#include "dashboard.h"
#include "metrics.h"

#include <stdio.h>

static lv_obj_t *lbl_load;
static lv_obj_t *lbl_temp;
static lv_obj_t *bar_mem;
static lv_obj_t *lbl_mem;
static lv_obj_t *led_state;
static lv_obj_t *lbl_state;

/*
 * The layout is fixed rather than responsive: 800x480 is the only output
 * this application will ever have. The size itself is NOT duplicated
 * here. main.c owns it, because it is what creates the window, and two
 * copies of a constant are two things to keep in step.
 *
 * Widgets are placed with lv_obj_align against the parent, so nothing in
 * this file needs to know the number.
 */

static void set_reading(lv_obj_t *label, const char *fmt, double value,
			const char *unit)
{
	if (value < 0.0) {
		lv_label_set_text_fmt(label, "%s  n/a", unit);
		return;
	}
	lv_label_set_text_fmt(label, fmt, value);
}

static void metrics_timer(lv_timer_t *timer)
{
	char state_word[BENCH_STATE_MAX];
	bench_state_t state;
	double mem;

	(void)timer;

	set_reading(lbl_load, "load  %.2f", metrics_loadavg(), "load");
	set_reading(lbl_temp, "SoC   %.1f C", metrics_soc_temp_c(), "SoC");

	mem = metrics_mem_used_percent();
	if (mem < 0.0) {
		lv_bar_set_value(bar_mem, 0, LV_ANIM_OFF);
		lv_label_set_text(lbl_mem, "memory  n/a");
	} else {
		lv_bar_set_value(bar_mem, (int32_t)(mem + 0.5), LV_ANIM_ON);
		lv_label_set_text_fmt(lbl_mem, "memory  %.0f %%", mem);
	}

	state = metrics_bench_state(state_word, sizeof state_word);
	lv_label_set_text(lbl_state, state_word);

	switch (state) {
	case BENCH_STATE_OK:
		lv_led_set_color(led_state, lv_palette_main(LV_PALETTE_GREEN));
		break;
	case BENCH_STATE_FAILED:
		lv_led_set_color(led_state, lv_palette_main(LV_PALETTE_RED));
		break;
	case BENCH_STATE_STARTING:
	case BENCH_STATE_UNKNOWN:
	default:
		/*
		 * Both yellow, and deliberately so, but they are not the
		 * same condition: "starting" changes on its own and
		 * "unknown" does not. The word underneath the LED is what
		 * distinguishes them, which is why the word is displayed
		 * rather than only the colour.
		 */
		lv_led_set_color(led_state, lv_palette_main(LV_PALETTE_YELLOW));
		break;
	}
	lv_led_on(led_state);
}

void dashboard_create(lv_obj_t *parent, lv_group_t *keyboard_group)
{
	lv_obj_t *title;
	lv_timer_t *timer;

	lv_obj_set_style_bg_color(parent, lv_color_hex(0x101418), LV_PART_MAIN);
	lv_obj_set_style_text_color(parent, lv_color_hex(0xE6E6E6), LV_PART_MAIN);

	title = lv_label_create(parent);
	lv_label_set_text(title, "bench");
	lv_obj_align(title, LV_ALIGN_TOP_LEFT, 20, 12);

	lbl_load = lv_label_create(parent);
	lv_obj_align(lbl_load, LV_ALIGN_TOP_LEFT, 20, 60);

	lbl_temp = lv_label_create(parent);
	lv_obj_align(lbl_temp, LV_ALIGN_TOP_LEFT, 20, 100);

	lbl_mem = lv_label_create(parent);
	lv_obj_align(lbl_mem, LV_ALIGN_TOP_LEFT, 20, 140);

	bar_mem = lv_bar_create(parent);
	lv_obj_set_size(bar_mem, 400, 20);
	lv_bar_set_range(bar_mem, 0, 100);
	lv_obj_align(bar_mem, LV_ALIGN_TOP_LEFT, 20, 174);

	led_state = lv_led_create(parent);
	lv_obj_set_size(led_state, 64, 64);
	lv_obj_align(led_state, LV_ALIGN_TOP_RIGHT, -60, 40);

	lbl_state = lv_label_create(parent);
	lv_obj_align(lbl_state, LV_ALIGN_TOP_RIGHT, -60, 120);

	/*
	 * The group exists even when there is no keyboard, because the
	 * touch path does not need it and the keyboard path cannot work
	 * without it. Adding widgets to a group with no indev attached is
	 * harmless.
	 */
	if (keyboard_group) {
		lv_group_add_obj(keyboard_group, bar_mem);
	}

	/* Draw once immediately rather than showing empty labels for the
	 * first half second. On a project whose acceptance criterion is
	 * time to first frame, half a second of blank widgets is not a
	 * detail. */
	timer = lv_timer_create(metrics_timer, DASHBOARD_REFRESH_MS, NULL);
	lv_timer_ready(timer);
}
