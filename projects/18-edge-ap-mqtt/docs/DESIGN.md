# Design: an edge access point with a broker nobody can join by accident

Written before any recipe, which is the order this repository settled on
after Project 1 was built first and documented afterwards. A design written
first catches the case where the implementation drifted from the intent;
documentation written afterwards structurally cannot.

| Section | What it settles |
|---|---|
| [What this is for](#what-this-is-for) | Two sibling projects already depend on it |
| [Which board](#which-board-and-the-firmware-that-follows) | A Pi 3 is not a Pi 3B+, and the radio firmware knows |
| [One radio, no cable](#one-radio-and-no-cable) | How the board is reached, and the way back in |
| [The network](#figure-1-the-network) | Addresses, and what hands them out |
| [The private CA](#figure-2-the-private-ca) | What signs what, and what never touches the board |
| [What the handshake proves](#figure-3-what-the-handshake-actually-proves) | Why the CA is load-bearing and not decorative |
| [The clock](#the-clock-is-the-hard-part) | An isolated board cannot check a notBefore it cannot know |
| [Two PACKAGECONFIG lines](#the-two-packageconfig-lines-this-project-rests-on) | Whether TLS is in the binary at all |
| [Ownership](#ownership) | Which component owns which interface and file |

The client's side of all this, which is a contract rather than a design,
is in `docs/PROTOCOL.md`: what a device must do to join, get a clock,
present an identity and be allowed to publish anything. `docs/BRINGUP.md`
is the order to do it in on a bench.

## What this is for

The root README gives a title. The specification is written elsewhere in
this repository, by projects that needed this one before it existed.

`projects/17-ble-gateway/README.md:133`, about its own broker:

```
  "Project 18 replaces that broker with one that has TLS and a private CA.
   This one listens on localhost and is a test fixture rather than a
   product decision."
```

`projects/20-optee-keystore/docs/BRINGUP.md:184`, about its verifier:

```
  "and publishes with a `mac` field; `benchkey-verify --mqtt` subscribes"
```

So this is not a greenfield broker. It is the replacement for a named
fixture, and it has two clients in this repository that were written first.
Three requirements follow that the title does not mention:

1. **It listens off-host.** Project 17's broker binds to localhost, which
   is why that project can only prove its pipeline on one board.
2. **Its clients are not on the board.** A BLE gateway on a Pi 3B+, a
   keystore verifier, and an ESP32 on the bench are three different
   machines.
3. **Those clients have to be able to verify it.** That is what makes a
   private CA load-bearing rather than ceremonial: without it, "MQTT over
   TLS" is an encrypted channel to whoever answered.

## Which board, and the firmware that follows

The README assigns a **Raspberry Pi 3**, and the bench has both a Pi 3 and
a Pi 3B+. The difference is not cosmetic here, because the wireless part
differs and this project is about the wireless part.

| Board | Wireless chip | Firmware file | Package in this repository |
|---|---|---|---|
| Raspberry Pi 3 | BCM43438 | `brcmfmac43430-sdio.bin` | **not installed by anything here** |
| Raspberry Pi 3B+ and Pi 4 | BCM43455 | `brcmfmac43455-sdio.bin` | `linux-firmware-rpidistro-bcm43455`, in `bench-image.bb` |

`meta-bench/recipes-core/images/bench-image.bb` installs the 43455 package
and nothing else. On a Pi 3B+ or a Pi 4 that is correct. On a plain Pi 3 it
is the exact failure that repository's own comment describes, from the
other direction: the driver loads, the firmware it wants is not there, and
the radio never probes.

**This is an open item, not a decision.** Which of the two boards is on the
bench for this project, and therefore which firmware package the image
needs, is settled by one line of `dmesg` on the first boot. It is listed in
`docs/evidence/README.md` and it is not guessed at here. Project 1 lost two
rounds to a radio whose firmware and vendor module were assumed.

**A second consequence of the chip, which does affect the design.**
`brcmfmac` is a FullMAC driver: the MAC layer runs in the chip's firmware
and the host speaks `cfg80211` directly, as `bench-image.bb` already
records. Access point mode therefore depends on what the firmware supports,
not on what `hostapd` can express. In practice that means **WPA2-PSK is the
safe target and WPA3-SAE is not**, and an access point that silently falls
back, or refuses to start, is the ordinary way to find that out. The design
targets WPA2 and records WPA3 as a thing to try on the board rather than a
thing to promise in a README.

## One radio and no cable

The Pi 3 has one radio. An access point on `wlan0` means that radio is not
also a station on somebody else's network. The bench README records at line
274 that this bench has no Ethernet cable, "not because it is better".

So the ordinary way of reaching a board under development, ssh over the
bench wireless network, is the thing this project removes.

**The access point becomes the access path.** A laptop associates to the
board's own network and reaches it at the address the board hands out. That
is not a workaround; it is what an edge access point is for, and it means
the first acceptance criterion is exercised every time anyone logs in.

**The recovery path is the console, and it gets written first.** If
`hostapd` does not start, there is no network at all: no ssh, no fallback
station, nothing. The way back in is the Renkforce USB/TTL cable on the
board's serial console, which the bench inventory does confirm.

This repository already learned this the expensive way. A first-boot script
under `set -e` died on a missing template before it reached the block that
wrote the access point, and left a board with no Ethernet reachable only
from the console. So:

- the console is enabled and stays enabled, and nothing in this project's
  provisioning may run before it
- the provisioning script writes the recovery-relevant configuration first
  and the optional features afterwards
- `hostapd` failing is a **logged refusal with the reason**, not a silent
  exit, because a refusal without evidence trains people to switch the
  guard off

**Why not the second radio, which exists.** Project 15 uses a USB wireless
adapter as a second interface and it works. Adding it here would keep the
board reachable on the bench network while it serves its own, which is
convenient and is the wrong choice for this project: it makes the
interesting failure impossible. A board that is still reachable when
`hostapd` has not started is a board where nobody finds out for a week.

## Figure 1: the network

```
   ESP32 station            laptop station          Pi 3B+ (Project 17)
   CN=esp32-01              CN=bench-laptop         CN=ble-gateway
        |                        |                        |
        |        WPA2-PSK, 2.4 GHz, one BSS               |
        +------------+-----------+------------+-----------+
                                 |
                          wlan0  10.18.0.1/24
              +--------------------------------------+
              |  Raspberry Pi 3                      |
              |                                      |
              |   hostapd    owns the BSS            |
              |   dnsmasq    DHCP only, .50 to .150  |
              |   chronyd    the only clock there is |
              |   mosquitto  8883, TLS, client certs |
              |                                      |
              |   console on the USB/TTL cable       |
              +--------------------------------------+
                                 |
                          no uplink, on purpose
```

**10.18.0.0/24, and the 18 is deliberate.** Project 15's router already
serves a bench LAN, and two projects handing out addresses on the same
prefix is the kind of collision that is invisible until both are powered
at once. The project number in the third octet makes the clash impossible
to have by accident and obvious to diagnose.

**dnsmasq does DHCP and not DNS.** It is perfectly capable of both, and
resolving names here would mean either forwarding upstream, which does not
exist, or answering for a domain this project does not own. Clients dial
the broker by IP address, which is also what fixes the certificate: the
server certificate carries `IP:10.18.0.1` in its subjectAltName, and a name
nobody can resolve is a name nobody can verify.

## Figure 2: the private CA

```
   bench-ca                        the laptop, never the board
   +------------------------+      key: ca/private/ca.key, mode 0600
   |  CN=bench-ca           |      kept outside this repository
   |  basicConstraints: CA  |
   |  pathlen: 0            |
   +-----------+------------+
               |
      signs    |
               +---------------------------------------+
               |                                       |
   +-----------v------------+            +-------------v------------+
   |  server                |            |  clients, one per device |
   |  CN=bench-ap           |            |  CN=ble-gateway          |
   |  SAN: IP:10.18.0.1     |            |  CN=keystore-verify      |
   |  extendedKeyUsage:     |            |  CN=esp32-01             |
   |    serverAuth          |            |  extendedKeyUsage:       |
   +------------------------+            |    clientAuth            |
   installed on the board                +--------------------------+
   key mode 0600, owner mosquitto        each key stays on its device
               |
               +--> bench-ca.crl, regenerated on every revocation
```

**pathlen:0** because nothing below this CA may sign anything else. A CA
that can mint intermediates is a CA whose compromise has no edge.

**Separate extendedKeyUsage on each side.** A certificate that is both
`serverAuth` and `clientAuth` lets a client that obtained one impersonate
the broker to another client. Splitting them costs one line in the openssl
extension file and removes the whole class.

**One certificate per device, not one per fleet.** The point of a private
CA is revocation: a shared certificate cannot be withdrawn from one device
without withdrawing it from all of them, which means in practice it is
never withdrawn. The CRL is part of the design rather than an afterthought,
and `mosquitto` is configured with `crlfile` so that it is actually read.

**The CA private key never reaches the board.** Signing happens on the
laptop. A board that can sign certificates is a board whose compromise
mints new identities, and this one is by design sitting in a room with its
radio on.

**Where this meets Project 20.** That project is a trusted application for
key storage on the same family of board. The broker's private key sitting
at mode 0600 on an ext4 partition is exactly the asset its keystore exists
to protect, and moving it there is the obvious next step for both projects.
It is named here and deliberately not attempted: Project 20 is software
complete and has never run on a board, so building on it now would stack an
unverified thing on an unverified thing.

## Figure 3: what the handshake actually proves

The part worth drawing, because "MQTT over TLS" is routinely taken to mean
the first half of this and not the second.

```
  station                                      broker
    |  ClientHello                                |
    |-------------------------------------------->|
    |                      ServerHello, cert chain|
    |<--------------------------------------------|
    |                                             |
    |  station checks, and all three must hold:   |
    |    signed by bench-ca                       |
    |    SAN contains the address it dialled      |
    |    notBefore <= now <= notAfter             |
    |                                             |
    |                          CertificateRequest |
    |<--------------------------------------------|
    |  client certificate, CertificateVerify      |
    |-------------------------------------------->|
    |                                             |
    |  broker checks:                             |
    |    signed by bench-ca                       |
    |    not listed in bench-ca.crl               |
    |    then CN becomes the username             |
    |                                             |
    |  the ACL is applied to that username        |
```

**`use_identity_as_username true` is what connects the two halves.**
Without it the broker has authenticated a certificate and then authorises
an unrelated username, and the PKI decorates a system whose real access
control is a password file. With it, the certificate's CN *is* the
identity, and the ACL below is enforced against something cryptographic.

**The ACL, as a table rather than as prose:**

| Identity | May publish | May subscribe |
|---|---|---|
| `ble-gateway` | `bench/17/#` | nothing |
| `keystore-verify` | `bench/20/#` | `bench/20/#` |
| `esp32-01` | `bench/18/esp32-01/#` | nothing |
| `bench-laptop` | nothing | `bench/#` |

A publisher that cannot subscribe cannot read other devices' data, and a
compromised sensor becomes a device that can lie about itself and nothing
else. That is the whole practical benefit of per-device identity, and it is
invisible unless the ACL is written this way round.

## The clock is the hard part

This is the finding that changes the build, and it is not in the title.

**Certificate validation is a comparison against the current time, and this
board does not know what time it is.** A Raspberry Pi has no
battery-backed real-time clock. It normally learns the time from the
network, and this board has no uplink by design. So at every boot the
clock starts at whatever the system decides, and if that is earlier than
the CA's `notBefore`, **every certificate on the bench is not yet valid**
and every client fails to connect, with an error that points at the
certificate rather than at the clock.

```
  power on
     |
     v
  systemd sets the clock forward to the latest of:
     the last saved timestamp   /var/lib/systemd/timesync/clock
     the image build time       baked in at build
     the RTC                    if there is one, and there is not
     |
     v
  is that time >= the CA certificate's notBefore ?
     |                                  |
    yes                                 no
     |                                  |
  handshakes verify           every client reports an
                              untrusted certificate, and
                              the clock is not mentioned
```

**Three ways to close it, and which this project takes.**

| Option | What it costs | Verdict |
|---|---|---|
| Issue certificates with `notBefore` well in the past | Nothing at build time. Widens the window in which a stolen key is usable | **Taken**, combined with the next row |
| Rely on systemd moving the clock forward to the image build time, and never issuing a certificate whose `notBefore` is after the image was built | An ordering rule between two things that look unrelated: when the CA was created, and when the image was built | **Taken**, and written into the bring-up |
| Add the Explorer 700's RTC | The bench does have one, on the HAT Project 6 uses. It occupies the 40-pin header and makes this project depend on that one | Recorded, not taken |

The ordering rule is the part that will be forgotten, so it is not left as
prose anywhere. It is a command:

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh clock-rule 20270301093000
```

taking the image's `/etc/timestamp` and comparing it with the CA's
`notBefore`. **The CA must be older than the image.** It refuses with both
timestamps printed and a sentence saying the clock is the cause, because
the failure it prevents shows up as an error about a certificate and sends
the reader in entirely the wrong direction.

It runs on the laptop with no board, and `tests/pki-test.sh` asserts it in
both directions. `docs/BRINGUP.md` repeats it as step 1, because the
ordering has to be got right before the image is built and nothing about it
looks like it belongs to a bring-up. The executable form is the one that
will still be right in six months.

### And the clients are worse off, which this section originally missed

Everything above is about the board. The board is the best placed machine
on this network, because it at least has an image build date to fall back
on.

**An ESP32 or an ESP8266 has no clock at all and powers up in 1970.** It
then checks the broker's certificate, finds a `notBefore` in 2026, and
refuses to connect. The error says the certificate is not yet valid and
mentions no clock, so the search starts at the certificate. Both of this
project's station clients are in exactly that position, and so, less
severely, is any Linux client whose own image predates this bench's
certificate authority.

That would have been found on the board, at the point where criterion 6 is
meant to pass, with three plausible suspects and the actual cause in none
of them.

```
  ESP32 powers up            access point
  clock = 1970-01-01              |
        |                         |
        |  DHCP request           |
        |------------------------>|
        |  offer + option 42 -----|  "the NTP server is 10.18.0.1"
        |<------------------------|
        |                         |
        |  NTP                    |
        |------------------------>|  chronyd, local stratum 10
        |<------------------------|  "about the image build date"
        |                         |
  clock >= the CA's notBefore     |
        |                         |
        |  TLS, and now the certificate verifies
        |------------------------>|
```

**So the island serves the one thing it knows.** `chronyd` with
`local stratum 10 orphan`, which means "serve my own clock even though it
is synchronised to nothing", and `dhcp-option=42` so clients are told where
to find it. Decision 111 guarantees the board's clock is no earlier than
the certificate authority, so every client that syncs to it lands in a time
where every certificate on the island is valid.

**It is not accurate time and is not claimed to be.** It is the image build
date plus uptime, wrong by days or weeks, and monotonic. That is all
certificate validity needs and it is not enough for anything else: nothing
on this island should timestamp a measurement from it, which is why
Projects 3 and 8 both take their timing from the board's own monotonic
clock.

| Rejected | Why |
|---|---|
| Hardcode a build timestamp into each client | Works, and has to be redone per client and per firmware build. The failure mode when it is forgotten is the one above |
| Turn off certificate time validation on the clients | Removes the check that makes an expired or not-yet-valid certificate fail, which is most of what a validity period is for |
| An upstream NTP server | There is no uplink, by design, because a second interface would make the interesting failure impossible |

## The two PACKAGECONFIG lines this project rests on

The traps file for this bench opens with the rule that a configuration file
proves nothing about whether a feature exists, because in Yocto the feature
set is chosen by whoever wrote `PACKAGECONFIG ??=`. Project 15 lost a build
to exactly this: NetworkManager parsed a connectivity configuration without
complaint and the feature was not in the binary.

This project has two such lines and **neither has been read**, because
`poky` and `meta-openembedded` are not checked out on the authoring laptop;
they live in `~/bench` on the WSL laptop. So this section states the
question rather than the answer.

| Recipe | What has to be on | What happens if it is not |
|---|---|---|
| `mosquitto` | `ssl` | The broker starts, the log complains about unknown options or refuses the listener, and there is no 8883. This is the whole project |
| `hostapd` | the build's WPA2 support, and `sae` only if WPA3 is ever attempted | An access point that comes up open, or does not come up |

To be read on the WSL laptop before the first build, not after it. The
configuration named is `bench-ble`, which exists today and already pins
`meta-networking`, so this can be answered before this project has a kas
file of its own:

```sh
./go shell bench-ble
```

then, inside that shell, `bitbake -e mosquitto | grep '^PACKAGECONFIG='`
and the same for `hostapd`. The answer goes in `docs/evidence/`, because a
`PACKAGECONFIG` is a property of a layer revision and this repository pins
its layers.

**If `ssl` is absent, the remedy is one line** in this project's kas file,
in the same place and the same shape as Project 15's three
`PACKAGECONFIG:append:pn-networkmanager` entries. Knowing that early is
worth more than the five minutes it costs, because the alternative is
finding out from a board that will not accept a connection.

## Ownership

The table that prevents the commonest class of bug, which is two managers
on one resource. This project is unusually exposed to it: **three different
things in this repository already want to configure `wlan0`.**

| Resource | Owner | Nothing else may |
|---|---|---|
| `wlan0` | `hostapd` | configure it. `bench-net-wifi` runs `wpa_supplicant` and a `systemd-networkd` profile on this exact interface and **must be removed from this image**, the way Project 15's router removes it. NetworkManager is not installed here at all |
| The address on `wlan0` | a static `systemd-networkd` file owned by this project | be assigned by DHCP. The access point cannot ask anybody for its own address |
| DHCP on `wlan0` | `dnsmasq` | answer DNS, or listen on any other interface |
| TCP 8883 | `mosquitto` | bind it. There is no 1883 listener at all |
| UDP 123 | `chronyd` | serve time. It is the only source on the island, and it serves the board's own approximate clock rather than anything accurate |
| The CA private key | the laptop | exist on the board, in the image, or in this repository |
| The server private key | `mosquitto`, mode 0600 | be group or world readable, or be committed |
| `/boot/ap.conf` | the card, written after flashing | be in the repository. It carries the SSID and the passphrase |
| The system clock | `systemd` | be assumed correct. See above |
| The serial console | `getty` | be taken over by anything. It is the only way back in |

## What gets built

| Path | What |
|---|---|
| `meta-bench/recipes-bench/bench-ap/` | `hostapd`, `dnsmasq` and `chrony` configuration, the static address, the provisioning that reads `/boot/ap.conf`, and the unit ordering |
| `meta-bench/recipes-bench/bench-broker/` | `mosquitto` configuration, the ACL, the tmpfiles entry and the unit |
| `projects/18-edge-ap-mqtt/pki/` | The CA tooling. **Runs on the laptop, never on the board**, and openssl 3.5.5 is present there, so it and its tests are exercisable with no hardware |
| `meta-bench/recipes-kernel/linux/files/ap.cfg` | Whatever access point mode needs that the shared kernel does not already have, behind an opt-in switch. **Not written until the board has been read** |
| `meta-bench/recipes-core/images/bench-ap-image.bb` | The image, with `bench-net-wifi` removed |
| `kas/bench-ap.yml` | `./go ap`, including `bench-rpi3.yml` and pinning `meta-networking` for `hostapd` and `mosquitto` |
| `tests/` | The PKI end to end, the ACL, the configuration files, and the clock ordering rule |

`meta-networking` is already pinned by two other configurations in this
repository, `kas/bench-router.yml` and `kas/bench-ble.yml`, and
`bench-ble-image.bb` already installs `mosquitto` and `mosquitto-clients`.
So the layer and the recipe are known to build here; what is unknown is
only whether TLS is compiled into them.

## What is deliberately absent

| Absent | Why | What it costs |
|---|---|---|
| Any uplink | One radio, and the interesting failure needs to be possible | No NTP, which is the clock problem above; no package installation on a running board |
| DNS | Nothing to forward to, and no domain this project owns | Clients dial an IP, which is also what the certificate's SAN can carry |
| A 1883 listener | A plaintext listener beside a TLS one is the one every client accidentally uses | A client that misconfigures TLS fails loudly instead of quietly succeeding |
| Username and password authentication | The certificate is the identity | No way in for a client that has not been issued a certificate, which is the point |
| WPA3-SAE | FullMAC firmware decides, not `hostapd`, and nothing here has tested it | Recorded as a board experiment rather than a promise |
| Bridging the wireless clients to anything | There is nothing to bridge to | This is an island, and the broker is the only service on it |
