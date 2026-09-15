# The USB composition, and why 9001

The SIM7600 family can present itself to the host in several ways, chosen
with `AT+CUSBPIDSWITCH=<pid>,1,1` on the AT port. The change survives a
reboot, which makes it the one setting that can lock you out of the module
over USB, and the reason this file exists at all: the decision is recorded
rather than remembered.

## The choice

| PID | Composition | Advantages | Costs |
|---|---|---|---|
| 9001 | Serial ports plus QMI and RMNET | Native WWAN in ModemManager, a real IP address on `wwan0`, signal and bearer statistics, no double NAT | Needs `qmi_wwan` and ModemManager; raw IP mode confuses older tools |
| 9011 | Serial ports plus RNDIS | Works with any host that speaks DHCP; the modem does its own NAT | Double NAT, no bearer state on the host, RNDIS is being retired in Linux |
| 9018 | Serial ports plus ECM, firmware dependent | Like RNDIS but a standard class driver, `cdc_ether` | Same double NAT; not on every firmware, query the module |

**This project uses 9001.** Three reasons, in order of weight:

1. **The host can see the bearer.** Signal, registration state, operator and
   bearer status are all ModemManager properties. Under RNDIS the modem is
   a black box that either forwards packets or does not, and the whole
   watchdog and the whole exporter would have nothing to read.
2. **One layer of NAT, not two.** Under 9011 and 9018 the modem NATs to its
   own private network and the Pi NATs again. Two translations means two
   places a port forward has to be arranged and two conntrack tables to
   reason about.
3. **RNDIS is on its way out of the kernel.** Choosing it in 2026 is
   choosing a migration in a few years.

The cost is real and worth naming: 9001 needs `qmi_wwan`, and `qmi_wwan`
runs the interface in raw IP mode, where a DHCP client finds nothing. Half
the confusing failures on a QMI modem are somebody running `dhclient wwan0`
and concluding the modem is dead.

## Recording what this module actually offers

The table above is the family. The PID list of a given firmware comes from
the module, so ask it and paste the answer here.

```sh
systemctl stop lte-watchdog
picocom -b 115200 /dev/lte-at
AT+CUSBPIDSWITCH?            # the current PID
AT+CUSBPIDSWITCH=?           # the PIDs this firmware offers
AT+CUSBPIDSWITCH=9001,1,1    # back to QMI if something else was set
```

Measured on this module: not yet run. When it is, the output of all three
commands belongs below, verbatim, with the firmware revision from `ATI`.

```
(to be filled in on first bring-up)
```

## Inspecting QMI directly

ModemManager owns `/dev/cdc-wdm0` while it runs, so it has to be stopped
before anything else opens the channel. This is the way to answer "is
ModemManager wrong or is the modem wrong", which is otherwise a long
argument with no evidence.

```sh
sudo systemctl stop ModemManager
qmicli -d /dev/cdc-wdm0 --dms-get-manufacturer
qmicli -d /dev/cdc-wdm0 --dms-get-revision
qmicli -d /dev/cdc-wdm0 --nas-get-signal-strength
sudo systemctl start ModemManager
```

`qmicli` comes from `libqmi`, which the router image installs for exactly
this. A debugging tool whose absence can only be fixed over the network is
not much use on a box whose failure mode is no network.

## If the module ends up in a composition the host cannot use

The USB link is gone, and the header UART is the way back. See step 9 of
[BRINGUP.md](BRINGUP.md). This is the only reason the UART is wired at all,
and it is enough of a reason.
