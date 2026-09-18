# Journal: Project 9

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled
list of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that
and not the alternative**.

All entries are 18 September 2026 unless noted.

---

## 1. The design document found the two-managers bug before a line was built

**What happened.** The method says to write `docs/DESIGN.md` before any
recipe, with an ownership table naming which component owns which device,
interface or file. This project looked like it had one contested
resource, the UART shared between console and debugger, which is the
whole reason agent-proxy exists and is not a discovery.

Filling the table out properly turned up a second one that nothing in the
specification mentions: **`/sys/fs/pstore` has two managers.**

**What was done.** `systemd` mounts pstore itself, which is in
`src/shared/mount-setup.c`. Then `systemd-pstore.service` copies every
record to `/var/lib/systemd/pstore/` and deletes it: `Storage=external`
and `Unlink=yes` are the compile-time defaults, and the unit is ordered
`Before=sysinit.target`, so it finishes long before a login prompt.

Acceptance criterion 2 says `/sys/fs/pstore/dmesg-ramoops-0` contains the
oops after the reboot. On a stock systemd image **that criterion would
have failed**, and not because ramoops was broken.

`bench-debug-image` masks the unit, and says why in the recipe.

**Why that and not the alternative.** Reading
`/var/lib/systemd/pstore/` instead would also work and would need no
mask. It was rejected because a debugging lab wants one owner of that
directory and wants records to persist until the person reading them says
otherwise. Clearing pstore after each capture is a step in the notebook,
done deliberately, so that an old record cannot be mistaken for a new
one. An archiver that empties the directory on every boot makes that step
impossible to perform.

The corroboration arrived from an unexpected direction afterwards: the
Raspberry Pi overlay README for `ramoops` carries the same warning in one
line. Two independent sources for a trap that costs an evening is worth
more than either.

---

## 2. Four symbols in the specification's fragment do nothing

**What happened.** Before writing `debug.cfg`, every symbol in the
specification's fragment was read out of the Kconfig at `rpi-6.6.y`
rather than assumed. Four of them are **promptless**: their value comes
from whatever selects them, and writing them in a fragment produces no
error, no warning and no effect.

| Written as a request | What it is | Ask for instead |
|---|---|---|
| `CONFIG_DEBUG_INFO` | bare `bool` | `CONFIG_DEBUG_INFO_DWARF5` |
| `CONFIG_HW_PERF_EVENTS` | `def_bool y depends on ARM_PMU` | `CONFIG_ARM_PMU` |
| `CONFIG_UPROBES` | `def_bool n` | `CONFIG_UPROBE_EVENTS` |
| `CONFIG_LOCKUP_DETECTOR` | bare `bool` | `CONFIG_SOFTLOCKUP_DETECTOR` |

The fourth was not in the original list and came out of checking the
others. `CONFIG_CONSOLE_POLL` is a fifth of the same kind and the
specification names it correctly, as a consequence rather than a request.

**What was done.** The fragment asks for the settable symbol in each case
and keeps the promptless one in a block labelled as assertions, so that
`./go kconfig` notices if a future defconfig stops selecting it.

**Why that and not the alternative.** Deleting the promptless lines would
be tidier and would lose the check. The value of `CONFIG_LOCKDEP=y` in
the file is not that it sets anything; it is that a kernel where lockdep
stopped being selected would be caught by a tool rather than by a
debugging session that found no lock reports and concluded the code was
correct.

**The general form, which belongs to the whole repository:** a fragment
is a list of requests, and a request the kernel silently ignores looks
exactly like one it granted.

---

## 3. A grep for `^config KFENCE` found nothing, and KFENCE exists

**What happened.** Verifying the memory-debugging symbols, `grep -A10
'^config KFENCE$'` against `lib/Kconfig.kfence` returned nothing. The
obvious reading is that the symbol does not exist on this tree.

**What was done.** Looked at the file instead of trusting the grep. It is
`menuconfig KFENCE`, not `config KFENCE`, and it has a prompt and is
perfectly settable.

**Why this is in the journal.** Because the wrong conclusion was one step
away and would have been written confidently into a fragment comment as
"KFENCE is not available on this tree". The pattern is the one this
repository keeps meeting: **a tool chose its own input, reported on what
it chose, and did not say what it had excluded.** A `^config` anchor
excluded every `menuconfig` in the kernel, silently.

The same check caught nothing wrong about `ARM_PMU` and something
important about `LOCKUP_DETECTOR`, so the pass paid for itself twice.

---

