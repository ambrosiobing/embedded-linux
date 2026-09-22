# Evidence

Raw output from the board and the host, unedited. Nothing here yet,
because no board has enumerated.

What belongs here, named by the document that refers to it:

| File | Referred to by | What it is |
|---|---|---|
| `lsusb-v.txt` | [DESCRIPTORS.md](../DESCRIPTORS.md) | the full `lsusb -v` on a Linux host. **The interview artefact.** |
| `dmesg-dwc2.txt` | [BRINGUP.md](../BRINGUP.md) | the controller coming up in device mode, with its endpoint count |
| `bench-gadget-status.txt` | [BRINGUP.md](../BRINGUP.md) | the tree bound, with all three device nodes present |
| `serial-by-id.txt` | [DESCRIPTORS.md](../DESCRIPTORS.md) | the ACM symlink, whose `ifNN` suffix proves the interface numbering |
| `iperf3.txt` | the acceptance table | throughput over the ECM link, criterion 2 |
| `evtest-latency.txt` | the acceptance table | host-side timestamps against the bridge's own log, criterion 4 |
| `journal-undervoltage.txt` | the acceptance table | ten minutes with the keyboard attached, criterion 7 |
| `device-manager.png` | [DESCRIPTORS.md](../DESCRIPTORS.md) | the Windows side, with the three in-box drivers bound |

**Raw, not a paraphrase**, and with the tool version at the top of each
capture. The value of a stored `lsusb -v` six months later is in the
field nobody thought was interesting at the time.

**A capture from a board that did not work is still evidence** as long as
it says so. This project has five different causes that all present as
"the host sees nothing", and a stored example of each is worth more than
another copy of the working case.
