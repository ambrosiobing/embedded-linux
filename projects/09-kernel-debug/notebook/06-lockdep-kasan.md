# 06: the faults that never crash

**Status: parts one to three NOT YET RUN.** No board has produced their
output. **Part four has been run**, on Sunday 4 October 2026 and Monday 5
October 2026, and its blocks are real console text rather than empty
ones. It is kept separate from the three above it for that reason, and
because it is not a fault this project injected.

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
modprobe buggy
echo uaf > /sys/kernel/debug/buggy/trigger
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
echo leak > /sys/kernel/debug/buggy/trigger
echo scan > /sys/kernel/debug/kmemleak; sleep 10
cat /sys/kernel/debug/kmemleak
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
grep -c '^unreferenced object' /sys/kernel/debug/kmemleak
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

## Part four: KFENCE found two faults nobody triggered

Parts one to three above wait on a fault the `buggy` module injects on
request. This part is the opposite case and was not planned: the tool
found two defects in code this project does not own, during an ordinary
boot, with nothing triggered and nobody looking.

### Symptom

None. The board boots, enumerates its USB hub, brings up Ethernet and
reaches a login prompt. Nothing is slow, nothing fails, and on an image
without KFENCE there is nothing to see at all.

### Tool, and why that one

KFENCE, from `debug.cfg`, already present because the image was built
with it rather than because anyone suspected the USB stack. It guards a
small random sample of allocations with canary bytes and checks them when
the object is freed.

    kfence: initialized - using 2097152 bytes for 255 objects

### Commands

There were none. That is the finding. The reports below are read out of
the picocom capture of a boot, and the only action taken was to have the
console attached before power.

### Raw output, report A, hub_port_init

