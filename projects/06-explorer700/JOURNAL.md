# Journal: Project 06

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 16 September 2026 unless noted.

---

## 1. The hardware was asked about, and the answer was a document

**What happened.** The four questions asked before writing anything were
the usual ones: is the HAT here, which Pi, is there a remote and a cable,
and how will the GPIO numbers be confirmed. Three got short answers. The
fourth got a URL: the Joy-it RB-Explorer700 manual of 16 November 2020.

**What was done.** Read it before writing a line, and it changed the
project.

The first attempt to read it failed in a way worth recording: the PDF is
image based, so text extraction returned nothing but stream objects and
font definitions and a confident report that the file contained no
schematic. It contains a complete one. The pages had to be read as images
instead, and page 3 turned out to be a per-peripheral block diagram with
the Raspberry Pi BCM number on every signal, with page 2 stating the
convention that makes it usable: "All pins listed here refer to the
GPIO/BCM pins of the Raspberry Pi."

**Why that and not the alternative.** The alternative was to build from the
specification's pin table, which is explicitly labelled as hypothesis and
which asks to be checked against exactly this document. Five of its eleven
rows do not survive the check. One of them is not survivable at all: see
entry 3.

The cost of asking was one message. The cost of not asking would have been
a display that cannot work, a joystick with three directions permuted, a
sensor at an address where nothing answers, and four floating ADC inputs
reported as measurements.

---

## 2. The question that was really a question about the CP2102

**What happened.** One of the four answers was not an answer but a
question: "does usb ttl a good alternative? whats cp2102".

**What was done.** Recorded here because the answer is a small piece of
bench knowledge that will come up again, and because it is the reason the
console step in [docs/BRINGUP.md](docs/BRINGUP.md) is step 1 rather than
an afterthought.

The CP2102 is a Silicon Labs USB-to-UART bridge chip soldered onto the HAT.
It does the same job as the Renkforce USB/TTL cable and is wired to the
same two pins. So a USB/TTL cable is not merely a good alternative, it is
the same thing in a different package, and the answer to "which" is decided
by geometry rather than by function: **the HAT covers the header**, so the
cable's clips have nowhere to go unless the HAT's own pass-through header
is used, while the CP2102 is already attached and needs one USB cable.

**Why this is an entry.** Because the useful part is not the definition. It
is that a question about a part turned out to be a question about physical
access, which is the same shape as Project 8 reasoning for two days about
which Pi a HAT was on. The manual's photographs answer it in seconds and
were already open.

---

## 3. The display cannot work the way the specification says, and no amount of care would have found that later

**What happened.** The specification puts the SSD1306 on I2C at 0x3C with
the `ssd1307fb` driver and has user space write packed 1 bit per pixel rows
to `/dev/fb1`. The manual's page 3 draws the panel with CS on GPIO8, RES on
GPIO19, D/C on GPIO16, and SCK and MOSI on the SPI pins. Chapter 16
confirms it from the other side by telling the reader to enable SPI before
running the display examples.

**What was done.** Read the driver rather than reasoning about properties.

```
drivers/video/fbdev/Kconfig:1928
config FB_SSD1307
        tristate "Solomon SSD1307 framebuffer support"
        depends on FB && I2C
```

`depends on FB && I2C`, and the driver is registered with
`module_i2c_driver`. It has no SPI probe path. **There is no device tree
property that makes an SPI panel reachable by it**, which is a different
category of wrong from a bad address.

The binding used instead is the DRM driver, `ssd130x-spi`, taking the plain
`solomon,ssd1306` compatible, with `dc-gpios` mandatory because 4-wire SPI
has no room for the control byte that carries data-versus-command on I2C.

**Why this entry matters more than the fix.** Because of what the failure
would have looked like. An I2C node at 0x3C where nothing answers produces
a device that never probes, and the first three things anybody debugs are
the address, the bus speed and the overlay syntax. The bus is the fourth
thing at best, and the driver's Kconfig line is not on the list at all.

It is also the second half of a pattern this bench keeps meeting. The same
specification paragraph asserts, correctly, that `nxp,pcf8591` binds a
driver with no of_match table because the I2C core strips the vendor prefix
from the compatible string. That is true, and it is four lines in
`drivers/of/base.c`. The two claims are written in the same confident
voice, one is exactly right and one is impossible, and nothing about the
prose separates them. Which is why [docs/bindings.md](docs/bindings.md)
cites a file and a line for every binding instead of describing it.

