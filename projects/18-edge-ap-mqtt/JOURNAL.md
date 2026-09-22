# Journal: Project 18

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

This file was started at the first command of the session rather than at
the first milestone, and appended as each command returned.

All entries are Monday 21 September 2026 unless noted.

---

## 1. The specification was already written, by a sibling project

**What happened.** The root README gives one line: "Edge Wi-Fi access point
with MQTT over TLS and a private PKI", Raspberry Pi 3, and the themes
`hostapd, dnsmasq, Mosquitto, X.509`. That is a title, not a
specification, so the first move was to look for anything in the repository
that says what this project is actually for.

Two places do, and neither was written by this project.

`projects/17-ble-gateway/README.md:133`, describing its own broker:

```
  "Project 18 replaces that broker with one that has TLS and a private CA.
   This one listens on localhost and is a test fixture rather than a
   product decision."
```

`projects/20-optee-keystore/docs/BRINGUP.md:184`, describing its verifier:

```
  "and publishes with a `mac` field; `benchkey-verify --mqtt` subscribes
   and"
```

**What was done.** Both were taken as the specification, in preference to
any idea of what an access point ought to be. Project 18's broker is not a
greenfield broker: it is the replacement for a named test fixture, and it
already has two clients in this repository that were written before it.

**Why that and not the alternative.** Starting from a generic notion of
"hostapd plus Mosquitto" would have produced a broker on localhost with a
self-signed certificate, which is what Project 17 already has and
explicitly calls a fixture rather than a product decision. The work only
means anything if it replaces that, which fixes three things the title does
not mention: the broker has to listen off-host, it has to be reachable by
clients that are not on the board, and those clients have to be able to
verify it, which is what makes the private CA load-bearing rather than
decorative.

This is the repository's self-containment rule doing real work. Nothing
outside the tree had to be consulted to find out what the project is.

---

## 2. The parts were checked before the design, and the inventory was wrong

**What happened.** Project 16's first journal entry records the habit this
repository learned the hard way: three projects were specified around
hardware that is not on the bench, and each was found out after its design
was written. So the inventory was checked first.

Project 18 needs a board, at least one wireless station to associate with
the access point, and something to publish MQTT. The bench has a Raspberry
Pi 3, and it has two wireless microcontrollers, an SBC-NodeMCU-ESP32 and a
Joy-it SBC-ESP8266-PROG, either of which is a station and an MQTT
publisher. So this project, like 16 and unlike 10 and 17, starts with its
hardware present.

**What was found on the way, which was not expected.** The bench inventory
this work keeps does not list a USB wireless adapter. Project 15's README
says one is on the bench and working, at
`projects/15-lte-router/README.md:269`:

```
  "The primary is now a USB wireless adapter on wan0 at metric 100,
   standing in for the cable."
```

and its image recipe installs `kernel-module-rtl8xxxu` with
`linux-firmware-rtl8192eu`, matched by a udev rule on USB id `2357:0109`.
A project at "Built and running on the board" with "both uplink radios up"
is strong evidence the part exists.

**What was done.** The adapter is treated as present, and this entry marks
that as **inferred from Project 15's records rather than seen**. Nothing in
the design depends on it yet; if it turns out to be wrong, the cost is one
paragraph about the uplink and not a recipe.

**Why that matters enough to write down.** The rule this repository keeps
relearning is to say which half of a statement was observed and which was
worked out, in the same sentence rather than in a later correction. The
inventory is the authority on parts and it is silent here, so the claim is
labelled rather than promoted.

---

## 3. One radio, and no cable: how the board is reached at all

**What happened.** The Raspberry Pi 3 has one wireless radio. An access
point on `wlan0` means that radio cannot also be a station on somebody
else's network, and the bench README records at line 274 that this bench
has no Ethernet cable, "not because it is better".

So the ordinary way of reaching a board being developed, ssh over the
bench wireless network, is exactly the thing this project takes away.

**What was done.** Written down as a design constraint before any recipe,
rather than discovered on a board that has stopped answering. The full
treatment is in `docs/DESIGN.md`; the short version is that the access
point becomes the access path. A laptop associates to the board's own
network and reaches it at the address the board hands out.

