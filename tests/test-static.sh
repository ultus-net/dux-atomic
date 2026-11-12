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
elif base=$(grep -E '^FROM quay\.io/fedora/fedora-bootc:[0-9]+@sha256:[0-9a-f]{64}$' "$repo_root/Containerfile"); then
  # A later variant stage (the NVIDIA image in #40) may add another base, so
  # every FROM must be either scratch or a tag+digest pin, not just the first.
  base_total=$(grep -cE '^FROM ' "$repo_root/Containerfile" || true)
  base_scratch=$(grep -cE '^FROM scratch( AS [A-Za-z0-9_.-]+)?$' "$repo_root/Containerfile" || true)
  base_pinned=$(grep -cE '^FROM [^ ]+:[^ ]+@sha256:[0-9a-f]{64}$' "$repo_root/Containerfile" || true)
  if ((base_total != base_scratch + base_pinned)); then
    echo "FAIL Containerfile has ${base_total} FROM lines but ${base_scratch} scratch and ${base_pinned} tag+digest pins" >&2
    failures=$((failures + 1))
  else
    echo "ok   Containerfile pins the base by tag and digest (${base#FROM })"
  fi
else
  echo "FAIL Containerfile does not pin the base as FROM quay.io/fedora/fedora-bootc:<tag>@sha256:<digest>" >&2
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
# printf output lets the probe pass before it runs. The login prompt must also
# not be anchored to end of line: a kernel message can land on the prompt's line
# (#50). Run 43068532421 printed "fedora login: [ 275.126011] clocksource: ..."
# and the old end-anchored pattern missed it, burning the whole login budget.
boot_smoke=$repo_root/tests/vm/boot-smoke.sh
common=$repo_root/build/common.sh
if ! grep -qF 'wait_for "DUX_USER:${test_user}"' "$boot_smoke" ||
   ! grep -qF "wait_for 'DUX_PROBE_END:ok'" "$boot_smoke" ||
   ! grep -qF "wait_for 'DUX_DIAG_END:ok'" "$boot_smoke" ||
   ! grep -qF "wait_for '^[A-Za-z0-9._-]+ login: '" "$boot_smoke" ||
   grep -qF "wait_for 'login: *\$'" "$boot_smoke" ||
   ! awk '
      # The operator chose to accept any window of 60s or more (#36), so a
      # later raise does not red the gate. The wait must still be the prompt
      # wait in serial_login and must still fail the login.
      /^serial_login\(\) \{/ { in_fn = 1; next }
      in_fn && /^\}/ { exit }
      in_fn && /if[[:space:]]+![[:space:]]+wait_for[[:space:]]+"\$\{test_user\}@"[[:space:]]+[0-9]+;[[:space:]]*then/ {
        n = $0
        sub(/.*@[}"]/, "", n)
        sub(/; then.*/, "", n)
        wait = (n + 0 >= 60)
      }
      in_fn && /echo "login failed: no shell prompt for \$\{test_user\}" >&2/ { msg = 1 }
      msg && /return 1/ { ret = 1 }
      END { exit !(wait && msg && ret) }
    ' "$boot_smoke" ||
   ! grep -qF 'DUX_SETUP_MARKER' "$boot_smoke" ||
   grep -qE 'wait_for "\$\{test_user\}@" [0-9]+ \|\| true' "$boot_smoke" ||
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

# A hosted TCG boot reached the login prompt after 21 minutes in run 43068532421
# (#50), so the login wait must consume BOOT_TIMEOUT and CI must budget for it.
# Lowering either brings back a red release for a slow runner, not a broken image.
ci_workflow=$repo_root/.github/workflows/ci.yml
if ! grep -qF "login: ' \"\$timeout_s\"" "$boot_smoke" ||
   ! awk '
      # Scope to the boot step: a BOOT_TIMEOUT on another job or step must not
      # satisfy this. The env block follows the step name, and the next
      # "- name:" ends the step.
      /^[[:space:]]*- name: Boot smoke test[[:space:]]*$/ { step = 1; next }
      step && /^[[:space:]]*- name: / { step = 0 }
      step && /^[[:space:]]+BOOT_TIMEOUT: / {
        v = $0; gsub(/[^0-9]/, "", v)
        if (v + 0 >= 1800) ok = 1
        step = 0
      }
      END { exit !ok }
    ' "$ci_workflow"; then
  echo "FAIL ci.yml budgets less than 1800s for the hosted boot, or boot-smoke does not spend BOOT_TIMEOUT on the login prompt" >&2
  failures=$((failures + 1))
else
  echo "ok   the hosted boot budget covers a slow TCG login"
fi

# The serial console is a test-only karg (#39): in the overlay it puts a serial
# getty on hardware with no serial port. make-disk.sh appends it on the test
# disk, through the same [customizations.kernel] line as the device timeout.
overlay=$repo_root/overlay
make_disk=$repo_root/tests/vm/make-disk.sh
if grep -rqF 'console=ttyS0' "$overlay"; then
  echo "FAIL overlay/ ships console=ttyS0; the serial console karg belongs on the test disk only" >&2
  failures=$((failures + 1))
elif ! awk '
      # The karg belongs on the test disk only, so it must sit on the single
      # [customizations.kernel] append line that boot-smoke.sh boots with (#39).
      /append = "/ { n++; if (index($0, "console=ttyS0,115200")) karg = 1 }
      END { exit !(n == 1 && karg) }
    ' "$make_disk"; then
  echo "FAIL tests/vm/make-disk.sh does not append console=ttyS0,115200 as the test disk's single kernel append" >&2
  failures=$((failures + 1))
else
  echo "ok   the serial console karg comes from the test disk only"
fi

workflow=$repo_root/.github/workflows/ci.yml

# A DNS or mirror blip on a hosted runner must not fail a release. Run
# 43033654470 spent 67 minutes in the package install before apt reported
# "Temporary failure resolving", and publish, verify and promote never ran.
# Every job installs through the bounded helper, and no bare apt-get remains.
# apt must also fail over off the Azure mirror: run 43052107613 spent the whole
# budget on Ign: lines for azure.archive.ubuntu.com and never reached
# archive.ubuntu.com, the second entry in the runner's mirror list.
installer=$repo_root/build/install-packages.sh
if [[ ! -x $installer ]] ||
   ! grep -qF 'budget=300' "$installer" ||
   ! grep -qF 'deadline=$((SECONDS + budget))' "$installer" ||
   ! grep -qF 'cap=$((deadline - SECONDS))' "$installer" ||
   ! grep -qF 'timeout "$cap" sudo env DEBIAN_FRONTEND=noninteractive' "$installer" ||
   ! grep -qF 'apt-get -o Acquire::Retries=1 -o Acquire::Retries::Delay=false' "$installer" ||
   ! grep -qF 'for attempt in 1 2 3; do' "$installer" ||
   ! grep -qF 'deprioritise_azure_mirror "$mirrors"' "$installer" ||
   ! grep -qF 'apt_retry install -y "$@"' "$installer" ||
   ! grep -qF 'build/install-packages.sh podman qemu-system-x86 qemu-utils ovmf' "$workflow" ||
   ! grep -qF 'build/install-packages.sh podman skopeo' "$workflow" ||
   ! grep -qF 'build/install-packages.sh skopeo' "$workflow" ||
   grep -qF 'apt-get install' "$workflow"; then
  echo "FAIL ci.yml installs runner packages without the bounded retry helper" >&2
  failures=$((failures + 1))
else
  echo "ok   the runner package installs retry a transient apt failure"
fi

# A job that runs the helper needs the repository in its workspace. Run
# 43082564852 failed publish with exit 127 because the install step ran with no
# checkout, and promote would have failed the same way one job later (#52).
# The checkout must also come first: a checkout after the install is too late.
if ! awk '
   /^jobs:$/ { injobs = 1; next }
   injobs && /^[^ ]/ { injobs = 0 }
   injobs && /^  [A-Za-z_][A-Za-z0-9_-]*:$/ {
     job = $0
     sub(/^  /, "", job)
     sub(/:$/, "", job)
     checkout = 0
     next
   }
   job != "" && /^[[:space:]]*(- )?uses: actions\/checkout@/ { checkout = 1 }
   job != "" && /build\/install-packages\.sh/ && !checkout {
     bad = bad (bad == "" ? "" : " ") job
   }
   END {
     if (bad != "") {
       printf "jobs run build/install-packages.sh with no checkout before it: %s\n", bad
       exit 1
     }
   }
 ' "$workflow"; then
  echo "FAIL a ci.yml job runs the package installer without a checkout before it" >&2
  failures=$((failures + 1))
else
  echo "ok   every job that runs the package installer checks out the repo first"
fi

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
# every signing command must write to a file of its own; a pipe-based wrapper
# would reintroduce the stall it is meant to prevent. Verification moved to its
# own job, because its stall survived both a command timeout and a step timeout.
if ! grep -qF 'with_log "$RUNNER_TEMP/sign.log" retry cosign sign' "$workflow" ||
   ! grep -qF 'with_log "$RUNNER_TEMP/attest.log" retry cosign attest' "$workflow"; then
  echo "FAIL ci.yml does not run every signing command with its output in a file" >&2
  failures=$((failures + 1))
else
  echo "ok   every signing command writes to its own log file"
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

# The signing job runs repository test code on a PR, so it holds no write token
# and pins every action; a floating tag would let that run change under it.
signing_block=$(awk '/^  signing:/{f=1;next} f&&/^  [a-z]/{exit} f' "$workflow")
if [[ -z $signing_block ]]; then
  echo "FAIL ci.yml has no signing job" >&2
  failures=$((failures + 1))
elif ! grep -qF 'tests/test-signing.sh' <<<"$signing_block"; then
  echo "FAIL the signing job does not run tests/test-signing.sh" >&2
  failures=$((failures + 1))
elif grep -qE '(packages|contents|id-token): write' <<<"$signing_block"; then
  echo "FAIL the signing job asks for a write token" >&2
  failures=$((failures + 1))
elif grep -F 'uses:' <<<"$signing_block" | grep -qvE '@[0-9a-f]{40} '; then
  echo "FAIL the signing job does not pin an action to a commit SHA" >&2
  failures=$((failures + 1))
elif ! grep -qF 'tests/test-signing.sh' "$repo_root/tests/lint.sh"; then
  echo "FAIL tests/lint.sh does not shellcheck tests/test-signing.sh" >&2
  failures=$((failures + 1))
else
  echo "ok   the signing job pins its actions, holds no write token, and is shellchecked"
fi

# A hang must name its own step. Each signing step holds one command and the
# verification job holds its own bound; the logs upload on every outcome,
# because a timed-out step keeps no log of its own.
split_ok=1
for spec in 'Sign the digest:15' 'Attest the SBOM:15'; do
  step=${spec%%:*}
  bound=${spec##*:}
  if ! awk -v step="- name: ${step}" -v bound="timeout-minutes: ${bound}" \
       'index($0, step){found=1; next} found && index($0, bound){ok=1; exit} found && /- name:/{exit} END{exit !ok}' \
       "$workflow"; then
    echo "FAIL ci.yml does not bound '${step}' at ${bound} minutes" >&2
    failures=$((failures + 1))
    split_ok=0
  fi
done
if ((split_ok == 1)); then
  echo "ok   sign and attest each carry their own bound"
fi
if ! awk '/- name: Upload publish logs/{found=1; next} found && /if: always\(\)/{ok=1; exit} found && /- name:/{exit} END{exit !ok}' "$workflow" ||
   ! grep -qF 'path: ${{ runner.temp }}/*.log' "$workflow" ||
   [[ $(grep -cF 'source "$RUNNER_TEMP/helpers.sh"' "$workflow") -lt 3 ]]; then
  echo "FAIL the publish logs do not upload on every outcome, or a signing step does not source the helpers" >&2
  failures=$((failures + 1))
else
  echo "ok   the publish logs upload on every outcome and the signing steps source the helpers"
fi

# Verification reads the registry and the transparency log on its own, and its
# stall outlived both a command timeout and a step timeout, so only a job bound
# ends it. It must hold no OIDC identity, and promotion must wait for it. The
# digest crosses the job boundary as a job output, so a lost output or a renamed
# step id would leave verification with an empty digest.
publish_block=$(awk '/^  publish:/{f=1;next} f&&/^  [a-z]/{exit} f' "$workflow")
verify_block=$(awk '/^  verify:/{f=1;next} f&&/^  [a-z]/{exit} f' "$workflow")
promote_block=$(awk '/^  promote:/{f=1;next} f&&/^  [a-z]/{exit} f' "$workflow")
if [[ -z $publish_block ]] ||
   ! grep -qF 'digest: ${{ steps.push.outputs.digest }}' <<<"$publish_block" ||
   ! grep -qF 'id: push' <<<"$publish_block" ||
   ! grep -qF 'echo "digest=$(cat "$RUNNER_TEMP/digest")" >> "$GITHUB_OUTPUT"' <<<"$publish_block"; then
  echo "FAIL the publish job does not export the pushed digest as a job output" >&2
  failures=$((failures + 1))
elif [[ -z $verify_block ]] ||
   ! grep -qF 'cosign verify' <<<"$verify_block" ||
   ! grep -qF 'cosign verify-attestation' <<<"$verify_block" ||
   ! grep -qF 'timeout-minutes: 20' <<<"$verify_block" ||
   [[ $(grep -cF 'DIGEST: ${{ needs.publish.outputs.digest }}' <<<"$verify_block") -lt 2 ]] ||
   grep -qF 'id-token: write' <<<"$verify_block"; then
  echo "FAIL the verify job is missing, unbounded, does not read the publish digest, or asks for an OIDC identity" >&2
  failures=$((failures + 1))
elif [[ $(grep -cF 'head -c 20000' <<<"$verify_block") -lt 2 ]] ||
     ! grep -qF '>"$RUNNER_TEMP/verify.log" || status=$?' <<<"$verify_block" ||
     ! grep -qF '>"$RUNNER_TEMP/verify-attestation.log" || status=$?' <<<"$verify_block" ||
     ! awk '/- name: Upload verify logs/{found=1; next} found && /if: always\(\)/{ok=1; exit} found && /- name:/{exit} END{exit !ok}' <<<"$verify_block" ||
     ! grep -qE 'name: verify-logs$' <<<"$verify_block"; then
  echo "FAIL the verify job does not keep cosign's payload out of the step log, or does not upload the logs on every outcome" >&2
  failures=$((failures + 1))
elif [[ $(grep -cF -- '- name: Verify the signature' <<<"$verify_block") -ne 1 ]] ||
     [[ $(grep -cF -- '- name: Verify the attestation' <<<"$verify_block") -ne 1 ]] ||
     ! awk '
      BEGIN { want="exit \"$status\"" }
      /^[[:space:]]*- name: Verify (the signature|the attestation|the provenance)$/ {
        if (in_step && last != want) bad=1
        in_step=1; last=""; next
      }
      in_step && /^[[:space:]]*- name:/ {
        if (last != want) bad=1
        in_step=0
      }
      in_step && NF { last=$0; sub(/^[[:space:]]+/, "", last) }
      END {
        if (in_step && last != want) bad=1
        exit bad
      }' <<<"$verify_block"; then
  echo "FAIL ci.yml does not end both verify steps with exit \"\$status\", so a failed cosign check could report green" >&2
  failures=$((failures + 1))
elif [[ -z $promote_block ]] ||
     ! grep -qF 'needs: [publish, verify]' <<<"$promote_block" ||
     ! grep -qF 'if: inputs.promote' <<<"$promote_block"; then
  echo "FAIL promotion is missing, or it can run before verification passes" >&2
  failures=$((failures + 1))
else
  echo "ok   verification has its own job bound and promotion waits for it"
fi

# Provenance is a claim about the build, and the SBOM attestation is a claim
# about the contents, so the image needs both. The attestation must name the
# pushed digest; an attestation of the tag would say nothing about the image
# that shipped. Verification reads the registry copy and pins the signer, so an
# attestation from another workflow or repository cannot satisfy it (#5).
attest_line=$(grep -nF '      - name: Attest build provenance' <<<"$publish_block" | head -1 | cut -d: -f1)
push_line=$(grep -nF '      - name: Push the commit tag' <<<"$publish_block" | head -1 | cut -d: -f1)
if [[ -z $attest_line || -z $push_line || $attest_line -le $push_line ]]; then
  echo "FAIL ci.yml attests provenance before it has pushed a digest to attest" >&2
  failures=$((failures + 1))
elif ! grep -qF 'attestations: write' <<<"$publish_block" ||
   ! grep -qF 'uses: actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6 # v4.2.2' <<<"$publish_block" ||
   ! grep -qF 'subject-name: ${{ env.IMAGE }}' <<<"$publish_block" ||
   ! grep -qF 'subject-digest: ${{ steps.push.outputs.digest }}' <<<"$publish_block" ||
   ! grep -qF 'push-to-registry: true' <<<"$publish_block" ||
   ! grep -qF 'create-storage-record: false' <<<"$publish_block"; then
  echo "FAIL ci.yml does not attest build provenance for the pushed digest, or asks for a permission the step does not need" >&2
  failures=$((failures + 1))
elif ! grep -qF 'retry cosign attest --yes --new-bundle-format' <<<"$publish_block" ||
     ! grep -qF -- '--predicate sbom/dux-atomic.spdx.json --type spdxjson' <<<"$publish_block"; then
  # A legacy tag attachment becomes invisible once any Sigstore bundle
  # references the digest, because cosign then verifies in bundle mode only.
  # Run 43106659542 failed verify that way after the provenance bundle landed.
  echo "FAIL ci.yml attests the SBOM without --new-bundle-format, so the provenance bundle hides it from cosign verify-attestation" >&2
  failures=$((failures + 1))
elif [[ -z $verify_block ]] ||
     ! grep -qF 'gh attestation verify "oci://$IMAGE@$DIGEST"' <<<"$verify_block" ||
     ! grep -qF -- '--bundle-from-oci' <<<"$verify_block" ||
     ! grep -qF -- '--cert-identity "https://github.com/ultus-net/dux-atomic/.github/workflows/ci.yml@refs/heads/main"' <<<"$verify_block" ||
     ! grep -qF '>"$RUNNER_TEMP/verify-provenance.log" 2>&1 || status=$?' <<<"$verify_block"; then
  echo "FAIL ci.yml does not verify the provenance of the digest it published" >&2
  failures=$((failures + 1))
else
  echo "ok   the pushed digest carries build provenance and verify pins the signer identity"
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
# sign would read as success and a stall would show nothing. Assert and run the
# extracted helper, not the file, so a duplicate literal elsewhere cannot
# satisfy the check. No fixture can wedge a log read, so a removed `|| true` is
# caught by the grep; the `bash -e` run catches a dropped status capture,
# because errexit would abort before the file is printed.
sed -n '/^          with_log() {/,/^          }$/p' "$workflow" | sed 's/^          //' \
  >"$retry_root/with_log.sh"
if ! grep -qF '"$@" >>"$file" 2>&1 || status=$?' "$retry_root/with_log.sh" ||
   ! grep -qF 'timeout 10 head -c 20000 "$file" || true' "$retry_root/with_log.sh" ||
   ! grep -qF 'echo "[with_log: printed 20000 of ${bytes} bytes from ${file##*/}]"' "$retry_root/with_log.sh" ||
   ! grep -qF 'return "$status"' "$retry_root/with_log.sh"; then
  echo "FAIL with_log does not bound its print, report the cut, or keep its command's status" >&2
  failures=$((failures + 1))
else
  echo "ok   with_log bounds its print, reports the cut, and keeps its command's status"
fi
logged=$(bash -ec 'source "$1"; with_log "$2" bash -c "echo printed; exit 3"' _ \
  "$retry_root/with_log.sh" "$retry_root/out.log" 2>&1) && rc=0 || rc=$?
if ((rc != 3)); then
  echo "FAIL with_log under bash -e did not keep its command's exit status (got $rc, expected 3)" >&2
  failures=$((failures + 1))
elif [[ $logged != *printed* ]]; then
  echo "FAIL with_log did not print its command's output" >&2
  failures=$((failures + 1))
else
  echo "ok   with_log under bash -e prints its command's output and keeps its failure status"
fi

# A command that prints a large single line must have its print trimmed by the
# bounded `head -c 20000`, as cosign verify-attestation does. The file keeps the
# whole output; only the step log is bounded.
cat >"$retry_root/long.sh" <<'SH'
head -c 30000 </dev/zero | tr '\0' A
SH
bash -ec 'source "$1"; with_log "$2" bash "$3"' _ \
  "$retry_root/with_log.sh" "$retry_root/long.log" "$retry_root/long.sh" \
  >"$retry_root/long.out" 2>&1 && rc=0 || rc=$?
if ((rc != 0)); then
  echo "FAIL with_log reported failure for a command that printed one long line" >&2
  failures=$((failures + 1))
elif [[ $(wc -c <"$retry_root/long.log") -ne 30000 ]]; then
  echo "FAIL with_log did not keep the full output in the file" >&2
  failures=$((failures + 1))
elif [[ $(wc -c <"$retry_root/long.out") -gt 21000 ]]; then
  echo "FAIL with_log did not trim its print to 20000 bytes (got $(wc -c <"$retry_root/long.out") bytes)" >&2
  failures=$((failures + 1))
elif ! grep -qF '[with_log: printed 20000 of 30000 bytes from long.log]' "$retry_root/long.out"; then
  echo "FAIL with_log did not report the bytes it dropped" >&2
  failures=$((failures + 1))
else
  echo "ok   with_log trims one long line to 20000 bytes and reports the drop"
fi

cat >"$retry_root/long-fail.sh" <<'SH'
head -c 30000 </dev/zero | tr '\0' A
exit 3
SH
bash -ec 'source "$1"; with_log "$2" bash "$3"' _ \
  "$retry_root/with_log.sh" "$retry_root/long-fail.log" "$retry_root/long-fail.sh" \
  >"$retry_root/long-fail.out" 2>&1 && rc=0 || rc=$?
if ((rc != 3)); then
  echo "FAIL with_log dropped the exit status of a command that printed a long line (got $rc)" >&2
  failures=$((failures + 1))
elif [[ $(wc -c <"$retry_root/long-fail.out") -gt 21000 ]] ||
     ! grep -qF '[with_log: printed 20000 of 30000 bytes from long-fail.log]' "$retry_root/long-fail.out"; then
  echo "FAIL with_log did not trim and report the long output of a failing command" >&2
  failures=$((failures + 1))
else
  echo "ok   with_log trims a long line and keeps the failing command's status"
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

# A report-only scan hides a new finding, and an ignore entry without an expiry
# hides it forever. Both are regressions the run would otherwise not show.
trivyignore=$repo_root/.trivyignore
if [[ ! -f $trivyignore ]]; then
  echo "FAIL .trivyignore is missing" >&2
  failures=$((failures + 1))
else
  trivy_entries=$(grep -cE '^(CVE-[0-9]{4}-[0-9]+|GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}) ' "$trivyignore" || true)
  trivy_bad=$(grep -nEv '^[[:space:]]*(#.*)?$|^(CVE-[0-9]{4}-[0-9]+|GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}) exp:[0-9]{4}-[0-9]{2}-[0-9]{2}$' "$trivyignore" || true)
  if [[ -n $trivy_bad ]]; then
    echo "FAIL .trivyignore has a line that is not a comment or '<advisory-id> exp:<date>':"$'\n'"$trivy_bad" >&2
    failures=$((failures + 1))
  elif ((trivy_entries == 0)); then
    echo "FAIL .trivyignore has no triaged entries" >&2
    failures=$((failures + 1))
  elif ! grep -qF -- '--exit-code 1' "$workflow" ||
       grep -qF 'continue-on-error: true' "$workflow" ||
       ! grep -qF -- '--ignorefile .trivyignore' "$workflow"; then
    echo "FAIL the vulnerability scan does not fail on a new finding or read .trivyignore" >&2
    failures=$((failures + 1))
  elif ! awk '/- name: Upload scan report/{found=1; next} found && /if: always\(\)/{ok=1; exit} found && /- name:/{exit} END{exit !ok}' "$workflow"; then
    echo "FAIL the scan-report upload does not run on failure" >&2
    failures=$((failures + 1))
  else
    echo "ok   the trivy scan is blocking, reads expiring ignores, and keeps the report on failure"
  fi
fi

if ((failures > 0)); then
  exit 1
fi
echo "static checks passed"
