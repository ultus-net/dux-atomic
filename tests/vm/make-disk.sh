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

with_test_user=1
if [[ ${NO_TEST_USER:-0} == 1 ]]; then
  with_test_user=0
fi

if ((with_test_user)); then
  case "$test_user$test_password" in
    *'"'* | *'\'* | *$'\n'*)
      echo "TEST_USER and TEST_PASSWORD must not contain quotes, backslashes, or newlines" >&2
      exit 2
      ;;
  esac
fi

# TCG boots on a shared runner can run at half speed, and udev then misses
# systemd's 45s device timeout before /boot appears. Raise the timeout on the
# test disk only, so the shipped image keeps the stock value. The serial console
# karg lives here for the same reason: a production install gets no serial getty.
config_dir=$(mktemp -d)
trap 'rm -rf "$config_dir"' EXIT
{
  echo '[customizations.kernel]'
  echo 'append = "systemd.default_device_timeout_sec=180 console=ttyS0,115200"'
  if ((with_test_user)); then
    echo '[[customizations.user]]'
    printf 'name = "%s"\n' "$test_user"
    printf 'password = "%s"\n' "$test_password"
  fi
} >"$config_dir/config.toml"
config_args=(-v "$config_dir/config.toml:/config.toml:ro")
if ((with_test_user)); then
  echo "test account: $test_user (no admin groups)" >&2
fi

# Pin the builder by digest so a moving :latest cannot change the disk output.
# Bump this deliberately; the digest is the manifest this repo was tested with.
bib_image=${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder@sha256:a0ee98db5bfb8337e45efb92f0c5d1a19179c85ce80a3360abc628fd1a17cc5c}

# Podman accepts the SELinux label only on an SELinux host; Ubuntu runners do
# not have it, so pass it conditionally.
security_args=()
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  security_args+=(--security-opt label=type:unconfined_t)
fi

podman run --rm --privileged \
  "${security_args[@]}" \
  "${config_args[@]}" \
  -v "$out:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  "$bib_image" \
  build "$image" --type qcow2 --rootfs btrfs --use-librepo=True --output /output \
  --chown "${SUDO_UID:-0}:${SUDO_GID:-0}"