**Why that and not the alternative.** The alternative, adding the USB
wireless adapter as a station so the board stays on the bench network while
serving its own, is the arrangement Project 15 uses and it is a good one.
It is not the arrangement for this project, because a second radio makes
the interesting failure impossible: if `hostapd` never starts, a board with
a working station interface is still reachable and nobody finds out. The
recovery path has to be designed rather than borrowed, which is the rule
this repository wrote after a first-boot script under `set -e` died before
writing the access point and left a board reachable only from the console.

**The recovery path, therefore, is the console**, over the Renkforce
USB/TTL cable that the inventory does confirm. It gets written into the
bring-up before the optional features, not after.

---

**Entries from here on are Tuesday 22 September 2026.**

---

## 4. The certificate authority was built first, because it is the only part that needs nothing

**What happened.** With the design written, the obvious next step by the
repository's own order is the recipes. It was not taken. Four things block
this project and three of them need a board or the WSL laptop: the radio
firmware, the access point capability, and whether `ssl` is even compiled
into mosquitto. Writing recipes against three unknowns produces work that
cannot be checked.

The private CA has none of those dependencies. `openssl version` on the
authoring laptop answers `OpenSSL 3.5.5 27 Jan 2026`, and a certificate
authority is openssl and a directory.

**What was done.** `projects/18-edge-ap-mqtt/pki/bench-pki.sh`, with
`init`, `server`, `client`, `revoke`, `verify`, `list` and `clock-rule`,
and `tests/pki-test.sh` beside it. Fifty-one assertions, all passing, on a
laptop with no board, no network and no broker.

**Why that and not the alternative.** The alternative is writing the
recipes now and finding out later. This project's whole argument is the
PKI: the access point is a configuration file and the broker is another
one, and what makes the work interesting is whether a client can tell the
real broker from anything else. Finishing that part first means the
interesting half is provably correct before the board is touched, and the
board work becomes a question about hostapd rather than about everything at
once.

**Elliptic curve, P-256, not RSA.** The clients include an ESP8266, where
an RSA-2048 handshake is seconds of a processor that has other work. The
broker and the laptop do not care. The constrained client decides.

---

## 5. Three path traps in one script, all of them Windows, all found by running it

**What happened.** The first run failed immediately:

```
req: subject name is expected to be in the format /type0=value0/...
This name is not in that format: 'C:/Program Files/Git/CN=bench-ca'
```

Every openssl subject starts with a slash and Git Bash rewrites arguments
that look like paths. The message names the right symptom and the wrong
cause, and sends the reader to inspect a subject string that is correct.

**What was tried, in order.**

| Attempt | Result |
|---|---|
| `MSYS_NO_PATHCONV=1`, which switches translation off entirely | Worse. `ecparam: Can't open "/tmp/pki-try/private/ca.key" for writing`. Every other argument here is a path and does need translating |
| `MSYS2_ARG_CONV_EXCL='/CN='`, excluding only the subject | The subject survives, the file paths still translate. Correct |
| Running it again | `bench-pki: could not generate the CRL` |

The third was the interesting one, and it took a fourth step to see,
because the script had thrown openssl's message away. Running the command
by hand:

```
Using configuration from C:\Users\AQUAMA~1\AppData\Local\Temp/pki-try/openssl.cnf
Could not open file or uri for loading CA private key from
  /tmp/pki-try/private/ca.key: No such file or directory
```

The configuration file was found, because that was an argument. What is
written inside it was not, because that was not. **The shell translates
arguments and never the contents of a file a program opens itself**, and
the generated `openssl.cnf` had `dir = /tmp/pki-try` in it.

**What was done.** A `native_path` helper using `cygpath -m` where it
exists and the path unchanged where it does not, applied to the `dir` line
only. A no-op on Linux and in CI.

**And the script now prints openssl's message.** Three of the failure paths
were `>/dev/null 2>&1 || die "could not do the thing"`, which is a refusal
that names nothing. The cause of the CRL failure was a path inside a
configuration file and the message mentioned neither paths nor
configuration. This bench already has a rule about guards that cannot be
argued with, and this was one.

---

## 6. Two bugs found by using the tool, not by testing it

**What happened.** Both appeared in ordinary use before any assertion
existed for either.

**The guard created the thing it exists to prevent.** Pointed at a
directory inside the checkout, `bench-pki.sh init` printed a correct
refusal, named both paths it compared, exited 2, and left
`projects/18-edge-ap-mqtt/pki/ca/` behind. The cause was ordering: the path
was resolved with `cd`, which needs the directory to exist, so `mkdir -p`
ran before the check. A guard with a side effect is not a guard, and this
one's side effect was a directory for a CA private key inside a repository
that gets pushed.

