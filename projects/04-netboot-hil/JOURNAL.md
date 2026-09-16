# Journal: Project 04

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 16 September 2026 unless noted.

---

## 1. The hardware was asked about before the design was written

**What happened.** Three facts about the bench decided what this project
could claim, and none of them was knowable from the specification: whether
a 3B+ exists, whether any Ethernet cable exists, and whether the LED parts
can be connected.

**What was done.** Asked, before writing anything. The answers changed two
of the four figures.

| Question | Answer | Consequence |
|---|---|---|
| A Pi 3B+ for the DUT | Yes, and also a Pi 3 and a 3B | Use the 3B+. It ships with network boot enabled in OTP, and the plain Pi 3 would need a permanent OTP bit the specification warns against |
| An Ethernet cable | A cable, but no wired modem or router anywhere | Not a blocker. The specification's second topology is a direct cable with the server as DHCP server, which needs no router at all |
| LEDs | Only the Joy-IT LinkerKit modules | Deferred, the same 2.0 mm socket that blocked Project 1 |

**Why that and not the alternative.** The alternative is to write the design
from the specification and discover at the bench that half of it cannot be
built. The bench layout figure in particular would have been drawn with a
router in it, which would have been wrong in a way that survives into the
documentation and gets copied.

The Ethernet answer is the one worth recording, because the first reading of
it was wrong. "No modem to connect to" sounds like a blocker for a project
whose subject is network boot, and it is not: two boards and one cable is
the entire network, and the specification already provides that topology. It
took reading `bench-isolated.conf` in the specification to see it.

---

## 2. The product is a lab, so most of it is not a recipe

**What happened.** Every other project in this repository puts its work in
`meta-bench`. This one puts one kernel fragment and one image there, and
everything else under `projects/04-netboot-hil/`.

**What was done.** Kept the split and said so in the design document rather
than letting the layout look like an oversight. The server configuration is
four files and an installer; the runner is a console helper, fixtures and
two test files.

**Why that and not the alternative.** The alternative is a `bench-lab-image`
built by this repository, which is more in its spirit and is a week of
`PACKAGECONFIG` work for something nobody measures. The server is the
instrument, not the product. The DUT is the product, and it boots an image
this repository does build, which is the whole point of the lab.

It is recorded as a stretch goal rather than dismissed. The day the lab
itself has to be reproducible from source, the argument changes.

---

## 3. The console protocol, and two defects the test found

**What happened.** `console.py` frames command output with a unique end
marker, because a serial console has no framing and matching on a shell
prompt fails the first time a command prints something that looks like one.
The test for it, written against a fake board rather than a real one, failed
two of its fifteen assertions on the first run.

**What was done.** Both were real.

**The marker was a timestamp.** `time.monotonic_ns()` looks unique and is
not: the monotonic clock has a resolution of about 15 ms on some hosts, and
two commands issued in quick succession got the same marker. The parser then
finds the previous command's marker still in the buffer and returns its
output as this one's. Replaced with a per-instance counter and the process
id, which cannot collide with itself and cannot collide with a second runner
on the same console.

**The echo was stripped unconditionally.** A console echoes the command
before running it, so the first line of what comes back is not output and
has to go. Dropping it always is right for an echoing console and silently
eats the first line of real output on one that does not echo, which ser2net
can be configured to produce and which a board in a strange state can start
doing without saying so. Now the echo is only stripped when the marker is
actually found in what remains, which is the evidence that there was one.

**Why this entry exists.** Neither defect is exotic and neither would have
been found by reading. The first needs two commands in the same 15 ms, and
the second needs a console that does not echo, and both are the sort of
thing that happens once in twenty runs and gets blamed on the hardware.
Writing the fake board took twenty minutes and it is the only reason either
is known.

It is also the skill's own rule paying for itself on the first project after
it was written down: prove the check fires. Here the check fired without
having to be broken on purpose, which is better.

---

## 4. A false positive in the server test, and what it taught

