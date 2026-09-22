# Journal: Project 20

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled
list of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that
and not the alternative**.

All entries are 16 September 2026 unless noted.

---

## 1. The threat model was written before the code, and it shortened the code

**What happened.** The obvious order is to build the trusted application
and then write a section about what it does not protect. The scope for
this project says the opposite, and the reason became clear while writing
it.

**What was done.** [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) first,
with the three things a Pi 3 cannot do, a table of four attackers and
which one is stopped, and the sentence to use on a CV instead of the one
everybody uses.

**Why that and not the alternative.** Two things came out of writing it
first, and neither would have survived being written afterwards.

The `export-once` command exists because HMAC is symmetric and the
verifier needs the same secret. Written afterwards, that is an
embarrassment to explain away. Written first, it is a design constraint,
and the design that follows is a single auditable command with an
irreversible lock rather than a key file copied around by a provisioning
script.

And the honest scope of the whole project is "the APIs, the boot flow and
the tools", which is what justified not building a secure boot chain,
not fusing keys, and not pretending the storage encryption means
anything. A project that had claimed protection would have had to keep
claiming it.

---

## 2. The eleven-integer UUID, and four places it is restated

**What happened.** A TA's UUID appears as a C macro of eleven separate
hex integers, as a string, as the `BINARY` line of a makefile, as a
variable in a recipe, and as a string in the Python binding. Nobody
proof-reads the eleven-integer form.

**What was done.** `tests/keystore-header-test.sh` parses
`bench_keystore_ta.h`, reassembles the UUID from the macro, and compares
it against the string form, the makefile, the recipe and the binding. The
same test checks the four command ids, the two lengths, the object names
and the LED event bytes across C, Python and the policy model.

**Why that and not the alternative.** The alternative is a comment saying
"keep these in step". The failure it prevents is silent in a specific way:
a TA built with one UUID and a client asking for another produces
`TEEC_ERROR_ITEM_NOT_FOUND`, which is the same error as a TA that is not
installed at all, which is the same error as a TA whose signature OP-TEE
rejects. Three causes, one number, and only one of them is visible from a
shell.

---

## 3. The linter reported my own example as a missing file

**What happened.** A comment in the recipe explained why SRC_URI does not
use a `subdir=` parameter, and quoted the parameter it was not using.
`scripts/lint.py` scans the whole recipe text for `file://` entries, found
the one in the comment, and reported a missing file.

**What was done.** The comment was reworded to describe the syntax rather
than spell it out, and it now says what happened.

**Why that and not the alternative.** Teaching the linter to skip comments
is the better tool, and it is a change to something every recipe in the
repository depends on, made to save five lines in one file. The comment I
had written argued exactly that about a different change one paragraph
earlier, so taking the other side of my own argument in the same file
would have been hard to defend. It is recorded here so that the second
recipe to hit it has a precedent to point at.

---

## 4. The signer and the verifier did not agree about two spaces

**What happened.** The scope gives the signing side as

```python
mac = benchkey.sign(json.dumps(rec, sort_keys=True).encode())
```

and the verifying side as

```python
canon = json.dumps(rec, sort_keys=True, separators=(",", ":")).encode()
```

Those are different bytes. `json.dumps` defaults to `", "` and `": "`,
with spaces; the verifier asks for neither.

**What was done.** Checked it rather than reasoned about it:

```
signer  : b'{"a": 1, "b": 2, "host_ts": 1789000000.5}'
verifier: b'{"a":1,"b":2,"host_ts":1789000000.5}'
equal   : False
```

Then one function, `canonical()`, in `benchkey.py`, shipped to both sides
and called by both. Five rules, each with the failure it prevents written
next to it: drop `mac`, sort keys, no spaces, escape non-ASCII, refuse
NaN. `tests/keystore-canonical-test.sh` holds the two spellings apart as
its first assertion.

**Why that and not the alternative.** The alternative is to fix the
verifier to match the signer, which works until somebody edits one of
them. The failure this produces is the worst kind available in a signing
system: every record verifies as BAD, the data is intact, the key is
correct, the HMAC implementation is correct, and the two sides hashed
different bytes. Nothing in any output points at the cause, and the
obvious reading of "every record is BAD" is that something is tampering
with them.

Two rules in that list are there for reasons worth separating. `allow_nan`
is off because Python writes `NaN` and `Infinity`, which are not JSON, so
a record containing one would be unverifiable by anything that is not
Python; failing at signing time is better. And `ensure_ascii` is on so
that the signed bytes cannot depend on an encoding choice made twice.

The rule this does **not** solve is floats: Python picks the shortest
representation that round-trips and another language may not, so a
verifier written in C would need care. That is in the module docstring
rather than discovered later.

---

## 5. TEE_ERROR_ACCESS_CONFLICT is 0xFFFF0003, and I had written 0xFFFF000C

**What happened.** The CLI translates the three TEE results that send you
somewhere specific. The numbers were written from memory.

**What was done.** Read `lib/libutee/include/tee_api_defines.h` at
optee_os 4.1.0:

```
0xFFFF0001  TEE_ERROR_ACCESS_DENIED
0xFFFF0003  TEE_ERROR_ACCESS_CONFLICT
0xFFFF0008  TEE_ERROR_ITEM_NOT_FOUND
0xFFFF000C  TEE_ERROR_OUT_OF_MEMORY
```

`0xFFFF000C` had been labelled `ACCESS_CONFLICT`. So a TA that ran out of
heap would have been reported as "a key already exists", and a real
conflict would have printed nothing at all. Both were fixed, and
`OUT_OF_MEMORY` gained its own line naming `TA_DATA_SIZE` as the number
to raise.

**Why that and not the alternative.** There is no alternative worth
naming; the entry is here because the defect is invisible to every test
in the suite. A wrong string in an error table compiles, runs, and gives
a confident wrong diagnosis to somebody who is already having a bad
evening. The only defence is reading the header, and the model in
`tests/keystore_model.py` now carries the same constants so that a future
edit has something to disagree with.

---

## 6. RPI3_PRELOADED_DTB_BASE is inert, and I had written a paragraph about it

**What happened.** The OP-TEE build's `rpi3.mk` passes
`RPI3_PRELOADED_DTB_BASE=0x00010000` to Trusted Firmware-A. I wrote that
into `docs/DESIGN.md` as one of two constants compiled into the secure
world, with a sentence about a boot partition whose firmware puts the
device tree elsewhere producing "a monitor that reads rubbish".

Then I read the reference `config.txt`, which says
`device_tree_address=0x01000000`. Those two numbers differ by a factor of
256, and both come from the same repository, so one of my claims was
wrong.