---

## 4. A second reading of the same page, and the joystick

**What happened.** The manual's block diagram labels the expander's pins
with net names, A to D, and then shows separately where those nets go. Read
in one pass it looks like it agrees with the specification. Read in two it
does not.

| | Specification | Manual |
|---|---|---|
| P0 | Up | **Left** (net A) |
| P1 | Down | **Up** (net B) |
| P2 | Left | **Down** (net C) |
| P3 | Right | Right (net D) |
| P4 | Press | **LED2** |
| GPIO20 | not used | **Press** |

**What was done.** Wrote the overlay to the manual, put all five keys in
one `gpio-keys-polled` node although they are on two different GPIO
controllers, and marked the whole block as the least certain thing in the
project in [docs/pin-map.md](docs/pin-map.md).

**Why that and not the alternative.** Two nodes would have been the obvious
split: four expander lines in one, the SoC pin in another. That gives one
physical joystick two event devices, and every consumer of this project,
the specification's own acceptance criterion included, would then have to
know about both. `gpio_keys_polled` polls descriptors and does not care
which chip they came from, so one node costs nothing.

**And the part that is not fixed by any of this.** The mapping is read off
a rendered page of a PDF at screen resolution. It is the best source short
of a net list and it is not a net list, and a permuted joystick works
perfectly and is wrong. `evtest` and a thumb settle it in under a minute,
which is why that is a numbered step in the bring-up document rather than
an assumption in the overlay.

---

## 5. The ADC measures nothing, and saying so was a design decision

**What happened.** The specification speculates that the PCF8591's inputs
are "tied on some board revisions to a potentiometer, a light-dependent
resistor and a thermistor". On this board all four go to a screw terminal
and a header, and nowhere else.

**What was done.** Gave `explorer-verify` a status word for it,
`unterminated`, and made the ADC row report the fact rather than the
values. It is not a failure and it is not an `ok` either.

**Why that and not printing the numbers.** Four floating CMOS inputs
produce four plausible, drifting, non-zero readings. A checker that printed
`in0_input` would be manufacturing evidence, and the output would be
indistinguishable from four working sensors. The specification's own
verification script does exactly that, and it is the one line in it that
would have shipped.

`tests/explorer-verify-test.sh` asserts both halves: that the status is
`unterminated`, and that the value 122 which the fake sysfs contains does
**not** appear anywhere in the output. The second assertion is the one that
would catch somebody helpfully adding the reading back.

---

## 6. The test found two defects in its subject on the first run, and one in itself

**What happened.** `tests/explorer-verify-test.sh` was written against a
tree of directories shaped like sysfs. Nine of its assertions failed on the
first run.

**What was done.** Three different causes, and they are worth separating.

**A redirect that swallowed every failure row.** `explorer-verify` had an
`i2c_check` helper that printed the driver name on stdout for the caller to
capture and called `chk` itself on failure. Every caller therefore wrote
`if i2c_check ... >/dev/null`, and that redirect discarded the failure rows
along with the name. A part with no driver produced **no line at all**:
the reader sees ten rows instead of eleven and has no reason to count them.
That is worse than a wrong status, and the exit code was still 1, so a test
that only checked the exit code would have called it correct. Fixed by
reporting through a variable instead of through stdout.

**A `set -e` trap in the test itself.** The helper that captured the exit
status was `cmd >/dev/null 2>&1; echo $?`, inside a function, inside a
command substitution. Under `set -e` the failing command ends the subshell
before the `echo` runs, so every "this should fail" assertion compared 1
against the empty string. It read as the program being wrong in four more
places than it was.

**A pattern that could not tell use from mention.** The companion suite,
`explorer-overlay-test.sh`, flagged three things on its first run: the
overlay's comment explaining why there is no `cs-gpios`, its comment
explaining why the buzzer is not a `pwm-beeper`, and the image recipe's
paragraph explaining why it names no `kernel-module` package. All three
were the documentation of the decision the rule exists to protect.

**Why that and not the alternative.** The use-versus-mention fix is now the
fourth, fifth and sixth of its kind in this repository, after the firewall
test on a cross-referencing comment, the image package check on
`bench-hub-image`, and the HIL server test on `install.sh`. Every time the
temptation is to widen the pattern or drop the rule, and every time the
right answer has been to name the legitimate context: here, a `code_of`
helper that strips comments, applied to the absence checks only. A rule
that gets silenced is worse than no rule, because it is still there
teaching its reader to skip a line.

