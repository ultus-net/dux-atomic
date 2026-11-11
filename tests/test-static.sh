#!/usr/bin/env bash
# tests/test-static.sh — cheap sanity checks for the image definition.
# The base pin, the package manifest and the package lock are gates here; the
# image build and tests/verify-image.sh prove the resolved package set.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

if [[ ! -f $repo_root/Containerfile ]]; then
  echo "FAIL Containerfile is missing" >&2
  failures=$((failures + 1))
elif grep -q 'ARG BASE_IMAGE' "$repo_root/Containerfile"; then
  echo "FAIL Containerfile still declares BASE_IMAGE; Dependabot cannot expand an ARG into FROM" >&2
  failures=$((failures + 1))
elif base=$(grep -E '^FROM ghcr\.io/ublue-os/base-main:[0-9]+@sha256:[0-9a-f]{64}$' "$repo_root/Containerfile"); then
  base_total=$(grep -cE '^FROM ghcr\.io/ublue-os/' "$repo_root/Containerfile")
  base_pinned=$(grep -cE '^FROM ghcr\.io/ublue-os/base-main:[0-9]+@sha256:[0-9a-f]{64}$' "$repo_root/Containerfile")
  if ((base_total != base_pinned)); then
    echo "FAIL Containerfile has ${base_total} ublue base FROM lines but only ${base_pinned} pinned" >&2
    failures=$((failures + 1))
  else
    echo "ok   Containerfile pins the base by tag and digest (${base#FROM })"
  fi
else
  echo "FAIL Containerfile does not pin the base as FROM ghcr.io/ublue-os/base-main:<tag>@sha256:<digest>" >&2
  failures=$((failures + 1))
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

# The lock records the resolved third-party packages. Fedora packages float with
# the updates repo, so comparing them would fail every build after an update;
# tests/verify-image.sh compares the non-Fedora lines only.
lock=$repo_root/manifests/packages-common.lock
if [[ ! -f $lock ]]; then
  echo "FAIL manifests/packages-common.lock is missing; run 'just lock'" >&2
  failures=$((failures + 1))
elif ! grep -qx "# manifests/packages-common.lock - regenerate with 'just lock'" "$lock"; then
  echo "FAIL packages-common.lock does not carry its regeneration header" >&2
  failures=$((failures + 1))
else
  lock_data=$(grep -vE '^(#|$)' "$lock" || true)
  if [[ -z $lock_data ]]; then
    echo "FAIL packages-common.lock has no package lines" >&2
    failures=$((failures + 1))
  elif grep -qvE $'^[^\t]+\t[^\t]+$' <<<"$lock_data"; then
    echo "FAIL packages-common.lock has a line without a single <nevra> TAB <vendor>" >&2
    failures=$((failures + 1))
  elif [[ $lock_data != "$(printf '%s\n' "$lock_data" | LC_ALL=C sort)" ]]; then
    echo "FAIL packages-common.lock is not sorted; regenerate it with 'just lock'" >&2
    failures=$((failures + 1))
  else
    echo "ok   packages-common.lock is present, headed and sorted"
  fi
fi

# A failed regeneration must not truncate the tracked lock, and a failed
# measurement must not be reported as drift.
lock_recipe=$(grep -A1 '^lock:$' "$repo_root/justfile" | tail -n 1 || true)
if [[ -z $lock_recipe ]] ||
   [[ $lock_recipe != *'tmp=manifests/packages-common.lock.tmp'* ]] ||
   [[ $lock_recipe != *'mv "$tmp" manifests/packages-common.lock'* ]] ||
   [[ $lock_recipe != *"trap 'rm -f \"\$tmp\"' EXIT"* ]] ||
   [[ $lock_recipe == *'$$tmp'* ]]; then
  echo "FAIL justfile lock recipe does not write a temp file, trap it, and move it on success" >&2
  failures=$((failures + 1))
elif ! grep -qF 'the lock measurement failed' "$repo_root/tests/verify-image.sh" ||
   ! grep -qF 'the package lock has no third-party lines' "$repo_root/tests/verify-image.sh"; then
  echo "FAIL tests/verify-image.sh does not separate a failed measurement from drift" >&2
  failures=$((failures + 1))
elif [[ $(grep -cF "grep -vF '+git'" "$repo_root/tests/verify-image.sh" || true) -lt 2 ]] ||
   ! grep -qF "sort -u | awk '!index(\$0, \"+git\")'" "$repo_root/build/package-lock.sh"; then
  echo "FAIL the lock generator or the gate does not drop +git builds, or the gate drops them on one side only" >&2
  failures=$((failures + 1))