## 4. The leak was one block, and the acceptance criterion counts objects

**What happened.** `fault_leak` was written first as a single
`kmalloc(16 * 1024)` with the pointer dropped, and the documentation said
"16 kB per trigger". Then the specification's acceptance criteria were
read properly: **"kmemleak lists 64 unreferenced 256-byte objects"**.

**What was done.** Changed it to 64 allocations of 256 bytes, which is
the same 16 kB in a different shape, and propagated that through the
module docstring, `DESIGN.md` and the fault-matrix figure.

**Why that and not the alternative.** kmemleak reports objects, not
bytes. It never prints "16 kB leaked", so a criterion written in bytes is
not checkable against its output; a criterion written in objects is. The
shape of the allocation had to follow the thing that could be verified,
rather than the other way round.

---

## 5. The Bash heredoc ate a backslash level, three times, and the asserts caught it

**What happened.** Three separate attempts to edit a file through a
`python - <<'PY'` heredoc failed because the shell consumed one level of
backslashes:

- a `sed` on `\^{}` in a TikZ file matched nothing and reported success;
- `'{\texttt{leak}\\\scriptsize ...'` as a Python string literal arrived
  with one backslash fewer than written;
- `'\node[umlnote...'` had its `\n` turned into a newline.

**What was done.** Every one of them was caught by an `assert old in
text` before the replace, which is the rule this repository already has
for exactly this. The edits were redone with the Edit tool.

**Why this is worth an entry.** The rule was written because this failure
destroyed all seven Project 20 figures once. It has now paid for itself
three times in one session, and the important part is not that the
heredoc is dangerous: it is that **`str.replace` returns the string
unchanged when the anchor is missing, and writes it back with no error.**
The assert is the only thing standing between that and a silent no-op.
The `sed` case is worse, because `sed` has no assert to add.

---

## 6. Two checks were written, then broken on purpose to see them fail

**What happened.** `tests/debug-proxy-test.sh` and
`tests/debug-decode-test.sh` both passed on the first run, 37 assertions
between them. A check that has never failed is indistinguishable from a
check that passes.

**What was done.** Both guards were removed from a copy of the script
under test and the suites rerun:

| Guard removed | Assertions that failed |
|---|---|
| The "device already held" refusal in `agent-proxy.sh` | 6 |
| The "no cross toolchain" refusal in `decode.sh` | 2 |

Then restored, and both went quiet again.

**What that turned up.** For `decode.sh`, only 2 of the 4 relevant
assertions failed, because a later check (`command -v
"${CROSS_COMPILE}addr2line"`) catches the same case by a different route
and still exits 1. The two guards overlap. That is fine and now known;
without the mutation it would have read as full coverage of a guard that
is partly redundant.

For `agent-proxy.sh` the mutation also confirmed an assertion that had
been nagging: "a held device never reaches agent-proxy" passes trivially
when the record file is simply absent, so it could have been green for
the wrong reason. Under the mutant it failed, which is the proof it was
actually measuring something.

---

## 7. The debugger's argument order is printed before it runs

**What happened.** `agent-proxy` takes its arguments in an unusual order:
the port pair, then a target host of `0` meaning a serial device follows,
then the device and baud. The upstream README could not be fetched to
confirm it (the kernel.org cgit path 404s and the GitHub mirror does not
exist), so the invocation rests on the widely documented form rather than
on a source that was read.

**What was done.** The script echoes the exact command line before
executing it, and the test asserts on the recorded argument vector rather
than only on the exit status.

**Why that and not the alternative.** Guessing silently would mean a
version of `agent-proxy` with different expectations fails with a usage
message that never names this script, on a bench where the same symptom
is also produced by a dead cable, a held device and a wrong overlay. An
echoed command turns that into a one-line diagnosis. **Where something
could not be verified, the code says what it assumed, out loud, at the
moment it matters.**

---

## 8. kexec was left out on purpose, and said so

**What happened.** The component drawing listed `kexec-tools` alongside
`trace-cmd` and `perf`, carried over from the specification's component
list. Then the specification was read more carefully: kexec appears under
**stretch goals**, as "capture a full crash dump with kexec and `crash`
instead of ramoops, **and document why that is rarely done on small
boards**".

**What was done.** Removed it from the image and from the drawing, and
put the reason in the README's "going further" section instead.

**Why that and not the alternative.** Shipping `kexec-tools` with no
working kdump path would be a capability in the package list that nobody
can use, and the interaction between a kexec crash kernel and the
reserved ramoops region on this firmware boot flow is exactly the kind of
thing that is half-working in a way nobody notices. The specification
asks for the explanation rather than the feature, and the explanation is
cheaper and more honest than a half-built version of it.

