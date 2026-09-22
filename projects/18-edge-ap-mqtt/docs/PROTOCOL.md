# What a client has to do to join this bench

The broker owns identity, topics and delivery. **Each publishing project
owns its own payload.** That boundary is deliberate: Project 17 already has
a `docs/PROTOCOL.md` describing the bytes it sends, and a second document
inventing a different format for the same data would be wrong the day it
was written.

So this file is the contract for getting on the network and being allowed
to say anything at all, and it stops at the payload.

## 1. Join the network

| | |
|---|---|
| SSID | whatever `/boot/ap.conf` says; not published here |
| Security | WPA2-PSK with CCMP. Not WPA3, not TKIP, not open |
| Address | DHCP, from `10.18.0.50` to `10.18.0.150` |
| Gateway | **none is offered**, and that is correct. This is an island |
| DNS | **none is offered**. Dial the broker by address |

A client that insists on a default route or a resolver before it considers
the network usable will decide this one is broken. Phones do this. It is
not a fault in the access point.

## 2. Get the time, or nothing else works

**This is the step most likely to be skipped and it fails in the least
obvious way.**

A device with no real-time clock powers up in 1970. It then checks the
broker's certificate, finds a `notBefore` years in the future, and refuses
to connect with an error about the certificate. Nothing in that error
mentions a clock, so the search starts in the wrong place and stays there.

The DHCP lease carries **option 42**, pointing at `10.18.0.1`, which runs
`chronyd`. A client must either use it or set its clock some other way
before opening a TLS connection.

What that clock is, stated plainly so nobody builds on it: the access
point's own image build date plus its uptime. It is wrong by days or weeks
and it is monotonic. **It is sufficient for certificate validity and for
nothing else.** Do not timestamp a measurement from it.

## 3. Present a certificate this bench issued

There is one listener, `8883`, and it is TLS. There is no plaintext port.

| Requirement | |
|---|---|
| TLS version | 1.2 or better |
| Server verification | against `ca.crt`, which the client must carry |
| Name checking | the certificate's subjectAltName carries `IP:10.18.0.1`. There is no DNS, so a client that only checks common names will fail, correctly |
| Client certificate | required. `require_certificate true` |
| Identity | the certificate's common name becomes the MQTT username |

A client therefore ships three things: the bench CA certificate, its own
certificate, and its own private key. Issue them with:

```sh
./go pki client esp32-01
```

An ESP32 or ESP8266 embeds `ca.crt` in the firmware image. Its own key
should be generated on the device where the hardware allows it, and where
it does not, it is issued on the laptop like the others and copied once.

**Do not reuse one certificate across devices.** The whole benefit of
per-device identity is that a compromised device can be revoked without
touching the others, and a shared certificate is one that in practice never
gets revoked at all. See decision 112.

## 4. Publish under your own name

The rule is mechanical, and `tests/broker-config-test.sh` asserts it for
every identity in the access control list rather than for a list it
carries:

```
  bench/<your common name>/...
```

So `esp32-01` writes under `bench/esp32-01/`, and nothing else. The
subtree below that is yours; the broker does not care about its shape.

**Publishers write and do not read.** A publisher that could also
subscribe would be able to read back everything in its own subtree,
including whatever else writes there, and a compromised sensor should be
able to lie about itself and learn nothing. The one exception is
`keystore-verify`, which publishes a value and subscribes for the answer,
and it is named as an exception in the file rather than implied by a
default.

The one identity that reads everything is `bench-laptop`, and it cannot
publish at all. A subscriber that could publish is a debugging tool that
can inject a reading into somebody's results.

### Project 17 has to change one line to publish here

Its gateway publishes to `bench/stwin` by default, which is not under its
own name and would be refused. The knob already exists:

```
  meta-bench/recipes-bench/bench-stwin/files/stwin.conf
  STWIN_TOPIC=bench/stwin      ->   bench/ble-gateway/stwin
```

Nothing in that project is changed from here. The requirement is recorded
in this file and in the access control list, and the change belongs to
whoever points the two at each other. It is one line because that project
made the topic configurable, which is the part worth noticing.

## 5. Envelope rules, which the broker does enforce

| | |
|---|---|
| Maximum message | 64 kB. Authentication is not trust: a device with a loop in its firmware is the ordinary cause, and the broker shares a gigabyte with everything else on the board |
| Maximum connections | 20 |
| Retain | off, unless a topic genuinely holds state. A retained sensor reading outlives its own truth and is handed to the next subscriber as though it were current |
| QoS | 0 for telemetry, where the next reading is along shortly and a lost one costs nothing. 1 where a message is an event rather than a sample |
| Persistence | none. This broker keeps nothing across a restart, deliberately: the data is worthless a minute later and an SD card has a finite number of writes |

## 6. What happens when you get it wrong

Each of these is a real refusal, not a hypothetical, and each is an
acceptance criterion:

| What you did | What you see |
|---|---|
| No client certificate | The TLS handshake fails before MQTT starts |
| A certificate from another CA | The same, and the broker log names the issuer |
| A revoked certificate | The same again. The broker reads the CRL at startup, so a revocation needs a broker restart to take effect |
| Published outside your subtree | The connection stays up and the publish is silently dropped, which is MQTT's behaviour and not the broker's choice. Check the broker log |
| Subscribed as a publisher | The same silent drop |
| Clock not set | "certificate is not yet valid", and see section 2 |
