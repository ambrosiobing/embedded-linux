SUMMARY = "The access point half of Project 18: hostapd, DHCP and an address"
DESCRIPTION = "An island network on wlan0. hostapd owns the BSS, a static \
systemd-networkd file owns the address, and dnsmasq hands out leases and \
answers no DNS because there is nothing to forward to. The SSID and the \
passphrase are read from the boot partition at every boot and written into \
a tmpfs, so no credential is in this repository or in the rootfs."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://bench-ap-setup \
    file://hostapd.conf.in \
    file://dnsmasq-ap.conf \
    file://10-bench-ap.network \
    file://bench-ap.tmpfiles.conf \
    file://chrony.conf \
    file://chrony-bench.conf \
    file://bench-ap-setup.service \
    file://bench-hostapd.service \
    file://bench-dnsmasq.service \
"

inherit systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

# scarthgap still unpacks into WORKDIR. On walnascar and later this becomes
# S = "${UNPACKDIR}", the same one line bench-lte and bench-tracker have to
# move when this repository moves release.
S = "${WORKDIR}"

do_install() {
    install -Dm0755 ${S}/bench-ap-setup ${D}${bindir}/bench-ap-setup

    # The template, not a configuration. bench-ap-setup fills it in and
    # writes the result to /run, because the result contains a passphrase
    # and /run is a tmpfs that does not survive into anybody's image copy.
    install -Dm0644 ${S}/hostapd.conf.in \
        ${D}${sysconfdir}/bench/hostapd.conf.in
    install -Dm0644 ${S}/dnsmasq-ap.conf \
        ${D}${sysconfdir}/bench/dnsmasq-ap.conf

    install -Dm0644 ${S}/10-bench-ap.network \
        ${D}${sysconfdir}/systemd/network/10-bench-ap.network

    install -Dm0644 ${S}/chrony.conf ${D}${sysconfdir}/bench/chrony.conf
    # A drop-in rather than a replacement unit, the same choice the broker
    # makes and for the same reason: the only change is which file is read.
    install -Dm0644 ${S}/chrony-bench.conf \
        ${D}${systemd_system_unitdir}/chronyd.service.d/bench.conf

    install -Dm0644 ${S}/bench-ap.tmpfiles.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/bench-ap.conf

    for unit in bench-ap-setup.service bench-hostapd.service \
            bench-dnsmasq.service; do
        install -Dm0644 ${S}/$unit ${D}${systemd_system_unitdir}/$unit
    done
}

FILES:${PN} += "\
    ${systemd_system_unitdir} \
    ${nonarch_libdir}/tmpfiles.d \
    ${sysconfdir}/bench \
    ${sysconfdir}/systemd/network \
"

CONFFILES:${PN} = "\
    ${sysconfdir}/bench/hostapd.conf.in \
    ${sysconfdir}/bench/dnsmasq-ap.conf \
"

# iw is here for a reason this project cannot do without, rather than as a
# debugging convenience. brcmfmac is a FullMAC driver, so whether this
# radio can be an access point at all is a property of the chip firmware,
# and `iw list` is how that question gets asked. A board that cannot ask it
# is a board where the answer is guessed.
#
# wireless-regdb and iw between them also decide whether the country code
# in the configuration means anything: without the database, hostapd's
# regulatory request has nothing to resolve against.
#
# chrony is here for certificates rather than for timekeeping, which is
# unusual enough to say twice. A station with no real-time clock powers up
# in 1970 and refuses the broker's certificate as not yet valid, with an
# error that mentions no clock at all. Both of this project's station
# clients, an ESP32 and an ESP8266, are in exactly that position. See
# files/chrony.conf and decision 111.
#
# NOT CONFIRMED: which layer provides chrony on the pinned revision. It is
# expected to be meta-networking, which kas/bench-ap.yml already pins for
# hostapd and mosquitto, but that has not been read on this laptop because
# the layers live on the WSL laptop. One command settles it:
#
#   ./go shell bench-ap
#   bitbake-layers show-recipes chrony
#
# If it turns out to be elsewhere, the fix is a layer line in the kas file
# rather than anything here.
RDEPENDS:${PN} += "\
    hostapd \
    dnsmasq \
    iw \
    wireless-regdb \
    chrony \
"

SYSTEMD_SERVICE:${PN} = "\
    bench-ap-setup.service \
    bench-hostapd.service \
    bench-dnsmasq.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