else
  echo "ok   the lock is written atomically, drift is separated from a failed measurement, and +git builds are dropped on both sides"
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
   ! grep -qE 'max=5 budget=600([^0-9]|$)' "$workflow" ||
   ! grep -qF 'timeout --kill-after=10 "$cap" "$@" && return 0' "$workflow" ||
   ! grep -qE 'cap=\$\(\(remaining < 300 \? remaining : 300\)\)' "$workflow" ||
   ! grep -qF '((remaining > 0)) || break' "$workflow" ||
   ! grep -qF '((remaining > pause)) || break' "$workflow" ||
   ! grep -qF 'attempt=$((attempt + 1))' "$workflow" ||
   ! grep -qF -- '--kill-after=10 180 cosign verify \' "$workflow" ||
   ! grep -qF -- '--kill-after=10 180 cosign verify-attestation' "$workflow" ||
   ! grep -qF '::notice::pushed $IMAGE@$digest' "$workflow" ||
   grep -qF 'until cosign sign' "$workflow"; then
  echo "FAIL ci.yml does not retry sign and attest separately with a capped attempt, a per-command budget, capped verification, and the pushed digest" >&2
  failures=$((failures + 1))
else
  echo "ok   the publish step caps each attempt and each command's retry budget"
fi

# A descendant that outlives `timeout` keeps the step's stdout pipe open, so
# every command must write to a file of its own; a pipe-based wrapper would
# reintroduce the stall it is meant to prevent.
if ! grep -qF 'with_log() {' "$workflow" ||
   ! grep -qF '"$@" >>"$file" 2>&1 || status=$?' "$workflow" ||
   ! grep -qF 'cat "$file"' "$workflow" ||
   ! grep -qF 'with_log "$RUNNER_TEMP/sign.log" retry cosign sign' "$workflow" ||
   ! grep -qF 'with_log "$RUNNER_TEMP/attest.log" retry cosign attest' "$workflow" ||
   ! grep -qF 'with_log "$RUNNER_TEMP/verify.log" timeout --kill-after=10 180 cosign verify' "$workflow" ||
   ! grep -qF 'with_log "$RUNNER_TEMP/verify-attestation.log" timeout --kill-after=10 180 cosign verify-attestation' "$workflow"; then
  echo "FAIL ci.yml does not run every signing and verification command with its output in a file" >&2
  failures=$((failures + 1))
elif ! grep -qF 'timeout 10 cat "$file"' "$workflow" ||
   ! grep -qF 'return "$status"' "$workflow"; then
  echo "FAIL with_log does not bound its read or does not keep its command's status" >&2
  failures=$((failures + 1))
else
  echo "ok   every signing and verification command writes to its own log file"
fi

# The failure path must report failure, and the digest notice must come before
# anything that can stall.
if ! awk '/failed after .* attempts in /{found=1} found && /return 1/{ok=1} END{exit !ok}' "$workflow"; then
  echo "FAIL the retry helper does not return 1 after its failure message" >&2
  failures=$((failures + 1))
else
  echo "ok   the retry helper returns failure after reporting it"
fi
notice_line=$(grep -nF '::notice::pushed $IMAGE@$digest' "$workflow" | head -1 | cut -d: -f1)
sign_line=$(grep -nF 'retry cosign sign' "$workflow" | head -1 | cut -d: -f1)
if [[ -z $notice_line || -z $sign_line || $notice_line -ge $sign_line ]]; then
  echo "FAIL ci.yml records the pushed digest after the first command that can stall" >&2
  failures=$((failures + 1))
else
  echo "ok   the pushed digest is recorded before the first command that can stall"
fi

# Run the helper itself with scaled constants: greps cannot show that a hang is
# cut, and the helper is the only thing that stops a stall eating the job.
retry_root=$(mktemp -d)
sbom_root=
trap 'rm -rf "$cond_root" "$sbom_root" "$retry_root"' EXIT
sed -n '/^          retry() {/,/^          }$/p' "$workflow" | sed 's/^          //' |
  sed 's/max=5 budget=600/max=5 budget=5/; s/remaining < 300 ? remaining : 300/remaining < 2 ? remaining : 2/; s/pause=30/pause=1/' \
    >"$retry_root/retry.sh"
