#!/usr/bin/env bash
# tests/test-static.sh — cheap sanity checks for the image definition.
# Not a gate on the base image: the tag is intentionally floating while we
# prototype.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

if [[ ! -f $repo_root/Containerfile ]]; then
  echo "FAIL Containerfile is missing" >&2
  failures=$((failures + 1))
elif ! grep -qx 'FROM ${BASE_IMAGE}' "$repo_root/Containerfile"; then
  echo "FAIL Containerfile does not build FROM \${BASE_IMAGE}" >&2
  failures=$((failures + 1))
else
  base=$(sed -n 's/^ARG BASE_IMAGE=//p' "$repo_root/Containerfile" | head -n 1)
  echo "ok   Containerfile builds FROM \${BASE_IMAGE} (${base:-unset})"
fi

manifest=$repo_root/manifests/packages-common.txt
if [[ ! -f $manifest ]]; then
  echo "FAIL manifests/packages-common.txt is missing" >&2
  failures=$((failures + 1))
else
  bad_lines=$(grep -nEv '^[[:space:]]*(#.*)?$|^[A-Za-z0-9][A-Za-z0-9+._-]*$' "$manifest" || true)
  if [[ -n $bad_lines ]]; then
    echo "FAIL packages-common.txt has non-package lines:"$'\n'"$bad_lines" >&2
    failures=$((failures + 1))
  else
    echo "ok   packages-common.txt is one package per line"
  fi
fi

desktop_unit=$repo_root/overlay/usr/lib/systemd/user/dux-atomic-desktop.service
defaults_unit=$repo_root/overlay/usr/lib/systemd/user/dux-atomic-dms-defaults.service
user_preset=$repo_root/overlay/usr/lib/systemd/user-preset/01-dux-atomic.preset
dms_binding=$repo_root/overlay/etc/systemd/user/niri.service.wants/dms.service
if [[ ! -f $desktop_unit ]] || ! grep -q '^ExecStart=/usr/bin/dms setup headless --compositor niri --terminal ghostty --skip-existing$' "$desktop_unit"; then
  echo "FAIL dux-atomic-desktop.service does not run dms setup headless" >&2
  failures=$((failures + 1))
elif [[ ! -f $defaults_unit ]]; then
  echo "FAIL dux-atomic-dms-defaults.service is missing" >&2
  failures=$((failures + 1))
elif [[ ! -L $dms_binding ]] || [[ $(readlink "$dms_binding") != /usr/lib/systemd/user/dms.service ]]; then
  echo "FAIL the image-level dms.service binding is missing" >&2
  failures=$((failures + 1))
elif [[ ! -f $user_preset ]]; then
  echo "FAIL the user preset is missing" >&2
  failures=$((failures + 1))
elif ! grep -qx 'enable dux-atomic-desktop.service' "$user_preset" ||
     ! grep -qx 'enable dux-atomic-dms-defaults.service' "$user_preset"; then
  echo "FAIL the user preset does not enable both first-login units" >&2
  failures=$((failures + 1))
elif ! grep -q 'systemctl --global preset dux-atomic-desktop.service dux-atomic-dms-defaults.service' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh does not apply the user preset" >&2
  failures=$((failures + 1))
else
  echo "ok   first-login desktop units are enabled through the user preset"
fi

if ((failures > 0)); then
  exit 1
fi
echo "static checks passed"