Kernel 6.6.63-v8, Raspberry Pi 3 Model B Plus Rev 1.3, boot of Sunday 4
October 2026, board time 3.075 s. Quoted whole:

    ==================================================================
    BUG: KFENCE: memory corruption in hub_port_init+0x6bc/0xcc8

    Corrupted memory at 0x000000003f22a999 [ ! ! . . . . . . . . . . . . . . ] (in kfence-#18):
     hub_port_init+0x6bc/0xcc8
     hub_event+0xd3c/0x1570
     process_one_work+0x1f8/0x530
     worker_thread+0x1ec/0x3e8
     kthread+0x110/0x128
     ret_from_fork+0x10/0x20

    kfence-#18: 0x000000006c7597fb-0x000000001b9f15f5, size=18, cache=kmalloc-64

    allocated by task 9 on cpu 0 at 3.074751s:
     __kmem_cache_alloc_node+0x2c4/0x328
     kmalloc_trace+0x40/0x88
     usb_get_device_descriptor+0x30/0x98
     hub_port_init+0x69c/0xcc8
     hub_event+0xd3c/0x1570
     process_one_work+0x1f8/0x530
     worker_thread+0x1ec/0x3e8
     kthread+0x110/0x128
     ret_from_fork+0x10/0x20

    freed by task 9 on cpu 0 at 3.075040s:
     hub_port_init+0x6bc/0xcc8
     hub_event+0xd3c/0x1570
     process_one_work+0x1f8/0x530
     worker_thread+0x1ec/0x3e8
     kthread+0x110/0x128
     ret_from_fork+0x10/0x20

    CPU: 0 PID: 9 Comm: kworker/0:1 Not tainted 6.6.63-v8 #1
    Hardware name: Raspberry Pi 3 Model B Plus Rev 1.3 (DT)
    Workqueue: usb_hub_wq hub_event
    ==================================================================

Eighteen bytes is `sizeof(struct usb_device_descriptor)`. The object was
allocated and freed 289 microseconds apart inside one call to
`hub_port_init`, and two bytes of its canary had changed by the time it
was freed.

### Raw output, report B, usb_get_status

Same kernel and board, boot of Monday 5 October 2026, board time 5.95 s.
This one had not appeared in any earlier boot:

    ==================================================================
    BUG: KFENCE: memory corruption in usb_get_status+0xc4/0x128

    Corrupted memory at 0x00000000218d3570 [ ! ! . . . . . . . . . . . . . . ] (in kfence-#34):
     usb_get_status+0xc4/0x128
     usb_port_resume+0x384/0x6a0
     usb_generic_driver_resume+0x28/0x78
     usb_resume_both+0xa8/0x190
     usb_runtime_resume+0x20/0x38
     __rpm_callback+0x50/0x200
     rpm_callback+0x74/0x88
     rpm_resume+0x50c/0x730
     __pm_runtime_resume+0x64/0xd0
     usb_autoresume_device+0x28/0x78
     hub_event+0xfd0/0x1570
     process_one_work+0x1f8/0x530
     worker_thread+0x1ec/0x3e8
     kthread+0x110/0x128
     ret_from_fork+0x10/0x20

    kfence-#34: 0x00000000748e0203-0x00000000b2bd45af, size=2, cache=kmalloc-64

    allocated by task 65 on cpu 3 at 5.949703s:
     usb_get_status+0x60/0x128
     usb_port_resume+0x384/0x6a0
     usb_generic_driver_resume+0x28/0x78
     usb_resume_both+0xa8/0x190
     usb_runtime_resume+0x20/0x38
     __rpm_callback+0x50/0x200
     rpm_callback+0x74/0x88
     rpm_resume+0x50c/0x730
     __pm_runtime_resume+0x64/0xd0
     usb_autoresume_device+0x28/0x78
     hub_event+0xfd0/0x1570
     process_one_work+0x1f8/0x530
     worker_thread+0x1ec/0x3e8
     kthread+0x110/0x128
     ret_from_fork+0x10/0x20

    freed by task 65 on cpu 3 at 5.950006s:
     usb_get_status+0xc4/0x128
     [the remaining frames repeat the allocation stack above, verbatim]

    CPU: 3 PID: 65 Comm: kworker/3:3 Tainted: G    B   W          6.6.63-v8 #1
    Hardware name: Raspberry Pi 3 Model B Plus Rev 1.3 (DT)
    Workqueue: usb_hub_wq hub_event
    ==================================================================

The bracketed line is the only elision, and it is marked because the
frames below the first one repeat the allocation stack exactly.

### What three boots say about sampling

| Boot | Report A, `hub_port_init` | Report B, `usb_get_status` |
|---|---|---|
| Sunday 4 October 2026, second boot | twice, at 3.075 s and 4.62 s | not seen |
| Monday 5 October 2026, third boot | not seen | not seen |
| Monday 5 October 2026, fourth boot | once, at 4.52 s | once, at 5.95 s |

**The empty row is the important one.** Nothing changed between the
second and third boots that could touch this, and nothing regressed
between the third and fourth. KFENCE guards 255 objects against every
allocation the kernel makes, so a defect it catches twice in one boot can
go unsampled in the next. A clean boot is not evidence of absence, and
recording it as one would be the mistake this entry exists to teach.

### Conclusion for this part

Established: both objects are small `kmalloc` buffers, 18 bytes and 2
bytes, both from `kmalloc-64`; both are allocated and freed inside a
third of a millisecond within the function that reports them; both show
two canary bytes changed at free time; and report A reproduces across two
separate boots from two separately built images.

Not established: the mechanism. Two sites with the same signature is more
than one observation and it is still not a cause. Nothing here says what
wrote those bytes, and this entry does not guess.

What would have been missed without the tool: all of it. There is no
symptom, no message, no failure and no slow path. The board that produced
these reports also served an ssh session, took a DHCP lease and ran for
an hour without complaint.

## Conclusion

To be written. What it should say, across all three parts:

The three faults in this entry have no symptom at the moment they
happen, and each needed a tool that costs something and had to be
decided on in advance. That is the whole project in one page: **by the
time a silent fault has a symptom, the information that would have
identified it is gone.** The decision is not which tool to reach for,
it is which cost to accept before anything goes wrong.
