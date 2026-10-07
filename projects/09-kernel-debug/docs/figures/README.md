# Figures

Eight drawings, each one file, each compiling on its own.

```sh
make                    # every figure to PDF
make png                # and to PNG
make fault-matrix.pdf   # just one
```

| File | What it shows | Where it is also drawn in text |
|---|---|---|
| `arch.tex` | One serial line, two consumers, and the proxy that makes that work | [DESIGN.md](../DESIGN.md#architecture) |
| `fault-matrix.tex` | Four faults against six tools, and the silence in three of the rows | [DESIGN.md](../DESIGN.md#the-fault-matrix) |
| `decision-tree.tex` | Given a symptom rather than a known fault, what to reach for | [DESIGN.md](../DESIGN.md#which-tool-when) |
| `schematic.tex` | Two wires, an LED, and the two ways to get the UART wrong | [DESIGN.md](../DESIGN.md#schematic) |
| `bench.tex` | What is on the table, and why two paths to the board are needed | [DESIGN.md](../DESIGN.md#bench-layout) |
| `uml-sequence.tex` | The same crash captured twice: after the fact, then live | [DESIGN.md](../DESIGN.md#a-crash-captured-twice) |
| `uml-components.tex` | What is built where, including the two firsts for this layer | [DESIGN.md](../DESIGN.md#components-and-what-is-new-here) |
| `uart-mux.tex` | Three bits decide which UART is on pins 8 and 10, and the reset value is neither | [hardware.md](../hardware.md) |

## Recordings

| File | What it shows | Referenced from |
|---|---|---|
| `heartbeat.gif` | The heartbeat LED beating, two periods, 240x210 at 15 fps | [BRINGUP.md](../BRINGUP.md#5-check-the-heartbeat) |

This one is evidence rather than a drawing, so unlike the PDFs and PNGs
below it is tracked. It is cut from an 11 s recording made on Sunday 4
October 2026 and cropped to the module; the recording itself is not in
the repository. Both were measured the same way and agree: two flashes
of about 100 ms, 0.30 s apart, repeating every 1.22 s in the source and
1.23 s in the GIF. The clip is a whole number of periods, so the loop
has no visible join and the pause reads as part of the pattern.

## On copying from vendor documents

**No figure here reproduces a drawing from a datasheet or a vendor page.**
`uart-mux.tex` is the clearest case: the facts in it come from four tables
in the Broadcom document, and the drawing is an original arrangement of
those facts showing one path through them, with the source named in the
figure itself and in its source comment.

That is a licensing point and also a better drawing. A vendor's table
answers every question at once; a figure here answers the one question the
surrounding text is asking. Cite the original by document, publisher,
date, table and page so a reader can go and check, and draw your own.

`preamble.tex` holds the palette and the styles. The colours carry
meaning and are the same in every figure: target user space, target
kernel, host, a debugging tool, hardware and files, and the grey used for
a fault that produces no symptom.

`fault-matrix.tex` is the one to read first. It is the argument for the
whole project: only one of the four faults announces itself, so the other
three have to be prepared for before they happen.

**Nothing in the build or the tests depends on TeX.** Every figure here is
also drawn in ASCII or mermaid inside the documents, so a reader without a
TeX installation loses the typesetting and none of the content. The PDFs
and PNGs are build products and are not tracked.

The requirement on Debian and Ubuntu is:

```sh
sudo apt-get install -y texlive-latex-extra texlive-pictures poppler-utils
```