Fixed by checking twice: once on the path as written before anything is
created, and again after resolution, because the first reads the path
literally and a symlink outside the tree can point into it.

**`list` printed every valid certificate with no name.**

```
state  expires        common name
valid   281225051030Z
REVOKED 281225051030Z  ble-gateway
```

The CA database is tab separated and leaves the revocation date empty for a
row that is still valid, so a valid row has two tabs together. A tab is an
IFS whitespace character, and IFS treats a run of whitespace as one
delimiter, so the empty field vanished and every column after it shifted
left by one. The row still had a state and a date and looked like a row.

Rewritten with `awk -F'\t'`, which does not collapse empty fields, and the
expiry is now printed as a date rather than as raw ASN.1 UTCTime.

**Why this is in the journal.** Neither was a hard bug and both were found
in the first minute of running the thing. That is the argument for using a
tool before writing its test: the test was going to assert what the tool
did, and what the tool did was wrong in two places.

---

## 7. The adversarial test credited the wrong mechanism, and breaking it twice found the right one

**What happened.** The suite has a deliberately hostile case: a certificate
request that asks to be a certificate authority. The comment beside it
said this is what `copy_extensions = none` prevents.

Following this bench's rule that a check which has never failed is
indistinguishable from one that passes, the setting was changed to `copy`
to watch the assertion fire.

**It did not fire. 48 passed, 0 failed.**

**What was done.** The hypothesis was wrong, so it was replaced with a
testable one: perhaps the extension sections, which name
`basicConstraints` explicitly, override anything copied from the request.
Setting `copy_extensions = copy` **and** deleting the `basicConstraints`
line from `client_ext` produced the failure:

```
FAIL: but the certificate issued is not a CA
```

So the real mechanism is the named extension, and a named extension beats a
copied one.

**Why that matters rather than being a curiosity.** `copy_extensions = none`
is still load bearing, but for something else entirely, and the first
version of the test did not cover it at all. The sections name
`basicConstraints` and `extendedKeyUsage` and say nothing about
`subjectAltName`. With copying on, a device could put **the broker's own
address** into its own client certificate, and anything matching on a SAN
would believe it.

So the hostile request now also asks for `IP:10.18.0.1, DNS:bench-ap`, and
two assertions check it does not get them. Breaking `copy_extensions`
alone now fires exactly those two and nothing else, which means the two
defences are covered independently:

| Defence | Covers | Proven by |
|---|---|---|
| `basicConstraints` named in the section | CA:TRUE and the key usages | removing that line |
| `copy_extensions = none` | everything the section does not name, subjectAltName above all | setting it to `copy` |

**The general shape, which this repository has met before.** An
explanation written in the same confident voice as an observation, and
wrong. The observation was that the hostile request failed. The mechanism
was invented to explain it. One experiment separated them, and the
experiment only happened because the rule here is to break a check rather
than trust it.

---

## 8. Two recipes, and they package their units in opposite ways on purpose

**What happened.** The access point and the broker both need systemd units
that differ from what their upstream recipes ship, and the obvious move is
to treat them the same way. They are treated differently, and the reason is
worth stating because it is the kind of thing that gets "tidied" later.

**What was done.**

| | Approach | Why |
|---|---|---|
| `hostapd`, `dnsmasq` | replacement units, `bench-hostapd.service` and `bench-dnsmasq.service` | The configuration is generated into `/run` at every boot because it carries a passphrase. That is a different shape from what the `hostapd` recipe assumes, which is a file in `/etc`, so almost nothing of its unit survives |
| `mosquitto` | a drop-in, `mosquitto.service.d/bench.conf` | The only change is which configuration file to read. A replacement unit would go on using an `ExecStart` upstream had moved past, and nobody would find out until a version bump |

**The trap inside the drop-in, which is why it has a test.** A drop-in
appends to a list, and `mosquitto.service` already has an `ExecStart`.
Without an empty `ExecStart=` first, the unit carries two of them and
starts a second broker that cannot bind the port the first one took. The
line looks redundant and is load-bearing, so `broker-config-test.sh`
asserts it.

**Why the passphrase goes to `/run` and not `/etc`.** `/run` is a tmpfs.
A passphrase written into `/etc` sits in the rootfs, survives reboots, and
ends up in any image anybody copies off the card afterwards. The generated
file lives for one boot and is rebuilt on the next, and it is mode 0600.

