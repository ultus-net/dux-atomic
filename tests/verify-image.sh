#!/usr/bin/env bash
# Run the built image's own lint and unit verification.
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
# The lock records the third-party packages this image resolves. Fedora packages
# move with the updates repository on every build, so only other vendors are
# compared; a drift there is a third-party rebuild and needs a lock update.
lock=$repo_root/manifests/packages-common.lock
expected=$(grep -vE '^(#|$)' "$lock" | grep -vE $'\tFedora Project$')
measured=$(CONTAINER_RUNTIME=$runtime "$repo_root/build/package-lock.sh" "$image" |
  grep -vE '^(#|$)' | grep -vE $'\tFedora Project$')
if [[ $measured != "$expected" ]]; then
  echo "FAIL the third-party package lock drifted; run 'just lock'" >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$measured") >&2 || true
  exit 1
fi
