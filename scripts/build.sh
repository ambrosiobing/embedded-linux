#!/bin/sh
#
# build.sh - build the bench image.
#
#   scripts/build.sh                 raspberrypi4-64, bench-image
#   scripts/build.sh bench-rpi3      another board, same layer
#   scripts/build.sh bench-dev       the debugging variant
#
# The first run takes one to three hours and downloads about 10 GB. Every
# run after that reuses the sstate cache and takes minutes, which is why the
# caches live outside the build tree.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

config=${1:-bench-rpi4}
kasfile=$REPO_DIR/kas/$config.yml
[ -f "$kasfile" ] || die "no such configuration: kas/$config.yml"

require_tool kas
require_no_running_build
require_case_sensitive "$BENCH_WORK"
require_disk_gb "$BENCH_WORK" 60

note "work dir   $BENCH_WORK"
note "build dir  $KAS_BUILD_DIR"
note "config     kas/$config.yml"

start=$(date +%s)
kas build "$kasfile"
end=$(date +%s)

elapsed=$(( end - start ))
if [ "$elapsed" -lt 60 ]; then
	note "build took ${elapsed} s"
else
	note "build took $(( elapsed / 60 )) min $(( elapsed % 60 )) s"
fi
note "images in $KAS_BUILD_DIR/tmp/deploy/images/"
ls -lh "$KAS_BUILD_DIR"/tmp/deploy/images/*/*.wic.bz2 2>/dev/null || true
