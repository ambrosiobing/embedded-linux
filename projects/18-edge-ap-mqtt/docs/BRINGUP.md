# Bring-up, Project 18

The order matters more here than in most of these projects, for one reason
that is worth reading before anything else: **this board's only network is
the one it serves.** If the access point does not start there is no ssh, no
fallback station and no cable. The way back in is the serial console, and
it is listed first below rather than last.

Nothing here has been done yet, on Tuesday 22 September 2026. This is the
order to do it in, not a record of doing it.

## 0. Before power: the way back in

The Renkforce USB/TTL cable on the board's serial console, connected and
working, before the card goes in. Every step below can fail in a way that
leaves no network, and every one of those failures is a two minute fix from
a console and an afternoon without one.

Three wires, and the third is the one people forget:

| Cable | Pi header |
|---|---|
| ground | pin 6 |
| the adapter's RX | pin 8, the Pi's TX |
| the adapter's TX | pin 10, the Pi's RX |

Not the red lead. The board is powered from its own supply, and joining two
supplies is how Project 3 lost a measurement and how boards get damaged.

## 1. The clock rule, which is decided before the image is built

The subtlest thing in this project and the easiest to get wrong, because
nothing about it looks like it belongs to a bring-up.

A Raspberry Pi has no battery-backed real-time clock, and this board has no
uplink by design, so it cannot learn the time. At boot the clock is moved
forward to roughly the image build time and no further. **If the CA is
created after the image is built, every certificate on the bench reads as
not yet valid**, every client fails, and the error names the certificate
rather than the clock.

So the certificate authority is created **first**, before the image:

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh init
```

and after the image exists, the rule is checked rather than assumed:

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh clock-rule "$(cat /etc/timestamp)"
```

taking `/etc/timestamp` from the built image. It prints both dates and
refuses with an explanation if the CA is the newer of the two.

## 2. Issue the certificates, on the laptop

The CA private key never goes near the board. Only four files travel.

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh server bench-ap 10.18.0.1
```

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh client ble-gateway
```

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh client bench-laptop
```

The address in the server command is not decoration: there is no DNS on
this network, so clients dial an address and the certificate's
subjectAltName has to carry that exact address. A certificate with only a
common name is one every modern TLS stack refuses.

The client names are not free either. They become MQTT usernames, because
the broker is configured with `use_identity_as_username`, and the access
control list in `meta-bench/recipes-bench/bench-broker/files/mosquitto.acl`
names them one by one. A certificate issued to a name that is not in that
file connects and can do nothing.

## 3. Build and flash

```sh
./go ap
```

```sh
./go flash /dev/sdX
```

The first build is expected to be a reconnaissance build. Two things about
this board are unread, both listed in `docs/evidence/README.md`: which
radio firmware a Pi 3 wants as against the Pi 3B+ part this repository
installs, and whether this chip's FullMAC firmware will run an access point
at all. The image installs `iw` so the second question can be asked on the
board rather than guessed.

## 4. Write the card, and mind which partition

**This is the step with a surprise in it.** The two pieces of identity this
board needs go to two different partitions, for a reason that is about the
authoring laptop rather than about the design:

| What | Where | Why there |
|---|---|---|
| SSID and passphrase | `/boot/ap.conf` | FAT, so Windows can write it |
| the four certificate files | `/boot/pki/` | also FAT, for the same reason |

The broker actually reads its certificates from `/etc/bench/pki`, which is
on the **ext4** root filesystem, and Windows cannot mount ext4. So they are
staged on the boot partition and installed at first boot by
`bench-broker-setup`, which also checks them.

With the card in the reader, its boot partition mounted as `E:` or
similar:

```
E:\ap.conf
```

holding two lines, and Notepad is fine. The provisioning script is written
to survive a byte order mark, CRLF endings and a missing final newline,
all three of which Notepad produces, and there is a test for each:

```
SSID=bench-18
PASSPHRASE=at least eight characters
```

Then the certificates, from a shell that can see the same card:

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh deploy bench-ap /e/pki
```

