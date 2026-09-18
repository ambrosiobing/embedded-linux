# Journal: Project 12

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 15 September 2026 unless noted.

---

## 1. The protocol document came before the protocol

**What happened.** The scope is explicit that `PROTOCOL.md` is written
first. It would have been faster to write `proto.c` and document it
afterwards.

**What was done.** [docs/PROTOCOL.md](docs/PROTOCOL.md) was written first
and is the specification of record. The header layout, the endianness, the
CRC variant, the bounds, the resynchronisation rule, the preferred
serialisation and both versioning rules are decided there. `proto.c`
implements it, `tests/sensorhub_reference.py` implements it again in
Python, and the C-ABI test compares the two.

**Why that and not the alternative.** Writing the document forced the
resynchronisation rule to be decided rather than emerge, and that rule
turned out to be the one substantive decision in the whole format. It also
made the second implementation possible: a Python reference written from
the document is an independent check, while one transcribed from the C
would only prove that transcription works.

---

## 2. Encode by hand, decode with a library

**What happened.** The obvious reading of the scope is tinycbor on the
microcontroller and libcbor on Linux. Two CBOR libraries, two build
systems, one protocol.

**What was done.** `proto.c` encodes all five payloads by hand, in about
sixty lines, with no dependency and no allocation. `sensorhubd.c` decodes
with libcbor.

**Why that and not the alternative.** The asymmetry is the argument. The
five payloads are fixed in shape: a sample is always a four entry map with
integer keys, two three element arrays and two scalars, so writing it out
is bounded work that will never grow. Incoming bytes are the opposite
case: unknown shape, arbitrary length, from a device that may be running
half a firmware, parsed by a daemon that sits on the system bus. That is a
job for a parser somebody else has already fuzzed.

The other gain is that the firmware needs no CBOR library at all, which on
a part where tinycbor is a measurable fraction of the image is not a small
thing.

The cost is real and worth naming: the hand encoder must obey RFC 8949's
preferred serialisation exactly, or two implementations will produce
different bytes for the same value. That is why the shortest-head rule is
in the document and why the test asserts it at four widths.

---

## 3. The float bug, found by writing the decoder second

**What happened.** The Python reference decoder failed on a sample frame
with `unsupported major type 6`. There is no major type 6 anywhere in the
protocol.

**What was done.** The head parser consumes the CBOR argument first: for
additional information 26 it reads four bytes as the argument. A float32
is major type 7 with additional information 26, and its four bytes **are**
the argument. The float branch then read four more, and everything after
it was decoded from the wrong offset, which surfaced several items later
as a nonsense major type.

The fix is one line, `struct.unpack(">f", struct.pack(">I", arg))`, and it
has a comment on it that says what the symptom looks like, because the
symptom points at everything except the cause.

**Why that and not the alternative.** The interesting part is not the bug,
it is what found it. The encoder and the decoder were written from the same
document by the same person within an hour of each other, and the encoder
was right. A round-trip test against a single implementation would have
passed, because the encoder was never wrong. It took writing the inverse
operation to notice.

---

## 4. The parser steps forward one byte, never one frame

**What happened.** The obvious recovery after a bad CRC is to skip the
frame: the header says how long it is, so skip that many bytes and carry
on.

**What was done.** The parser discards the leading start-of-frame byte and
starts hunting again. The same rule applies when the length field is above
the 512 byte maximum.

**Why that and not the alternative.** The length that says how far to skip
is part of what just failed its own integrity check. Trusting it means
that one dropped byte on the line puts the receiver permanently one frame
out of step, because every subsequent "frame" starts in the middle of a
real one and every CRC fails. The symptom is a link that looks dead rather
than one that lost a frame, and it is a bad afternoon to debug.

Stepping one byte costs a memmove of at most 519 bytes on a failure, which
at the rate failures actually happen is nothing. `tests/sensorhub-proto-
test.sh` has the case as an explicit assertion: an absurd length followed
by a good frame, and the good frame has to arrive.

---

## 5. Two reply strategies, because there are two kinds of wait

**What happened.** `SetRate` and `Calibrate` are both methods that have to
wait for the hub. The tempting thing is to implement them the same way.

**What was done.** `SetRate` blocks the event loop for at most 200 ms,
measured from `CLOCK_MONOTONIC`. `Calibrate` takes a reference to the
message, returns without replying, and the reply is sent from the frame
parser when the ACK arrives, or from a three second timer if it does not.

**Why that and not the alternative.** The rule is that a handler may block
for as long as nobody would notice, and no longer. The hub acknowledges a
rate change in microseconds, so 200 ms is a generous bound on something
that will not happen; a calibration takes about two seconds, which is long
enough that every other client of the daemon would be stalled behind it.
The bus default timeout is 25 seconds, so a handler that approaches it
does not just fail, it makes the daemon look hung.

