# Evidence, Project 18

Empty on purpose, on Monday 21 September 2026.

Nothing has been built and nothing has been powered. No access point has
carried a station, no certificate has been presented to anything, and no
client has connected. The acceptance table in this project's README marks
every criterion accordingly.

A directory with a file explaining why it is empty is more honest than an
absent directory, which reads as an oversight.

## The questions that block work, in the order they can be answered

The first three need no board. The last two need one boot each.

**1. Is `ssl` in mosquitto's PACKAGECONFIG, and what does hostapd's say.**
The whole project rests on this and it is unread, because `poky` and
`meta-openembedded` live in `~/bench` on the WSL laptop and not on the
authoring laptop. A configuration file proves nothing about whether a
feature is in the binary; Project 15 lost a build to exactly that. On the
WSL laptop, `./go shell bench-ble`, then:

```sh
bitbake -e mosquitto | grep '^PACKAGECONFIG='
```

and the same for `hostapd`. Paste both lines here with the layer revision
they came from, because a `PACKAGECONFIG` is a property of a pinned layer
rather than of a package name.

**1b. Which layer provides chrony.** Same class of unknown as the one
above and answered by the same shell. The access point serves time to its
clients, because a station with no clock powers up in 1970 and refuses the
broker's certificate as not yet valid; see decision 113. `chrony` is
expected to be in meta-networking, which `kas/bench-ap.yml` already pins,
but that has not been read. On the WSL laptop:

```sh
bitbake-layers show-recipes chrony
```

If it is elsewhere, the fix is a layer line in the kas file and nothing
else.

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
