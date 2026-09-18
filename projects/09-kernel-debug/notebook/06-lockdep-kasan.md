# 06: the faults that never crash

**Status: NOT YET RUN.** No board has produced the output below.

## Symptom

**Nothing, in every case.** These are the two faults that produce no
event at all, plus the one detector that needs no fault to be triggered.

| Fault | What you would notice | When |
|---|---|---|
| `uaf` | An occasional impossible value | Rarely, non-deterministically |
| `leak` | The box runs out of memory | In about a month |
| a bad lock order | A deadlock | On the one run where the timing lines up |

Nothing here can be found by waiting for a symptom, which is the argument
for having the tools on before you need them.

## Part one: the use after free, under KASAN

**This needs the other kernel.** `./go debug-kasan`, a separate card or a
separate `kernel8.img`. See the [configuration
rationale](../docs/CONFIG-RATIONALE.md) for what it costs and why it is
not in the ordinary debug image.

**On the board over the picocom console:**

```sh
sudo modprobe buggy
echo uaf | sudo tee /sys/kernel/debug/buggy/trigger
dmesg | sed -n '/BUG: KASAN/,/^\[.*\] =\+$/p'
```

```
NOT YET RUN
```

What the report should contain, and what makes it worth the 128 MB of
shadow memory: **two stacks, the allocation site and the free site**, not
just the bad access. `CONFIG_STACKDEPOT_ALWAYS_INIT` is what makes those
available, and it is selected by KASAN rather than requested.

Acceptance criterion 6 is that report existing with both stacks.

### The same fault on the ordinary kernel

Run it on the non-KASAN debug kernel too, and record what happens, which
should be: the `pr_info` prints `0xdeadbeef` correctly and nothing else
occurs. **That is the lesson.** A use after free reads the right value
most of the time, because the allocator has not reused the object yet.

### And with KFENCE, which is the production-friendly answer

KFENCE is in the ordinary debug image. It samples, so a single trigger
will almost certainly not be caught. Run it a few hundred times:

```sh
for i in $(seq 500); do echo uaf > /sys/kernel/debug/buggy/trigger; done
dmesg | grep -A20 'BUG: KFENCE'
```

```
NOT YET RUN
```

The point of this half is the trade: KASAN catches it the first time and
costs too much to ship; KFENCE costs almost nothing and catches it
eventually. Being able to explain that choice is worth more than either
report.

## Part two: the leak, under kmemleak

Back on the **ordinary debug kernel**, since kmemleak is in `debug.cfg`.

**On the board over the picocom console:**

```sh
echo leak | sudo tee /sys/kernel/debug/buggy/trigger
echo scan | sudo tee /sys/kernel/debug/kmemleak; sleep 10
sudo cat /sys/kernel/debug/kmemleak
```

```
NOT YET RUN
```

Acceptance criterion 7 is **64 unreferenced objects of 256 bytes.** The
module allocates 64 separate objects rather than one 16 kB block for
exactly this reason: kmemleak reports objects, not bytes, so the shape of
the allocation is what makes the criterion checkable.

The scan is explicit even though automatic scanning is on, because a
report that appears on its own schedule cannot be attributed to the
trigger that caused it.

### Count the objects rather than reading them

```sh
sudo grep -c '^unreferenced object' /sys/kernel/debug/kmemleak
```

## Part three: lockdep, which needs no trigger at all

`CONFIG_PROVE_LOCKING` reports a lock ordering that *could* deadlock, on
a run where it did not. There is nothing to trigger: it either finds
something during ordinary operation or it does not.

```sh
dmesg | grep -iE 'possible.*deadlock|lock.*inversion|WARNING.*lockdep'
```

```
NOT YET RUN
```

An empty result here is a genuine result and should be recorded as one.

To see it actually fire, use the experiment from entry
[03](03-ftrace.md): replace `mdelay` with `msleep` in `fault_lock` and
rebuild. Sleeping inside a spinlock section is illegal, and
`CONFIG_DEBUG_ATOMIC_SLEEP` reports it with a backtrace the first time it
happens.

```
NOT YET RUN
```

## Conclusion

To be written. What it should say, across all three parts:

The three faults in this entry have no symptom at the moment they
happen, and each needed a tool that costs something and had to be
decided on in advance. That is the whole project in one page: **by the
time a silent fault has a symptom, the information that would have
identified it is gone.** The decision is not which tool to reach for,
it is which cost to accept before anything goes wrong.