The first version of `wait_for_ack` counted loop iterations instead of
consulting the clock, which is wrong in a way that only shows up with
traffic: at 100 Hz there are samples arriving continuously, `poll` returns
immediately every time, and a counter expires in microseconds. Rewritten
against the monotonic clock, with the reason in a comment.

---

## 6. Explicit property getters instead of offsetof

**What happened.** sd-bus lets a property be declared as a signature plus
an offset into the userdata struct, and the scope's example does exactly
that. It is four characters instead of four lines.

**What was done.** Four explicit getter functions.

**Why that and not the alternative.** The offset form is unchecked. A
property declared `"t"` whose field is a `uint32_t` compiles cleanly and
serves four bytes of the next field as the top half of the value. Nothing
warns, and the number looks plausible. With a getter, the argument to
`sd_bus_message_append` has a type the compiler can see against the
signature string beside it.

It also made `ProtocolVersion` possible to define correctly. The property
reports the version the **hub** is speaking, not the one the daemon
implements, and those are different fields; with an offset it would have
been whichever one was easier to reach.

---

## 7. polkit is asked without user interaction

**What happened.** The scope's `CheckAuthorization` call passes
`AllowUserInteraction = 1`, which lets polkit find an authentication agent
and wait for a human.

**What was done.** Zero.

**Why that and not the alternative.** The project's own pitfall list
warns that a handler blocking longer than the bus timeout makes every
client hang. Waiting for a person is unbounded by construction, and this
is a system service on a headless board: there is usually no agent, and
when there is, the wait can exceed 25 seconds.

With zero, the answer comes from the rules immediately. The consequence is
deliberate and stated in the code: authorisation is a property of the
caller's group, decided by `50-sensorhub.rules`, rather than of somebody
being at a keyboard. On a bench that is what was wanted anyway.

---

## 8. Everything upstream was read rather than remembered

**What happened.** This daemon calls into two libraries whose functions
are variadic or macro-generated, which is the combination where a wrong
guess compiles cleanly and fails at run time. There is no board here to
find out on.

**What was done.** Four things were checked in upstream sources before
being used:

| Question | Where the answer came from |
|---|---|
| How does `sd_bus_message_append` take an array? | `man/sd_bus_message_append.xml`: "must begin with the number of entries, followed by the entries themselves". So `"tadad"` takes an int count before each array |
| Does libcbor have `cbor_float_get_float` and what does it return? | `src/cbor/floats_ctrls.h` at v0.11.0: returns `double`, and is marked `_CBOR_NODISCARD` |
| Are `cbor_map_handle`, `cbor_get_int`, `cbor_string_handle` spelled that way? | `src/cbor/{maps,ints,strings}.h`, all present, all NODISCARD |
| Does `struct cbor_pair` have `key` and `value`? | `src/cbor/data.h` line 201 |

**Why that and not the alternative.** `sd_bus_message_append` is variadic:
a wrong argument list produces a signal nobody can decode, at run time,
with no warning at compile time. That is the single worst failure mode
available in this project, and fifteen minutes of reading headers removes
it. The libcbor NODISCARD annotations matter for a different reason: with
`-Werror`, ignoring one of those return values fails the build, and
finding that out in CI rather than while writing is the slow way round.

---

## 9. The three layer recipes all existed, which was worth checking

**What happened.** The image needs polkit, libcbor and a Python D-Bus
binding. Assuming a recipe exists is how a project gets to the end of a
three hour build and discovers it does not.

**What was done.** The scarthgap branch of meta-openembedded was fetched
and searched:

```
meta-oe/recipes-extended/libcbor/libcbor_0.11.0.bb
meta-oe/recipes-extended/polkit/polkit_124.bb
meta-python/recipes-devtools/python/python3-dbus-next_0.2.3.bb
```

Reading the polkit recipe rather than only noting its existence produced
three facts the project needed:

- `REQUIRED_DISTRO_FEATURES = "polkit"`, so `kas/bench-hub.yml` has to add
  the distro feature, exactly as `kas/bench-router.yml` already does for
  NetworkManager
- the rules directories are mode 700 owned by `polkitd`, so a recipe
  cannot simply `install -d` into them
- the default JavaScript engine is mozjs, which is SpiderMonkey

**Why that and not the alternative.** The third fact became a decision.
mozjs is tens of megabytes of rootfs and one of the longest compiles in the
whole build, to evaluate eleven lines of rule. The recipe already offers
duktape, and `kas/bench-hub.yml` selects it with the warning that comes
with it written out: duktape is not a complete modern JavaScript, and a
rule using something like `Array.includes` will fail on it. The rule here
uses an equality test and `subject.isInGroup`, which is the oldest part of
the polkit API.

The second fact produced the other decision: rather than reimplement the
directory handling, the recipe does
`require recipes-extended/polkit/polkit-group-rule.inc`, which is meta-oe's
own idiom for a recipe that ships a polkit rule. Requiring a file from
another layer works the same way this repository already requires
`core-image-minimal.bb` from poky.

---

## 10. The eight files that name each other

