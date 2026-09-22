# Project 18: an edge access point with a broker nobody can join by accident

**Board:** Raspberry Pi 3. **Theme:** hostapd, dnsmasq, Mosquitto, X.509.

An island. One board runs the wireless network, hands out the addresses,
and is the only service on it: an MQTT broker that will not talk to a
client it cannot name. There is no uplink, no DNS, and no plaintext
listener.

The subject is not the access point, which is a configuration file, and not
the broker, which is another one. It is the **private certificate
authority** underneath them, and the question of what "MQTT over TLS"
actually proves. An encrypted channel to whoever answered is not the same
thing as a channel to the broker you meant, and a broker that accepts any
certificate is not the same thing as one that knows who is publishing.

## State

**Written, not yet built, as of Tuesday 22 September 2026.**

The certificate authority, both recipes, the image, the kas configuration
and four test suites exist, and **197 assertions pass** on the authoring
laptop with no board, no network and no broker:

| Suite | |
|---|---|
| `sh tests/pki-test.sh` | 51 passing |
| `sh tests/ap-config-test.sh` | 64 passing |
| `sh tests/broker-config-test.sh` | 43 passing |
| `sh tests/broker-setup-test.sh` | 28 passing |

`python scripts/lint.py` is clean. **BitBake has never parsed these
recipes**, nothing has been built, and nothing has been powered, so this is
a rung below Software complete on purpose.

One blocker was removed rather than waited on. Whether scarthgap's
mosquitto already builds with `ssl` is still unread, but `kas/bench-ap.yml`
now appends it: `PACKAGECONFIG` is a space separated list, so asking for
something already present costs nothing and asking for something absent is
the difference between this project working and not.

Two questions still need the board, and `docs/evidence/README.md` carries
the command for each: which radio firmware this Pi wants, and whether its
FullMAC firmware will run an access point at all.

## This project is not greenfield, and that is the most useful fact about it

Two other projects specified it before it existed.

`projects/17-ble-gateway/README.md:133`, about its own broker:

> Project 18 replaces that broker with one that has TLS and a private CA.
> This one listens on localhost and is a test fixture rather than a product
> decision.

`projects/20-optee-keystore/docs/BRINGUP.md:184` has a verifier that
subscribes over MQTT.

So the broker has two clients in this repository already, written first,
and three requirements follow that the one-line title does not mention: it
listens off-host, its clients are on other machines, and those clients have
to be able to verify it. That last one is what makes the private CA
load-bearing instead of ceremonial.

## What this project has that most do not

Its clients. The bench carries an **SBC-NodeMCU-ESP32** and a **Joy-it
SBC-ESP8266-PROG**, either of which is a wireless station and an MQTT
publisher, plus the Pi 3B+ that Project 17 runs on and the laptop. So the
acceptance criteria below can be met with parts that are on the table,
which Projects 10 and 17 cannot say.

The parts were checked against the inventory **before** the design was
written, which is journal entry 2 and a habit this repository learned by
specifying three projects around hardware that is not here.

## What this project adds

| Path | What | State |
|---|---|---|
| `projects/18-edge-ap-mqtt/pki/bench-pki.sh` | The CA. `init`, `server`, `client`, `revoke`, `verify`, `list`, `clock-rule`. Runs on the laptop and refuses to run inside the checkout | **written** |
| `tests/pki-test.sh` | Issue, verify, revoke, re-verify, the hostile request that asks to be a CA, and `deploy` putting four files on a card and not the fifth | **62 passing** |
| `meta-bench/recipes-bench/bench-ap/` | `hostapd` and `dnsmasq` configuration, the static address, the provisioning that reads `/boot/ap.conf`, and three units | **written** |
| `meta-bench/recipes-bench/bench-broker/` | `mosquitto` configuration, the ACL, the tmpfiles entry and a drop-in rather than a unit | **written** |
| `meta-bench/recipes-core/images/bench-ap-image.bb` | The image, with `bench-net-wifi` removed | **written**, never built |
| `kas/bench-ap.yml` | `./go ap`, and the `ssl` PACKAGECONFIG append | **written**, never built |
| `projects/18-edge-ap-mqtt/docs/PROTOCOL.md` | What a client must do to join at all: the network, the clock, the certificate, and the rule that it publishes under its own name | **written**, and checked against the access list by a test |
| `projects/18-edge-ap-mqtt/docs/BRINGUP.md` | Seven steps, starting with the serial console because it is the only way back in | **written** |
| `meta-bench/recipes-kernel/linux/files/ap.cfg` | Only if the shared kernel turns out to lack something | **blocked**, until the board has been read |
| `tests/ap-config-test.sh`, `tests/broker-config-test.sh`, `tests/broker-setup-test.sh` | Both provisioning scripts against fixture cards, all three configurations asserted for meaning rather than syntax, and the access list checked against the document that describes it | **135 passing** |

## Acceptance criteria

