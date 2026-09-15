# One firmware file, packaged, because poky does not package it.
#
# The bench's second uplink is a TP-Link TL-WN823N v2/v3, USB 2357:0109, a
# Realtek RTL8192EU driven by the in-tree rtl8xxxu. That driver asks for
# rtlwifi/rtl8192eu_nic.bin.
#
# poky's linux-firmware recipe splits out rtl8188, rtl8192cu, rtl8192ce,
# rtl8192su, rtl8723, rtl8821 and rtl8822, and nothing claims the 8192eu
# file. So it falls into the catch-all ${PN} package, which is every
# firmware blob for every device Linux supports: hundreds of megabytes on a
# board that has two radios and a modem.
#
# Splitting it out is what a layer is for. PACKAGES =+ puts the new package
# ahead of the catch-all so that it claims the file first; the other way
# round it would be an empty package and a rootfs full of firmware for
# hardware nobody owns.
#
# The licence is the same Realtek redistribution notice the sibling
# packages carry, and the notice file itself lives in ${PN}-rtl-license.

PACKAGES =+ "${PN}-rtl8192eu"

LICENSE:${PN}-rtl8192eu = "Firmware-rtlwifi_firmware"

FILES:${PN}-rtl8192eu = " \
    ${nonarch_base_libdir}/firmware/rtlwifi/rtl8192eu_nic.bin \
"

RDEPENDS:${PN}-rtl8192eu += "${PN}-rtl-license"
