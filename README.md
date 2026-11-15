# Unwritten Lab

*Unwritten on top of secureblue's hardened IoT image. An experiment.*

## What this is

[Unwritten](https://github.com/celinekrestel/unwritten) builds a lean GNOME desktop from the minimal fedora-bootc image. This lab asks whether it can stay that lean and still get [secureblue](https://secureblue.dev)'s security core.

secureblue's `iot-main-hardened` image has no desktop, but it already carries that core: secureblue's kernel and kernel arguments, its sysctl settings and module blocklist, all of its SELinux modules (including those for Flatpak and user namespaces), the patched `bwrap`, hardened_malloc, NTS time, PAM hardening, no SUID files and no `sudo`. The lab adds GNOME piece by piece, as Unwritten does, and takes out what secureblue adds for servers.

> [!WARNING]
> Not for daily use. secureblue tests GNOME only on its Silverblue images, not on top of its IoT image. Test on a spare disk.

## How it differs from Unwritten

| | Unwritten | Lab |
| --- | --- | --- |
| Base | fedora-bootc 45 | secureblue `iot-main-hardened` 45 |
| Kernel | Fedora's | secureblue's, with its own Secure Boot key |
| Hardening | a few sysctl settings and module blocks | secureblue's, see above |
| Time | systemd-timesyncd | chrony with NTS |
| DNS | systemd-resolved | Unbound; `ujust dns-selector resolver resolved` for the WireGuard profiles |
| Flatpaks | system-wide | per user, with hardened_malloc |
| Updates | manual | automatic, as secureblue sets it up |

The kill switch, btrbk, the `run0` wrapper and Unwritten's GNOME settings are copies of Unwritten's files in `files/system`. A change in Unwritten has to be made here too.

**Taken out** (`files/scripts/`):

- `teardown.sh`: virtualization and Docker (libvirt, QEMU, moby, containerd), toolbox, the SSH server, greenboot, and secureblue's server profile (idle shells closed after five minutes, TCP SACK off, SSH open in the firewall). The firewall uses secureblue's desktop zone, with no services at all.
- `lean.sh`: the leftovers Unwritten also removes, as far as they exist here.

**Ported from secureblue's desktop images:**

- Flatpak hardening (`usr/libexec/unwritten/flatpak-setup`): once per user, Flathub becomes a user remote and every Flatpak gets hardened_malloc; Steam is exempt. `flatpak-system-helper` is masked.
- Service masks: bluetooth, geoclue, ModemManager, avahi, sssd, iscsi, thermald and a few more. cups stays.
- GNOME defaults (`zz2-secureblue-defaults.gschema.override`): no extension installs from the web, no automount, no thumbnails.

**Not ported:** Trivalent, the Xwayland switch, USBGuard, Homebrew, Bazaar, the codecs and secureblue's update notifications.

**Known gaps:**

- `gstreamer1-plugin-openh264` is missing: secureblue removes Fedora's openh264 repository, so GNOME screencasts are saved as .webm.
- secureblue's desktop zone doesn't open DHCPv6. Check that IPv6 works.
- `rootflags=subvol=root,compress=zstd:1` isn't set, because it depends on the disk layout.
- `ujust audit-secureblue` reads `IMAGE_ID`, takes this image for an IoT image and skips its desktop checks.
- dnf can't remove leftover dependencies here (secureblue deletes dnf's install records), so the scripts name them.

## Setting up signing (once)

The lab has its own key, separate from Unwritten's.

