#!/usr/bin/env bash
# Build and verify exactly one thin flavor on top of the pre-built common image.
# Called on the same runner for PR smoke tests and by separate DX/Deck CI jobs.
set -euo pipefail

flavor="${1:?Usage: bash scripts/ci-build-flavor.sh dx|deck}"
case "$flavor" in dx|deck) ;; *) echo "Invalid flavor: $flavor" >&2; exit 1 ;; esac

image=$(jq -er --arg flavor "$flavor" '.[] | select(.flavor == $flavor) | .image' config/variants.json)
common="localhost/cachyos-bazzite-common:build"
target="localhost/$image:build"

sudo podman image exists "$common"
sudo podman build --layers --pull=never \
  --build-arg "COMMON_IMAGE=$common" \
  --build-arg "TARGET_FLAVOR=$flavor" \
  --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY" \
  --label "org.opencontainers.image.title=$image" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --label "org.opencontainers.image.revision=$GITHUB_SHA" \
  --label "org.opencontainers.image.version=latest" \
  --label "io.darkphilosophy.build-inputs=${FINGERPRINT:-}" \
  --label "containers.bootc=1" \
  -f Containerfile -t "$target" .

# Check real artifact contents, not just static YAML assertions.
shared_rev=$(sudo podman image inspect "$target" | jq -er '.[0].Labels["io.darkphilosophy.shared-stage"]')
if [[ "$shared_rev" != "$GITHUB_SHA" ]]; then
  echo "::error::$flavor does not inherit the common image of this run" >&2
  exit 1
fi
sudo podman run --rm --entrypoint /usr/bin/bash "$target" -euo pipefail -c '
  rpm -q kernel-cachyos ublue-setup-services >/dev/null
  ! rpm -q fw-fanctrl >/dev/null 2>&1 || exit 1
  test -f /etc/pki/containers/darkphilosophy.pub
  test -e /usr/lib/systemd/system/ksmd.service
  systemd-sysusers --cat-config docker.conf | grep -Fx "g docker - -" >/dev/null
'
if [[ "$flavor" == "dx" ]]; then
  sudo podman run --rm --entrypoint /usr/bin/bash "$target" -euo pipefail -c '
    rpm -q gdm >/dev/null
    ! rpm -q sddm >/dev/null 2>&1
    ! rpm -q steam >/dev/null 2>&1
  '
else
  sudo podman run --rm --entrypoint /usr/bin/bash "$target" -euo pipefail -c '
    test -d /usr/share/gamescope-session-plus
    rpm -q steam >/dev/null
  '
fi
echo "::notice::Verified $flavor from common revision $shared_rev"
