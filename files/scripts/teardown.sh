#!/bin/bash
# Take out what secureblue's IoT image carries for servers and edge devices.
# Every removal is guarded, so the build keeps going if secureblue changes its package list.
# The log says what was removed and what wasn't there.
#
# dnf can't clean up dependencies here: secureblue deletes dnf's records of why a package was
# installed (its files/scripts/libdnf5-clear-history.sh), as the Fedora base images do. So the
# lists below name the leftovers too, like the 'DNF removals' in Unwritten's recipe.yml.
set -euo pipefail

installed_matching() {
    rpm -qa --qf '%{NAME}\n' "$@" | sort -u
}

remove_present() {
    local present=() pkg
    for pkg in "$@"; do
        if rpm -q --quiet "${pkg}"; then
            present+=("${pkg}")
        else
            echo "Not installed, skipped: ${pkg}"
        fi
    done
    if [[ ${#present[@]} -gt 0 ]]; then
        dnf5 -y remove "${present[@]}"
    fi
}

# Virtualization and Docker from secureblue's common layer (its recipes/common/common-packages.yml),
# with what they pull in: VM firmware, TPM emulation, storage back ends for VMs.
# Toolbox goes too. Stays: distrobox, podman and its helpers (passt, crun, container-selinux),
# and xorriso if virt-install brought it along, because it can burn Blu-ray discs.
mapfile -t virt < <(installed_matching 'libvirt*' 'qemu-*' 'glusterfs*' 'moby-engine*' 'docker-*')
remove_present "${virt[@]}" \
    virt-install virt-manager-common python3-libvirt libosinfo osinfo-db osinfo-db-tools \
    podman-machine gvisor-tap-vsock virtiofsd edk2-ovmf seabios-bin seavgabios-bin ipxe-roms-qemu \
    swtpm swtpm-libs swtpm-tools libtpms librbd1 librados2 libiscsi libblkio \
    iscsi-initiator-utils iscsi-initiator-utils-iscsiuio \
    containerd rootlesskit tini-static \
    toolbox

# From Fedora IoT: the SSH server, greenboot (health checks that roll back after failed boots),
# and device onboarding, where present.
mapfile -t greenboot < <(rpm -qa --qf '%{NAME}\n' 'greenboot*')
remove_present openssh-server "${greenboot[@]}" fdo-client fdo-init zezere parsec

# secureblue's server profile (its files/system/server and recipes/common/server-modules.yml):
# - bash-timeout.sh sets TMOUT=300. zsh honours it too, so idle terminals would close after 5 minutes.
# - 56-server-hardening.conf turns TCP SACK off, which costs throughput on lossy links (Wi-Fi, VPN).
# - FedoraServer.xml is the server firewall zone, with SSH open.
rm -f /etc/profile.d/bash-timeout.sh /usr/lib/sysctl.d/56-server-hardening.conf /etc/firewalld/zones/FedoraServer.xml
if ! rpm -q --quiet openssh-server; then
    rm -f /etc/ssh/sshd_config.d/30-hardening.conf
fi

# The firewall zone of secureblue's desktop images instead: no services at all, not even DHCPv6
# (Unwritten keeps that one open). The zone file is already in the image.
test -f /etc/firewalld/zones/FedoraWorkstation.xml
sed -i 's/^DefaultZone=.*/DefaultZone=FedoraWorkstation/' /etc/firewalld/firewalld.conf
grep -qx 'DefaultZone=FedoraWorkstation' /etc/firewalld/firewalld.conf
