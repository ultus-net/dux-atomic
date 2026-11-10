#!/usr/bin/env bash
# Run the built image's own lint and unit verification.
#
#   tests/verify-image.sh [image]

set -euo pipefail

image=${1:-localhost/dux-atomic:dev}
runtime=${CONTAINER_RUNTIME:-podman}

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
