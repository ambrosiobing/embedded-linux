SUMMARY = "Gateway configuration for the bench router"
DESCRIPTION = "Everything about the routing box that is configuration \
rather than code: two NetworkManager uplink profiles with different route \
metrics, an access-point profile, the connectivity check, one nftables file \
holding the whole packet path, DHCP for the bench LAN, the ModemManager \
port filter and stable names for the modem's serial ports."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://eth0-uplink.nmconnection \
    file://lte.nmconnection.in \
    file://bench-ap.nmconnection.in \
    file://wan-wifi.nmconnection.in \
    file://connectivity.conf \
    file://bench-lan.conf \
    file://nftables.conf \
    file://90-forward.conf \
    file://ModemManager.conf \
    file://76-bench-uplink.rules \
    file://77-sim7600.rules \
    file://bench-router-setup \
    file://bench-router-setup.service \
    file://bench-router-nft.service \
    file://bench-router-dhcp.service \
"

inherit allarch systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

S = "${WORKDIR}"

do_install() {
    # NetworkManager refuses to read a keyfile that anyone but root can
    # read, and says so only in its log, so the mode is not cosmetic.
    install -Dm0600 ${S}/eth0-uplink.nmconnection \
        ${D}${sysconfdir}/NetworkManager/system-connections/eth0-uplink.nmconnection

    install -Dm0644 ${S}/connectivity.conf \
        ${D}${sysconfdir}/NetworkManager/conf.d/10-connectivity.conf

    # The two profiles that carry identity stay templates in the image.
    # bench-router-setup instantiates them on first boot from the card.
    install -Dm0644 ${S}/lte.nmconnection.in \
        ${D}${datadir}/bench-router/lte.nmconnection.in
    install -Dm0644 ${S}/bench-ap.nmconnection.in \
        ${D}${datadir}/bench-router/bench-ap.nmconnection.in
    install -Dm0644 ${S}/wan-wifi.nmconnection.in \
        ${D}${datadir}/bench-router/wan-wifi.nmconnection.in

    install -Dm0644 ${S}/nftables.conf ${D}${sysconfdir}/bench/nftables.conf
    install -Dm0644 ${S}/bench-lan.conf ${D}${sysconfdir}/bench/dnsmasq.conf

    install -Dm0644 ${S}/90-forward.conf \
        ${D}${sysconfdir}/sysctl.d/90-forward.conf

    install -Dm0644 ${S}/ModemManager.conf \
        ${D}${sysconfdir}/ModemManager/ModemManager.conf

    install -Dm0644 ${S}/76-bench-uplink.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/76-bench-uplink.rules
    install -Dm0644 ${S}/77-sim7600.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/77-sim7600.rules

    install -Dm0755 ${S}/bench-router-setup ${D}${bindir}/bench-router-setup

    for unit in bench-router-setup bench-router-nft bench-router-dhcp; do
        install -Dm0644 ${S}/$unit.service \
            ${D}${systemd_system_unitdir}/$unit.service
    done

    # Two masks, both of which would otherwise fight NetworkManager for an
    # interface. systemd-networkd is enabled in this distro and would claim
    # wlan0 while NetworkManager is trying to run an access point on it;
    # the packaged dnsmasq.service would bind port 53 on every address.
    # Masking in the image rather than in a first-boot script means the
    # state is visible in the package manifest.
    install -d ${D}${sysconfdir}/systemd/system
    for masked in systemd-networkd.service systemd-networkd.socket \
            dnsmasq.service; do
        ln -sf /dev/null ${D}${sysconfdir}/systemd/system/$masked
    done
}

FILES:${PN} += "\
    ${sysconfdir}/NetworkManager \
    ${sysconfdir}/ModemManager \
    ${sysconfdir}/bench \
    ${sysconfdir}/sysctl.d \
    ${sysconfdir}/systemd/system \
    ${datadir}/bench-router \
    ${nonarch_base_libdir}/udev/rules.d \
    ${systemd_system_unitdir} \
"

CONFFILES:${PN} = "\
    ${sysconfdir}/bench/nftables.conf \
    ${sysconfdir}/bench/dnsmasq.conf \
    ${sysconfdir}/NetworkManager/conf.d/10-connectivity.conf \
    ${sysconfdir}/ModemManager/ModemManager.conf \
"

# The services this configuration is configuration for. Naming them here
# rather than only in the image means the recipe is not silently useless
# if someone installs it into an image of their own.
RDEPENDS:${PN} += "networkmanager modemmanager dnsmasq nftables"

SYSTEMD_SERVICE:${PN} = "\
    bench-router-setup.service \
    bench-router-nft.service \
    bench-router-dhcp.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
