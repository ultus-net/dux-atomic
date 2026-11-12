#!/usr/bin/env bash
# Run the built image's own lint and unit verification, then compare the
# installed third-party packages against manifests/packages-common.lock.
#
#   tests/verify-image.sh [image]

set -euo pipefail

image=${1:-localhost/dux-atomic:dev}
runtime=${CONTAINER_RUNTIME:-podman}
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

"$runtime" run --rm "$image" bootc container lint
"$runtime" run --rm "$image" systemd-analyze verify \
  /usr/lib/systemd/system/dux-atomic-greeter-defaults.service \
  /usr/lib/systemd/user/dux-atomic-desktop.service \
  /usr/lib/systemd/user/dux-atomic-dms-defaults.service
# The Fedora base carries no desktop, so every name in the manifest has to
# resolve in the built image. Query all of them in one call, so a silently
# dropped name fails here rather than at the first login, and a new manifest
# entry is covered without touching this script. Two entries are provides
# (dms-greeter, xinit), so query by whatprovides rather than package name.
packages=$(grep -Ev '^[[:space:]]*(#.*)?$' "$repo_root/manifests/packages-common.txt")
# shellcheck disable=SC2086 # Word splitting is intended: the manifest is one name per line.
if ! "$runtime" run --rm "$image" rpm -q --whatprovides $packages >/dev/null; then
  "$runtime" run --rm "$image" rpm -q --whatprovides $packages >&2 || true
  echo "FAIL a name from manifests/packages-common.txt does not resolve in the image" >&2
  exit 1
fi
# The Fedora base enables sshd.service, and this image documents that a fresh
# install has no console or SSH login. A base bump must not restore it.
state=$("$runtime" run --rm "$image" systemctl is-enabled sshd.service 2>&1 || true)
if [[ $state != disabled ]]; then
  echo "FAIL sshd.service is '${state}', expected disabled" >&2
  exit 1
fi
# Secure Boot needs no per-machine enrollment only while the base keeps Fedora's
# kernel and modules. The signature is the whole difference between that base
# and a base that ships its own signed kernel, so check the issuer here (#65).
"$runtime" run --rm -v "$repo_root:/mnt:ro" "$image" \
  bash /mnt/tests/verify-kernel-signature.sh
# xdg-desktop-portal reads /etc before /usr/share, so the override is what
# routes FileChooser to gtk instead of nautilus, which this image does not ship.
"$runtime" run --rm "$image" grep -qx \
  'org.freedesktop.impl.portal.FileChooser=gtk;' \
  /etc/xdg-desktop-portal/niri-portals.conf \
  || { echo "FAIL the file-chooser portal override is missing or wrong" >&2; exit 1; }
# Steam pulls the 32-bit graphics stack through its own dependencies, so this
# driver is not a manifest name and needs its own assertion.
"$runtime" run --rm "$image" rpm -q mesa-vulkan-drivers.i686 \
  || { echo "FAIL the 32-bit mesa Vulkan driver is not installed" >&2; exit 1; }
# The lock records the third-party packages the manifest names. Fedora packages
# move with the updates repository on every build, so only other vendors are
# compared; a drift there is a third-party rebuild and needs a lock update.
# The vendor string is package-controlled, so this is a drift signal rather
# than a provenance check; docs/known-gaps.md records the limitation. A +git
# build tracks an upstream branch, so it cannot be pinned; the generator leaves
# it out and the VM boot test covers a broken build.
lock=$repo_root/manifests/packages-common.lock
expected=$(grep -vE '^(#|$)' "$lock" | grep -vE $'\tFedora Project$' | grep -vF '+git' || true)
if [[ -z $expected ]]; then
  echo "FAIL the package lock has no third-party lines to compare" >&2
  exit 1
fi
# A nonzero status here means the generator or the image is broken, not that the
# lock drifted, so keep the two diagnoses apart. The filters run afterwards, so
# an empty third-party set reads as drift with a diff instead.
if ! raw=$(CONTAINER_RUNTIME=$runtime "$repo_root/build/package-lock.sh" "$image"); then
  echo "FAIL the lock measurement failed; the generator or the image is broken" >&2
  exit 1
fi
measured=$(grep -vE '^(#|$)' <<<"$raw" | grep -vE $'\tFedora Project$' | grep -vF '+git' || true)
if [[ $measured != "$expected" ]]; then
  echo "FAIL the third-party package lock drifted; run 'just lock'" >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$measured") >&2 || true
  exit 1
fi