---

## 9. The backslash hazard, twice in one command, caught by the linter

**What happened.** The broker recipe was edited with a Python script in a
shell heredoc, adding one line to `SRC_URI` and one `install` line. Both
edits contained a backslash continuation. Neither arrived.

The `install` line came out as one long line with the backslash gone and
the newline turned into spaces, which is still valid shell and merely
breaks the 88-column rule. The `SRC_URI` edit did nothing at all: the
anchor string contained a backslash, so it never matched, and
`str.replace` returned the text unchanged without complaining.

**What caught it.** `scripts/lint.py`:

```
meta-bench/recipes-bench/bench-broker/bench-broker_0.1.bb:
  files/mosquitto-bench.conf is not in SRC_URI
```

**What was done.** Both fixed with the editing tool rather than through a
heredoc, which is what this bench's own method says to do for anything
containing a backslash continuation, and which was not done here.

**Why it is in the journal rather than quietly fixed.** This is the
failure that has cost this bench the most: four silent drops in one
session, three caught by a linter and the fourth by hardware, twice, at
forty-five minutes and a reflash each time. It happened again today, in the
same shape, in a session where the rule had already been read. The rule is
not "be careful with backslashes", it is "do not put them through a
heredoc", and the linter is the only reason this one cost a minute.

---

## 10. The configuration tests, and the assertion that read its own comment

**What happened.** `tests/ap-config-test.sh` asserts the shipped hostapd
template has no TKIP, because TKIP in the pairwise list is how a network
that looks like WPA2 negotiates something weaker with an old client. It
failed on the first run.

It was right to fail. The word is in the template, in the comment
explaining that TKIP is deliberately absent.

**What was done.** Comment and blank lines are stripped before anything is
asserted absent, by an `active()` helper used for both configuration files.
Presence checks are anchored with `^` and were never affected.

**Why that matters beyond one word.** It is the mirror of a failure this
repository has already shipped, where a regex matched its own file's
comments and silenced itself. Same cause, opposite direction: a check that
cannot tell prose from configuration is wrong either way, and the more
carefully a configuration file is commented the more likely it becomes.

**The assertions worth having are the ones no single file could make.**
Three of them are cross-file, and each covers a pair that is individually
valid and wrong together, with nothing on the board reporting it:

- the DHCP range must be inside the subnet of the static address, and must
  not include the access point's own address. Otherwise clients get
  addresses and simply cannot reach the broker
- the broker's listener address must be the address the interface is
  given. Otherwise mosquitto starts, fails to bind, and restarts until
  systemd gives up, and the log reads as a broker problem
- the file `acl_file` names must be a file the recipe installs. A
  configuration file naming an artefact is a claim about it, and here the
  cost of the claim being wrong is a broker that will not start on a board
  with no other way in

**And one that is about the repository rather than the board.** A search
for `*.key`, `*.crt` and `*.pem` under the layer and the project, asserting
there are none. The image carries capability and the card carries
identity, and a private key committed once has to be replaced rather than
removed.

**Proven by breaking, all of them.** `require_certificate false` fires one
assertion; adding a 1883 listener fires two; moving the listener to another
address fires two and prints both files and both addresses; giving a
publisher `readwrite` fires one and prints the rule it found. Restored from
checksummed copies afterwards.

---

## 11. The certificates cannot go where the passphrase goes, and that decided the bring-up

**What happened.** Writing the bring-up order made a constraint visible
that the design had not noticed. The wireless passphrase goes to
`/boot/ap.conf`, which is FAT and therefore writable from the Windows
authoring laptop. The broker's certificates go to `/etc/bench/pki`, which
is on the **ext4** root filesystem, and Windows cannot mount ext4.

So the two pieces of identity this board needs cannot be delivered the same
way, even though the design treats them as the same kind of thing.

**What was tried, in order.**

| Option | Verdict |
|---|---|
| Put the certificates in `/etc/bench/pki` before flashing | Impossible on this laptop. Needs the WSL laptop for a step that otherwise does not need it |
| Copy them over the network after first boot | Works, and the network exists by then because the access point does not need certificates. But it makes the first boot a half-provisioned state that has to be reasoned about, and it cannot be done from a machine that has not yet joined the network |
| Stage them on `/boot/pki` and install at first boot | **Taken.** One partition, one tool, writable everywhere, and the install step becomes a place to put checks |

