# 03: the lock held too long, found by tracing

**Status: NOT YET RUN.** No board has produced the output below.

## Symptom

**Nothing.** No oops, no panic, no message. The board is late by three
seconds and then carries on. If you were not watching for it you would
call it a glitch.

This is the fault that justifies the project. A debugger cannot find it:
by the time you have a prompt, the three seconds are over and there is
nothing to inspect. The question is not "what is the state now", it is
"what happened before now", and only a tracer answers that.

## Tool, and why this one

The `irqsoff` tracer. It keeps the longest interrupts-disabled section it
has seen, with the stack that produced it, which is exactly the shape of
this fault.

`function_graph` is the second tool here and answers the other half: not
how long, but what ran.

## Commands

**On the board over the picocom console:**

```sh
cd /sys/kernel/tracing
echo 0 > tracing_on; echo irqsoff > current_tracer; echo 0 > tracing_max_latency
echo 1 > tracing_on
echo lock | sudo tee /sys/kernel/debug/buggy/trigger
cat tracing_max_latency
```

Then the trace itself:

```sh
head -40 /sys/kernel/tracing/trace
```

For the call sequence rather than the duration, using `trace-cmd`, and
writing to `/dev/shm` because the trace is large and the console is not:

```sh
trace-cmd record -o /dev/shm/lock.dat -p function_graph -g trigger_write \
    sh -c 'echo lock > /sys/kernel/debug/buggy/trigger'
```

**On the board over ssh**, to get the file off. Not the serial console:
the file is megabytes and the cable does about 11 kB/s.

```sh
scp /dev/shm/lock.dat user@host:/tmp/
```

**On the authoring laptop (Windows):**

```bash
trace-cmd report /tmp/lock.dat | head -60
```

## Raw output

Tool versions:

```
NOT YET RUN
```

`tracing_max_latency`, in microseconds:

```
NOT YET RUN
```

The irqsoff trace, with the stack:

```
NOT YET RUN
```

The function graph around `trigger_write`:

```
NOT YET RUN
```

## Conclusion

To be written. The claim it should support is acceptance criterion 4: a
maximum latency within 5 percent of 3 s, with `fault_lock` in the stack,
and `trace-cmd report` showing the call graph of `trigger_write`.

3 s is 3,000,000 microseconds, so 5 percent is a window of 2,850,000 to
3,150,000.

## What else should be true, and is part of the lesson

- **The soft lockup detector should complain**, and RCU may as well. That
  is expected. `CONFIG_SOFTLOCKUP_DETECTOR` is on for this reason.
- **The heartbeat LED keeps beating throughout.** This is the detail
  worth watching for once: the timer that drives it runs on another core,
  so the instrument that usually means "alive" says "alive" while one
  core is entirely stuck. On a single-core board it would stop, and so
  would the console.
- **`perf` gives a different answer to the same fault**, which is entry
  [04](04-perf.md), and comparing the two is the point of having both.

## The experiment the specification asks for

Replace `mdelay` with `msleep` in `fault_lock` and rebuild. Sleeping
inside a spinlock section is illegal, and `CONFIG_DEBUG_ATOMIC_SLEEP`
reports it immediately with a backtrace. It is a different bug with a
different tool, caught without any trigger at all, and it is the cheapest
demonstration in the project of what lockdep and its neighbours buy.