"Configured" means a file says so; "measured" means a board did. Nothing in
this table is measured on Tuesday 22 September 2026.

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | `hostapd` brings up the BSS and a station associates | the `hostapd` log and `iw dev wlan0 station dump` | **Not started.** Blocked behind the radio firmware question |
| 2 | `dnsmasq` hands that station an address in the planned range | the lease, from both ends | **Not started** |
| 3 | The broker listens on 8883 and there is no 1883 anywhere | `ss -ltnp` on the board | **Not started** |
| 4 | A client on a different machine verifies the server against the private CA, by the address it dialled | `openssl s_client` in full, with the `Verify return code` line | **Not started.** The SAN has to carry the IP, since there is no DNS to resolve a name |
| 5 | A client with no certificate is refused | the broker log and the client error | **Not started** |
| 6 | A client with a valid certificate publishes, and its CN is the username the ACL sees | a publish, and the broker log naming the identity | **Not started.** This is `use_identity_as_username`, and without it the PKI decorates a system whose real access control is something else |
| 7 | The ACL refuses a publisher that subscribes, and a publisher that publishes outside its own prefix | two refusals in the broker log | **Not started.** The point of per-device identity, and invisible unless written this way round |
| 8 | A revoked certificate is refused after the CRL is regenerated | a connection that worked, then the same one refused | **Not started.** The criterion most likely to be skipped, and the only one that proves the CA is doing work rather than decorating |
| 9 | Project 17's gateway publishes to this broker from its own board, replacing its localhost fixture | both boards' logs, with timestamps | **Not started.** This is the criterion that closes the sibling project's own open item |
| 10 | The board is reachable only through its own access point and the serial console | an ssh session over `wlan0`, and no other path | **Not started.** Exercised every time anyone logs in, which is the nice property of making the AP the access path |
| 11 | The clock rule holds: the CA's `notBefore` is earlier than the image build timestamp | both timestamps, recorded together | **Not started**, because no image has been built and there is no timestamp to compare against. The check itself exists and is tested in both directions: `bench-pki.sh clock-rule` |

Two criteria this repository asserts that the theme does not ask for:

| # | Criterion | State |
|---|---|---|
| 12 | The whole PKI is exercisable with no board and no network | **Met.** `sh tests/pki-test.sh`, 51 assertions, on a laptop with openssl and nothing else. Issue, verify, revoke, regenerate the CRL, re-verify, and a hostile request that asks to be a certificate authority and to carry the broker's own address. Two of its assertions were proven by breaking what they check |
| 13 | Configuration is tested for meaning, not syntax | **Met.** 83 assertions across the two configuration suites, including four that no single file could make: the DHCP range must lie inside the static address's subnet and exclude the address itself, the broker's listener must be the address the interface is given, and `acl_file` must name a file the recipe installs. Each was proven by breaking it |

## What is tested without hardware

| Check | Command | Covers | |
|---|---|---|---|
| The PKI | `sh tests/pki-test.sh` | Issue a CA, a server certificate and two client certificates; verify the chain; check the SAN carries the address; check `extendedKeyUsage` splits server from client; revoke one; regenerate the CRL; verify the revoked one now fails and the other still passes; and a hostile request that asks to be a certificate authority and to carry the broker's own address, which gets neither | **51 passing** |
| The clock rule | same suite | The CA's `notBefore` against a build timestamp, in both directions, which is the whole of criterion 11 | **passing** |
| The access point | `sh tests/ap-config-test.sh` | `bench-ap-setup` driven against fixture cards, including a byte order mark, CRLF endings and a file with no final newline; every refusal it can produce; that `hostapd` is WPA2 with CCMP and no TKIP and isolates its clients; that `dnsmasq` answers no DNS and offers no gateway; and that the DHCP range lies inside the static address's subnet without including the address | **54 passing** |
| The broker | `sh tests/broker-config-test.sh` | That there is exactly one listener and it is not 1883; that the CRL is read at all; that `require_certificate` and `use_identity_as_username` are both on; that every publisher can write and not read; that the listener address is the one the interface is given; that the drop-in does not start a second broker; and that no key or certificate is committed anywhere | **29 passing** |

**What none of it proves.** That the radio will run an access point,
that this station will associate, or that the broker binary has TLS
compiled into it at all. Those need the board and the build, and they are
criteria 1 to 10.

## The thing most likely to go wrong, stated early

**Not the certificates. The clock.**

A Raspberry Pi has no battery-backed real-time clock, and this board has no
uplink by design, so it cannot learn the time from the network. At boot the
clock is moved forward to roughly the image build time and no further. If
the CA was created *after* that, every certificate on the bench is not yet
valid, every client fails, and the error names the certificate rather than
the clock.

The design takes two of the three available remedies and records the third.
`docs/DESIGN.md` has the reasoning and the figure; the short version is
that the CA is created before the image is built, and a test asserts it.
