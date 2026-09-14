#!/bin/sh
#
# host-setup.sh - install what a Yocto build host needs, then check the
# things that are easy to get wrong and expensive to discover three hours
# into a build.
#
# Debian and Ubuntu only. On another distribution install the equivalent of
# the package list below and run this script again; the checks still apply.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

[ "$(id -u)" -ne 0 ] || die "run this as your normal user; it calls sudo itself."

if ! command -v apt-get >/dev/null 2>&1; then
	note "not a Debian or Ubuntu host: install the Yocto host packages yourself"
	note "https://docs.yoctoproject.org/ref-manual/system-requirements.html"
else
	note "installing Yocto host packages"
	sudo apt-get update
	sudo apt-get install -y \
		gawk wget git diffstat unzip texinfo gcc build-essential \
		chrpath socat cpio python3 python3-pip python3-pexpect \
		xz-utils debianutils iputils-ping python3-git python3-jinja2 \
		python3-subunit zstd liblz4-tool file locales libacl1 \
		bmap-tools \
		libgpiod-dev gpiod shellcheck python3-yaml
	sudo locale-gen en_US.UTF-8
fi

if ! command -v kas >/dev/null 2>&1; then
	note "installing kas"
	pip3 install --user kas || pip3 install --user --break-system-packages kas
	case :$PATH: in
	*:"$HOME/.local/bin":*) ;;
	*) note "add HOME/.local/bin to your PATH" ;;
	esac
fi

note "checking the build directory"
require_case_sensitive "$BENCH_WORK"
require_disk_gb "$BENCH_WORK" 60

note "checking the repository location"
require_case_sensitive "$REPO_DIR"

note "host is ready. Next: ./go check, then ./go build"