**What was done.** Read TF-A's own documentation for the platform:

> `RPI3_PRELOADED_DTB_BASE`: Auxiliary build option needed when using
> `RPI3_DIRECT_LINUX_BOOT=1`.

The OP-TEE build does not set `RPI3_DIRECT_LINUX_BOOT`. Its BL33 is
U-Boot, not a kernel, so the option has no effect at all. The addresses
that do matter are `kernel_address` and `device_tree_address` in
`config.txt`, which have to agree with `kernel_addr_r` and `fdt_addr_r`
in `uboot.env`, and they do: `0x02000000` and `0x01000000` on both sides.

`DESIGN.md` now says that, the boot figure says it, and the paragraph
that was wrong says it was wrong.

**Why that and not the alternative.** The alternative was to leave it: it
was plausible, it was about a part of the system nobody on this bench has
booted, and it would have survived review. That is exactly the shape the
working method warns about, a mechanism invented from a fragment of
evidence and written in the same voice as an observation. It was caught
by cross-checking two files from one repository against each other, which
took four minutes, and it would have cost an evening of suspecting a
device tree address that was never involved.

The same reading turned up two facts worth keeping: there is no
`armstub=` line in that `config.txt`, because the firmware loads a file
of that name in 64-bit mode without being asked; and U-Boot picks between
`bcm2710-rpi-3-b.dtb` and `bcm2710-rpi-3-b-plus.dtb` at run time from
`board_name`, so the 3B and 3B+ difference is handled below this project.

---

## 7. Every figure had its line breaks eaten

**What happened.** The seven TikZ figures were written through shell
heredocs. A TikZ line break inside a node is `\\`, and the heredoc
consumed one level of every backslash, so every `\\` became `\` and every
`\\\command` became something else. `{console shows the\TF-A banner?}` is
not a line break, it is an undefined control sequence, and that figure
would not have compiled at all.

**What was done.** Counted the damage per file, rewrote all six affected
figures with a tool that does not eat backslashes, and then checked the
repair mechanically: no line ends in an odd number of backslashes, and no
control sequence of the shape `\TF-A` survives.

**Why that and not the alternative.** The working method already names
this hazard and says to use the editing tool rather than a heredoc for
anything containing a backslash continuation. I used a heredoc for seven
files in a row because they are prose-shaped and it did not feel like
recipe editing. The lesson is the one already written down, and the
detail worth adding is that the failure is invisible in the file being
written: a figure with broken line breaks looks fine in a terminal and
fails in a tool nobody runs until much later.

The mechanical check afterwards matters as much as the rewrite. "I
rewrote them carefully" is not a verification.

---

## 8. meta-arm refuses this board, and says where to say otherwise

**What happened.** OP-TEE lists the Raspberry Pi 3 as a reference
platform, so meta-arm was expected to build for it.

**What was done.** `optee.inc` opens with

```
COMPATIBLE_MACHINE ?= "invalid"
COMPATIBLE_MACHINE:qemuarm64 ?= "qemuarm64"
# Please add supported machines below or set it in .bbappend or .conf
```

and `OPTEEMACHINE ?= "${MACHINE}"`, which would be passed to OP-TEE as
`PLATFORM=raspberrypi3-64` while the platform directory is `plat-rpi3`.

Both are set in `kas/bench-tee.yml`, in the place that comment names, for
`optee-os`, `optee-os-tadevkit` and `optee-test`. `optee-client` needs
neither: it has no `COMPATIBLE_MACHINE` and no platform, which is the
tell that it is ordinary normal-world userspace.

**Why that and not the alternative.** Three bbappends would have done the
same thing in three files. The four lines are in the kas file because
whether this bench builds OP-TEE is a property of this configuration
rather than of the layer, and because the three recipes share one include,
so the declaration belongs where the include says to put it.

Reading those two files also settled what the platform actually is:
`plat-rpi3/conf.mk` forces `CFG_WITH_ARM_TRUSTED_FW=y` and sets
`CFG_TZDRAM_START = 0x10100000` with a 15 MB window. On a board with a
TrustZone address-space controller that window is enforced by hardware.
On this one it is enforced by everyone agreeing not to look, which is the
threat model in one line.

---

## 9. Secure storage is not where the documentation says

**What happened.** Every OP-TEE document, and the scope for this project,
says secure storage lives in `/data/tee`.

**What was done.** meta-arm builds optee-client with

```
-DCFG_TEE_FS_PARENT_PATH='${localstatedir}/lib/tee'
```

so on this image it is `/var/lib/tee`. The tmpfiles entry creates it, and
says in a comment that deleting it destroys the key with no recovery,
because that is the sort of thing somebody reads at exactly the wrong
moment.

**Why that and not the alternative.** Following the documentation would
have produced a tmpfiles entry creating a directory nothing uses, and a
troubleshooting section pointing at an empty path. The fact is one cmake
flag deep and worth writing down where the consequence is.

---

## 10. A template unit starts nothing

**What happened.** The scope's unit file orders itself
`After=tee-supplicant.service`, which is what every OP-TEE tutorial says.

**What was done.** meta-arm ships `tee-supplicant@.service`, a template,
and sets `SYSTEMD_SERVICE` to that name. A template with no instance and
no `DefaultInstance` is not a unit that starts: `After=` on the plain
name orders against something that does not exist, and systemd accepts
that silently.

Three changes followed. `bench-keystore` installs the wants symlink that
`systemctl enable tee-supplicant@0` would write, and says in a comment
why it, rather than optee-client, owns that decision.
`optee-selftest.service` orders against `tee-supplicant@0.service`. And
`optee-selftest` does not rely on the ordering at all: it waits for
`/dev/tee0` and then for a session to open, because a wait is a guarantee
and an ordering is a hint.

**Why that and not the alternative.** Copying the tutorial line would
have produced the first pitfall in the scope's own list, on a board, with
an error message that names neither the supplicant nor the file it could
not read. The failure is at the first session rather than the first
signature, which puts it a long way from the code anyone would suspect.

---

## 11. The linter's newest rule needed narrowing, and the proof it still fires

**What happened.** Another session added a rule: every file in `SRC_URI`
must be mentioned after `do_install` begins, written from a defect where
two files were fetched and the install lines were lost in editing. This
recipe fetches a `Makefile` and a `sub.mk` that `do_configure` arranges
into a build directory and that nothing installs, and the rule reported
both.

**What was done.** The search now starts at the first build task rather
than at `do_install`, and the docstring says which recipe made that
necessary and why the original defect is still caught: those files
appeared in no task at all.

Then the part that matters: the rule was broken on purpose to check it
still works. Removing the line that installs `keystore.tmpfiles.conf`
produces

```
SRC_URI names keystore.tmpfiles.conf, which do_install never mentions
```

and restoring it makes the rule quiet again.

**Why that and not the alternative.** The alternative is to narrow a rule
and trust that it still catches what it was written for. A check that has
never failed is not a check that is working, and a narrowed check that
has not been re-broken is a check that might now pass everything.

The first attempt at breaking it failed for its own instructive reason:
the anchor string I searched for ended in a backslash continuation, the
heredoc ate it, and the `assert` caught the mismatch instead of silently
editing nothing. That assert is in the working method for exactly this,
and it earned its place twice in one session.

---

## 12. What was run, and what it proves

**What happened.** None of this can be built here: no Yocto host, no
board, no secure world. The question was what can honestly be checked.

**What was done.** Three suites, run locally:

| Suite | Assertions | What it covers |
|---|---|---|
| `tests/keystore-canonical-test.sh` | 25 | The five serialisation rules, a round trip, tampering, a forged MAC, a foreign key, a stream, stable re-signing |
| `tests/keystore-policy-test.sh` | 29 | The four commands against an independent model: provisioning, a reboot, both ways to lose a key, parameter contracts |
| `tests/keystore-header-test.sh` | 28 | The UUID, command ids, lengths, object names and LED bytes across five files |

Plus `python scripts/lint.py` clean, `sh -n` on every new shell file, and
a smoke test of `optee-armstub.sh` against a fake boot partition, which
installs, reports and removes without touching anything it should not.

**Why that and not the alternative.** What none of it proves is that a
secure world boots, that the TA loads, that it is signed with a key this
OP-TEE trusts, or that a MAC ever came out of the secure world. The
README says so in its State section rather than at the bottom, and the
acceptance table marks four rows "policy proven against a model,
unproven on a TEE", which is a different thing from proven.

---

## 13. What is deliberately not done

- **The secure world is not a recipe.** `./go armstub` installs a
  prebuilt `armstub8.bin` instead. The five things a recipe would have to
  settle are listed in `docs/BRINGUP.md`; the short version is that TF-A
  for this board produces a FIP rather than a kernel, needs U-Boot as
  BL33, and cannot go into `IMAGE_BOOT_FILES` until it is a recipe, which
  is circular. A recipe written here could not be built or booted, and
  one that looks right and is wrong is worse than a documented manual
  step.
- **No ECDSA.** The stretch goal replaces HMAC with P-256 so that the
  verifier needs no secret and `export-once` can disappear. It is the
  right design and it is four times the TA; the symmetric version teaches
  the same three mechanisms, and the threat model says plainly that the
  hole exists and why.
- **No monotonic counter**, so a replayed record verifies. Worth saying
  out loud because "the signature is valid" and "this reading is fresh"
  are different claims, and only the first is made here.
- **No PKCS#11 token.** OP-TEE ships a TA for it and `libckteec` to talk
  to it, which would make openssl use the TEE. That is a larger and more
  useful project than this one and deserves its own.

---

## 14. A four-byte variable where the API writes eight

**What happened.** The commit was pushed and CI went green, which proves
less about this project than about most: CI compiles `bench-status.c`,
`lte-gpio.c` and `rt-toggle.c`, and it does not compile any of the three C
files added here, because two of them need `libteec` and the third needs
the OP-TEE development kit. So a green run meant the shell, the Python and
the lint were checked and the C had still never been near a compiler.

Reading the headers afterwards found this, in `cmd_export_once`:

```c
uint32_t size;
...
res = TEE_GetObjectBufferAttribute(key, TEE_ATTR_SECRET_VALUE,
                                   params[0].memref.buffer, &size);
