# The build host

BitBake is fussy about where it runs, and every one of these rules exists
because breaking it costs hours rather than minutes.

## Requirements

- Linux, or Windows with WSL2. A native ext4 file system either way.
- About 60 GB free while the build runs, and roughly 10 GB of it downloaded
  the first time.
- A case-sensitive file system. This is not optional: BitBake will merge two
  recipes whose names differ only in case and say nothing about it.

`scripts/common.sh` probes for both the case sensitivity and a `/mnt` path
before any long command starts, and refuses rather than letting the build
fail three hours in.

## Host packages

`./go setup` installs these. The first table is the Yocto Project's own host
requirement list; the second is what this repository's checks add. Nothing is
installed that nothing uses, which is the same rule the image itself follows.

The list is filtered against `apt-cache policy` at install time, so a package
that a newer release has dropped is skipped with a note rather than failing
the whole run. That is how `liblz4-tool` is handled: it became `lz4` after
24.04, both names are in the list, and whichever one the release still has is
the one that gets installed. `pkg-config` and `pkgconf` are the same
arrangement. After the install the script checks that each pair left a working
binary behind, because a silently missing tool is worse than a failed install.

### Required by the Yocto Project

| Package | Why it is needed |
|---|---|
| `gawk` | BitBake and the kernel's kconfig scripts use GNU awk extensions that `mawk` does not have |
| `wget` | Fetcher for recipes whose `SRC_URI` is an http or https tarball |
| `git` | Fetcher for git `SRC_URI` entries, and how kas clones poky and the other layers |
| `diffstat` | The patch tooling summarises what each patch touched when applying `SRC_URI` patches |
| `unzip` | Unpacks `.zip` sources |
| `texinfo` | Provides `makeinfo`, which the native binutils and gcc builds need for their documentation |
| `gcc` | The host compiler. BitBake builds a native toolchain with it before it can cross-compile anything |
| `build-essential` | `make`, the C library headers and the rest of the native build chain |
| `chrpath` | Rewrites `RPATH` in binaries so native tools and the SDK still work after being relocated |
| `socat` | Connects sockets and pseudo-terminals for `devshell` and the image test harness |
| `cpio` | Builds and unpacks initramfs archives |
| `python3` | BitBake is written in Python |
| `python3-pip` | Installs Python tools that the distribution does not package |
| `python3-pexpect` | Drives interactive processes, used by `runqemu` and the image tests |
| `xz-utils` | `.tar.xz` sources, and xz-compressed images |
| `debianutils` | Provides `which`, which many recipe configure scripts call |
| `iputils-ping` | BitBake's sanity check confirms network access before starting a long fetch |
| `python3-git` | GitPython. `buildhistory` commits into its own git repository, and this build sets `BUILDHISTORY_COMMIT = "1"` |
| `python3-jinja2` | Template engine used by the recipe and image tooling, including `wic` |
| `python3-subunit` | Streams test results for `oe-selftest` and ptest runs |
| `zstd` | The default compression for sstate artefacts, so every cache hit passes through it |
| `lz4` | Compresses kernel images and initramfs. Was `liblz4-tool` before 24.04 |
| `file` | Identifies binary types during package QA |
| `locales` | Provides `locale-gen`. BitBake requires a UTF-8 locale and refuses to start without one |
| `libacl1` | Access-control-list handling when the rootfs is assembled by a non-root user |

### Added by this repository

| Package | Why it is needed |
|---|---|
| `bmap-tools` | `./go flash` writes the image using its block map, which skips the empty blocks |
| `libgpiod-dev` | `./go check` compiles `bench-status.c` against the host libgpiod. On 24.04 and later that is v2, the same API the target uses, so a mistake in the GPIO calls surfaces in seconds rather than two hours into a build |
| `gpiod` | `gpiodetect` and `gpioset` on the host. Not needed for the build itself, but it is the same toolset used for bring-up on the board, and having it here makes the instructions in the project docs testable |
| `shellcheck` | `./go check` and CI lint every shell script in the repository |
| `python3-yaml` | `scripts/lint.py` parses the kas files to check they are still valid |
| `pkg-config` | Resolves the compiler and linker flags for libgpiod. Without it the compile step in `./go check` cannot run at all, and nothing else in the host list pulls it in. Newer releases are migrating the name to `pkgconf`, so both are in the list and whichever one exists is installed |
| `nftables` | Project 15 ships the router's whole packet path as one ruleset file. The invariants in it are asserted by a test that runs anywhere; `nft -c -f` additionally checks the syntax, and only this package provides it |
| `pipx` | Installs kas into its own environment. Current Debian and Ubuntu mark the system Python externally managed, so a plain `pip install` is refused |

### kas

kas is not in the table because it is not always an apt package:

```sh
sudo apt-get install -y kas || pipx install kas
```

`./go setup` tries apt first, then pipx, then pip. After a pipx install, kas
lands in `~/.local/bin`, so `pipx ensurepath` and a new shell may be needed
before the command is found.

## Under WSL2

Clone into the Linux file system, not onto a Windows mount:

```sh
mkdir -p ~/src && cd ~/src
git clone <this repository>
cd embedded-linux-bench
```

A checkout under `/mnt/c` is both case-insensitive and slow enough to turn a
three-hour build into an overnight one. The scripts will stop you.

If `$HOME` sits on a small partition, point the work directory elsewhere.
Everything BitBake writes goes there, including the two caches:

```sh
BENCH_WORK=/data/bench ./go build
```

WSL2 grows its virtual disk on demand but does not shrink it. 60 GB of build
tree stays allocated to the VM afterwards unless the disk is compacted, so
`./go clean` after a successful build is worth the two minutes.

## First run

```sh
./go setup      # host packages, kas, libgpiod-dev, shellcheck
./go check      # about 2 minutes, nothing long starts yet
./go build      # 1 to 3 hours
```

`./go check` is worth the two minutes before anything long. It parses every
shell file, runs the static layer checks, runs the state-machine tests, and
compiles the application with `-Werror` against the host's libgpiod v2, the
same API the target uses. A mistake in the GPIO calls surfaces there in
seconds instead of two hours into a BitBake run.

## Caches

`DL_DIR` and `SSTATE_DIR` live beside the build tree rather than inside it,
so `./go clean` deletes the build and keeps the expensive parts. A rebuild
after that takes minutes. Deleting the caches as well means downloading 10 GB
again, so do that only when disk space actually runs out.

To share the sstate cache between machines, point `SSTATE_MIRRORS` at it in
the `local_conf_header` of `kas/bench-rpi4.yml`. That is what the opt-in CI
build job expects from a self-hosted runner.

## Moving the repository between machines by hand

If a git remote is not convenient, use tar rather than zip. Tar preserves the
executable bit on `go` and the scripts, and it does not rewrite line endings.
A shell script that arrives with CRLF endings fails with a confusing
`bad interpreter` message.

```sh
tar czf embedded-linux-bench.tar.gz embedded-linux-bench
```