**What happened.** A D-Bus service is not one artefact. The interface name
appears in the daemon, the bus policy, the activation file and the unit;
the device path appears in the daemon, the udev rule and the unit; the
polkit action appears in the daemon, the action file and the rule; the
unit name appears in the activation file, the udev rule and the recipe.
Every one of those is a string typed by hand.

**What was done.** `tests/sensorhub-policy-test.sh`, 53 assertions, which
parses all eight and compares them against each other. It derives the
systemd device unit name from the device path the way systemd does, so
`BindsTo=dev-sensorhub.device` is checked against
`ExecStart=... /dev/sensorhub` rather than both being read and nodded at.

**Why that and not the alternative.** Each of these mistakes produces a
symptom a long way from its cause. A wrong name in the bus policy is a
daemon that starts and cannot own its name. A wrong unit name in the
activation file is a bus activation that times out with nothing in the
journal. A missing `TAG+="systemd"` in the udev rule is a `BindsTo` that
binds to a device unit which never exists, so unplugging does nothing and
nobody finds out until it matters.

None of that needs hardware to catch. It needs somebody to compare the
strings, and a person comparing strings is a person who will eventually
not.

The test also caught something while being written: an assertion that
searched the recipe text for the string "sensorhub" passed for the wrong
reason, because a comment several lines above mentioned `USERADD_PARAM`.
Rewritten to extract the user name from the assignment and compare it
against the one in the policy and the unit, which is the comparison that
was wanted.

---

## 11. What was run, and what was not

**What happened.** Three of the four checks for this project can run on
the laptop it was written on. One cannot.

**What was done.**

| Suite | Assertions | Ran here |
|---|---|---|
| `tests/sensorhub-proto-test.sh` | 41 | yes |
| `tests/sensorhub-policy-test.sh` | 53 | yes |
| `tests/sensorhub-cabi-test.sh` | every encoder, the CRC and the parser, over 900 randomised cases | **no: needs a C compiler** |
| `./go check`, the daemon compile | 1 | **no: needs gcc, libsystemd, libcbor** |

The two that did not run are the two that need a compiler, and this
machine has none. What was done instead:

- the Python half of the C-ABI test was extracted and byte-compiled, so it
  is at least syntactically valid
- its comparison logic was rehearsed with the reference implementation on
  both sides, which proved the plumbing: the tuple shapes, the chunked
  feeding loop and the randomised stream generator all behave, and the
  reference parser gives identical results for chunk sizes 1, 2, 3, 5, 7,
  13 and 64
- every upstream signature the daemon uses was read from the upstream
  headers, as entry 8 records

**Why that and not the alternative.** The alternative is to write it, call
it done and let CI find out. Project 1 established what that costs:
seventeen CI failures, and two days in which nobody read the results. This
is the same situation with one difference, which is that it is written
down here before the first CI run rather than after it.

The honest summary is in the project README's first section: the protocol
is proven, the daemon is reviewed and compiles nowhere yet, and no frame
has crossed a wire.

---

## 12. What is deliberately not done

- **No firmware project.** `firmware/README.md` says why at length: a
  generated CubeIDE project is thousands of lines that cannot be built,
  tested or reviewed anywhere in this repository's toolchain, and
  committing one by hand would produce a directory that looks like working
  firmware and has never been compiled. The half that is portable,
  `proto.c`, is written, frozen against golden vectors and compared
  against an independent implementation in CI.
- **No `ObjectManager`.** It is the natural next step, one object per
  sensor, and it is a stretch goal rather than part of the interface the
  criteria describe.
- **No meson build.** Two source files. A build system would be the
  largest thing in the directory, and every other bench recipe compiles in
  `do_compile`.
- **No temperature on the bus.** The daemon decodes it and drops it. The
  interface as specified carries motion only; decoding the whole map
  anyway is deliberate, because a firmware that stopped sending that key
  has changed the sample shape and that should be noticed here rather than
  by a client wondering why a later key moved.

## 13. An evidence index, and the one capture that needs no firmware

**What happened.** A review across the repository found no `docs/evidence/`
in this project, while the acceptance table names seven captures that would
go in one. The project is blocked on firmware that is deliberately not
written, so every row reads "not started" apart from the two met in CI.

**What was done.** `docs/evidence/README.md` added, one row per criterion
with the command that produces it.

Writing it surfaced something the acceptance table does not make obvious.
Six of the seven captures need a Nucleo streaming frames, and one does not:
`busctl introspect` needs only the daemon running on a real bus. That is
criterion 1, it is the cheapest row in the table, and it converts "written"
into "owns a name on a system bus", which is the claim this project cannot
currently make at all. It is noted at the foot of the index as the first
one to take.

**Why that and not the alternative.** The alternative was to wait for the
firmware and write the index alongside the first real capture. Waiting
would have kept the introspection row invisible behind six that are
genuinely blocked, which is how a cheap piece of evidence stays untaken.
