# Figures

Seven drawings, each one file, each compiling on its own.

```sh
make                    # every figure to PDF
make png                # and to PNG
make layer-tools.pdf    # just one
```

| File | What it shows | Where it is also drawn in text |
|---|---|---|
| `layer-tools.tex` | Every layer, the one tool that answers for it, and a healthy answer | [DESIGN.md](../DESIGN.md#which-tool-shows-which-layer) |
| `decision-tree.tex` | Given a black screen or a dead touch, which layer to suspect | [DESIGN.md](../DESIGN.md#reading-it-as-a-decision-tree) |
| `arch.tex` | Panel to widget, and who opens what | [DESIGN.md](../DESIGN.md#architecture) |
| `uml-sequence.tex` | One touch across six boundaries, each with its own tool | [DESIGN.md](../DESIGN.md#one-touch-end-to-end) |
| `schematic.tex` | One ribbon, two wires, and the power budget | [DESIGN.md](../DESIGN.md#schematic) |
| `bench.tex` | What is on the desk, and why a screen project needs a serial cable | [DESIGN.md](../DESIGN.md#bench-layout) |
| `boot-budget.tex` | Where ten seconds goes, and what each instrument is blind to | [DESIGN.md](../DESIGN.md#the-ten-second-budget) |

`preamble.tex` holds the palette and the styles. The colours carry
meaning and are the same in every figure, and here they mean **which
layer**: hardware, kernel driver, compositor, client, and the brokers
(`seatd` and `systemd`) that hand one to the other.

`layer-tools.tex` is the one to read first. It is the actual deliverable
of the project: the dashboard is the excuse, and knowing which tool shows
which layer is the skill.

**Nothing in the build or the tests depends on TeX.** Every figure here is
also drawn in ASCII or mermaid inside the documents, so a reader without a
TeX installation loses the typesetting and none of the content. The PDFs
and PNGs are build products and are not tracked.

The requirement on Debian and Ubuntu is:

```sh
sudo apt-get install -y texlive-latex-extra texlive-pictures poppler-utils
```
