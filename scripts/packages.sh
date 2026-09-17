#!/bin/sh
#
# packages.sh - the image package list, in a form the README can hold.
#
# The acceptance criterion for this project is that every package in the
# image can be justified in one line. This prints the list so that the table
# in the README is generated rather than remembered.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

# Newest, not lexically last: one directory per MACHINE and one manifest
# per image, so on a host that has built more than one the name order is
# not the order anybody means. See newest_path in common.sh.
manifest=$(find "$KAS_BUILD_DIR/tmp/deploy/images" -name '*.manifest' -type f \
	-printf '%T@ %p\n' 2>/dev/null | newest_path manifest)

if [ -n "$manifest" ]; then
	note "manifest $manifest"
	awk '{ print $1 }' "$manifest" | sort -u
	note "$(awk 'END { print NR }' "$manifest") packages"
	exit 0
fi

require_tool kas
note "no manifest yet, asking BitBake instead"
kas shell "$REPO_DIR/kas/bench-rpi4.yml" -c \
	'bitbake -e bench-image | grep "^IMAGE_INSTALL="'
