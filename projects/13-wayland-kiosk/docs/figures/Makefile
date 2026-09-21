# Render the figures.
#
#   make                 every figure to PDF
#   make png             and to PNG, for a README or a slide
#   make layer-tools.pdf just one
#
# Needs a TeX installation with tikz, circuitikz and standalone, which is
# texlive-latex-extra and texlive-pictures on Debian and Ubuntu. Nothing
# in the build or the test suite depends on this: the figures are drawn
# in ASCII and mermaid in the documents as well, so a reader with no TeX
# loses nothing but the typesetting.

FIGURES := arch layer-tools decision-tree schematic bench uml-sequence boot-budget
PDFS    := $(addsuffix .pdf,$(FIGURES))
PNGS    := $(addsuffix .png,$(FIGURES))

.PHONY: all png clean

all: $(PDFS)

png: $(PNGS)

%.pdf: %.tex preamble.tex
	pdflatex -interaction=nonstopmode -halt-on-error $< >/dev/null

# 200 dpi is legible in a browser and small enough to commit if it ever
# has to be. It normally does not: the PDFs and PNGs are not tracked.
%.png: %.pdf
	pdftoppm -png -r 200 -singlefile $< $*

clean:
	rm -f *.aux *.log *.pdf *.png