**What was done.** `bench-pki.sh deploy` on the laptop side and
`bench-broker-setup` on the board side, with a unit ordered before
`mosquitto.service`.

**Why the third option is better than merely possible.** Having an install
step at all is what makes the checks possible, and the checks turn out to
matter more than the copying:

- the certificate and the key must be a **pair**. Copying one from one
  issue and the other from another is easy, the filenames are identical and
  the contents opaque, and mosquitto's own complaint names neither file on
  a board whose only other way in is a serial cable
- the certificate must be signed by the `ca.crt` next to it. Every client
  checks exactly that, so otherwise the broker presents a chain nothing on
  the bench can verify
- a board provisioned on a previous boot must not refuse to start because
  the card has since been cleaned, which it should be

None of those is possible if the files simply appear in `/etc` at flash
time.

---

## 12. Two guards on the one mistake that cannot be undone

**What happened.** The certificate directory holds four files that must
travel to the card and one that must never leave the laptop, and they look
alike. A glob, or a tired hand at the end of a session, puts
`private/ca.key` on a FAT partition that anybody who picks up the card can
read. Deleting it afterwards fixes nothing: every certificate that key ever
signed has to be reissued.

**What was done.** A guard at each end, because they fail differently.

`bench-pki.sh deploy` names its four files one at a time rather than
globbing, and checks the destination afterwards for a CA key or a
`private/` directory. It also refuses to carry another device's
certificate, because a loop over `issued/*` would put every client key on
the broker, and a client key on two machines is an identity two machines
can present.

`bench-broker-setup` refuses **before it copies anything** if it finds
`ca.key`, `private`, `index.txt`, `serial` or `openssl.cnf` on the card.
The ordering is the point: a run that installed the good files first would
leave a board that works and a problem nobody looks for again.

**Why both, when either would do.** They cover different people. The deploy
guard helps whoever used the tool; the board guard helps when the files
arrived some other way, which on a bench with two laptops and a card reader
is most of the time.

**Proven by breaking, both.** Removing `ca.key` from the board side's
danger list fires four assertions, and the fourth is the one that matters:
`nothing was installed` fails too, which is the test confirming that
without the guard the files really had been copied before anything
complained. Removing the certificate and key comparison fires three.

---

## 13. A guard that refused a directory it should have accepted

**What happened.** Running `deploy` for the first time, with
`BENCH_PKI_DIR` pointing at a Windows temporary directory:

```
bench-pki: refusing to put a certificate authority inside the repository.
  BENCH_PKI_DIR /c/Users/.../embedded-linux-bench/C:\Users\AQUAMA~1\...\Temp/pki-dep
  repository    /c/Users/.../embedded-linux-bench
```

The path in the message is nonsense, and it says exactly what happened. The
guard classifies a path as absolute by testing for a leading slash, and a
Windows absolute path starts with a drive letter, so `C:\Users\...` was
treated as relative and had the working directory prefixed to it. The
result was inside the checkout, so the guard refused.

**Why it had not been caught.** The test suite uses `mktemp -d`, which
gives a POSIX path, so the Windows form was never exercised. The check
itself was only added a few hours earlier, when the guard was found to be
creating the directory it then complained about.

**What was done.** The case now accepts a drive-letter prefix as absolute
as well as a leading slash.

**What made it a two second diagnosis instead of an argument.** The guard
printed both paths it compared. This bench's own rule says a refusal that
cannot be argued with is one people learn to switch off, and here the same
property that makes a correct refusal useful made an incorrect one
obvious. A guard that had simply said "refusing: bad path" would have been
indistinguishable from the guard working.

---

## 14. The backslash hazard, a third time in one session

**What happened.** Wiring `bench-broker-setup` into its recipe, through a
Python script in a shell heredoc again. The anchor contained a backslash
continuation, the heredoc consumed it, and the replace found nothing.

This time it failed loudly:

```
AssertionError: '    file://mosquitto-bench.conf \\n'
```

**Why that is the difference between this and the last two.** The same
mistake earlier today edited nothing and said nothing, and the linter
caught it a step later. The only thing that changed is that this script
asserted its anchor before replacing, which is what this bench's method has
said to do all along:

> Never call `.replace()` on recipe text without asserting the anchor was
> found.

Three occurrences in one session, in a session where the rule had been read
at the start. The rule is not "be careful": it is "use the editing tool for
anything with a backslash", and the assert is the cheap second line of
defence for when that is forgotten anyway.