started_at=$SECONDS
if ! bash -c 'source "$1"; retry sleep 60' _ "$retry_root/retry.sh" 2>/dev/null; then
  if ((SECONDS - started_at > 12)); then
    echo "FAIL the retry helper let a hanging command run past its budget" >&2
    failures=$((failures + 1))
  else
    echo "ok   the retry helper cuts a hanging command inside its budget"
  fi
else
  echo "FAIL the retry helper reported success for a hanging command" >&2
  failures=$((failures + 1))
fi
if bash -c 'source "$1"; retry true' _ "$retry_root/retry.sh" 2>/dev/null; then
  echo "ok   the retry helper returns success without retrying"
else
  echo "FAIL the retry helper reported failure for a command that succeeded" >&2
  failures=$((failures + 1))
fi

# with_log must print its command's output and keep its status, or a failed
# sign would read as success and a stall would show nothing.
sed -n '/^          with_log() {/,/^          }$/p' "$workflow" | sed 's/^          //' \
  >"$retry_root/with_log.sh"
if logged=$(bash -c 'source "$1"; with_log "$2" bash -c "echo printed; exit 3"' _ \
     "$retry_root/with_log.sh" "$retry_root/out.log" 2>&1); then
  echo "FAIL with_log reported success for a command that failed" >&2
  failures=$((failures + 1))
elif [[ $logged != *printed* ]]; then
  echo "FAIL with_log did not print its command's output" >&2
  failures=$((failures + 1))
else
  echo "ok   with_log prints its command's output and keeps its failure status"
fi

# Rekor's public instance rejects the full file inventory, so the filter must
# keep dropping files and the relationships that point at them.
sbom_root=$(mktemp -d)
cat >"$sbom_root/in.json" <<'JSON'
{
  "SPDXID": "SPDXRef-DOCUMENT",
  "files": [
    {"fileName": "etc/motd", "SPDXID": "SPDXRef-File-etc-motd"},
    {"fileName": "usr/bin/sh", "SPDXID": "SPDXRef-File-usr-bin-sh"}
  ],
  "packages": [
    {"SPDXID": "SPDXRef-Package-coreutils", "name": "coreutils"},
    {
      "SPDXID": "SPDXRef-Package-bash",
      "name": "bash",
      "filesAnalyzed": true,
      "packageVerificationCode": {"packageVerificationCodeValue": "d6a770ba38583ed4bb4525bd96e50461655d2758"}
    }
  ],
  "relationships": [
    {"spdxElementId": "SPDXRef-Package-coreutils", "relationshipType": "CONTAINS", "relatedSpdxElement": "SPDXRef-File-etc-motd"},
    {"spdxElementId": "SPDXRef-Package-coreutils", "relationshipType": "DEPENDENCY_OF", "relatedSpdxElement": "SPDXRef-Package-bash"},
    {"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": "SPDXRef-Package-coreutils"}
  ]
}
JSON
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL jq is missing, so the SBOM filter cannot be checked" >&2
  failures=$((failures + 1))
elif ! jq -c -f "$repo_root/build/sbom-packages-only.jq" \
     "$sbom_root/in.json" >"$sbom_root/out.json"; then
  echo "FAIL build/sbom-packages-only.jq did not run" >&2
  failures=$((failures + 1))
elif [[ $(jq '.files | length' "$sbom_root/out.json") != 0 ]] ||
     [[ $(jq '.relationships | length' "$sbom_root/out.json") != 2 ]] ||
     [[ $(jq '[.packages[] | select(.filesAnalyzed != false or .packageVerificationCode != null)] | length' \
          "$sbom_root/out.json") != 0 ]] ||
     jq -e '.relationships[] | select(.relatedSpdxElement == "SPDXRef-File-etc-motd")' \
       "$sbom_root/out.json" >/dev/null; then
  echo "FAIL the SBOM filter keeps files, their relationships, or a package that still claims analysis" >&2
  failures=$((failures + 1))
elif ! grep -qF 'jq -c -f build/sbom-packages-only.jq' "$workflow" ||
     ! grep -qF '> dux-atomic.spdx.json' "$workflow" ||
     ! grep -qF 'path: dux-atomic.spdx.json' "$workflow"; then
  echo "FAIL ci.yml does not filter the SBOM into the uploaded file" >&2
  failures=$((failures + 1))
else
  echo "ok   the SBOM filter drops files and their relationships"
fi

if ((failures > 0)); then
  exit 1
fi
echo "static checks passed"
