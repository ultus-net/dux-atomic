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
dms_binding=$repo_root/overlay/usr/lib/systemd/user/niri.service.wants/dms.service
seed_source=$repo_root/overlay/usr/share/dux-atomic/dms/session.json
if [[ ! -f $desktop_unit ]] || ! grep -qx 'ExecStart=/usr/bin/dms setup headless --compositor niri --terminal ghostty --skip-existing' "$desktop_unit"; then
  echo "FAIL dux-atomic-desktop.service does not run dms setup headless" >&2
  failures=$((failures + 1))
elif ! grep -qx 'TimeoutStartSec=120' "$desktop_unit"; then
  echo "FAIL dux-atomic-desktop.service has no start timeout" >&2
  failures=$((failures + 1))
elif ! grep -qx 'ConditionUser=!root' "$desktop_unit" ||
     ! grep -qx 'ConditionUser=!greeter' "$desktop_unit" ||
     ! grep -qx 'Before=graphical-session-pre.target' "$desktop_unit"; then
  echo "FAIL dux-atomic-desktop.service is not ordered or can run as root/greeter" >&2
  failures=$((failures + 1))
elif [[ ! -f $defaults_unit ]] ||
     ! grep -qx 'ExecStart=/usr/bin/install -Dm0644 /usr/share/dux-atomic/dms/session.json %S/dms/session.json' "$defaults_unit"; then
  echo "FAIL dux-atomic-dms-defaults.service does not seed the session file" >&2
  failures=$((failures + 1))
elif ! grep -qx 'ConditionUser=!root' "$defaults_unit" ||
     ! grep -qx 'ConditionUser=!greeter' "$defaults_unit" ||
     ! grep -qx 'Before=graphical-session-pre.target' "$defaults_unit"; then
  echo "FAIL dux-atomic-dms-defaults.service is not ordered or can run as root/greeter" >&2
  failures=$((failures + 1))
elif [[ ! -f $seed_source ]] || ! grep -q '"wallpaperPath": "#101418"' "$seed_source"; then
  echo "FAIL the DMS session seed is missing or has no dark background" >&2
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
elif ! grep -qx 'systemctl --global preset dux-atomic-desktop.service dux-atomic-dms-defaults.service' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh does not apply the user preset" >&2
  failures=$((failures + 1))
else
  echo "ok   first-login desktop units are enabled through the user preset"
fi

greeter_unit=$repo_root/overlay/usr/lib/systemd/system/dux-atomic-greeter-defaults.service
greeter_seed=$repo_root/overlay/usr/share/dux-atomic/greeter/memory.json
greeter_wants=$repo_root/overlay/usr/lib/systemd/system/greetd.service.wants/dux-atomic-greeter-defaults.service
if [[ ! -f $greeter_unit ]] ||
   ! grep -qx 'ExecStart=/usr/bin/install -m 0644 -o greeter -g greeter /usr/share/dux-atomic/greeter/memory.json /var/cache/dms-greeter/.local/state/memory.json' "$greeter_unit"; then
  echo "FAIL dux-atomic-greeter-defaults.service does not seed the greeter memory" >&2
  failures=$((failures + 1))
elif ! grep -qx 'Before=greetd.service' "$greeter_unit" ||
     ! grep -qx 'ConditionPathExists=!/var/cache/dms-greeter/.local/state/memory.json' "$greeter_unit"; then
  echo "FAIL dux-atomic-greeter-defaults.service is not ordered before greetd or would overwrite a choice" >&2
  failures=$((failures + 1))
elif [[ ! -f $greeter_seed ]] || ! grep -q '"lastSessionDesktopId": "niri.desktop"' "$greeter_seed"; then
  echo "FAIL the greeter memory seed does not default to niri" >&2
  failures=$((failures + 1))
elif [[ ! -L $greeter_wants ]] || [[ $(readlink "$greeter_wants") != /usr/lib/systemd/system/dux-atomic-greeter-defaults.service ]]; then
  echo "FAIL dux-atomic-greeter-defaults.service is not bound to greetd" >&2
  failures=$((failures + 1))
elif ! grep -qx 'getent passwd greeter >/dev/null || {' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh does not check the greeter account" >&2
  failures=$((failures + 1))
else
  echo "ok   the greeter defaults to the niri session"
fi

# A regression here is silent: waiting on the echoed command instead of the
# printf output lets the probe pass before it runs.
boot_smoke=$repo_root/tests/vm/boot-smoke.sh
common=$repo_root/build/common.sh
if ! grep -qF 'wait_for "DUX_USER:${test_user}"' "$boot_smoke" ||
   ! grep -qF "wait_for 'DUX_PROBE_END:ok'" "$boot_smoke" ||
   grep -qF "wait_for 'DUX_PROBE_END'" "$boot_smoke"; then
  echo "FAIL boot-smoke waits on an echoed marker instead of printf output" >&2
  failures=$((failures + 1))
elif ! grep -qF 'readlink "$portal_mask"' "$common" ||
     ! grep -qF '= /dev/null' "$common" ||
     ! grep -qF "trap 'rm -rf \"\$check_root\"' EXIT" "$common"; then
  echo "FAIL build/common.sh does not assert the portal mask target or trap the scratch root" >&2
  failures=$((failures + 1))
else
  echo "ok   the vm login probes and greeter mask fail closed"
fi

if ((failures > 0)); then
  exit 1
fi
echo "static checks passed"