```

and in `lib/libutee/include/tee_internal_api.h` at 4.1.0:

```c
TEE_Result TEE_GetObjectBufferAttribute(TEE_ObjectHandle object,
                                        uint32_t attributeID, void *buffer,
                                        size_t *size);
```

**What was done.** `size_t size;`. On aarch64 that is the difference
between four bytes and eight: passing a `uint32_t *` is an incompatible
pointer type, and a compiler that allowed it would have the callee write
eight bytes into a four-byte object and corrupt whatever the stack put
next to it. The comment now says which types are in play and why.

The cause is worth naming. OP-TEE 4.x defaults to the GlobalPlatform 1.2
types, where `TEE_Param.memref.size` is `size_t`. The 1.1 types, with
`uint32_t`, are still there behind `CFG_TA_OPTEE_CORE_API_COMPAT_1_1`,
which the OP-TEE example TAs set in their makefiles and this one does not.
Code adapted from an example built that way compiles there and not here,
and the header that says so is two directories away from the example.

Checked at the same time and not defects: `bool` is available, because
`tee_api_types.h` includes `<stdbool.h>`; `TEE_OpenPersistentObject` and
`TEE_CreatePersistentObject` take `size_t` lengths and receive `strlen`
and `sizeof`; `TEE_MACComputeFinal` takes `size_t` and `size_t *` and is
handed `memref.size` and its address; and the whole client side is clean,
because `TEEC_TempMemoryReference.size` is `size_t` and `benchkey.c` uses
`size_t` throughout.

**Why that and not the alternative.** The alternative was to leave it for
the first build on a Yocto host, which is where it would have appeared as
a compile error with a clear message, so nothing would have been lost
except an afternoon and the rebuild. What made it worth finding now is
what it says about the green tick: a suite that compiles three of six C
files reports on three of six, and the report does not mention the other
three. A check that selects its own inputs has to say what it selected,
and the acceptance table should not read as though CI covered this.

The repair for the class, rather than the instance, is a CI step that
compiles `benchkey.c` against the real `libteec` headers from a pinned
tag, exactly as the existing job builds libgpiod v2 from a pinned tag to
compile the GPIO daemon. That is the same shape of fix and the same
precedent; it is not in this commit because it is a change to the shared
workflow rather than to this project.

---

## 15. A second wrong constant, and the one a compiler could never catch

**What happened.** Checking every libteec symbol in `benchkey.c` and
`benchkey-cli.c` against `tee_client_api.h` at 4.1.0 found all twenty-one
present and correctly spelled, and then found this:

```c
if (origin == 2 /* TEEC_ORIGIN_TEE */)
```

```
#define TEEC_ORIGIN_API          0x00000001
#define TEEC_ORIGIN_COMMS        0x00000002
#define TEEC_ORIGIN_TEE          0x00000003
```

Two is `COMMS`. So `benchkey sign` against a missing or unsigned TA, which
returns `ITEM_NOT_FOUND` with origin `TEE`, would have printed "no key.
Run: benchkey generate" instead of the line about `/lib/optee_armtz` and
tee-supplicant. A wrong diagnosis pointing at a wrong fix, which is the
same shape as entry 5 and the second instance of it.

**What was done.** Not `2` to `3`. `benchkey-cli.c` now includes
`<tee_client_api.h>`, which it already links against, and every one of
the five values in that block is a symbol: `TEEC_ERROR_ACCESS_DENIED`,
`TEEC_ERROR_ACCESS_CONFLICT`, `TEEC_ERROR_ITEM_NOT_FOUND`,
`TEEC_ERROR_OUT_OF_MEMORY` and `TEEC_ORIGIN_TEE`. All five are in that
header; none had to be invented.

**Why that and not the alternative.** Correcting the number would have
left four other literals that were also recalled from memory, one of
which was already known to have been wrong once.

The wider point is the one worth keeping, because it answers a question
that was asked directly: would a CI step that compiles this file have
caught it? No. `origin == 2` is valid C, and so is `0xffff000c`. The
type defect in entry 14 is exactly what a compiler catches; these two are
exactly what it does not. Both were found the same way, by reading the
header the code claims to speak.

So the compile step is still worth having, and it is not the guard for
this class. The guard is refusing to write a literal where a symbol
exists, which converts a value error into a name error, and a name error
is one the compiler does see.

## 16. Three acceptance rows cited a folder that was never created

**What happened.** A review across the repository found criteria 1, 2 and 6
citing `docs/evidence/xtest-report.txt` and "a timing table in
`docs/evidence/`", with no such directory in the project. The rows are all
marked "not started", so nothing was overclaimed, and a reader following
the citation still arrived nowhere.

**What was done.** `docs/evidence/README.md` added, one row per criterion
with its command, including the two that carry caveats rather than numbers:
`leds.jpg` is deferred on the same terms as Project 1, needing three bare
LEDs or an LK-Cable, and the whole folder carries a pointer to
`THREAT-MODEL.md` because the Pi 3 has no secure boot and no hardware
unique key.

**Why that and not the alternative.** The alternative was to reword the
three rows so they stopped naming a path. That would have removed the
dangling reference and also the information: the point of naming
`xtest-report.txt` is that criterion 2 is settled by one whole command
output and not by a summary of it. Keeping the path and creating the index
keeps that, and turns the citation into a plan a reader can act on.

## 17. Four builds, each failing one step further along, and then an image

Monday 21 September 2026. The first time `./go tee` was ever run.

**Software complete was a claim about code nothing had compiled.** The
front page said it, journal entries 14 and 15 had already noted that CI
compiles five C files and none of this project's three, and the first
build proved the point four times in a row:

| attempt | stopped at | cause |
|---|---|---|
| 1, four seconds | task queue | `Nothing RPROVIDES 'python3-gpiod'`: the LED daemon's binding lives in meta-python, and `kas/bench-tee.yml` named only meta-oe. Project 17 declares the same layer for the same reason in its own kas file |
| 2, 23 minutes | TA link | `cannot find libgcc.a`. The dev kit's `gcc.mk` builds its own compiler variable from `CROSS_COMPILE`, sets `CC := false` on purpose, and locates libgcc with a bare compiler and `CFLAGS64`, which `ta_dev_kit.mk` defaults from the recipe's `CFLAGS`. Yocto puts `--sysroot` in `CC`, not `CFLAGS`. Measured: with the sysroot the compiler names an absolute path, without it the two words "libgcc.a", and the tune flags make no difference either way. One line, the same one meta-arm's `optee.inc` carries |
| 3, three minutes | CLI link | `cannot find -lbenchkey`. `do_install` had made the unversioned symlink for the package since the recipe was written; `do_compile` never made it for itself. And a warning that was not a warning: `MAX_INPUT` redefined, because `linux/limits.h` owns that name as 255 and this file's 1 MiB won only by coming second |
| 4, 43 minutes | nothing | `bench-tee-image-raspberrypi3-64.rootfs-20260921211144.wic.bz2`, 58 MB |

The TA linked, stripped and signed on attempt 3. That was the first
time `7b53ed98-cbfb-42ec-92b6-fe56e7682c5c.ta` existed.

**What the cheap checks did before any of it.** `docs/BRINGUP.md` step
1 says to run the fragment checks before paying for the long build, and
they earned it: `./go ksym -f tee` refused two promptless symbols the
fragment could not set, `DMA_SHARED_BUFFER` and `GENERIC_ALLOCATOR`. The
fragment had explained in prose that TEE selects them, and the checker
reads a marker on the line above, not a paragraph above the group. The
intent was documented and never declared.

Then the checker's own hint misled: its "selected by" list named three
files for each symbol and omitted `drivers/tee/Kconfig`, the one that
mattered, because `head -3` ran before `sort -u` and cut raw matches in
traversal order. I concluded from that list that the two symbols were
incidental, which is the opposite of true, and only reading the kernel
source corrected it. The checker now deduplicates before truncating,
says how many it is hiding, and verifies the marker's claim against the
selectors rather than printing near it, which its header had promised
since it was written. Proved by pointing the marker at a file that does
not select the symbol and watching it fail.

**What is still not true.** No secure world. `armstub8.bin` comes from
the OP-TEE reference checkout, which needs `repo` installed and has
never been built on this bench, and `docs/BRINGUP.md` gave a `repo init`
with no `-b`, which would have taken tip rather than the 4.1.0 the
recipes pin. Corrected before either half was built. A board booted from
this image finds no TEE, and that is the expected intermediate state.

**And what it cost the rest of the repository.** The `do_compile` fix
was committed with `git add` of one path while the index already held
another session's entire Project 19 tree, and `git commit` took all of
it: 41 files under a message about libgcc. That published a recipe whose
`inherit bundle` needs meta-rauc, which only one configuration provides,
and BitBake halts parsing for every configuration when one recipe cannot
inherit. No build in the repository could start until the two files
moved under `dynamic-layers/meta-rauc/`. CI then stayed red for four
pushes on shellcheck findings this laptop cannot see, and I pushed three
of them without reading the first. The disk budget, the archive tiers,
the dynamic layer and every one of those runs are in the commits between
`c8d7043` and the image.

## 18. The secure world, built in forty minutes once two facts were known

Tuesday 22 September 2026, from about 07:00. `armstub8.bin` had never
existed on this bench. It does now: 1,261,624 bytes, TF-A v2.6 debug with
a FIP holding BL2, BL31, OP-TEE as BL32 at 0x7CED8 bytes and U-Boot as
BL33 at 0x84B90, plus `uboot.env` at 16,384 bytes.

**What the bring-up document did not say, and now does.** Two host
prerequisites: `repo` (`apt-get install repo`, Ubuntu 26.04 ships 2.54)
and `python3-pyelftools`, without which `optee_os` stops at
`gen_ldelf_hex.py` with a message that names the package. The first
`make` failed on it after U-Boot had already built; the second succeeded.

**`make -j8` was the wrong target, and reading `rpi3.mk` said why.**
`all` builds `buildroot`, `linux` and `update_rootfs`, none of which this
project uses: the image is Yocto's. And `update_bootfs`, the target that
populates `out/boot`, depends on `linux` and installs the Linaro 5.17
kernel as `kernel8.img` plus `bootcode.bin` and friends from a **2019**
firmware tag, over a Yocto boot partition carrying a 2025 set. What this
project needs is three files: `armstub8.bin`, which embeds U-Boot in the
FIP so no separate `u-boot.bin` is wanted; `out/uboot.env`; and a
`config.txt` that the installer writes itself. `tf-a` and `u-boot-env`
produce the first two and nothing else. `out/boot` is then two `cp`
lines. `./go armstub install` reads exactly those two.

**The manifest, saved.** `repo manifest -r` names all 11 components at
their exact commits, every OP-TEE one at `refs/tags/4.1.0`, so the two
halves agree on the version the recipes pin. It also says TF-A is
**v2.6**, where the kas comment says 2.10; the comment only claims that
`plat/rpi/rpi3` exists, which is true of both, but the evidence file
carries the real one. It is in `out/rpi3-manifest.xml` and goes into
`docs/evidence/` with the first console capture.

**Entry 6 held.** `RPI3_PRELOADED_DTB_BASE=0x00010000` in the TF-A flags
against `device_tree_address=0x01000000` in every `config.txt` looked like
a mismatch that would stop the board with nothing on the console. The
reference `uboot.env.txt` has `fdt_addr_r=0x01000000` and
`kernel_addr_r=0x02000000`, the reference `config.txt` has the same two,
and the installer's block has the same two. TF-A's constant is read only
when TF-A boots a kernel itself; with U-Boot as BL33 it is inert, which is
what entry 6 said and what the reference build ships and boots with.

**Not yet read, and it matters for the first boot.** `uboot.env.txt` line
31: `mmcboot=run load_kernel; run set_bootargs_tty set_bootargs_mmc
set_common_args; run boot_it`. `booti` replaces the kernel command line
the firmware built from `cmdline.txt` with U-Boot's own `bootargs`, so the
kernel will see the reference environment's `root=` and `console=`, not
Yocto's `root=/dev/mmcblk0p2 console=serial0,115200`. The three
`set_bootargs_*` definitions were asked for four times tonight and never
printed. If the first boot finds no root, this is the first place to look.

## 19. One card, a hot one, and a diagnosis I got wrong out loud

**The bench has one card.** The bring-up's step 0 said "the card is the
one this project will own", written for a bench with more cards than this
one. Joseph's practice is one card and an archive of every flashed
instance before the card is reused, which is what `./go archive` and the
Desktop copy are for. The document now says that.

**The first flash died at three percent** with `fsync: Input/output
error`, and `dmesg` showed `reset high-speed USB device ... using
vhci_hcd`, a command aged 63 seconds, and `Sense Key 0xb, ASC 0x47/0x1`,
a data-phase CRC error. I read that as USB/IP failing under a bulk write
and said so with more confidence than the evidence carried. Two further
`usbipd attach` attempts hung; the third said `Device busy (exported)`.
Then the card was hot to the touch.

A different card, the same reader and the same USB/IP path, wrote the
same image in **16 seconds at 11.6 MiB/s** with no reset. The link was
never the fault; the medium was, and a faulting card presents through a
reader as exactly the resets and CRC errors I attributed to the link.
Without a second card as a control the two are indistinguishable from the
kernel log, and I did not say that when I named the cause. The hot card
is out of the pool.

**The second card was the NanoPi NEO Air's.** Mounted read-only before
anything was written: `extlinux/`, `u-boot-sunxi-with-spl.bin`,
`sun8i-h3-nanopi-neo-air.dtb`, `flash-emmc.sh`, hostname `neo-air`. It is
the card Projects 2 and 3 provision the eMMC from, and Project 3 needs it
again for `10-uboot`. It is archived as `proj02-neo-air` on the Desktop
and `~/bench/neo-air/out` still holds everything `./go neo-air card`
writes back in minutes. Erased knowingly, on Joseph's say-so, with the
restore named. Project 3's journal carries the same note.

**The install, proved by its own status.** Before: `armstub8.bin absent`,
`uboot.env absent`, `config.txt does not mention it`, `kernel8.img
present`. After: `armstub8.bin present, 1261624 bytes`, `uboot.env
present`, `config.txt boots the secure world`, `kernel8.img present`, the
original `config.txt` kept beside it. The merged `config.txt` has no
second `kernel_address` or `device_tree_address` fighting the block, and
no `arm_64bit=1`, which it does not need: the firmware selects 64-bit mode
when `kernel8.img` is present, and the reference build's three-line
`config.txt` relies on the same inference. The first TF-A banner is the
proof of that; if it is absent, `arm_64bit=1` is the first line to add.

**Corrected in entry 21 on Tuesday 22 September 2026.** That inference
does not exist. With `armstub8.bin` present the board reaches 64-bit mode
anyway, which is why this paragraph looked right; take the stub away and
the same card boots to silence, because the firmware defaults `arm_64bit`
to 0 on a Pi 3 and goes looking for a `kernel7.img` that is not there.

**Two hand-over faults of mine, both now in the skill.** I gave a
`wifi.conf` template with placeholder values as a runnable block and it
was run as given: the card briefly carried a network called `YOUR_SSID`.
The board's script wants the SSID bare and the PSK as 64 hex from
`wpa_passphrase`, or a passphrase in double quotes; the skill had said so
since before this project and I re-derived it from the script mid-flash
because I had not read that section. And the release sequence was never
written as a sequence: `umount` in WSL, `usbipd detach` in an
Administrator PowerShell, then Windows' Safely Remove Hardware on the USB
drive, in that order, each handing the device to the next owner. Joseph
supplied the third step. Both are in `references/bench.md` now, with a
pointer at the top of the skill saying to read that section before any
card is touched.

**Where it stands.** The card holds the Yocto normal world, the secure
world, `uboot.env`, the installer's `config.txt` block and `wifi.conf`.
It has not been powered. The board is the 3B, v1.2, Project 8's second
board, chosen because OP-TEE's `plat-rpi3` was written against it and
because the 3B+ is spoken for by Project 17 and by daqring. The first
boot is watched on the console for three banners in order, TF-A, OP-TEE,
U-Boot, and the whole capture is `docs/evidence/boot-console.txt`.

## 20. Four CPUs, a TEE that bound, and a CPU that never came back

Tuesday 22 September 2026, late. The board booted the secure world for
the first time, reached a systemd start-up, and then one CPU disappeared
into OP-TEE and took the machine with it. Both halves of that sentence
are results.

**The firmware's device tree is not the tree OP-TEE needs.** The
Raspberry Pi firmware hands the kernel a tree with all four CPUs at
`enable-method = "spin-table"`, no `/psci` node and no `/firmware` node.
With TF-A underneath, the spin-table addresses are stale: CPU 0 comes up,
CPUs 1 to 3 are released into nothing and the kernel spends about fifteen
seconds timing out on them. And with no `/firmware/optee` the `optee`
driver never probes, so a secure world that booted correctly is invisible
to Linux.

**Patched in RAM at the U-Boot prompt, deliberately, before writing
anything permanent.** `fdt resize 4096`, then `/psci` with `compatible =
"arm,psci-1.0"` and `method = "smc"`, then `enable-method psci` on
`/cpus/cpu@0` through `cpu@3`, then `/firmware/optee` with `compatible =
"linaro,optee-tz"` and `method = "smc"`, then `fdt rsvmem add 0x08000000
0x400000` and `fdt rsvmem add 0x10100000 0xf00000`. Nothing touched the
card. The point of doing it this way is that a permanent fix written
before a proven one is a guess with a build attached to it.

**It worked, and the log says so in four places.**

```
psci: PSCIv1.1 detected in firmware
psci: Trusted OS migration not required
smp: Brought up 1 node, 4 CPUs
optee: revision 4.1 (18b424c2)
optee: initialized driver
```

Fifteen seconds of CPU timeouts gone. The console survived past
`bcm2835-aux-uart` because the firmware's own tree carries the pin
muxing. `Run /sbin/init as init process`, then systemd 255.22, then a
`tee-supplicant` slice.

**Entry 18's open worry is closed, and it was a false alarm.** That entry
said `booti` would replace the kernel command line the firmware built
from `cmdline.txt` with U-Boot's own `bootargs`, and that the three
`set_bootargs_*` definitions were the first place to look if the first
boot found no root. They were never needed: `bootargs` is not set in this
environment, so U-Boot left `/chosen` alone and the kernel saw Yocto's
line intact, `root=/dev/mmcblk0p2 rootfstype=ext4 rootwait`, and mounted
the right filesystem.

**Then CPU 3 went into the secure world and did not return.** From about
twenty seconds on, every RCU stall report names the same task:

```
Task dump for CPU 3:
task:kworker/3:2  state:R  running task
Workqueue: optee_bus_scan optee_bus_scan
Call trace:
 __switch_to+0xd8/0x140
 0x0
