# Figures

Seven drawings, each one file, each compiling on its own.

```sh
make            # every figure to PDF
make png        # and to PNG
make arch.pdf   # just one
```

| File | What it shows | Where it is also drawn in text |
|---|---|---|
| `arch.tex` | Two worlds, the monitor between them, and the inversion at the bottom | [DESIGN.md](../DESIGN.md#architecture) |
| `boot.tex` | The boot chain, from the GPU firmware to `/dev/tee0` | [DESIGN.md](../DESIGN.md#the-boot-chain) |
| `schematic.tex` | Three LEDs and the console | [DESIGN.md](../DESIGN.md#schematic) |
| `bench.tex` | What is on the table, and the two build paths on the host | [DESIGN.md](../DESIGN.md#bench-layout) |
| `uml-sequence.tex` | One signing call, including both RPCs | [DESIGN.md](../DESIGN.md#one-signing-call-as-a-sequence) |
| `uml-components.tex` | What is built where, and the contract that spans two machines | [DESIGN.md](../DESIGN.md#components-and-what-each-is-for) |
| `decision-tree.tex` | Where a failure lives, ordered by what each question costs | [DESIGN.md](../DESIGN.md#where-a-failure-lives) |

`preamble.tex` holds the palette and the styles. The colours carry
meaning and are the same in every figure: normal world user space, normal
world kernel, secure world, the EL3 monitor, hardware and files, and off
the board.

**Nothing in the build or the tests depends on TeX.** Every figure here is
also drawn in ASCII or mermaid inside the documents, so a reader without a
TeX installation loses the typesetting and none of the content. The PDFs
and PNGs are build products and are not tracked.

The requirement on Debian and Ubuntu is:

```sh
sudo apt-get install -y texlive-latex-extra texlive-pictures poppler-utils
```
