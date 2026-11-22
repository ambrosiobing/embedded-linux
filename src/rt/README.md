# rt

Real-time latency measurement and orchestration tools (`bench-rt`).

- `rt-toggle.c`: `SCHED_FIFO` GPIO square-wave generator recording its own wake-up latency histogram.
- `rt-capture`: External MCC 118 DAQ capture script recording edge transitions.
- `rt-analyze`: Sub-sample edge interpolation and latency histogram analyzer.
- `rt-compare`: Compares internal `rt-toggle` / `cyclictest` histograms against external `rt-analyze` distributions.
- `rt-run`: End-to-end experiment runner enforcing isolation, affinity, governor, and thermal invariants.
- `rt-irq-affinity`: Inspects, confines, and verifies `/proc/irq` CPU affinities.

## Host Build

```sh
make -C src/rt
```