**What happened.** `hil-server-config-test.sh` asserts that nothing names
`/dev/ttyUSB0` as a device to open, because the whole point of the udev rule
is that allocation order is not a promise. It flagged `install.sh`.

**What was done.** Read the line. `install.sh` names `/dev/ttyUSB0` inside
the `udevadm info -a -n /dev/ttyUSB0` command it tells the operator to run,
which is how you find the port path to put in the rule. That is naming the
device in order to stop naming it.

The check now excludes lines mentioning `udevadm`.

**Why that and not deleting the check.** This is the third time in this
repository that a new rule has needed narrowing for a legitimate case: the
firewall test flagged a comment cross-referencing another image, the image
package check flagged `bench-hub-image` pointing at what the real-time image
does, and now this. The pattern is always the same, a rule that cannot tell
use from mention, and the fix is always to name the legitimate context
rather than to widen the exception or silence the rule.

A rule that gets silenced is worse than no rule, because it is still there
teaching whoever reads the output to skip a line.

---

## 5. Two interfaces, two owners, and the failure in between

**What happened.** Writing the DUT image raised a question the specification
does not: what happens when systemd-networkd starts on a board whose root
filesystem is mounted over the interface it is about to manage.

**What was done.** `bench-netboot` ships
`10-eth0-netboot.network` with `KeepConfiguration=yes`, and the file
explains itself at length because the failure is not obvious from the
symptom.

The kernel configures `eth0` before userspace exists, because `ip=dhcp` is
on the command line, and mounts the root over that address. systemd-networkd
then starts, sees an interface it is willing to manage, and by default takes
it over: it drops the address and acquires its own. For the few hundred
milliseconds in between, the NFS server is unreachable, and the process
reading from the root filesystem at that moment is systemd-networkd.

**Why this is in the journal rather than only in the file.** Because the
symptom is a board that reaches userspace, prints a few lines and stops,
with `nfs: server not responding` and no shell to ask. Nothing about that
points at the network configuration, and the obvious reading is a bad image
or a flaky cable.

This is the same shape as Project 15's ownership table: one resource, two
managers, and a failure that looks like something else. The design document
has a table for exactly this reason, and `eth0` is in it.

---

## 6. The fstab names a card that is not there

**What happened.** `core-image-minimal` carries fstab entries for the boot
partition. On a board with no card, those are mounts of a device that never
appears, and a failed mount unit at every boot.

**What was done.** A `ROOTFS_POSTPROCESS_COMMAND` in the image comments them
out, with the reason next to it.

**Why it matters more than it looks.** The lab's first test asserts that
`systemctl --failed` is empty. A permanent, harmless failure in that list
makes the assertion impossible and, worse, would have to be worked around by
weakening the test to allow one known failure. A check that has to be read
past is a check nobody reads, and an allowance for one known failure is how
a second one gets in unnoticed.

---

## 7. The cable that was never the problem

**What happened.** Project 1 deferred its serial console because the bench's
Renkforce USB/TTL adapter is a PL2303HXA, a generation Windows refuses to
drive. Project 4 uses that same cable as its main instrument.

**What was done.** Nothing. It works here, because the machine it plugs into
is the Linux server rather than the Windows laptop, and `pl2303` handles the
HXA without comment.

**Why this is worth a paragraph.** The deferral in Project 1 was recorded as
being about the cable, and Project 15 later found a possible replacement
adapter on the SIM7600 HAT and wrote that up too. Both of those were
reasoning about the wrong half. The cable was always fine. The host was the
problem, and a sentence in Project 1 saying "Windows refuses this cable"
would have been true where "this cable does not work" was not.

The lesson is the one about separating what was seen from what was worked
out, and it is now in the skill: an observation and a mechanism written in
the same voice are not the same kind of claim.

---

## 8. Nothing has booted

**What happened.** The software is written and the parts that can be tested
on a laptop are tested: 15 assertions on the console protocol, 32 on the
server configuration. No board has been powered on.

**What was done.** Said so, in the state paragraph and in every row of the
acceptance table.

**What is most likely to be wrong when hardware arrives**, recorded in
advance so that the journal can say whether the guess was right:

