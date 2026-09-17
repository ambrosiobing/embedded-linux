SUMMARY = "Netboot adjustments for the device under test"
DESCRIPTION = "The two things a diskless board needs in userspace that a \
card-booted one does not: a network configuration that does not take the \
root filesystem's own interface away from the kernel, and an fstab with no \
entry for a card that is not there. Project 4's DUT runs with no microSD \
card at all."
HOMEPAGE = "https://github.com/ambrosiobing/embedded-linux"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;\
md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://10-eth0-netboot.network"

inherit allarch features_check

REQUIRED_DISTRO_FEATURES = "systemd"

S = "${WORKDIR}"

do_install() {
    install -Dm0644 ${S}/10-eth0-netboot.network \
        ${D}${nonarch_libdir}/systemd/network/10-eth0-netboot.network
}

FILES:${PN} += "${nonarch_libdir}/systemd/network"

# systemd-networkd reads the file; nfs-utils gives the DUT the userspace
# tools to look at its own mount, which is the first thing anyone wants
# when a netbooted board misbehaves.
RDEPENDS:${PN} += "systemd nfs-utils-client"
