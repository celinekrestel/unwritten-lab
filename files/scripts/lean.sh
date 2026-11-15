#!/bin/bash
# The leftovers Unwritten's recipe.yml removes from fedora-bootc ('DNF removals'), as far as they
# exist here. Guarded like teardown.sh, so a missing package is skipped, not an error.
#
# Left alone on purpose:
# - clevis, tpm2-*, lvm2, device-mapper-* and dracut-*: secureblue's initramfs configuration asks
#   for some of them, and dracut stops when a requested module is missing.
# - sssd: PAM stays safe until the authselect profile here is known.
set -euo pipefail

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

remove_present \
    yelp yelp-libs yelp-xsl \
    nfs-utils nfsv3-client-utils nfsv4-client-utils nfs-common-utils rpcbind gssproxy libnfsidmap quota quota-nls \
    sos python3-boto3 python3-botocore python3-s3transfer python3-jmespath \
    atheros-firmware brcmfmac-firmware cirrus-audio-firmware intel-audio-firmware intel-gpu-firmware \
    intel-npu-firmware microcode_ctl nvidia-gpu-firmware nxpwireless-firmware qcom-wwan-firmware \
    realtek-firmware tiwilink-firmware \
    fwupd-plugin-modem-manager fwupd-plugin-uefi-capsule-data libmbim libqmi libqrtr-glib passim \
    NetworkManager-cloud-setup WALinuxAgent-udev chunkah cloud-utils-growpart criu criu-libs \
    kdump-utils kexec-tools makedumpfile net-tools sg3_utils sg3_utils-libs socat stalld \
    7zip 7zip-standalone-all
