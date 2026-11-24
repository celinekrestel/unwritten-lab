#!/bin/bash
# Trust this image's signature inside secureblue's own container policy.
#
# BlueBuild's 'signing' module can't be used on secureblue. It looks for /etc/containers/policy.json,
# doesn't find it (since Fedora 45, secureblue keeps its policy in /usr/share/containers/) and
# creates one from its own template, which accepts unsigned images from any registry. That file
# would replace secureblue's strict policy completely, and 'ujust audit-secureblue' would fail.
set -euo pipefail

image="ghcr.io/celinekrestel/unwritten-lab"
policy="/usr/share/containers/policy.json"
key_cli="/etc/pki/containers/unwritten-lab.pub"   # The BlueBuild CLI copies cosign.pub there
key="/usr/share/pki/containers/unwritten-lab.pub"

test -f "${policy}"
test -f "${key_cli}"                               # Missing if cosign.pub isn't in the repository root
test ! -e /etc/containers/policy.json             # An override there would shadow secureblue's policy

command -v jq >/dev/null || dnf5 -y install jq

# The key goes next to secureblue's own keys under /usr, where it can't be changed on a machine.
install -D -m 0644 "${key_cli}" "${key}"
rm -f "${key_cli}"

jq --arg image "${image}" --arg key "${key}" \
    '.transports.docker[$image] = [{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}]' \
    "${policy}" > /tmp/policy.json
install -m 0644 /tmp/policy.json "${policy}"
rm -f /tmp/policy.json

# Where the signature lives, as BlueBuild's signing module would set it up.
cat > /etc/containers/registries.d/unwritten-lab.yaml <<EOF
docker:
  ${image}:
    use-sigstore-attachments: true
EOF

# Stop the build unless secureblue's default ('reject') and the new entry are both in place.
jq -e --arg image "${image}" \
    '.default[0].type == "reject" and (.transports.docker[$image] | length == 1)' "${policy}"