---

## 15. The clock problem had a second half, and the design had only written the first

**What happened.** The design's clock section, and decision 111, both
reason carefully about the board: no real-time clock, no uplink, so systemd
brings the clock up at about the image build date, so the certificate
authority must be older than the image. All correct, and all about one
machine out of four.

Writing the client half of the bring-up made the gap obvious. **An ESP32
and an ESP8266 have no clock at all and power up in 1970.** Each one then
checks the broker's certificate, finds a `notBefore` in 2026, and refuses
to connect. The error says the certificate is not yet valid and mentions no
clock anywhere.

Both of this project's station clients are in that position. So, less
severely, is any Linux client whose own image predates this bench's
certificate authority, which includes Project 17's gateway if it is not
rebuilt.

**Where it would have been found.** On the board, at criterion 6, with
three plausible suspects: the subjectAltName, the chain, and the CA. The
actual cause is in none of them and the error points at all three.

**What was done.** The island serves the one thing it knows.

- `chronyd` with `local stratum 10 orphan`, which means "serve my own clock
  even though it is synchronised to nothing". Without that line chronyd
  refuses to answer at all, which is correct on the internet and leaves
  every client here in 1970
- `dhcp-option=42,10.18.0.1` so clients are told where to find it
- both asserted, including a cross-file check that the NTP address handed
  out is the address the interface actually has

Decision 111 already guarantees the board's clock is no earlier than the
CA, so a client that syncs to it lands in a time where every certificate on
the island is valid. The two decisions compose, which is the nice part:
the second is only sound because the first holds.

**What it is not, said in the configuration file as well as here.** It is
not accurate time. It is the image build date plus uptime, wrong by days or
weeks, and monotonic. That is exactly what certificate validity needs and
it is not enough for anything else, so nothing on this island should
timestamp a measurement from it. Projects 3 and 8 both take their timing
from the board's own monotonic clock, for this reason.

**The alternatives, and why each was rejected.**

| Rejected | Why |
|---|---|
| Hardcode a build timestamp into each client firmware | Works, and has to be redone per client and per build. The failure when it is forgotten is the one above, discovered on a board |
| Turn off certificate time validation on the clients | Removes the check that makes an expired or not-yet-valid certificate fail, which is most of what a validity period is for |
| An upstream NTP server | There is no uplink, by design, because a second interface would make the interesting failure impossible |

**One thing not confirmed, and labelled rather than assumed.** Which layer
provides `chrony` on the pinned revision. It is expected to be
meta-networking, which `kas/bench-ap.yml` already pins for hostapd and
mosquitto, but the layers live on the WSL laptop and this was written on
the other one. The recipe carries the one command that settles it. This is
the same class of unknown as mosquitto's `ssl` PACKAGECONFIG and it is
handled the same way: name it, give the command, and do not pretend.

---

## 16. bench-pki.sh was an entry point that did not go through ./go

**What happened.** The repository's conventions say plainly that every
entry point goes through `./go`, and that adding one means a line in the
help block and a case. `bench-pki.sh` had been written, tested, referenced
three times in the bring-up and twice in the design, and invoked by path
every time.

**What was done.** `./go pki`, forwarding its arguments, with the
subcommands listed in the help block.

**Why it is worth a journal entry rather than a silent fix.** The
convention exists because the first thing a reader sees is `./go` with no
arguments, and a tool that is not in that list is a tool nobody finds. This
one is also the tool that has to be run **before the image is built**, by
decision 111, which makes it the worst possible one to leave undiscoverable.

---

## 17. The access list named topics that no project publishes to

**What happened.** Writing the client contract meant writing down what each
identity may publish, which meant looking at what the two existing clients
actually publish. They do not publish to the topics the access list grants.

Project 17's gateway publishes to `bench/stwin`:

```
meta-bench/recipes-bench/bench-stwin/files/stwin.conf:22
  STWIN_TOPIC=bench/stwin
```

The access list, written a few hours earlier, granted `ble-gateway` write
on `bench/17/#`. Every publish that project makes would have been silently
dropped, which is MQTT's behaviour for an ACL refusal: the connection stays
up, the publish disappears, and nothing tells the publisher.

`bench/17/#`, `bench/20/#` and `bench/18/esp32-01/#` were all invented. The
only MQTT topic in the tree is `bench/stwin`, and the only other
project-numbered path is `bench/16/position`, which is a CoAP resource and
not a topic at all.