1. In the repository root, create a key pair without a passphrase (GitHub Actions can't use an encrypted key):

   ```shell
   skopeo generate-sigstore-key --output-prefix cosign --passphrase-file /dev/null
   ```

   This writes `cosign.pub` and `cosign.private`. `.gitignore` keeps `cosign.private` out of Git.
2. On GitHub, create the repository `unwritten-lab`, empty.
3. Settings → Environments → New environment `signing`. Deployment branches: `main` only. Add the environment secret `SIGNING_SECRET` with the contents of `cosign.private`.
4. Keep `cosign.private` in your password manager, then delete the local file.
5. Commit `cosign.pub` and push `main`. Without `cosign.pub` the build stops on purpose (`signing-policy.sh`).
6. After the first build, check that the package `unwritten-lab` is public (Package settings). Built from this public repository, it was public right away. If it's private, change its visibility, or machines can't pull it without credentials.

## Testing on a spare disk

secureblue's container policy rejects every image it doesn't list, and `bootc` follows that policy even without `--enforce-container-sigpolicy`. So before the switch, the test machine trusts the lab's key, for the lab image only, through three temporary files. That makes the first switch a signed one, too.

1. Before you boot the spare disk, note the key's checksum, in this repository's root:

   ```shell
   sha256sum cosign.pub
   ```

2. Install secureblue's GNOME image from its ISO, including its post-install steps (Secure Boot: `ujust enroll-secure-boot-keys`, then the password `secureblue` on the blue MOK screen). Or use an existing secureblue installation.
3. Open a root shell. Stock secureblue has no `run0` wrapper like Unwritten's, so its FAQ says `run0 -i` (because of exit code 203). Steps 4 to 7 run in this shell.

   ```shell
   run0 -i
   ```

4. Pin the current deployment, so it stays in the boot menu:

   ```shell
   ostree admin pin 0
   ```

5. Create the three files. `/etc/containers/policy.json` mustn't exist yet; secureblue keeps its policy in `/usr/share/containers/`.

   ```shell
   ls /etc/containers/policy.json   # Must say "No such file or directory"
   mkdir -p /etc/pki/containers /etc/containers/registries.d
   curl -fsSLo /etc/pki/containers/unwritten-lab-bootstrap.pub https://raw.githubusercontent.com/celinekrestel/unwritten-lab/main/cosign.pub
   sha256sum /etc/pki/containers/unwritten-lab-bootstrap.pub   # Must match step 1
   ```

   The policy accepts the lab image signed with this key, and nothing else:

   ```shell
   cat > /etc/containers/policy.json <<'EOF'
   {
       "default": [{"type": "reject"}],
       "transports": {
           "docker": {
               "ghcr.io/celinekrestel/unwritten-lab": [
                   {
                       "type": "sigstoreSigned",
                       "keyPath": "/etc/pki/containers/unwritten-lab-bootstrap.pub",
                       "signedIdentity": {"type": "matchRepository"}
                   }
               ]
           }
       }
   }
   EOF
   ```

   The signature is stored next to the image in the registry, and this file tells bootc to look for it there. The lab image brings the same setting as `/etc/containers/registries.d/unwritten-lab.yaml`, written by `signing-policy.sh`:

   ```shell
   cat > /etc/containers/registries.d/unwritten-lab-bootstrap.yaml <<'EOF'
   docker:
     ghcr.io/celinekrestel/unwritten-lab:
       use-sigstore-attachments: true
   EOF
   ```

6. Switch. bootc checks the signature before it downloads the layers, and nothing from the image runs before the reboot:

   ```shell
   bootc switch --enforce-container-sigpolicy ghcr.io/celinekrestel/unwritten-lab:latest
   ```

   If `bootc` refuses because of layered packages: `rpm-ostree rebase ostree-image-signed:docker://ghcr.io/celinekrestel/unwritten-lab:latest`
7. Remove the three files and leave the root shell. The new deployment takes over this `/etc` only when the machine shuts down, so it starts without them and uses the lab image's own policy:

   ```shell
   rm /etc/containers/policy.json /etc/containers/registries.d/unwritten-lab-bootstrap.yaml /etc/pki/containers/unwritten-lab-bootstrap.pub
   exit
   ```

   If the machine rebooted before this step, run the `rm` on the lab system. Until then, image updates fail there, because two registries.d files name the same image.
8. Reboot.
9. Check the switch: `rpm-ostree status` shows the image as `ostree-image-signed:docker://ghcr.io/celinekrestel/unwritten-lab:latest`, and `run0 -i bootc upgrade --check` checks the signature again, now against the lab image's own policy.
10. `ujust audit-secureblue`

What to look at:

- `rpm -qa | wc -l` (Unwritten: 1021), `find /usr -perm /6000`, `cat /proc/cmdline`
- `systemctl list-unit-files --state=enabled`
- `flatpak override --user --show` and `modinfo xpad` (8BitDo controller)
- WireGuard and the kill switch, after `ujust dns-selector resolver resolved`
- Steam, printing, IPv6
- Blu-ray: secureblue blocks `sr_mod`, `cdrom` and `udf`; `ujust override-enable-module` brings each one back

## Undoing

- Test machine: boot the pinned entry, or `run0 -i bootc rollback`. Then `run0 -i ostree admin pin --unpin <index>`. If secureblue still has the three files from step 5 (step 7 skipped), remove them there too, or they keep shadowing secureblue's policy.
- Everything else: delete this repository and the package `unwritten-lab`. Unwritten itself never changes.

If the lab works out, its result goes into Unwritten in one commit, signed with Unwritten's key again.

## Credits

The lab builds on [secureblue](https://github.com/secureblue/secureblue) (Apache-2.0). `files/scripts/removesuid.sh` is copied from secureblue unchanged. `flatpak-setup`, the service masks and the GNOME defaults follow secureblue's desktop images.
