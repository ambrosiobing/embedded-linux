#!/bin/sh
#
# sdk.sh - build the cross SDK and, with "check", prove that it works.
#
#   scripts/sdk.sh              build the installer
#   scripts/sdk.sh install      run the installer into /opt/poky
#   scripts/sdk.sh check        cross-compile sdk/hello-gpiod with it
#
# The SDK is the real output of this project: Projects 5, 10, 11 and 12
# compile against the same sysroot that is on the board.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

require_tool kas
require_no_running_build
require_host_disk_gb 25

sdk_installer() {
	find "$KAS_BUILD_DIR/tmp/deploy/sdk" -name '*.sh' -type f 2>/dev/null |
		sort | tail -1
}

case ${1:-build} in
build)
	note "populating the SDK (30 to 60 min on a cold cache)"
	kas build "$REPO_DIR/kas/bench-rpi4.yml" -c populate_sdk
	note "installer: $(sdk_installer)"
	;;
install)
	inst=$(sdk_installer)
	[ -n "$inst" ] || die "no SDK installer found. Run scripts/sdk.sh build first."
	note "installing $inst"
	sh "$inst"
	;;
check)
	env_script=$(find /opt/poky -maxdepth 2 -name 'environment-setup-*' 2>/dev/null |
		sort | tail -1)
	[ -n "$env_script" ] || die "no SDK environment found under /opt/poky."
	note "using $env_script"
	# shellcheck disable=SC1090
	( . "$env_script" && cd "$REPO_DIR/sdk/hello-gpiod" &&
		make clean && make && make check )
	note "copy sdk/hello-gpiod/hello-gpiod to the board and run it"
	;;
*)
	die "usage: sdk.sh [build | install | check]"
	;;
esac
