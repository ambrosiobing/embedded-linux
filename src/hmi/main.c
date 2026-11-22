/* SPDX-License-Identifier: MIT
 *
 * bench-hmi: the dashboard as a Wayland client.
 *
 * Creates one full screen window, wires the compositor's input devices
 * to a focus group, and runs LVGL's loop until the compositor closes it.
 *
 * THREE THINGS HERE ARE NOT INTERCHANGEABLE WITH THE OBVIOUS
 * ALTERNATIVE, and each one was read out of LVGL 9.3.0's headers rather
 * than written from memory, because the project specification warns that
 * these names move between point releases:
 *
 *   lv_wayland_timer_handler(), NOT lv_timer_handler(). The header says
 *   it "must be called in the application run loop instead of the
 *   regular lv_timer_handler". The Wayland backend needs to service the
 *   protocol socket in the same pass, and the plain handler does not.
 *
 *   lv_wayland_window_create() takes a char *, not a const char *, so
 *   the title lives in a mutable array.
 *
 *   lv_wayland_get_keyboard() and lv_wayland_get_touchscreen() take the
 *   display and return the indev the backend already made. They do not
 *   create one; lv_wayland_keyboard_create() does that, and calling both
 *   would give two input devices for one seat.
 */

#include "dashboard.h"
#include "metrics.h"

#include "lvgl/lvgl.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* The official 7 inch panel. The compositor gives us the whole output,
 * so this is the size of the output rather than a preference. */
#define PANEL_W 800
#define PANEL_H 480

/* Upper bound on how long to sleep between LVGL passes. The handler
 * returns when it next needs to run; this caps that so a long idle
 * period still services input promptly. */
#define MAX_SLEEP_MS 30

static bool window_closed(lv_display_t *disp)
{
	(void)disp;
	/*
	 * Returning true lets the backend destroy the window. The unit
	 * has Restart=always, so a compositor restart brings the
	 * dashboard back rather than leaving a blank screen; that is the
	 * behaviour acceptance asks for.
	 */
	LV_LOG_WARN("bench-hmi: compositor closed the window");
	return true;
}

int main(void)
{
	/* lv_wayland_window_create takes a mutable title. */
	char title[] = "bench-hmi";
	const char *root;
	lv_display_t *disp;
	lv_indev_t *keyboard;
	lv_indev_t *touch;
	lv_group_t *group = NULL;

	/*
	 * Announced at startup, because a dashboard reading a test tree
	 * would otherwise look exactly like one reading the real files
	 * and showing implausible numbers.
	 */
	root = metrics_set_root_from_env();
	if (root && *root)
		printf("bench-hmi: metrics root is %s (BENCH_METRICS_ROOT)\n",
		       root);

	lv_init();

	disp = lv_wayland_window_create(PANEL_W, PANEL_H, title, window_closed);
	if (!disp) {
		fprintf(stderr,
			"bench-hmi: could not create a Wayland window.\n"
			"  Is WAYLAND_DISPLAY set, and is the compositor "
			"running?\n"
			"  Check: wayland-info | grep xdg_wm_base\n");
		return 1;
	}

	/*
	 * The compositor already gives a kiosk client the whole output,
	 * so this is belt and braces rather than the mechanism. It costs
	 * nothing and it makes the intent explicit for the case where
	 * this binary is run under a desktop compositor for debugging.
	 */
	lv_wayland_window_set_fullscreen(disp, true);

	touch = lv_wayland_get_touchscreen(disp);
	keyboard = lv_wayland_get_keyboard(disp);

	if (!touch)
		LV_LOG_WARN("bench-hmi: no touch device from the compositor; "
			    "check wl_seat capabilities with wayland-info");

	if (keyboard) {
		group = lv_group_create();
		lv_indev_set_group(keyboard, group);
		lv_group_set_default(group);
	} else {
		LV_LOG_WARN("bench-hmi: no keyboard device from the "
			    "compositor; Tab and Enter will do nothing");
	}

	dashboard_create(lv_screen_active(), group);

	while (lv_wayland_window_is_open(disp)) {
		uint32_t next_ms = lv_wayland_timer_handler();

		if (next_ms == 0 || next_ms > MAX_SLEEP_MS)
			next_ms = MAX_SLEEP_MS;

		usleep(next_ms * 1000);
	}

	return 0;
}
