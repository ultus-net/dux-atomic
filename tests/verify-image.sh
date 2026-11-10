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
