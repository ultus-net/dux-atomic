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
elif ! grep -qx 'ExecCondition=/usr/libexec/dux-atomic/needs-setup.sh' "$desktop_unit" ||
     ! grep -qx 'ExecStartPost=/usr/bin/install -Dm0644 /dev/null %S/dux-atomic/desktop-setup.done' "$desktop_unit" ||
     [[ ! -x $repo_root/overlay/usr/libexec/dux-atomic/needs-setup.sh ]]; then
  echo "FAIL dux-atomic-desktop.service has no setup condition or completion marker" >&2
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

# The first-login condition decides retry vs skip. Run the real script against
# one fixture per case so a change in its logic is visible without a VM.
condition=$repo_root/overlay/usr/libexec/dux-atomic/needs-setup.sh
if ! grep -qF '${XDG_STATE_HOME:-$HOME/.local/state}' "$condition"; then
  echo "FAIL needs-setup.sh does not match the unit's %S marker path" >&2
  failures=$((failures + 1))
fi
cond_root=$(mktemp -d)
trap 'rm -rf "$cond_root"' EXIT
mkdir -p "$cond_root/fresh" \
  "$cond_root/partial/.config/niri" \
  "$cond_root/user/.config/niri" \
  "$cond_root/done/.config/niri" "$cond_root/done/.local/state/dux-atomic" \
  "$cond_root/reset/.local/state/dux-atomic" \
  "$cond_root/xdgstate/.config/niri" "$cond_root/xdgstate-state/dux-atomic"
# Copied from ~/.config/niri/config.kdl after `dms setup headless` in image
# 3e886bc33a30; see docs/research/2026-11-10-dms-first-login.md.
printf 'include optional=true "dms/colors.kdl"\n' >"$cond_root/partial/.config/niri/config.kdl"
printf '// user config\n' >"$cond_root/user/.config/niri/config.kdl"
printf 'include optional=true "dms/colors.kdl"\n' >"$cond_root/done/.config/niri/config.kdl"
printf 'include optional=true "dms/colors.kdl"\n' >"$cond_root/xdgstate/.config/niri/config.kdl"
: >"$cond_root/done/.local/state/dux-atomic/desktop-setup.done"
: >"$cond_root/reset/.local/state/dux-atomic/desktop-setup.done"
: >"$cond_root/xdgstate-state/dux-atomic/desktop-setup.done"
condition_failed=0
for spec in fresh:run partial:run user:skip done:skip reset:run xdgstate:skip; do
  name=${spec%%:*}
  expected=${spec##*:}
  env_args=("HOME=$cond_root/$name")
  if [[ $name == xdgstate ]]; then
    env_args+=("XDG_STATE_HOME=$cond_root/xdgstate-state")
  else
    # Empty means unset for the ${XDG_STATE_HOME:-...} default.
    env_args+=("XDG_STATE_HOME=")
  fi
  # Exit 0 means run, 1 means skip. A crash is neither and must fail the test.
  if env "${env_args[@]}" "$condition"; then status=0; else status=$?; fi
  case $status in
    0) got=run ;;
    1) got=skip ;;
    *) got="exit-${status}" ;;
  esac
  if [[ $got != "$expected" ]]; then
    echo "FAIL setup condition ${name}: expected ${expected}, got ${got}" >&2
    failures=$((failures + 1))
    condition_failed=1
  fi
done
if ((condition_failed == 0)); then
  echo "ok   the first-login condition retries partial setups and skips user configs"
fi

# A regression here is silent: waiting on the echoed command instead of the
# printf output lets the probe pass before it runs.
boot_smoke=$repo_root/tests/vm/boot-smoke.sh
common=$repo_root/build/common.sh
if ! grep -qF 'wait_for "DUX_USER:${test_user}"' "$boot_smoke" ||
   ! grep -qF "wait_for 'DUX_PROBE_END:ok'" "$boot_smoke" ||
   ! grep -qF "wait_for 'DUX_DIAG_END:ok'" "$boot_smoke" ||
   ! grep -qF 'if ! wait_for "${test_user}@" 20' "$boot_smoke" ||
   ! grep -qF 'DUX_SETUP_MARKER' "$boot_smoke" ||
   grep -qF 'wait_for "${test_user}@" 20 || true' "$boot_smoke" ||
   grep -qF "wait_for 'DUX_DIAG_END'" "$boot_smoke" ||
   grep -qF "wait_for 'DUX_PROBE_END'" "$boot_smoke"; then
  echo "FAIL boot-smoke waits on an echoed marker instead of printf output" >&2
  failures=$((failures + 1))
elif ! grep -qF 'readlink "$portal_mask"' "$common" ||
     ! grep -qF '= /dev/null' "$common" ||
     ! grep -qF "trap 'rm -rf \"\$check_root\"' EXIT" "$common" ||
     ! grep -qF 'cannot read ${manifest}' "$common" ||
     grep -qF 'packages-common.txt || true' "$common"; then
  echo "FAIL build/common.sh does not assert the portal mask target, trap the scratch root, or read the manifest fail-closed" >&2
  failures=$((failures + 1))
else
  echo "ok   the vm login probes and greeter mask fail closed"
fi

workflow=$repo_root/.github/workflows/ci.yml
if ! grep -qF 'retry cosign sign --yes "$IMAGE@$digest"' "$workflow" ||
   ! grep -qF 'retry cosign attest --yes' "$workflow" ||
   ! grep -qF 'attempt >= max' "$workflow" ||
   ! grep -qF 'max=5' "$workflow" ||
   grep -qF 'until cosign sign' "$workflow"; then
  echo "FAIL ci.yml does not retry sign and attest separately, or retries forever" >&2
  failures=$((failures + 1))
else
  echo "ok   the publish step retries sign and attest with a bounded loop"
fi

if ((failures > 0)); then
  exit 1
fi
echo "static checks passed"
