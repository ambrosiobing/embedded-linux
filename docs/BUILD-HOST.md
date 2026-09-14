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
