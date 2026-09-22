# Figures

Seven drawings, each one file, each compiling on its own.

```sh
make                      # every figure to PDF
make png                  # and to PNG
make endpoint-budget.pdf  # just one
```

| File | What it shows | Where it is also drawn in text |
|---|---|---|
| `endpoint-budget.tex` | Seven endpoints, seven spent, and the five interfaces | [DESIGN.md](../DESIGN.md#the-endpoint-budget) |
| `arch.tex` | The configfs tree to the host's drivers, and the two controllers | [DESIGN.md](../DESIGN.md#architecture) |
| `uml-state.tex` | Unbound to Configured, and who drives each transition | [DESIGN.md](../DESIGN.md#enumeration-as-a-state-machine) |
| `uml-sequence.tex` | One key press, and why no release is ever sent | [DESIGN.md](../DESIGN.md#one-key-press) |
| `schematic.tex` | Two cables, and the second supply that must not exist | [DESIGN.md](../DESIGN.md#schematic) |
| `bench.tex` | What is on the desk, and why it is almost nothing | [DESIGN.md](../DESIGN.md#bench-layout) |
| `decision-tree.tex` | Five causes that all look like "the host sees nothing" | [BRINGUP.md](../BRINGUP.md#if-something-is-wrong) |

`preamble.tex` holds the palette and the styles. The colours carry
meaning and are the same in every figure, and here they mean **which side
of the cable**: the Pi's user space and kernel, the hardware, the host,
and one colour used only for endpoints, because endpoints are the scarce
thing this project is about.

`endpoint-budget.tex` is the one to read first. It is the constraint that
decides what the device can be, and the specification asks for it to be
written before the gadget is built and checked against `lsusb -v`
afterwards.

**Nothing in the build or the tests depends on TeX.** Every figure here is
also drawn in ASCII or mermaid inside the documents, so a reader without a
TeX installation loses the typesetting and none of the content. The PDFs
and PNGs are build products and are not tracked.

The requirement on Debian and Ubuntu is:

```sh
sudo apt-get install -y texlive-latex-extra texlive-pictures poppler-utils
```
