# Bring-up

First boot in order, with the check that catches each silent failure. The
order is not arbitrary: every step here can fail in a way that looks like
the next step failing, so each one is confirmed before the next is tried.

**Every command block says which machine it is for.** There are two
laptops with two clones and no shared filesystem, and a board with two
ways in.

## Before power

The rule this bench applies before every project, and it is short here:

- The USB/TTL adapter's **red 5 V lead stays open.** The board has its own
  supply. Two sources on one rail is how the adapter, and sometimes the
  board, is destroyed.
- The LED goes to **GPIO17 through 330 ohm** to ground. Nothing else on
  the header is driven by anything in this project.
- Nothing here writes a GPIO from software that has not been checked
  against the schematic: the only output is the LED, and it is driven by
  a kernel trigger declared in `config.txt` rather than by any program.

## 1. Build

On the **build laptop (WSL)**:

```bash
./go debug
```

The KASAN kernel is a second, separate build. It shares sstate with the
first for everything except the kernel itself.

```bash
./go debug-kasan
```

**Keep `vmlinux` and `System.map`.** They are the point of the debug
kernel and `rm_work` would delete them; `kas/bench-debug.yml` excludes
`linux-raspberrypi` for that reason. Find them under the kernel work
directory:

```bash
find build/tmp/work -name vmlinux -path '*linux-raspberrypi*' -printf '%T@ %p\n' | sort -n | tail -1
```

**This is the file every later step depends on, and the one nothing can
verify for you.** A `vmlinux` from a different build of identical source
resolves addresses to the wrong symbols, confidently and silently. Copy
it, `System.map` and `buggy.ko` into one directory now, and keep them
together.

## 2. Flash and check the card

On the **build laptop (WSL)**:

```bash
./go flash /dev/sdX
```

Then read the boot partition back, because the three overlay lines are
where this project succeeds or fails and they are easier to check now
than from a board that will not talk:

```bash
grep -E 'enable_uart|disable-bt|ramoops|gpio-led|gpu_mem' /mnt/boot/config.txt
```

Expected, in some order:

```
enable_uart=1
dtoverlay=disable-bt
dtoverlay=ramoops,base-addr=0x0b000000,total-size=0x20000,record-size=0x4000,console-size=0x8000
dtoverlay=gpio-led,gpio=17,label=heartbeat,trigger=heartbeat
```

And the command line:

```bash
cat /mnt/boot/cmdline.txt
```

It must contain `kgdboc=ttyAMA0,115200` and `nokaslr`.

## 3. First boot, and the two checks that catch the classic failure

On the **authoring laptop (Windows)**, start the proxy before powering the
board, so the boot messages are captured:

```bash
./go proxy /dev/ttyUSB0
```

Then a terminal on the console port, **logged to a file**. This is not
optional advice: `panic_on_oops` with a ten second timeout means an
unlogged session loses the oops you just caused.

```bash
picocom --logfile boot-$(date +%F-%H%M).log localhost:5550
```

Power the board. Then, **on the board over the picocom console**:

```sh
ls -l /dev/serial1
```

`serial1` should point at `ttyAMA0`. **If it points at `ttyS0`, the
`disable-bt` overlay did not take**, the PL011 is still on the Bluetooth
radio, and `kgdboc=ttyAMA0` has attached to a UART that is not on the
header. Everything else will work and the debugger will do nothing.

```sh
dmesg | grep -i uart-pl011
```

The PL011 should have registered as `ttyAMA0` and be the console.

## 4. Check that kgdboc actually attached

**On the board over the picocom console:**

```sh
cat /sys/module/kgdboc/parameters/kgdboc
```

Expect `ttyAMA0,115200`.

