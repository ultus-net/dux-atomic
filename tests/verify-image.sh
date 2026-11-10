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
# Steam pulls the 32-bit graphics stack; assert the client and its Vulkan driver.
"$runtime" run --rm "$image" rpm -q steam \
  || { echo "FAIL steam is not installed" >&2; exit 1; }
"$runtime" run --rm "$image" rpm -q mesa-vulkan-drivers.i686 \
  || { echo "FAIL the 32-bit mesa Vulkan driver is not installed" >&2; exit 1; }
# The rest of the gaming group is named explicitly, so a base change that drops
# one of them fails here instead of at the first game launch.
for package in gamescope mangohud steam-devices; do
  "$runtime" run --rm "$image" rpm -q "$package" \
    || { echo "FAIL $package is not installed" >&2; exit 1; }
done
# The lock records the third-party packages the manifest names. Fedora packages
# move with the updates repository on every build, so only other vendors are
# compared; a drift there is a third-party rebuild and needs a lock update.
# The vendor string is package-controlled, so this is a drift signal rather
# than a provenance check; docs/known-gaps.md records the limitation.
lock=$repo_root/manifests/packages-common.lock
expected=$(grep -vE '^(#|$)' "$lock" | grep -vE $'\tFedora Project$' || true)
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
measured=$(grep -vE '^(#|$)' <<<"$raw" | grep -vE $'\tFedora Project$' || true)
if [[ $measured != "$expected" ]]; then
  echo "FAIL the third-party package lock drifted; run 'just lock'" >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$measured") >&2 || true
  exit 1
fi