**And then the checks were broken on purpose.** Eleven defects
reintroduced one at a time: a driver moved back to `=m`, the BMP280 I2C
glue deleted, the pressure sensor put back at the specification's 0x77, the
keys label changed so it no longer matched what the checker greps for, a
pin used that the pin map does not document, two joystick keys put on one
expander line, the ADC reported as `ok`, a loose 1-Wire probe counted as a
defect, an unbalanced brace, a fragment with its target removed, and an
overlay parameter pointing at a label that does not exist. All eleven
fired, and both suites were clean again afterwards.

The last three are the structural checks, and they exist because **the
overlay has never been through `dtc`**: there is none on the authoring
laptop. They are not a device tree compiler and the test says so in a
comment rather than letting a green result imply more than it proves. What
they do catch is the two things that are easy to get wrong by hand here,
an unbalanced brace and a parameter naming a label that does not exist,
and the second is worth having because `__overrides__` is the least
familiar syntax in the file.

That last paragraph is the part that makes the other ninety-six
assertions mean anything. This repository has shipped three checks that
never fired, and a rule that never fires is indistinguishable from one that
passes.

---

## 7. The radio firmware in the base image is for a chip a Pi 3B does not have

**What happened.** Noticed while writing the bring-up document, not while
testing anything. `bench-image` installs
`linux-firmware-rpidistro-bcm43455`, which is the WiFi chip in a 3B+ and a
Pi 4. A plain **Pi 3B carries a BCM43430**, and that firmware is not in the
image.

**What was done.** Nothing to the image, and a warning in
[docs/BRINGUP.md](docs/BRINGUP.md) saying to use the 3B+ if the network
matters, or to work over the CP2102 console.

**Why that and not fixing it.** It is not this project's defect and not
this project's file. `bench-image.bb` is shared by every project in the
repository, `kas/bench-rpi3.yml` changes only the machine, and Projects 6,
10 and 19 all inherit the gap. Changing a shared image recipe inside a
project commit is how a one-line fix turns into somebody else's rebuild.

**Separating what was seen from what was worked out**, because this bench
has been caught not doing that.

This entry originally said that the 3B carrying a different radio was
"recalled, not verified against a board". Half of that has since been
checked and the entry is corrected here rather than edited silently.

**Verified.** `meta-raspberrypi`'s `linux-firmware-rpidistro_git.bb` on
scarthgap defines seven packages, among them `${PN}-bcm43430` and
`${PN}-bcm43455`, and their `FILES` are disjoint: the first claims
`firmware/brcm/brcmfmac43430*`, the second does not. So the two chips need
different packages and the image names only one of them. That is a fact
about the recipe and it is now read rather than remembered.

**Still not verified.** Which chip the Pi 3 in this drawer actually has.
The board number is printed on it and `dmesg | grep brcmfmac` says it in
one line, and neither has been looked at. If it is a 3B+, the warning in
the bring-up document costs a sentence and nothing else.

The distinction is worth keeping visible: reading a recipe is cheap and
was done; reading a board needs the board.

---

## 8. What is still open

Nothing has been on hardware, and no build has been run.

The symbols in `explorer.cfg` are checked against the Linux 6.6 source and
not against a `.config`, which is a different question with a different
tool. From `references/traps.md`: `./go ksym` reads the unpacked kernel's
own Kconfig and needs `kernel_configme` rather than `unpack`, and
`./go kconfig` compares against the `.config` a build actually produced.
Both are minutes and both are still to be run.

The four things most likely to be wrong when the HAT is first powered, in
the order they would show up:

1. **The pressure sensor's identity.** The manual says BMP280 twice and
   BMP180 once. `i2cdetect` settles the address and the driver settles the
   part, because a chip id mismatch names the id it read.
2. **The joystick's direction mapping.** Read off a rendered page.
   `evtest` and a thumb.
3. **Whether the 1-Wire header has a pull-up fitted.** Not documented
   anywhere. `w1_master_slave_count` of 0 with a probe plugged in is the
   symptom.
4. **The buzzer's polarity.** Assumed active high because a buzzer behind a
   transistor usually sounds when the base is driven, and the manual draws
   the net without a polarity. `beeper_active=0` flips it with no rebuild.

Each of those is a parameter or a one-line change, which was the point of
making the pin numbers parameters in the first place: every one of them
came from a manual rather than from a net list, so a wrong guess should
cost a `config.txt` edit and not a build.
