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