---

## 9. The module is the layer's first, and its package is not named after it

**What happened.** Fifteen recipes in `recipes-bench/` and every one of
them builds userspace. `bench-buggy` is the first that inherits `module`,
and it behaves differently in a way that fails quietly.

**What was done.** Read `module.bbclass` and oe-core's own `hello-mod`
rather than writing the recipe from memory, which settled two things:

- `MAKE_TARGETS` is **not** set by `module.bbclass`, so `oe_runmake` runs
  with no target and gets the Makefile's first rule. The Makefile's `all`
  target is load-bearing and renaming it breaks the build with a make
  error that reads like a broken recipe.
- The package is `kernel-module-buggy`, from the kernel module split
  class, **not** `bench-buggy`. An image installing `bench-buggy` gets
  nothing, and BitBake does not consider that an error: the recipe built,
  and nothing asked for its output.

Both are written in the recipe and in the image, next to the lines they
explain.

**Why that and not the alternative.** The second one is the dangerous
one, because the failure is an image that builds, boots and has no
`/sys/kernel/debug/buggy`, on a board where a missing debugfs directory
has four other plausible causes.

---

## 10. `KERNEL_MODULE_AUTOLOAD` was deliberately not set

**What happened.** The natural thing for a module recipe is to add it to
`KERNEL_MODULE_AUTOLOAD` so it is there after boot.

**What was done.** Left out, and a comment in the recipe says why.

**Why that and not the alternative.** This module exists to break the
kernel. A fault injector that loads itself on every boot is one typo away
from a board that panics before the console is up, on an image whose
whole purpose is to be running when something goes wrong. It is loaded by
hand from a notebook entry that says what is about to happen.

The same reasoning shapes the module itself: nothing fires at load time,
every fault is behind an explicit keyword on a write-only file, and an
unknown keyword is an error that lists what it would have accepted rather
than a silent no-op. A typo that silently did nothing would let an
evening end with "the tool found nothing", which is the same shape as a
working tool reporting a clean run.

---

## 11. `strim` does not return what it was given

**What happened.** `trigger_write` called `strim(command)` and then
compared `command` against the keyword table, discarding the return
value.

**What was done.** Kept the returned pointer and compared that.

**Why it matters.** `strim` skips leading whitespace by returning a
pointer further into the buffer; it only trims the trailing end in place.
So `echo ' null'` would have failed to match, and the error message would
have printed the untrimmed string, for a reason nothing on the console
would explain. Found by reading the code back rather than by any tool.

---

## 12. The BSP's kgdb shortcut was not used, and the doubt is recorded

**What happened.** `meta-raspberrypi` offers `ENABLE_KGDB = "1"`, which
`rpi-cmdline.bb` turns into `kgdboc=serial0,115200`.

**What was done.** Set `CMDLINE_KGDB` to the explicit
`kgdboc=ttyAMA0,115200` instead, and wrote the reason in the kas file and
a check in `docs/BRINGUP.md`.

**Why that and not the alternative.** `serial0` is a device-tree alias.
`console=serial0` works because the console code resolves aliases through
the stdout-path mechanism. `kgdboc` resolves its argument through
`tty_find_polling_driver`, which matches a registered tty driver name and
index, and an alias is not one.

**This is inferred from reading, not seen on a board**, and it is
labelled that way in both places rather than stated as a finding. Being
explicit costs nothing if the alias does work; if it does not, the
failure it avoids is a debugger silently attached to no port at all, on a
board where everything else looks correct.

---

## 13. What is not done

Stated plainly, because an acceptance table with blanks invites the
assumption that the blanks are oversights.

**Nothing has been built and no board has been booted.** Every measured
row in the README is empty and every notebook output block says `NOT YET
RUN`. What exists is the configuration, the module, the host tools, 37
assertions that run on a laptop, and the documents.

Two things are known to need a board before they can be trusted:

1. The `kgdboc=serial0` inference in entry 12.
2. Whether `total-size=0x20000` with a 32 kB console region actually
   leaves six usable dmesg slots, which is arithmetic until a seventh
   crash overwrites the first.

And one thing cannot be checked on the authoring laptop at all: this
machine has no cross compiler, so `buggy.c` **has never been compiled**.
It is C written against kernel headers and read back carefully, which is
not the same as building. That is the first thing the build laptop
should say something about.