1. The udev rule's `KERNELS` value, which is a placeholder until the real
   USB port is read on the server. Everything downstream depends on
   `/dev/tty-dut3` existing.
2. The TFTP file list in `deploy.sh`. The names differ between a Raspberry
   Pi OS boot partition and a Yocto deploy directory, and `start4.elf`
   against `start.elf` is a 3B+ against a Pi 4 distinction that is easy to
   get backwards.
3. Whether the bench image's `getty` actually comes up on `serial0` on a
   3B+, where the console UART is the mini UART unless Bluetooth is
   disabled. The specification says to use the `disable-bt` overlay and this
   image has not been asked to.
4. Whether `pytest`, `pyserial` and `python3-libgpiod` on Raspberry Pi OS
   are new enough for the libgpiod v2 API the loopback test uses.

---

## 9. CI went red on five shellcheck findings, and one of them was the old bug again

**What happened.** The push of this project turned the `lint` job red at the
"Shell scripts" step. Five findings, none of them in a program that had ever
been run, because none of this has been run:

```
projects/04-netboot-hil/runner/deploy.sh:50   SC2012  ls instead of find
projects/04-netboot-hil/runner/deploy.sh:80   SC2043  loop runs once
projects/04-netboot-hil/runner/deploy.sh:110  SC2012  ls instead of find
projects/04-netboot-hil/server/install.sh:82  SC2086  unquoted $TOPOLOGY
tests/hil-server-config-test.sh:118           SC2016  $ in single quotes
```

**What was done.** Four fixes at the cause and one stated intent.

`deploy.sh:110` was the interesting one. It read
`ls -1 "$NFS_ROOT/lib/modules" | head -1` to learn which kernel release the
DUT will report, and that is the lexical-order bug this repository has now
written six times: a rootfs that has carried two kernels has two
directories there, and `6.12.93` sorts before `6.6.63` because `1` is less
than `6`. The consequence here is a `kernel-release` file naming the wrong
kernel, which `test_kernel_is_the_one_we_deployed` would then compare
against and pass on. Replaced with a `find -printf '%T@ %f'` ranked by time,
with the reasoning in a comment next to it.

`deploy.sh:50` was the same shape and not the same bug: `ls -1t` does sort
by time, so it was correct and only awkward. Changed for consistency and to
clear the finding.

`deploy.sh:80` was a `for` loop over one literal path, written that way so a
missing device tree would be skipped rather than fatal. A plain assignment
and test does the same thing and says so. Checked that the change does not
alter control flow under `set -e`: a failing `[ -f x ] && cp` is the left
operand of an AND-OR list, which errexit ignores, so the script continues in
both forms. Verified with a probe rather than assumed, because a script that
exits early there would silently skip deploying the root filesystem.

`install.sh:82` was an unquoted `$TOPOLOGY` in the destination path, four
lines below the same variable quoted correctly in the source path. Quoted.

`tests/hil-server-config-test.sh:118` was not a defect. The string is a grep
pattern that must match install.sh's text including a literal dollar sign,
so the single quotes and the escape are both deliberate; expanding it would
search for this test's own empty `$other` and assert nothing. A
`# shellcheck disable=SC2016` with five lines saying why, rather than a
rewrite that would weaken the assertion.

**Why that and not the alternative.** The alternative for all five is to add
them to the `-e` exclusion list in CI, which is one line and turns the
checker off for the whole repository. Four of the five were real, one of
them was a wrong answer waiting for a board, and a checker you switch off
when it disagrees with you is not a checker.

**What this cost and what it says.** Nothing was caught locally, because
this bench has no shellcheck: the authoring machine is Windows, and
`scripts/host-check.sh` skips the step with a note when the tool is absent.
That skip is honest and it means CI is the first place these appear, which
is a twenty-minute round trip per finding. It is the same lesson as
[Decision 59](../../walkthrough/DECISIONS.md): the sort bug had already been
found, fixed, tested and written up, and it still arrived in a new file,
because a fix applied where it was found does not reach where it lives next.
