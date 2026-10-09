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
kasfile=$(resolve_kas_config "$config")
config=$(basename "$kasfile" .yml)

require_tool kas
require_no_running_build
warn_stray_build_tree
# Two figures, because the guard used to model every build as a build from
# nothing and that modelled it coarser than BitBake does. Friday 9 October
# 2026: build/tmp had been removed to free the Windows drive, the first run
# recreated it for this configuration and grew the virtual disk by about
# 17 GB, then stopped on a recipe defect. The second run, needing one
# recipe and an image assembly on a tmp that was now resident, was refused
# for having 20 GB free where 25 were demanded, and nothing left inside
# the guest could clear that. A guard whose remedy cannot be run from where
# the operator stands gets switched off, so it now says which case it is
# in. 25 GB is the measured cost of recreating tmp; 5 GB is a floor for a
# resident tmp, chosen rather than measured, and said so.
if [ -d "$KAS_BUILD_DIR/tmp" ]; then
	note "host disk  build/tmp is resident, floor 5 GB on the Windows drive"
	require_host_disk_gb 5
else
	note "host disk  build/tmp is absent, recreating it needs 25 GB on the Windows drive"
	require_host_disk_gb 25
fi
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