**What was done.** The prefixes are not a list any more. The rule is that a
device writes under its own common name:

```
  bench/<common name>/...
```

so `ble-gateway` writes under `bench/ble-gateway/`, and the test asserts
that property for every identity the file contains rather than checking
four hardcoded strings.

**Why a rule rather than corrected strings.** The old test was a second
copy of the access list and agreed with it by construction, so it could
never have caught this. The new one caught two invented cases the moment it
was written, and it catches devices it has never seen: adding
`user sneaky-01` with `topic write bench/esp32-01/#` fails, and so does any
publisher given `readwrite`. Both were tried.

The rule also removes a class of mistake rather than one instance of it.
Two devices cannot be given overlapping subtrees by accident, because the
prefix is derived from an identity that is already unique.

**What was deliberately not done.** Project 17's file was not edited. That
project is at "Software complete" and its topic is already configurable,
which is the part worth noticing: making `STWIN_TOPIC` a setting was
somebody's good judgement and it means this costs one line rather than a
patch. The requirement is recorded in `docs/PROTOCOL.md` and in the access
list, and the change belongs to whoever points the two at each other.

**And a check that the documents agree.** The protocol document and the
access list are now checked against each other: every identity the list
grants has to appear in the document, and the document has to state the
naming rule and the Project 17 requirement. Adding a user to the list alone
fails. That is the one class of error the linter structurally cannot see,
because it checks links and not claims, and this project had already made
it once.

---

## 18. Two limits the broker did not have

**What happened.** Writing the envelope rules for the contract made an
absence visible. Mosquitto's default maximum message is 256 MB and there
was no `max_connections` at all.

**Why that matters here specifically.** Every client on this network holds
a certificate this bench issued, and it is tempting to read that as trust.
It is not: it says a device is who it claims to be, not that its firmware
has no loop in it. The broker shares a gigabyte with everything else on a
Pi 3, and one publish can reach that default.

**What was done.** `message_size_limit 65536` and `max_connections 20`,
both far above anything this bench sends, which is the point: they are
bounds on damage rather than sizing estimates, so they are round and
generous. Project 17's records are tens of bytes.

The test asserts both exist and that the limit is actually a bound rather
than a formality, by checking it is under a megabyte. A limit set to the
default and written down is worse than none, because it reads as a
decision.

---

## 19. The first push went red, on the one check this laptop cannot run

**What happened.** `1d189ce` pushed, and the `lint` job failed at the
`Shell scripts` step. Fifteen shellcheck findings across five of the six
new shell files, in two codes.

This is the expected shape rather than a surprise. The authoring laptop
has no shellcheck, by design, and `scripts/lint.py` says so in its own
output: "no shellcheck on this host, so of its findings only SC2086,
SC2120, SC1072/SC1073, SC2010, SC2012, SC2015, SC1087 and SC1010 are
checked here. CI runs the real thing." Neither of the two codes below is
in that list.

**SC1007, six times.** `CDPATH= cd -- "$dir"` reads as an assignment with
a space after the equals sign. The idiom is correct and deliberate, and
shellcheck wants the empty value written out.

The uncomfortable part is that **this repository had already converged on
the answer**. `tests/tracker-at-test.sh` and `tests/tracker-budget-test.sh`
carry `CDPATH='' cd`, because a previous CI run made somebody change them.
The convention existed, in files I had read, and six new files were
written against the older spelling anyway.

**SC2115, nine times, and this one is not style.**

```
  rm -rf "$work/etc"
      ^---------^ SC2115: Use "${var:?}" to ensure this never expands to /etc
```

If `$work` were ever empty, that line is `rm -rf /etc`. It cannot be empty
today: it comes from `mktemp -d` under `set -eu`. But the cost of the
guard is four characters and the cost of being wrong about "cannot" is the
machine. All nine are now `"${work:?}/etc"`, which makes the shell abort
rather than delete.

**What this says about the division of labour, which is worth keeping.**
The linter on this laptop is a partial shellcheck plus the checks
shellcheck cannot make, and it passed. CI is the real gate and it caught
fifteen things in eight seconds. That is the arrangement working rather
than failing: the alternative is not "no findings", it is finding them on
a board.

**What would have caught SC1007 earlier and for free.** Reading the two
sibling test files for their idiom rather than only for their structure.
Both were open on this screen the day before.
