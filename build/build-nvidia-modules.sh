#!/usr/bin/env bash
# build/build-nvidia-modules.sh — compile the NVIDIA akmod during the image
# build. The base's akmods.service carries ConditionPathExists=!/run/ostree-booted,
# and a bootc host is ostree-booted with /usr read-only, so the module cannot be
# built at first boot.

set -euo pipefail

mapfile -t kernels < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel | sort -V)
if ((${#kernels[@]} == 0)); then
  echo "no kernel is installed, so there is nothing for akmods to build" >&2
  exit 1
fi
kernel=${kernels[-1]}

# akmods warns when its log directory is absent and writes RPMs under /var/cache.
install -d /var/log/akmods /var/cache/akmods
akmods --force --kernels "$kernel"

bash "$(dirname -- "${BASH_SOURCE[0]}")/check-nvidia-modules.sh" "$kernel"
