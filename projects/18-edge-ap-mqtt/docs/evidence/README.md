# Evidence, Project 18

**No longer empty, as of Monday 9 November 2026.** One file:
[build-2026-11-09.txt](build-2026-11-09.txt), the first build of
`bench-ap-image`.

It was empty on purpose from Monday 21 September 2026 until then, and the
paragraph that said so is kept here because the reasoning still holds for
everything else: **nothing has been powered.** No access point has carried
a station, no certificate has been presented to anything, and no client has
connected. Eleven of the thirteen criteria still read "Not started" and the
build changed none of them, because none of them is "the image builds".

A directory with a file explaining why it is empty is more honest than an
absent directory, which reads as an oversight.

## The questions that block work, in the order they can be answered

The first three need no board. The last two need one boot each.

**1. Is `ssl` in mosquitto's PACKAGECONFIG, and what does hostapd's say.**
**Half answered on Monday 9 November 2026.** mosquitto: yes, and
[mosquitto-packageconfig-2026-11-09.txt](mosquitto-packageconfig-2026-11-09.txt)
carries the value, the layer revision it belongs to, and the cmake flags
that are the stronger evidence, `WITH_TLS=ON` among them.

**hostapd was read the same day and the question was wrong for it.**
[hostapd-and-chrony-2026-11-09.txt](hostapd-and-chrony-2026-11-09.txt)
has it: eighteen matching lines and not one a `PACKAGECONFIG=`
assignment, with `PACKAGECONFIG_CONFARGS=""` empty. No feature in that
recipe reaches the build through a configure argument. `SRC_URI` fetches
`file://defconfig`, so hostapd is configured by symbols in a file the way
a kernel is.

That is not a defect in the question. Both halves were written before
either could be read, and the analogy with mosquitto was reasonable until
the first reading broke it. **The restated question is below as 1c.**

The same reading recorded what the pinned revision carries, because this
project is a security boundary: hostapd 2.10 plus 17 patches covering four
distinct CVEs, so the version number alone would mislead a reader about
its age.

Two things came with the answer. This project's own
`PACKAGECONFIG:append:pn-mosquitto = " ssl"` in `kas/bench-ap.yml` is
redundant at this layer revision, and worth keeping as insurance rather
than deleting. And `websockets` is on from the layer default while the
broker configuration declares one listener, 8883, so the binary carries a
feature nothing here uses.

The reasoning that made this question first still stands for hostapd: a
configuration file proves nothing about whether a feature is in the
binary, and Project 15 lost a build to exactly that. `poky` and
`meta-openembedded` live in `~/bench` on the WSL laptop and not on the
authoring laptop. On the WSL laptop, `./go shell bench-ap`, which is this
project's configuration and not `bench-ble` as this paragraph said until
Monday 9 November 2026, then:

```sh
bitbake -e mosquitto | grep '^PACKAGECONFIG='
```

and the same for `hostapd`. Paste both lines here with the layer revision
they came from, because a `PACKAGECONFIG` is a property of a pinned layer
rather than of a package name.

**1b. Which layer provides chrony. ANSWERED Monday 9 November 2026:
meta-networking 4.5**, which `kas/bench-ap.yml` already pins, so the
expectation held and no kas change was needed. It was the same class of
unknown as the one above and the same shell answered it. The access point serves time to its
clients, because a station with no clock powers up in 1970 and refuses the
broker's certificate as not yet valid; see decision 113. `chrony` is
expected to be in meta-networking, which `kas/bench-ap.yml` already pins,
but that has not been read. On the WSL laptop:

```sh
bitbake-layers show-recipes chrony
```

If it is elsewhere, the fix is a layer line in the kas file and nothing
else.

**1c. Which symbols are in hostapd's defconfig. ANSWERED Monday
9 November 2026**, in
[hostapd-defconfig-2026-11-09.txt](hostapd-defconfig-2026-11-09.txt).
`CONFIG_DRIVER_NL80211=y` and `CONFIG_LIBNL32=y` are present, so hostapd
can reach the radio, and WPA2 needs no symbol. A suspected defect was
cleared rather than confirmed: the defconfig comments out
`CONFIG_IEEE80211W` while `hostapd.conf.in` sets `ieee80211w=1`, which
would stop hostapd starting if the symbol still gated anything. It does
not. meta-oe ships a defconfig whose own comment calls 802.11w an
unfinalised draft, and that standard was finalised in 2009; upstream
2.10 has no such option in 412 lines, so protected management frames are
unconditional. Nothing was changed.

It replaced the
hostapd half of question 1, which asked about a mechanism that recipe does
not use. The two that matter here are the **nl80211 driver**, which is how
hostapd reaches a Linux radio at all, and the **WPA2 path** the access point
is configured for. A configuration file in this repository cannot answer
it, which was the whole reason question 1 existed. Unread as of Monday
9 November 2026.

**2. The CA's notBefore against the image build timestamp.** Not a
measurement, a rule, and the reason is in `docs/DESIGN.md` under the clock.
This board has no real-time clock and no uplink, so at boot the clock is
moved forward to roughly the image build time and no further. A CA created
after the image was built produces certificates that are not yet valid on
every client, and the error points at the certificate rather than at the
clock. Record both timestamps here the first time an image is built.

**3. Which board, and therefore which radio firmware.** A Raspberry Pi 3
carries a BCM43438 and wants `brcmfmac43430-sdio.bin`; a Pi 3B+ carries a
BCM43455. This repository installs only the 43455 package, in
`meta-bench/recipes-core/images/bench-image.bb`. One line of the first boot
settles it:

```sh
dmesg | grep -i brcmfmac
```

Paste the whole block, including the firmware filename it asked for and the
chip id it reported. Project 1 lost two rounds to a radio whose firmware
and vendor module were assumed rather than read.

**4. Whether this radio will run an access point at all, and on what.**
`brcmfmac` is a FullMAC driver, so access point support is a property of
the chip's firmware rather than of `hostapd`. Before trusting any of it:

```sh
iw list | sed -n '/Supported interface modes/,/^\s*[A-Za-z]/p'
```

The line to look for is `* AP`. If WPA3 is ever attempted, the evidence for
that is a separate capture, because a FullMAC part that advertises AP mode
has said nothing about SAE.

## What goes here afterwards, in the order the criteria are numbered

- the `hostapd` log of a station associating, and `iw dev wlan0 station
  dump` showing it
- the DHCP lease, from `dnsmasq` and from the client
- `openssl s_client -connect 10.18.0.1:8883` in full, including the chain
  it verified and the `Verify return code` line
- a publish and a subscribe across two different machines, with the
  timestamps on both
- the same connection **refused** after that client's certificate is
  revoked and the CRL is regenerated, which is the criterion most likely to
  be skipped and the only one that proves the CA is doing work
- a client without a certificate being refused, and a client with a
  certificate publishing outside its ACL being refused