**This check is here because of a specific doubt, and the doubt is
recorded rather than hidden.** meta-raspberrypi offers `ENABLE_KGDB = "1"`
which emits `kgdboc=serial0,115200`. `serial0` is a device-tree alias.
`console=serial0` works because the console code resolves aliases;
`kgdboc` resolves its argument through `tty_find_polling_driver`, which
matches a registered tty driver name and index. **Inferred, not yet seen
on this board:** that `kgdboc=serial0` therefore attaches to nothing.
`kas/bench-debug.yml` sets the explicit name instead, which costs nothing
if the alias does work.

If this file is empty, kgdboc did not attach and nothing later in this
document will work.

## 5. Check the heartbeat

**On the board over the picocom console:**

```sh
cat /sys/class/leds/heartbeat/trigger
```

The `heartbeat` trigger should be the one in brackets. The LED should be
visibly beating. It is the only instrument that still reports once the
kernel has stopped, so confirm it now rather than when you need it.

## 6. Check pstore is mounted and empty

**On the board over the picocom console:**

```sh
mount | grep pstore; ls /sys/fs/pstore/
```

Expect a pstore mount and an empty directory on a board that has not
crashed yet.

**If the directory is empty after a crash**, read this: `systemd` mounts
pstore itself, and `systemd-pstore.service` archives every record to
`/var/lib/systemd/pstore/` and then deletes it, before `sysinit.target`.
`bench-debug-image` masks that unit so the records stay where every
instruction ever written says to look. Confirm the mask took:

```sh
systemctl is-enabled systemd-pstore.service
```

Expect `masked`. If it is not, the crash evidence is in
`/var/lib/systemd/pstore/` instead, and nothing is lost, only moved.

## 7. Load the module

**On the board over the picocom console:**

```sh
modprobe buggy; dmesg | tail -3; ls -l /sys/kernel/debug/buggy/
```

Expect the load message, the usage line, and a write-only `trigger`. The
module does nothing at load time on purpose.

Now unload and reload it ten times, which is acceptance criterion 9:

```sh
for i in $(seq 10); do modprobe -r buggy && modprobe buggy || echo "FAILED at $i"; done; dmesg | grep -ci warn
```

## 8. Only now, cause a fault

Everything above is confirmation that the instruments work. The notebook
takes over from here, one entry per fault:

| Entry | Fault | Tool |
|---|---|---|
| [01-oops.md](../notebook/01-oops.md) | `null` | the console and `decode.sh` |
| [02-kgdb.md](../notebook/02-kgdb.md) | `null` again | gdb, live |
| [03-ftrace.md](../notebook/03-ftrace.md) | `lock` | the irqsoff tracer |
| [04-perf.md](../notebook/04-perf.md) | `lock` again | `perf record` |
| [05-pstore.md](../notebook/05-pstore.md) | `null` and SysRq `c` | ramoops |
| [06-lockdep-kasan.md](../notebook/06-lockdep-kasan.md) | `uaf` and `leak` | KASAN, kmemleak, lockdep |

Start with `01-oops.md`. It is the fault that announces itself, which
makes it the one that proves the toolchain before the silent three need
it.

## If something is wrong

```
  the board says nothing at all
  |
  +-- is the proxy running and did it print the two ports?
  |     no  --> something else holds /dev/ttyUSB0. The script names the
  |             pid and the process. Close it; never open the device
  |             directly while the proxy is up.
  |
  +-- yes --> is the LED beating?
        |
        +-- yes --> the kernel is running and the console is misrouted.
        |           Check enable_uart and which UART is on the header
        |           (step 3).
        |
        +-- no, dark --> it never booted, or it panicked. Power cycle
        |                with the log running; if still nothing, the card
        |                or config.txt is the suspect (step 2).
        |
        +-- no, frozen --> it is stopped in the debugger, or wedged with
                           interrupts off. Try gdb on 5551 before
                           power cycling: if it answers, the kernel is
                           alive and waiting for you.
```

---

Back to [DESIGN.md](DESIGN.md), the
[configuration rationale](CONFIG-RATIONALE.md), or the
[project README](../README.md).
