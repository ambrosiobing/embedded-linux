/* SPDX-License-Identifier: MIT
 *
 * The widgets, and the 500 ms timer that feeds them.
 */

#ifndef BENCH_DASHBOARD_H
#define BENCH_DASHBOARD_H

#include "lvgl/lvgl.h"

/* Build the dashboard on parent and start its metrics timer.
 *
 * keyboard_group receives every focusable widget, so that Tab moves
 * focus and Enter activates. It may be NULL when no keyboard input
 * device exists, in which case the dashboard is touch only.
 *
 * Acceptance asks that the keyboard work with the touch driver
 * unloaded, which is why focus is wired up here rather than left to
 * whichever indev happens to exist at startup. */
void dashboard_create(lv_obj_t *parent, lv_group_t *keyboard_group);

/* The metrics refresh period, in milliseconds. The specification fixes
 * this at 500 ms and acceptance measures against it, so it is a named
 * constant rather than a number buried in a call. */
#define DASHBOARD_REFRESH_MS 500

#endif /* BENCH_DASHBOARD_H */