`deploy` copies exactly four files, named one at a time rather than by a
glob, and refuses if it finds a CA private key in the destination. The
board refuses too, before it copies anything, for the same reason: a CA key
that has left the laptop is not recoverable by deleting it, and every
certificate it ever signed has to be reissued.

## 5. First boot, with the console attached

Expect it to be interesting. In order:

```sh
dmesg | grep -i brcmfmac
```

This settles the firmware question. Paste the whole block into
`docs/evidence/`, including the filename it asked for and the chip it
reported.

```sh
iw list | sed -n '/Supported interface modes/,/^[[:space:]]*[A-Za-z]/p'
```

Look for `* AP`. If it is absent, this project stops here and the answer is
a USB wireless adapter that is not a FullMAC part, which the bench has and
Project 15 uses.

```sh
systemctl status bench-ap-setup bench-hostapd bench-dnsmasq
```

```sh
journalctl -u bench-broker-setup -u mosquitto
```

`bench-ap-setup` refuses with the filename and what to write if `ap.conf`
is missing or its passphrase is the wrong length. `bench-broker-setup`
refuses with the filename if the certificates are missing, not a pair, or
signed by a different authority.

## 6. Join it, from the laptop

The access point is the access path, which means criterion 10 is exercised
every time anybody logs in.

Associate to the SSID, take an address from `10.18.0.50` upward, and:

```sh
ssh root@10.18.0.1
```

Then the broker, from the laptop rather than from the board, because a
broker that works only when addressed as localhost is what Project 17
already has:

```sh
openssl s_client -connect 10.18.0.1:8883 -CAfile ~/.bench-pki/ca.crt
```

The line to keep is `Verify return code: 0 (ok)`. Anything else is
criterion 4 unmet, and the two usual causes are a subjectAltName that does
not carry `10.18.0.1` and a clock that is behind the CA's `notBefore`.

Before that, if a station is an ESP32 or an ESP8266, check it got the
time. A client that powers up in 1970 refuses the broker's certificate as
not yet valid and says nothing about a clock:

```sh
chronyc clients
```

on the board, which lists who has asked. A station that never asked is one
whose DHCP client ignored option 42, and its firmware has to set the time
itself.

Then a publish with an identity, and a publish without one:

```sh
mosquitto_pub -h 10.18.0.1 -p 8883 --cafile ~/.bench-pki/ca.crt --cert ~/.bench-pki/issued/bench-laptop.crt --key ~/.bench-pki/issued/bench-laptop.key -t bench/18/hello -m x
```

That one should be **refused**, and it is not a mistake in the command:
`bench-laptop` is read-only in the access control list. A subscriber that
can also publish is a debugging tool that can inject a reading into
somebody's results, so the refusal is criterion 7 working.

## 7. Revocation, which is the criterion most likely to be skipped

It is also the only one that proves the certificate authority is doing work
rather than decorating. Do it while the bench is set up, not later.

```sh
projects/18-edge-ap-mqtt/pki/bench-pki.sh revoke ble-gateway
```

Then redeploy the CRL to the card, or copy it over the network, and restart
the broker: mosquitto reads `crlfile` at startup, so regenerating it is not
enough on its own. The connection that worked before must now fail, and the
other clients must be untouched. Both halves go in `docs/evidence/`.

## If there is no network at all

In order of how often each one is the cause:

| Symptom | Look at |
|---|---|
| no SSID visible anywhere | `journalctl -u bench-hostapd`, then `iw list` for `* AP` |
| SSID visible, cannot join | the passphrase in `ap.conf`, and whether `bench-ap-setup` refused |
| joined, no address | `journalctl -u bench-dnsmasq`; it binds the address, so it fails if `systemd-networkd` has not assigned it yet |
| TLS fails, certificate "not yet valid" | the client's clock. It is 1970 and it did not reach the time server: `chronyc clients` on the board, and `dhcp-option=42` in the lease it was given |
| address, no ssh | the address is `10.18.0.1`, not whatever the client's gateway field says; there is no gateway on this island by design |
| ssh works, broker refuses | `journalctl -u mosquitto`, then whether `/etc/bench/pki` has four files |

And if none of that is reachable, the console from step 0, which is why it
is step 0.