```

The trace ends at `0x0` because the unwinder cannot follow an `smc`
instruction into EL3. That CPU also stopped taking its timer interrupt,
which the report says in its own words, `Possible timer handling issue on
cpu=3 timer-softirq=258`. `rcu_preempt` had last run there, so it starved,
and every `umount` in systemd's path then blocked forever in
`synchronize_rcu_expedited`. One `device.pta` session opened and closed
cleanly just before Linux printed; the next entry into the secure world
never came back.

**The SD card went down with it**, which is what made one failure look
like two. `mmc0: timeout waiting for hardware interrupt` from 19.9
seconds, `rpi_firmware_property_list` hitting `Firmware transaction
timeout` inside `bcm2835_sdhost_set_clock`, then `mmc0: tried to HW reset
card, got error -110`, `mmc0: card 0001 removed`, the ext4 journal
aborted and the root filesystem remounted read only. At the time I could
not separate a wedged kernel from a failing card, and said so rather than
picking one, having already named a card fault as a link fault once this
week. Entry 21 separates them with a control.

**Where the permanent fix stands.** Not designed yet, on purpose. The
patch above is now known to produce a booting system, so the question is
only where to put it: an overlay on the boot partition, a `bootcmd` in
`uboot.env` running the same `fdt` commands, or a device tree shipped by
the image. None of those is worth choosing while the secure world still
wedges a CPU, because the next experiment may change what the tree has to
contain.

## 21. A control boot that would not boot, and a line missing since the image was first built

Same night. To find out whether the SD failure belonged to OP-TEE or to
the card, the obvious experiment is the same card in the same board with
no secure world at all. It cost three hours and produced four findings,
only one of which was the one I was looking for.

**`./go armstub remove` does not remove the secure world, and the script
says both things.** `do_install` explains that there is deliberately no
`armstub=` line because the firmware loads a file named `armstub8.bin`
whenever one is present. `do_remove` deletes the `config.txt` block, says
in its own comment that this is enough to boot without the stub, and
leaves `armstub8.bin` on the partition on purpose. Both cannot be true. I
did not settle which by experiment; I renamed the file to
`armstub8.bin.off` and moved on, so the contradiction is recorded rather
than resolved. Whichever way it resolves, `do_remove` needs fixing:
either its comment is wrong or its behaviour is.

**`do_remove` also destroys the only record of a working
configuration.** It restores `config.txt` by moving
`config.txt.bench-orig` over it, so a hand edit is lost and the backup is
consumed in the same operation. The edit at risk was
`device_tree_address=0x04000000`, which is the line the whole of entry 20
depends on. Copied to `~/config.txt.optee-secure.bak` first.

**Every `./go armstub` line in the bring-up needs `sudo`.** Step 2 gives
`./go armstub install /mnt/boot ...` with no `sudo`, against a partition
the same document says to mount with `sudo mount`. It worked on Tuesday
22 September 2026 only because that install happened to run as root.
Without it the first write stops at `mv: replace '/mnt/boot/config.txt',
overriding mode 0755?`, which nobody reads as a permissions problem.

**And then the control boot produced nothing at all.** Console attached,
picocom started before power, and not one byte. My first guess was that
`enable_uart=1` had gone with the removed block. Wrong, and disproved
from the file in a minute: it is at line 245 of the image's own
`config.txt`, well before the block. That file has exactly five active
settings in 252 lines, and the one that matters is the one that is not
there.

**There is no `arm_64bit=1`, and on a Raspberry Pi 3 it defaults to 0.**
Three boots settle what that means, and no single one of them would have:

| `armstub8.bin` | `arm_64bit` | Result |
|---|---|---|
| present | absent | boots, 64 bit, TF-A then OP-TEE then U-Boot then the kernel |
| absent | absent | silence, green ACT LED blinks once and stops |
| absent | `=1` | boots, firmware loads `kernel8.img` directly |

So the claim at the end of entry 19, that `arm_64bit=1` is not needed
because the firmware selects 64-bit mode when `kernel8.img` is present,
is **wrong** and is corrected here. What is true is narrower: with
`armstub8.bin` present the mode is entered anyway. Without it,
`kernel8.img` alone is not enough, the firmware looks for a `kernel7.img`
that this card has never had, and it stops without a word.
`bench-tee-image` has therefore never been able to boot on a Pi 3 except
through U-Boot, which loads `kernel8.img` by name, and nothing in the
repository could have noticed.

**`uart_2ndstage=1` paid for itself on the first boot it was present
for.** The Raspberry Pi firmware is silent on the UART unless told
otherwise, which is why a boot stage that fails before the kernel fails
invisibly. With it set, the firmware names every file it reads and every
address it picks:

```
Read File: config.txt, 2763
dtb_file 'bcm2710-rpi-3-b.dtb'
Loaded 'kernel8.img' to 0x200000 size 0x1a52a00
Device tree loaded to 0x2eff6e00 (size 0x911c)
```

Two of those are worth keeping: left alone, this firmware puts the kernel
at `0x200000` and the device tree at `0x2eff6e00`, nowhere near the
`0x01000000` the installer's block asks for.

**The control itself, which is the result the other three paid for.**
Same card, same board, same reader, no secure world: four CPUs, root
remounted read write, a login prompt, `dd if=/dev/mmcblk0 of=/dev/null
bs=1M count=512` reading half a gigabyte straight off the raw device with
no error, 207 seconds of uptime without a single `mmc0` timeout, and a
clean `poweroff` with `All filesystems unmounted`. Against a first
timeout at 19.9 seconds with the secure world in place.

**So the card is exonerated and the failure is one failure, not two.**
`mmc0: Problem switching card into high-speed mode!`, which I had flagged
as possible evidence against the card, appears at 3.58 seconds in the
clean boot and 4.2 seconds in the failed one. It is a constant of this
card and this controller and it means nothing. What killed the SD stack
was the machine dying around it.

**Next.** The stub back in place, `arm_64bit=1` and `uart_2ndstage=1`
kept, and `maxcpus=1` on the kernel command line, to ask whether OP-TEE
wedges only when it is entered from a secondary CPU. That is one line of
bootargs and it either localises the hang or rules out the cheapest
explanation for it.

## 22. The three defects, fixed, and a fourth that only a test found

Tuesday 22 September 2026, after the control boot. Entry 21 listed three
things the board had proved were wrong with this repository and left them
unfixed, which is the right order but a poor place to stop. All three are
fixed now, and exercising the fix found a fourth that no boot had yet
reached.

**`write_block` writes five settings, not three.** `arm_64bit=1` and
`uart_2ndstage=1` join `enable_uart=1`, `kernel_address` and
`device_tree_address`, each with the comment that says why it is not
redundant. The next card carries them without a hand edit.

**`do_remove` renames the stub instead of arguing about it.**
`armstub8.bin` becomes `armstub8.bin.off`. The script used to contain two
comments that could not both be true, `do_install` saying the firmware
loads that file whenever it is present and `do_remove` saying the
`config.txt` lines were enough to boot without it. Renaming is correct
under either, costs nothing, and keeps the file so that putting the
secure world back stays one command. `do_install` clears a stale `.off`,
and `do_status` now says "armstub8.bin absent, but armstub8.bin.off is
here", because "absent" on its own is a card whose history you cannot
see.

**The bring-up says `sudo`.** Every `./go armstub` line, against a
partition the same page mounts with `sudo mount`, with the actual failure
quoted, `mv: replace '/mnt/boot/config.txt', overriding mode 0755?`,
because nobody reads that as a permissions problem. The alternative,
mounting with `-o uid=$(id -u)`, is named for anyone who would rather not
run the script as root. Step 3 also gained the fourteen `fdt` commands
that make the firmware's tree usable, and its TF-A banner now reads v2.6
rather than v2.10.

**And the fourth, which came out of running the thing rather than
reading it.** Installed, removed, and looked at what `remove` had
produced: the image's original `config.txt`, faithfully restored, with no
`arm_64bit=1` in it. So `remove` returned a card that cannot boot and
reported that it had restored it. That is worse than the failure it was
meant to undo, and it is what I had done to this card an hour earlier
without noticing, which is why the control boot was silent. `do_remove`
now appends `arm_64bit=1` when the restored file lacks it, and running
`remove` twice leaves exactly one copy.

**Exercised end to end on win11 aquamarine** against a fake boot
partition, not on the card: install, status, remove, status, remove
again, install again. The `config.txt` comes back byte for byte apart
from the appended line, the `.off` is cleared on reinstall, and the
`arm_64bit` append does not duplicate. `sh -n` clean, lint clean.

None of this touches the thing that actually matters next, which is why
OP-TEE wedges CPU 3. It removes the traps between here and asking that
question again.

## 23. Four boots that narrow it to one function, and two experiments I designed badly

Tuesday 22 September 2026, late. Entry 20 left the fault described but not
located: something wedged CPU 3 inside OP-TEE and the SD stack died around
it. Two more boots locate it, and the answer is narrower than anything I
had guessed.

**First, the whole boot chain, finally captured.** The earlier boots were
caught mid-stream at the U-Boot prompt; this one has it from the first
line. TF-A v2.6 debug, BL1 then BL2 then BL31, `rpi3: Detected: Raspberry
Pi 3 Model B (1GB, Embest, China) [0x00a22082]`, OP-TEE loaded as image 21
at `0x10100000` and U-Boot as image 5 at `0x11000000`, then OP-TEE 4.1.0
printing its own memory map before handing to U-Boot 2021.10. Worth
keeping, because that map confirms two numbers we had invented blind in
entry 20:

```
TEE_SHMEM_START type NSEC_SHM 0x08000000 size 0x00400000
TEE_RAM_RX  0x10100000..0x10178fff
TEE_RAM_RW  0x10179000..0x107fffff
TA_RAM      0x10800000..0x10ffffff
```

Secure memory is `0x10100000` for `0xf00000`, shared memory `0x08000000`
for `0x400000`. Both `fdt rsvmem add` lines are exactly right, guessed
from the OP-TEE platform defaults and now confirmed by the secure world
itself.

And U-Boot states the device tree problem in its own words rather than
ours: `ERROR: Did not find a cmdline Flattened Device Tree` /
`Could not find a valid device tree`. That is `fdt_addr_r` at
`0x01000000` against a tree the firmware put at `0x04000000`.

**The `maxcpus=1` experiment, and why my framing of it was wrong.** The
question was whether OP-TEE wedges only when entered from a secondary
CPU. With one CPU the board reached systemd, ran to 12.2 seconds, and
then stopped. No stall reports, no panic, no further output, and Enter at
the console produced nothing.

That is the same wedge, and with only one CPU there is nobody left to run
the stall detector or print anything, so it presents as sudden total
silence. So the answer is **no**: entry from a secondary CPU is not the
fault. I should also have predicted the shape of the failure before
running it, because a hang on the only CPU cannot report itself, and for
a few minutes the silence looked like a different bug rather than the
same one.

**The experiment that did locate it: leave out `/firmware/optee`.** Same
card, same `maxcpus=1`, same `/psci` patch, same reserved memory, one
node omitted so the `optee` driver never probes. TF-A and OP-TEE still
boot, still hold their memory, still answer PSCI.

It ran for **317 seconds**, reached `raspberrypi3-64 login:` at 14.5
seconds, accepted a root login, and powered off cleanly with
`All filesystems unmounted`.

**Four boots, and what each one excludes:**

| CPUs | TF-A and OP-TEE resident | `/firmware/optee` | Outcome |
|---|---|---|---|
| 4 | no | no | healthy 207 s, login, 512 MB read, clean poweroff |
| 4 | yes | yes | CPU 3 wedged at about 20 s, RCU stalls, SD stack dies |
| 1 | yes | yes | dead at 12.2 s, total silence |
| 1 | yes | no | healthy 317 s, login, clean poweroff |

The card is excluded. The SD controller is excluded. Having a secure
world resident under Linux is excluded: rows three and four differ by one
device tree node and nothing else, and row four is healthy. Which CPU
makes the call is excluded. What is left is **the `optee` driver's calls
into OP-TEE**, and the only stack trace in evidence names
`optee_bus_scan`, the device enumeration that runs once at probe.

**A red herring I raised and then disproved.** Both failing boots had
`brcmfmac: brcmf_sdio_htclk: HT Avail timeout` shortly before the
trouble, and I said out loud that it might be the trigger that walks into
whatever OP-TEE is doing wrong. Row four has the same timeout at 13.19
seconds and reached a login prompt one second later. It is just what this
image does without its WiFi firmware.

**Two hand-over faults of mine, both costing a card cycle or a reboot.**

I put `arm_64bit=1` and `uart_2ndstage=1` on the card for the control
boot, where they were necessary, and then restored the secure world on
top without taking them off. That boot produced nothing at all, and
rather than three changes from a known-good state it should have been
one. The fix was to copy back `config.txt.optee-secure.bak`, the exact
3041 bytes that had booted an hour earlier, and change only
`cmdline.txt`. Which of the two lines broke it is still unknown and does
not matter; neither belonged in that boot.

And I handed over the seventeen `fdt` commands as a single paste. U-Boot's
console has no flow control and echoes every character, so the paste
overran it and arrived as `fdt mknoe / psci` and
`fdt set ible arm,psci-1.0`. One line at a time, waiting for the prompt,
works. The proper fix for next time is to put the sequence in a text file
on the FAT partition and load it with `fatload` plus `env import -t`,
which turns seventeen pastes into three and is reusable at every boot.
Worth knowing: U-Boot matches `fdt` subcommands by prefix, which is why
the mangled `fdt mknoe` still created the node.

**Next.** Rebuild the kernel with `CONFIG_OPTEE=m` rather than built in.
Today the driver probes during boot and takes the machine down before
there is a shell to ask anything from. As a module, the board boots to a
prompt with the secure world underneath it, and `modprobe optee` moves
the failure to a moment of our choosing, with `dmesg`, `/proc` and a
working console still available. Every question after this one needs
that.

## 24. The driver becomes selectable, and the linter caught two comments

Tuesday 22 September 2026, after entry 23. The next question needs a
board that boots, so the driver becomes a module. That is one symbol and
five files, and the gap between those two numbers is the entry.

**What it is not.** Not `CONFIG_OPTEE=m` in `tee.cfg`. That file's header
argues for built in and the argument is right for the product: this image
installs no kernel modules, so `=m` without a matching package is a
driver that exists in the build tree, is absent from the card, and looks
at the console exactly like a secure world that never booted. Changing it
in place would have left the repository arguing with itself.

**What it is.** The driver symbol moved out of `tee.cfg` into two
siblings, `tee-builtin.cfg` and `tee-modular.cfg`, one line each and a
header saying which question they answer. `BENCH_TEE_MODULAR` in the
bbappend picks exactly one. Everything else the TEE subsystem needs stays
in `tee.cfg` rather than being written twice.

A switch that picks between files rather than overriding a symbol is not
style. Two fragments setting one symbol to different values is an
override: `merge_config` takes the last and warns, and `./go kconfig`
then reports the losing fragment's line as one that never reached
`.config`. The repository's own check would have failed on the overlay
version.

**Two things the switch is not sufficient for, both of which cost a
bring-up if missed.** The module has to be in the image, so
`bench-tee-modular-image.bb` names `kernel-module-optee`; without it the
build succeeds, the card boots, and `modprobe` says the module is not
found. And the module must not load itself: the driver carries an OF
match on `linaro,optee-tz`, so with `/firmware/optee` in the device tree
udev autoloads it during boot and reproduces the exact failure the
variant exists to escape. `modprobe.blacklist=optee` on the kernel
command line stops the alias-driven load and leaves an explicit
`modprobe optee` working. Both are in the bring-up now.

**`scripts/lint.py` caught two of my comments, and both were real.**

The first was a line whose first word after the hash was a config symbol,
written to explain where that symbol had moved to. `merge_config` parses
such a line as a directive turning the option **off**, so a sentence
explaining the split would have quietly unset the thing it described.

The second was a comment saying that no module package exists for the TEE
subsystem itself and none is wanted. The linter reads `kernel-module-*`
names out of image comments and fails any that no image installs, a rule
written after Project 1 lost two rounds to a driver described in three
paragraphs and named in no image at all. Mentioning a package in order to
say it does not exist trips it, correctly: the checker cannot read intent,
and a rule that could would not have caught Project 1's defect either.
Reworded to name no package.

**Nothing is built yet.** This is five files and a lint run on win11
aquamarine; the kernel rebuild happens on win11 skyhorizon with
`./go tee-mod`. When the hang is understood, the fragment, the image and
the kas file should be deleted rather than left as a second way to build
Project 20 that nobody remembers the purpose of. The recipe says so in
its own comment.
