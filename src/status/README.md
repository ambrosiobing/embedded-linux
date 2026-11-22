# status

Status LED daemon (`bench-status`) and systemd health state writer (`bench-state`).

- `bench-status.c`: Mirrors `/run/bench/state` (`ok`, `starting`, `failed`) onto three GPIO LED lines via `libgpiod` v2.
- `bench-state`: POSIX shell helper invoked by `bench-state.timer` and `OnFailure=` drop-ins to compute and latch `/run/bench/state`.

## Host Build

```sh
make -C src/status
```
