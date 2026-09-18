# Project 3, host side. Runs on the Windows host, where the PPK2 is.
#
# CLOSE THE POWER PROFILER DESKTOP APP FIRST. It holds the serial port and
# ppk2_boot.py then fails with an access error that mentions neither the
# app nor the port.
#
#   make measure PORT=COM5 VARIANT=00-baseline N=6
#
# N IS SIX AND NOT FIVE ON PURPOSE. The specification asks for five boots
# per variant, and the first run of every variant is discarded by rule
# because a filesystem change can trigger a long fsck on the next mount.
# Six runs leave five measurements. Asking for five leaves four, which is
# the kind of quiet shortfall nobody notices until the standard deviations
# are being compared.

PORT    ?= COM5
N       ?= 6
VARIANT ?= 40-final
RESULTS ?= ../results
PYTHON  ?= python

# Ten seconds between boots, so the rails are down and the next run starts
# from the same state as the last one.
OFF_S ?= 10

.PHONY: measure analyze plot clean-variant

measure:
	mkdir -p $(RESULTS)/$(VARIANT)
	for i in $$(seq -w 1 $(N)); do \
	    $(PYTHON) ppk2_boot.py $(PORT) $(RESULTS)/$(VARIANT)/boot-$$i.csv || true; \
	    sleep $(OFF_S); \
	done
	$(MAKE) analyze VARIANT=$(VARIANT)

# "|| true" above is deliberate. ppk2_boot.py exits non-zero when the
# boot-complete marker never rose, which is a real outcome and not a reason
# to abandon the remaining runs. The run is kept, analyze.py discards it by
# name, and the discard appears in summary.md where it can be read.

analyze:
	$(PYTHON) analyze.py $(RESULTS)/$(VARIANT)

plot:
	$(PYTHON) analyze.py $(RESULTS)/$(VARIANT) --plot $(RESULTS)/$(VARIANT)/current.png

clean-variant:
	rm -f $(RESULTS)/$(VARIANT)/boot-*.csv $(RESULTS)/$(VARIANT)/summary.md
