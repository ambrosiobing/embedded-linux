#!/bin/sh
# embedded-linux-bench - one entry point for all twenty projects.
#
#   ./go              show this list
#   ./go setup        install the host packages and check the build directory
#   ./go check        compile and test everything that needs no board
#   ./go build        build bench-image for the Raspberry Pi 4
#   ./go dev          build the debugging variant
#   ./go rpi3         build the same layer for a Raspberry Pi 3
#   ./go router       build bench-router-image, the LTE router of Project 15
#   ./go release      build with SBOM, CVE check and source archive
#   ./go sdk          build the cross SDK installer
#   ./go sdk install  run that installer into /opt/poky
#   ./go sdk-check    cross-compile sdk/hello-gpiod with the installed SDK
#   ./go flash /dev/sdX   write the image to a card
#   ./go kconfig      check that the kernel fragment reached the .config
#   ./go reproduce    build the same commit again and diff the package lists
#   ./go packages     the image package list, for the README table
#   ./go lint         static checks that need no Yocto host
#   ./go projects     list the projects and where each one lives
#   ./go shell        a BitBake shell inside the kas environment
#   ./go clean        delete the build tree, keep the caches
#
# SPDX-License-Identifier: MIT
cd "$(dirname "$0")" || exit 1

case "${1:-}" in
setup)      exec sh ./scripts/host-setup.sh ;;
check)      exec sh ./scripts/host-check.sh ;;
build)      exec sh ./scripts/build.sh bench-rpi4 ;;
dev)        exec sh ./scripts/build.sh bench-dev ;;
rpi3)       exec sh ./scripts/build.sh bench-rpi3 ;;
router)     exec sh ./scripts/build.sh bench-router ;;
release)    exec sh ./scripts/build.sh bench-release ;;
sdk)        shift; exec sh ./scripts/sdk.sh "${1:-build}" ;;
sdk-check)  exec sh ./scripts/sdk.sh check ;;
flash)      shift; exec sh ./scripts/flash.sh "$@" ;;
kconfig)    shift; exec sh ./scripts/check-kernel-config.sh "$@" ;;
reproduce)  shift; exec sh ./scripts/reproduce.sh "$@" ;;
packages)   exec sh ./scripts/packages.sh ;;
lint)       exec python3 ./scripts/lint.py ;;
projects)
	for d in projects/*/; do
		[ -d "$d" ] || continue
		title=$(head -1 "$d/README.md" 2>/dev/null | sed 's/^# //')
		printf '  %-22s %s
' "${d%/}" "$title"
	done
	;;
shell)
	KAS_WORK_DIR=${BENCH_WORK:-$HOME/bench}
	KAS_BUILD_DIR=$KAS_WORK_DIR/build
	export KAS_WORK_DIR KAS_BUILD_DIR
	exec kas shell kas/bench-rpi4.yml
	;;
clean)
	work=${BENCH_WORK:-$HOME/bench}
	printf 'Delete %s/build? The caches stay. [y/N] ' "$work"
	read -r answer
	case "$answer" in
	y | Y) rm -rf "$work/build" && echo "build tree deleted" ;;
	*) echo "nothing done" ;;
	esac
	;;
*)
	sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
	;;
esac
