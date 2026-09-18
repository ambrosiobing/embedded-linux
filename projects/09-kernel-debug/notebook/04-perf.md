# 04: the same lock fault, asked a different question

**Status: NOT YET RUN.** No board has produced the output below.

## Symptom

The same three second stall as entry [03](03-ftrace.md). Running the same
fault through a second tool is deliberate: the two answers differ, and
the difference is the thing to learn.

| Question | Tool | Answer shape |
|---|---|---|
| How long was interrupts-off, and where? | `irqsoff` tracer | One worst case, with its stack |
| What did the CPU spend its time on? | `perf record` | A distribution over all samples |
| What ran, in what order? | `function_graph` | A call sequence |

A tracer keeps the extreme. perf keeps the typical. For a fault that
happens once, the extreme is what you want; for a system that is merely
slow, the distribution is.

## Tool, and why this one

`perf record` with call graphs. It samples on a hardware counter, which
is why `CONFIG_ARM_PMU` matters: without it perf still runs and silently
has only software events, so there are no cycles and no cache misses.
A working tool with half its instruments is the least useful failure
available.

## Commands

**On the board over the picocom console:**

First, confirm the hardware counters are actually there. Do this before
trusting any number below.

```sh
perf list | grep -E 'cycles|cache-misses' ; dmesg | grep -i pmu
```

Then record the fault:

```sh
perf record -g -o /dev/shm/lock.data -- \
    sh -c 'echo lock > /sys/kernel/debug/buggy/trigger'
perf report -i /dev/shm/lock.data --stdio | head -40
```

The `perf probe` half of the acceptance criterion, which puts a dynamic
tracepoint on a function in the module:

```sh
perf probe -m buggy --add fault_lock
perf stat -e probe:fault_lock -- \
    sh -c 'echo lock > /sys/kernel/debug/buggy/trigger'
perf probe --del probe:fault_lock
```

## Raw output

Tool versions, and whether the PMU is present:

```
NOT YET RUN
```

`perf report`:

```
NOT YET RUN
```

`perf stat` on the probe:

```
NOT YET RUN
```

## Conclusion

To be written. The claim it should support is acceptance criterion 5:
most samples attributed to `fault_lock` or `__delay`, and the probe
firing exactly once per trigger.

`__delay` appearing rather than `fault_lock` is not a failure. `mdelay`
expands into a delay loop, and the samples land where the cycles are
spent; the call graph is what connects them back to `fault_lock`, which
is why `-g` is not optional here.

## What perf cannot tell you here, and it is worth writing down

perf will show that time was spent in the delay loop. It will **not**
tell you that interrupts were disabled while it happened, and that is
the actual bug. A busy loop with interrupts enabled looks identical in a
perf profile and is a far less serious fault.

So: perf found where the time went, and the irqsoff tracer found what was
wrong. Neither is a substitute for the other, and reaching for the
familiar one first is how a three second stall gets diagnosed as "the
delay is too long" rather than "the delay holds a lock with interrupts
off".
