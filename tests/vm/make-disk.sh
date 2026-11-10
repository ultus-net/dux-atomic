#!/usr/bin/env bash
# Build a bootable qcow2 from a local image with bootc-image-builder.
#
# Must run as root, because bootc-image-builder writes loop devices:
#   sudo tests/vm/make-disk.sh [image] [output-dir]
#
# The image must be in rootful podman storage. Either build it with sudo
# podman, or copy it across:
#   podman save localhost/dux-atomic:dev | sudo podman load
#
# The base image ships no interactive user, so the disk is built with one test
# account for the login stage. Override it with TEST_USER and TEST_PASSWORD, or
# skip it with NO_TEST_USER=1. A production install creates the real account
# with useradd or the installer, never through this script.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
image=${1:-localhost/dux-atomic:dev}
out=${2:-$repo_root/output}
test_user=${TEST_USER:-dux}
test_password=${TEST_PASSWORD:-dux-test}
mkdir -p "$out"

if ! podman image exists "$image"; then
  echo "image $image is not in rootful podman storage" >&2
  echo "copy it in with: podman save $image | sudo podman load" >&2
  exit 2
fi

config_args=()
if [[ ${NO_TEST_USER:-0} != 1 ]]; then
  config_dir=$(mktemp -d)
  trap 'rm -rf "$config_dir"' EXIT
  cat >"$config_dir/config.toml" <<EOF
[[customizations.user]]
name = "$test_user"
password = "$test_password"
groups = ["wheel"]
EOF
  config_args+=(-v "$config_dir/config.toml:/config.toml:ro")
  echo "test account: $test_user / $test_password" >&2
fi

podman run --rm --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  "${config_args[@]}" \
  -v "$out:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  build "$image" --type qcow2 --rootfs btrfs --use-librepo=True --output /output \
  --chown "${SUDO_UID:-0}:${SUDO_GID:-0}"
