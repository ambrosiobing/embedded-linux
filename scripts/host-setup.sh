#!/bin/sh
#
# host-setup.sh - install what a Yocto build host needs, then check the
# things that are easy to get wrong and expensive to discover three hours
# into a build.
#
# Debian and Ubuntu. The package list spans several releases on purpose:
# names come and go (liblz4-tool became lz4, and the transitional package
# was dropped after 24.04), so anything without an installation candidate on
# this release is reported and skipped rather than failing the whole run.
#
# On another distribution, install the equivalents and run this again; the
# checks after the install still apply.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

[ "$(id -u)" -ne 0 ] || die "run this as your normal user; it calls sudo itself."

# The Yocto reference list, plus what this repository's own checks need.
# lz4 and liblz4-tool are the same tool under two names across releases;
# whichever one this distribution has is the one that gets installed.
PACKAGES="
gawk wget git diffstat unzip texinfo gcc build-essential
chrpath socat cpio python3 python3-pip python3-pexpect
xz-utils debianutils iputils-ping python3-git python3-jinja2
python3-subunit zstd lz4 liblz4-tool file locales libacl1
bmap-tools libgpiod-dev gpiod shellcheck python3-yaml pipx
pkg-config pkgconf nftables python3-numpy libsystemd-dev libcbor-dev
libdrm-dev device-tree-compiler
"

# Packages that have no candidate on this release and are not worth a
# warning, because another name in the list covers the same tool.
ALTERNATIVES="lz4 liblz4-tool pkg-config pkgconf"

installable() {
	candidate=$(apt-cache policy "$1" 2>/dev/null |
		sed -n 's/^  Candidate: //p')
	[ -n "$candidate" ] && [ "$candidate" != "(none)" ]
}

install_packages() {
	wanted=""
	skipped=""

	for pkg in $PACKAGES; do
		if installable "$pkg"; then
			wanted="$wanted $pkg"
		else
			skipped="$skipped $pkg"
		fi
	done

	[ -n "$wanted" ] || die "no packages are installable; is the apt index broken?"

	# shellcheck disable=SC2086
	sudo apt-get install -y $wanted

	for pkg in $skipped; do
		covered=0
		for alt in $ALTERNATIVES; do
			[ "$pkg" = "$alt" ] && covered=1
		done
		if [ "$covered" -eq 0 ]; then
			note "no candidate on this release, skipped: $pkg"
		fi
	done

	# Each either/or pair above has to leave a working binary behind.
	for tool in lz4 pkg-config; do
		command -v "$tool" >/dev/null 2>&1 ||
			note "warning: no $tool binary after the install"
	done
}

install_kas() {
	command -v kas >/dev/null 2>&1 && return 0

	note "installing kas"
	if installable kas; then
		sudo apt-get install -y kas
		return 0
	fi

	# Modern Debian and Ubuntu mark the system Python externally managed,
	# so a plain pip install into the user site is refused. pipx is the
	# supported route; the last fallback is for older hosts.
	if command -v pipx >/dev/null 2>&1; then
		pipx install kas
		pipx ensurepath >/dev/null 2>&1 || true
	else
		pip3 install --user kas ||
			pip3 install --user --break-system-packages kas
	fi

	case :$PATH: in
	*:"$HOME/.local/bin":*) ;;
	*) note "add HOME/.local/bin to your PATH, then open a new shell" ;;
	esac
}

if ! command -v apt-get >/dev/null 2>&1; then
	note "not a Debian or Ubuntu host: install the Yocto host packages yourself"
	note "https://docs.yoctoproject.org/ref-manual/system-requirements.html"
else
	note "installing Yocto host packages"
	sudo apt-get update
	install_packages
	sudo locale-gen en_US.UTF-8
	install_kas
fi

note "checking the build directory"
require_case_sensitive "$BENCH_WORK"
require_disk_gb "$BENCH_WORK" 60

note "checking the repository location"
require_case_sensitive "$REPO_DIR"

if command -v kas >/dev/null 2>&1; then
	note "kas $(kas --version 2>&1 | head -1)"
else
	die "kas is still not on PATH. Open a new shell, or add HOME/.local/bin."
fi

note "host is ready. Next: ./go check, then ./go build"
