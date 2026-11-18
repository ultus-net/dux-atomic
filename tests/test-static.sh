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
elif base=$(grep -E '^FROM registry\.fedoraproject\.org/fedora-bootc:[0-9]+@sha256:[0-9a-f]{64}$' "$repo_root/Containerfile"); then
  # The primary Containerfile must pin the fedora-bootc base by tag+digest.
  base_total=$(grep -cE '^FROM ' "$repo_root/Containerfile" || true)
  base_scratch=$(grep -cE '^FROM scratch( AS [A-Za-z0-9_.-]+)?$' "$repo_root/Containerfile" || true)
  base_pinned=$(grep -cE '^FROM [^ ]+:[^ ]+@sha256:[0-9a-f]{64}$' "$repo_root/Containerfile" || true)
  if ((base_total != base_scratch + base_pinned)); then
    echo "FAIL Containerfile has ${base_total} FROM lines but ${base_scratch} scratch and ${base_pinned} tag+digest pins" >&2
    failures=$((failures + 1))
  else
    echo "ok   Containerfile pins the base by tag and digest (${base#FROM })"
    # Also require any sibling Containerfile* to follow the same rule.
    for cf in "$repo_root"/Containerfile*; do
      if [[ ! -f $cf || $cf == "$repo_root/Containerfile" ]]; then
        continue
      fi
      if grep -q 'ARG BASE_IMAGE' "$cf"; then
        echo "FAIL ${cf##*/} still declares BASE_IMAGE; Dependabot cannot expand an ARG into FROM" >&2
        failures=$((failures + 1))
        continue
      fi
      base_total=$(grep -cE '^FROM ' "$cf" || true)
      base_scratch=$(grep -cE '^FROM scratch( AS [A-Za-z0-9_.-]+)?$' "$cf" || true)
      base_pinned=$(grep -cE '^FROM [^ ]+:[^ ]+@sha256:[0-9a-f]{64}$' "$cf" || true)
      if ((base_total != base_scratch + base_pinned)); then
        echo "FAIL ${cf##*/} has ${base_total} FROM lines but ${base_scratch} scratch and ${base_pinned} tag+digest pins" >&2
        failures=$((failures + 1))
      else
        echo "ok   ${cf##*/} pins its base by tag and digest"
      fi
    done
  fi
else
  echo "FAIL Containerfile does not pin the base as FROM registry.fedoraproject.org/fedora-bootc:<tag>@sha256:<digest>; quay.io/fedora deletes the previous daily digest" >&2
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

# The NVIDIA variant installs a second manifest (#72). The shared image reads
# only packages-common.txt, so the variant names its own file through
# PACKAGE_MANIFEST_EXTRA. Losing either half of that wiring still builds an
# image: it just ships none of the variant's userspace or akmod packages. The
# akmod build set is named here because the image build compiles the module,
# and the build fails there without a compiler and matching headers.
variant_manifest=$repo_root/manifests/packages-nvidia.txt
variant_containerfile=$repo_root/Containerfile.nvidia
variant_build_deps=(akmod-nvidia akmods kernel-devel-matched gcc make)
missing_deps=()
for dep in "${variant_build_deps[@]}"; do
  grep -qx "$dep" "$variant_manifest" 2>/dev/null || missing_deps+=("$dep")
done
if [[ ! -f $variant_manifest ]]; then
  echo "FAIL manifests/packages-nvidia.txt is missing" >&2
  failures=$((failures + 1))
elif ((${#missing_deps[@]} > 0)); then
  echo "FAIL packages-nvidia.txt no longer names the akmod build set: ${missing_deps[*]}" >&2
  failures=$((failures + 1))
elif ! grep -qE '^[[:space:]]+PACKAGE_MANIFEST_EXTRA=packages-nvidia\.txt([[:space:]]|$)' "$variant_containerfile"; then
  echo "FAIL Containerfile.nvidia does not set PACKAGE_MANIFEST_EXTRA=packages-nvidia.txt, so the variant installs no variant packages" >&2
  failures=$((failures + 1))
elif ! grep -qF 'install_manifest "$extra"' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh does not install the caller-named extra manifest" >&2
  failures=$((failures + 1))
elif ! grep -qF 'check-kernel-devel.sh "${kernels[-1]}" "${devels[@]}"' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh no longer fails the build when no installed kernel-devel matches the newest kernel" >&2
  failures=$((failures + 1))
elif ! grep -qF 'check-manifest-name.sh "$PACKAGE_MANIFEST_EXTRA"' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh does not validate the extra manifest name before installing it" >&2
  failures=$((failures + 1))
elif ! grep -qF 'build-nvidia-modules.sh' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh does not compile the akmod during the image build" >&2
  failures=$((failures + 1))
elif ! grep -qF 'rpm -q akmod-nvidia >/dev/null 2>&1' "$repo_root/build/common.sh"; then
  echo "FAIL build/common.sh compiles the akmod without a guard, so the shared image would run it" >&2
  failures=$((failures + 1))
elif grep -qF 'PACKAGE_MANIFEST_EXTRA' "$repo_root/Containerfile"; then
  echo "FAIL Containerfile sets PACKAGE_MANIFEST_EXTRA, so the shared image would install a variant manifest" >&2
  failures=$((failures + 1))
else
  echo "ok   the NVIDIA variant names its own manifest and the shared image does not"
fi

# build/common.sh reads the shared overlay and every modules/*/ tree, and skips
# a tree the build context lacks. A variant that omits one COPY therefore builds
# without it and still exits 0, so compare the ctx stages rather than trust the
# two files to stay in step.
ctx_trees=$(grep -oE '^COPY (build|manifests|overlay|modules) ' "$repo_root/Containerfile")
variant_ctx_trees=$(grep -oE '^COPY (build|manifests|overlay|modules) ' "$variant_containerfile")
if [[ $ctx_trees != "$variant_ctx_trees" ]]; then
  echo "FAIL Containerfile.nvidia exposes different build-context trees than Containerfile, so a variant can build without a tree the shared build reads" >&2
  failures=$((failures + 1))
else
  echo "ok   every Containerfile exposes the same build-context trees"
fi

# The two helpers the variant path adds are decision functions, so exercise
# them here: a matching devel must pass, a mismatched or absent one must fail
# with its message, a manifest name must become a path under manifests/, and a
# path or an empty name must be refused. A behaviour change reds this block
# without needing an image.
kernel_devel_check=$repo_root/build/check-kernel-devel.sh
manifest_name_check=$repo_root/build/check-manifest-name.sh
variant_kernel=7.3.3-300.fc45.x86_64
helpers_ok=0
if bash "$kernel_devel_check" "$variant_kernel" "$variant_kernel" &&
   bash "$manifest_name_check" packages-nvidia.txt | grep -qx '/ctx/manifests/packages-nvidia.txt'; then
  kd_mismatch=$(bash "$kernel_devel_check" "$variant_kernel" 7.2.11-300.fc45.x86_64 2>&1) || kd_mismatch_status=$?
  kd_empty=$(bash "$kernel_devel_check" "$variant_kernel" 2>&1) || kd_empty_status=$?
  mn_slash=$(bash "$manifest_name_check" ../packages-common.txt 2>&1) || mn_slash_status=$?
  mn_empty=$(bash "$manifest_name_check" '' 2>&1) || mn_empty_status=$?
  if [[ ${kd_mismatch_status:-0} -eq 1 && ${kd_empty_status:-0} -eq 1 ]] &&
     [[ ${mn_slash_status:-0} -eq 1 && ${mn_empty_status:-0} -eq 1 ]] &&
     [[ $kd_mismatch == *"does not match the newest kernel $variant_kernel"* ]] &&
     [[ $kd_empty == *'does not match the newest kernel'* ]] &&
     [[ $mn_slash == *'must be a file name in manifests/: ../packages-common.txt'* ]] &&
     [[ $mn_empty == *'must be a file name in manifests/'* ]]; then
    helpers_ok=1
  fi
fi
if ((helpers_ok == 1)); then
  echo "ok   the variant's manifest-name and kernel-devel helpers accept their inputs and refuse the rest"
else
  echo "FAIL build/check-manifest-name.sh or build/check-kernel-devel.sh lost a green or red path, or its message" >&2
  failures=$((failures + 1))
fi

# The module check is the assertion that the image build produced a driver.
# Exercise its green, missing-module, empty-module, and usage paths against a
# scratch tree, so a behaviour change reds without an image.
modules_check=$repo_root/build/check-nvidia-modules.sh
modules_root=$(mktemp -d)
modules_dir=$modules_root/$variant_kernel/extra/nvidia
mkdir -p "$modules_dir"
for module in nvidia nvidia-uvm nvidia-drm nvidia-modeset nvidia-peermem; do
  printf 'module' > "$modules_dir/$module.ko.xz"
done
modules_ok=0
if bash "$modules_check" "$variant_kernel" "$modules_root"; then
  rm "$modules_dir/nvidia-uvm.ko.xz"
  mod_missing=$(bash "$modules_check" "$variant_kernel" "$modules_root" 2>&1) || mod_missing_status=$?
  : > "$modules_dir/nvidia-uvm.ko.xz"
  mod_empty=$(bash "$modules_check" "$variant_kernel" "$modules_root" 2>&1) || mod_empty_status=$?
  bash "$modules_check" >/dev/null 2>&1 || mod_usage_status=$?
  if [[ ${mod_missing_status:-0} -eq 1 && ${mod_empty_status:-0} -eq 1 && ${mod_usage_status:-0} -eq 2 ]] &&
     [[ $mod_missing == *'nvidia-uvm'* && $mod_missing == *"$variant_kernel"* ]] &&
     [[ $mod_empty == *'nvidia-uvm'* ]]; then
    modules_ok=1
  fi
fi
rm -rf "$modules_root"
if ((modules_ok == 1)); then
  echo "ok   the module check accepts a complete set and reds a missing or empty module"
else
  echo "FAIL build/check-nvidia-modules.sh lost its green, red, or usage path" >&2
  failures=$((failures + 1))
fi

# The lock records every installed package whose origin repository is not a
# Fedora repository, so a Fedora updates bump cannot red it. tests/verify-image.sh
# compares the whole recorded set against the generator's measurement.
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
    echo "FAIL packages-common.lock has a line without a single <nevra> TAB <from_repo>" >&2
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
elif ! grep -qF "awk '!index(\$0, \"+git\")'" "$repo_root/build/package-lock.sh"; then
  echo "FAIL the lock generator does not drop +git builds" >&2
  failures=$((failures + 1))
else
  echo "ok   the lock is written atomically, drift is separated from a failed measurement, and the generator drops +git builds"
fi

# The comparison is one helper so tests/test-lock-drift.sh can run it with no
# image. Pin the call, the operator's drift message, and the branch that keeps a
# failed measurement apart from drift, so a later edit cannot collapse them.
if ! grep -qF 'build/compare-lock.sh' "$repo_root/tests/verify-image.sh" ||
   ! grep -qF "FAIL the third-party package lock drifted; run 'just lock'" "$repo_root/tests/verify-image.sh" ||
   ! grep -qF 'elif ((compare_status != 0))' "$repo_root/tests/verify-image.sh" ||
   ! grep -qF 'FAIL the lock measurement failed; the generator or the image is broken' "$repo_root/tests/verify-image.sh"; then
  echo "FAIL tests/verify-image.sh no longer calls build/compare-lock.sh or lost the drift and failed-measurement messages" >&2
  failures=$((failures + 1))
else
  echo "ok   the lock comparison runs through build/compare-lock.sh and keeps both diagnoses"
fi

# Secure Boot needs no per-machine enrollment only while the base keeps Fedora's
# signed kernel, and the image job is the only place that can see it (#65). Pin
# the call and the issuer: the old base shipped a signed kernel too, so the
# presence of a signature alone would not have caught the swap.
kernel_check=$repo_root/tests/verify-kernel-signature.sh
if [[ ! -f $repo_root/tests/pe-signature.py ]] ||
   ! grep -qF 'tests/verify-kernel-signature.sh' "$repo_root/tests/verify-image.sh" ||
   ! grep -qF 'exactly one certificate' "$kernel_check" ||
   ! grep -qF 'CN=fedoraca' "$kernel_check" ||
   ! grep -qF 'CN=kernel-signer' "$kernel_check"; then
  echo "FAIL nothing checks that the image's kernel is signed by Fedora, so a base bump could break Secure Boot silently" >&2
  failures=$((failures + 1))
else
  echo "ok   the image job checks that the kernel is signed by Fedora"
fi

# The dotfiles install their npm globals only when npm exists, and TypeScript
# type stripping needs Node 22.18 (#67). Pin both probes and the 22.18 floor, so
# a later edit cannot drop the contract or the packages behind it quietly.
if ! grep -qF 'node --version' "$repo_root/tests/verify-image.sh" ||
   ! grep -qF 'npm --version' "$repo_root/tests/verify-image.sh" ||
   ! grep -qF 'node_minor < 18' "$repo_root/tests/verify-image.sh" ||
   ! grep -qF 'node_major < 22' "$repo_root/tests/verify-image.sh" ||
   ! grep -qx 'nodejs' "$manifest" ||
   ! grep -qx 'nodejs-npm' "$manifest"; then
  echo "FAIL the image does not prove Node 22.18 and npm run, so the dotfiles npm globals could be skipped at first login" >&2
  failures=$((failures + 1))
else
  echo "ok   the image proves Node 22.18 and npm run for the dotfiles npm globals"
fi

# docs/developer-tooling.md states how a new tool is placed (#80). The rule is
# the deliverable, and the order is the rule, so compare the delivery paths in
# the placement table against the expected sequence. Reordering, removing, or
# rewording a path reds here. Then anchor the test that decides the Homebrew
# row, the support-tier boundary that keeps it narrow, and the record it cites.
# The grandfather row is #82: a Fedora-packaged user CLI the dotfiles already
# deliver keeps its Homebrew delivery until the dotfiles move it, and the
# inventory below the split names every `brew` entry so the row cannot go vague.
tooling_doc=$repo_root/docs/developer-tooling.md
tooling_research=$repo_root/docs/research/2026-11-14-package-delivery-layers.md
tooling_inventory=$repo_root/docs/research/2026-11-14-brewfile-inventory-measurement.md
expected_delivery=$'Image\nImage, recorded in the lock\nA pinned `podman` container\nFlathub\nHomebrew, from the dotfiles `Brewfile`\nGrandfathered: the dotfiles `Brewfile`, until the dotfiles move it\nThat project\'s devcontainer or a Distrobox'
actual_delivery=$(awk -F'|' '
  /^## How a new tool is placed$/ { inside = 1; next }
  inside && /^## / { inside = 0 }
  inside && /^\|/ {
    cell = $3
    gsub(/^[ \t]+|[ \t]+$/, "", cell)
    if (cell == "Delivery" || cell ~ /^-+$/) next
    print cell
  }' "$tooling_doc" 2>/dev/null || true)
if [[ ! -f $tooling_doc ]] ||
   [[ $actual_delivery != "$expected_delivery" ]] ||
   ! grep -qF 'dnf5 repoquery --available <name>' "$tooling_doc" ||
   ! grep -qF 'Homebrew is the fallback, not the default' "$tooling_doc" ||
   ! grep -qF 'https://docs.brew.sh/Support-Tiers' "$tooling_doc" ||
   ! grep -qF 'Ubuntu within its standard support window or a Homebrew-provided Docker image' "$tooling_doc" ||
   ! grep -qF '[the package-delivery research record](research/2026-11-14-package-delivery-layers.md)' "$tooling_doc" ||
   [[ ! -f $tooling_research ]]; then
  echo "FAIL docs/developer-tooling.md changed the ordered delivery paths, the Homebrew boundary, or the research record it cites" >&2
  failures=$((failures + 1))
else
  echo "ok   docs/developer-tooling.md keeps the ordered delivery paths and the Homebrew boundary"
fi

# The inventory is the other half of #82: every `brew` entry in the dotfiles
# Brewfile gets a row, so the page cannot claim completeness it does not have
# (the claim this check replaced), and the Homebrew row names only the tools
# Fedora 45 does not carry. A dropped row, a renamed row, or a widened Homebrew
# row reds here. The expected names are frozen in Brewfile order on purpose: a
# count alone lets a rename through, and the order is the list's own order.
inventory_rows=$(awk -F'|' '
  /^## The inventory the dotfiles install$/ { inside = 1; next }
  inside && /^## / { inside = 0 }
  inside && /^\|/ {
    cell = $2
    gsub(/^[ \t]+|[ \t]+$/, "", cell)
    if (cell == "Tool" || cell ~ /^-+$/) next
    print cell
  }' "$tooling_doc" 2>/dev/null || true)
inventory_names=$(printf '%s\n' "$inventory_rows" | sed -n 's/^`\(.*\)`$/\1/p')
expected_inventory_names=$'atuin\nazure-cli\nbash-preexec\nchezmoi\ndirenv\ndysk\nfd\ngh\ngit-credential-oauth\nglab\ngo\nrclone\nripgrep\nrestic\nshellcheck\nstarship\nstress-ng\ntealdeer\ntelevision\nugrep\nyq\nzoxide\ncharmbracelet/tap/crush'
if [[ $inventory_names != "$expected_inventory_names" ]] ||
   ! grep -qF '[the inventory measurement](research/2026-11-14-brewfile-inventory-measurement.md)' "$tooling_doc" ||
   ! grep -qF '| `fd`, `starship`, `go` (Fedora'"'"'s `golang`) | Homebrew, through the dotfiles `Brewfile` |' "$tooling_doc" ||
   [[ ! -f $tooling_inventory ]]; then
  echo "FAIL docs/developer-tooling.md no longer inventories the 23 Brewfile names in order, widened the Homebrew row, or dropped the measurement record" >&2
  failures=$((failures + 1))
else
  echo "ok   docs/developer-tooling.md inventories all 23 Brewfile names in order and links the measurement"
fi

# The desktop is one module: manifests/packages-desktop.txt plus modules/desktop/.
# A swap replaces those two paths and a headless build deletes them, so pin the
# seam rather than the product. The invariant: the shared build, the shared
# manifest, the image definition and the image verifier name no desktop product;
# only the module, the tests that exercise it and the documents that describe it
# may. The properties below are the ones any desktop must keep, so they survive
# a swap.
desktop_manifest=$repo_root/manifests/packages-desktop.txt
desktop_overlay=$repo_root/modules/desktop
desktop_names='dms|dms-greeter|niri|ghostty|quickshell|matugen|dux-search|dux-calendar|dux-files'
leaks=
if [[ ! -f $desktop_manifest ]] || [[ ! -d $desktop_overlay ]]; then
  echo "FAIL the desktop module needs both manifests/packages-desktop.txt and modules/desktop/" >&2
  failures=$((failures + 1))
elif ! grep -qx 'install_manifest /ctx/manifests/packages-desktop.txt' "$desktop_overlay/usr/libexec/ultus-atomic/build.d/50-desktop.sh"; then
  echo "FAIL the desktop build step does not install the desktop manifest" >&2
  failures=$((failures + 1))
else
  # Reachable shared files only. manifests/packages-common.lock records the
  # origin of what landed and the changelog records history, so both keep the
  # old names.
  while IFS= read -r shared; do
    if grep -qE "(^|[^[:alnum:]_-])(${desktop_names})([^[:alnum:]_-]|$)" "$shared"; then
      leaks+="${shared#"$repo_root"/}"$'\n'
    fi
  done < <(
    echo "$repo_root/Containerfile"
    echo "$repo_root/manifests/packages-common.txt"
    echo "$repo_root/tests/verify-image.sh"
    find "$repo_root/build" -type f -print
    find "$repo_root/overlay" -type f -print
    find "$repo_root/modules" -path "$desktop_overlay" -prune -o -type f -print
  )
  if [[ -n $leaks ]]; then
    echo "FAIL the shared build names a desktop product outside the module:" >&2
    printf '%s' "$leaks" >&2
    failures=$((failures + 1))
  else
    echo "ok   no desktop product name leaks outside the module"
  fi
fi

# First-login setup keeps its safety contract: no unit runs as root or as the
# greeter, every one is ordered into the session, and the setup unit is bounded,
# gated on a condition script, and marks completion so a retry cannot redo it.
module_units=$(find "$desktop_overlay/usr/lib/systemd" -type f -name '*.service' -path '*/user/*' 2>/dev/null || true)
if [[ -z $module_units ]]; then
  echo "FAIL the desktop module ships no user unit" >&2
  failures=$((failures + 1))
else
  unit_failures=0
  for unit in $module_units; do
    for line in 'ConditionUser=!root' 'ConditionUser=!greeter' 'Before='; do
      grep -q "^${line}" "$unit" || {
        echo "FAIL ${unit#"$repo_root"/} does not carry ${line}" >&2
        unit_failures=1
      }
    done
  done
  setup_unit=$(grep -l '^ExecCondition=' $module_units 2>/dev/null | head -1 || true)
  if [[ -z $setup_unit ]]; then
    echo "FAIL no desktop user unit gates first-login setup on a condition script" >&2
    unit_failures=1
  else
    condition=$(sed -n 's/^ExecCondition=//p' "$setup_unit" | head -1)
    grep -q '^TimeoutStartSec=' "$setup_unit" || {
      echo "FAIL ${setup_unit#"$repo_root"/} has no start timeout" >&2
      unit_failures=1
    }
    grep -q '^ExecStartPost=' "$setup_unit" || {
      echo "FAIL ${setup_unit#"$repo_root"/} writes no completion marker" >&2
      unit_failures=1
    }
    [[ -n $condition && -x $desktop_overlay$condition ]] || {
      echo "FAIL the first-login condition script '${condition}' is missing or not executable in the module" >&2
      unit_failures=1
    }
  fi
  if ((unit_failures == 0)); then
    echo "ok   the desktop units refuse root and the greeter, are ordered, and bound first-login setup"
  else
    failures=$((failures + 1))
  fi
fi

# The greeter seeds a session choice before greetd starts, and a seeded file is
# JSON the greeter can read.
all_module_units=$(find "$desktop_overlay/usr/lib/systemd" -type f -name '*.service' 2>/dev/null || true)
greeter_unit=$(grep -l '^Before=greetd.service' $all_module_units 2>/dev/null | head -1 || true)
seed=$(find "$desktop_overlay" -name 'memory.json' -print -quit 2>/dev/null || true)
if [[ -z $greeter_unit ]]; then
  echo "FAIL no desktop unit seeds the greeter before it starts" >&2
  failures=$((failures + 1))
elif [[ -z $seed ]] || ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$seed" 2>/dev/null; then
  echo "FAIL the greeter seed is missing or is not JSON" >&2
  failures=$((failures + 1))
elif ! grep -q 'Session' "$seed"; then
  echo "FAIL the greeter seed names no session" >&2
  failures=$((failures + 1))
else
  echo "ok   the greeter seed is JSON and pins a session name"
fi

# The identity token this branch retired. Every check below reads it from this
# one line, so the token assertion can allow that line and nothing else in this
# file.
legacy_token=dux-atomic

# Bindings travel with the module and name an absolute unit path, so a swap
# cannot leave a link pointing at a name only the old desktop shipped. A target
# that still names the old identity is the failure a rename leaves behind, and
# git grep does not read a symlink's target, so check it here. The image test
# proves each target resolves after installation, including package-owned units
# the module does not ship.
binding_failures=0
while IFS= read -r link; do
  target=$(readlink "$link")
  case $target in
    /usr/lib/systemd/*) ;;
    *) echo "FAIL ${link#"$repo_root"/} points at '${target}', not an absolute unit path" >&2
       binding_failures=1
       continue ;;
  esac
  if [[ $target == *$legacy_token* ]]; then
    echo "FAIL ${link#"$repo_root"/} still points at '${target}', which names the old identity" >&2
    binding_failures=1
  fi
done < <(find "$desktop_overlay" -type l)
if ((binding_failures == 0)); then
  echo "ok   every desktop binding names an absolute unit path inside the module's overlay"
else
  failures=$((failures + 1))
fi

# The swap procedure is documentation, so a swap that costs more than the two
# module paths reds here until the document says otherwise.
if [[ ! -f $repo_root/docs/desktop.md ]] ||
   ! grep -qF 'manifests/packages-desktop.txt' "$repo_root/docs/desktop.md" ||
   ! grep -qF 'modules/desktop/' "$repo_root/docs/desktop.md"; then
  echo "FAIL docs/desktop.md is missing or does not name both module paths" >&2
  failures=$((failures + 1))
else
  echo "ok   docs/desktop.md names the two paths a desktop swap replaces"
fi

# The first-login condition decides retry vs skip. Run the real script against
# one fixture per case so a change in its logic is visible without a VM.
condition=$repo_root/modules/desktop/usr/libexec/ultus-atomic/needs-setup.sh
if ! grep -qF '${XDG_STATE_HOME:-$HOME/.local/state}' "$condition"; then
  echo "FAIL needs-setup.sh does not match the unit's %S marker path" >&2
  failures=$((failures + 1))
fi
cond_root=$(mktemp -d)
trap 'rm -rf "$cond_root"' EXIT
mkdir -p "$cond_root/fresh" \
  "$cond_root/partial/.config/niri" \
  "$cond_root/user/.config/niri" \
  "$cond_root/done/.config/niri" "$cond_root/done/.local/state/ultus-atomic" \
  "$cond_root/reset/.local/state/ultus-atomic" \
  "$cond_root/xdgstate/.config/niri" "$cond_root/xdgstate-state/ultus-atomic"
# Copied from ~/.config/niri/config.kdl after `dms setup headless` in image
# 3e886bc33a30; see docs/research/2026-11-10-dms-first-login.md.
printf 'include optional=true "dms/colors.kdl"\n' >"$cond_root/partial/.config/niri/config.kdl"
printf '// user config\n' >"$cond_root/user/.config/niri/config.kdl"
printf 'include optional=true "dms/colors.kdl"\n' >"$cond_root/done/.config/niri/config.kdl"
printf 'include optional=true "dms/colors.kdl"\n' >"$cond_root/xdgstate/.config/niri/config.kdl"
: >"$cond_root/done/.local/state/ultus-atomic/desktop-setup.done"
: >"$cond_root/reset/.local/state/ultus-atomic/desktop-setup.done"
: >"$cond_root/xdgstate-state/ultus-atomic/desktop-setup.done"
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
elif ! grep -qF 'readlink "$portal_mask"' "$desktop_overlay/usr/libexec/ultus-atomic/build.d/50-desktop.sh" ||
     ! grep -qF '= /dev/null' "$desktop_overlay/usr/libexec/ultus-atomic/build.d/50-desktop.sh" ||
     ! grep -qF "trap desktop_cleanup EXIT" "$desktop_overlay/usr/libexec/ultus-atomic/build.d/50-desktop.sh" ||
     ! grep -qF 'copr disable duxlabs/dms' "$desktop_overlay/usr/libexec/ultus-atomic/build.d/50-desktop.sh" ||
     ! grep -qF 'cannot read ${path}' "$repo_root/build/manifest.sh" ||
     ! grep -qF 'install_manifest "$manifest"' "$common" ||
     ! grep -qF 'install_manifest /ctx/manifests/packages-desktop.txt' "$desktop_overlay/usr/libexec/ultus-atomic/build.d/50-desktop.sh" ||
     ! grep -qF '/usr/libexec/ultus-atomic/build.d/*.sh' "$common" ||
     grep -qF 'packages-common.txt || true' "$common"; then
  echo "FAIL the greeter mask, the manifest reader or a manifest install does not fail closed" >&2
  failures=$((failures + 1))
else
  echo "ok   the greeter mask and both manifest installs fail closed"
fi

# boot-smoke.sh gained an opt-in POST_LOGIN_CMD hook for automated post-login
# probes such as the dotfiles bootstrap (#70). It must stay off by default, and
# a command that never returns must fail the boot test rather than warn.
if ! grep -qF 'if [[ -n ${POST_LOGIN_CMD:-} ]]; then' "$boot_smoke" ||
   ! grep -qF 'DUX_POST_END:' "$boot_smoke" ||
   ! awk '/post-login command did not finish/ { found = 1; next }
          found { n++ }
          found && n <= 3 && /^[[:space:]]*exit 1$/ { ok = 1 }
          found && n > 3 { found = 0; n = 0 }
          END { exit ok ? 0 : 1 }' "$boot_smoke"; then
  echo "FAIL boot-smoke.sh lost the opt-in POST_LOGIN_CMD hook or its fail-closed timeout" >&2
  failures=$((failures + 1))
else
  echo "ok   boot-smoke.sh keeps the opt-in POST_LOGIN_CMD hook fail-closed"
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

# repin-base workflow assertions: file exists, weekly cron, dispatch input, probe and rewrite gating
repin_workflow=$repo_root/.github/workflows/repin-base.yml
if [[ ! -f $repin_workflow ]]; then
  echo "FAIL repin-base workflow is missing" >&2
  failures=$((failures + 1))
elif ! grep -qE '17 5 \* \* 1' "$repin_workflow"; then
  echo "FAIL repin-base workflow does not schedule weekly at '17 5 * * 1'" >&2
  failures=$((failures + 1))
elif ! grep -qF "workflow_dispatch:" "$repin_workflow" || ! grep -qF "apply:" "$repin_workflow" || ! grep -qF "default: false" "$repin_workflow"; then
  echo "FAIL repin-base workflow lacks workflow_dispatch input 'apply' defaulting to false" >&2
  failures=$((failures + 1))
elif ! grep -qF "skopeo inspect --raw" "$repin_workflow" || ! grep -qF "skopeo inspect --format '{{.Digest}}'" "$repin_workflow"; then
  echo "FAIL repin-base workflow does not probe the registry with skopeo inspect --raw and resolve with --format '{{.Digest}}'" >&2
  failures=$((failures + 1))
elif ! grep -qF "github.event_name == 'schedule'" "$repin_workflow" || ! grep -qF "github.event.inputs.apply" "$repin_workflow"; then
  echo "FAIL repin-base workflow does not gate rewrites on schedule or inputs.apply == 'true'" >&2
  failures=$((failures + 1))
elif grep -qE 'refs/heads/main' "$repin_workflow" || grep -qF "--force" "$repin_workflow"; then
  echo "FAIL repin-base workflow pushes to main or force-pushes" >&2
  failures=$((failures + 1))
else
  echo "ok   repin-base workflow file present and carries the expected probes and gates"
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

# The image ships dnf5, and the pinned base's /etc/dnf/dnf.conf carries only a
# comment and [main], so every default the linutil Configure DNF entry sets is
# absent (#111). The overlay replaces that file; the built-image readback proves
# the values dnf5 resolves, so this check keeps the file and that readback.
dnf_conf=$repo_root/overlay/etc/dnf/dnf.conf
# The readback is asserted as one whole line. A fragment is satisfied by a
# comment that mentions the command, or by a renamed call that keeps the
# fragment, so both ends are anchored and nothing else in the script counts.
dnf_readback='dnf_conf=$("$runtime" run --rm "$image" dnf5 --dump-main-config) \'
if [[ ! -f $dnf_conf ]]; then
  echo "FAIL overlay/etc/dnf/dnf.conf is missing; the image ships dnf5 with no configured defaults" >&2
  failures=$((failures + 1))
elif ! awk '
      # Only keys under [main] count: dnf5 ignores a key in another section.
      # Each key appears exactly once, because a repeated key is a reviewable
      # mistake even though dnf5 would silently take the last value.
      /^\[main\]$/ { section = 1; next }
      /^\[/ { section = 0 }
      section && /^(max_parallel_downloads|fastestmirror|defaultyes|gpgcheck)=/ {
        key = $0
        sub(/=.*/, "", key)
        seen[key]++
      }
      END {
        split("max_parallel_downloads fastestmirror defaultyes gpgcheck", want, " ")
        for (i = 1; i <= length(want); i++) if (seen[want[i]] != 1) exit 1
        exit 0
      }
    ' "$dnf_conf"; then
  echo "FAIL overlay/etc/dnf/dnf.conf does not set each of the four defaults exactly once under [main]" >&2
  failures=$((failures + 1))
elif ! grep -qxF "$dnf_readback" "$repo_root/tests/verify-image.sh"; then
  echo "FAIL tests/verify-image.sh no longer reads the dnf.conf values back with dnf5 --dump-main-config" >&2
  failures=$((failures + 1))
else
  echo "ok   the overlay ships the dnf.conf defaults and the verifier reads them back"
fi

# The image enables firewalld and the overlay replaces the public zone with a
# closed baseline: SSH for the operator and DHCPv6 for the network (#116). The
# distribution default also allows mDNS, so a file naming it reds rather than
# restoring the advertisement. The verifier's readback and its expected value are
# both kept whole: a readback whose comparison is deleted would otherwise red
# only in the hosted job, where it cannot red at all.
firewalld_zone=$repo_root/overlay/etc/firewalld/zones/public.xml
firewalld_readback='zone_services=$("$runtime" run --rm "$image" firewall-offline-cmd --zone=public --list-services) \'
firewalld_expect="if [[ \$zone_services != 'dhcpv6-client ssh' ]]; then"
if [[ ! -f $firewalld_zone ]]; then
  echo "FAIL overlay/etc/firewalld/zones/public.xml is missing; the image enables firewalld with no managed zone" >&2
  failures=$((failures + 1))
elif ! grep -qxF '  <service name="ssh"/>' "$firewalld_zone" ||
     ! grep -qxF '  <service name="dhcpv6-client"/>' "$firewalld_zone"; then
  echo "FAIL overlay/etc/firewalld/zones/public.xml does not allow both ssh and dhcpv6-client" >&2
  failures=$((failures + 1))
elif grep -qE '<service name="(mdns|http|https|samba-client|cockpit)"' "$firewalld_zone"; then
  echo "FAIL overlay/etc/firewalld/zones/public.xml opens a service the baseline does not approve" >&2
  failures=$((failures + 1))
elif ! grep -qxF "$firewalld_readback" "$repo_root/tests/verify-image.sh"; then
  echo "FAIL tests/verify-image.sh no longer reads the firewalld zone back with firewall-offline-cmd" >&2
  failures=$((failures + 1))
elif ! grep -qxF "$firewalld_expect" "$repo_root/tests/verify-image.sh"; then
  echo "FAIL tests/verify-image.sh reads the zone back but no longer compares it to 'dhcpv6-client ssh'" >&2
  failures=$((failures + 1))
else
  echo "ok   the overlay ships a closed firewalld baseline and the verifier reads it back"
fi

# job_block <name>: print one job from $workflow, so every job assertion reads
# the block the same way and a renamed job cannot widen one copy silently.
workflow=$repo_root/.github/workflows/ci.yml
job_block() {
  awk -v job="$1" '
    $0 == "  " job ":" { found = 1; next }
    found && /^  [a-z][a-z0-9-]*:/ { exit }
    found { print }
  ' "$workflow"
}
# The module's acceptance criterion is a build without it (#129), so the suite
# carries a job that deletes the module and then reads the image. A job that
# deletes the module and never reads the image proves only that dnf works.
headless_block=$(job_block headless)
if [[ -z $headless_block ]]; then
  echo "FAIL ci.yml has no headless job, so nothing proves the image builds without the desktop module" >&2
  failures=$((failures + 1))
elif ! grep -qF 'needs.changes.outputs.desktop' <<<"$headless_block"; then
  echo "FAIL the headless job is not gated on a desktop path filter" >&2
  failures=$((failures + 1))
elif ! grep -qF 'steps.desktop.outputs.desktop' "$workflow"; then
  echo "FAIL the changes job publishes no desktop output, so the headless job never runs" >&2
  failures=$((failures + 1))
elif ! grep -qF 'rm -rf modules/desktop manifests/packages-desktop.txt' <<<"$headless_block"; then
  echo "FAIL the headless job does not delete both module paths before its build" >&2
  failures=$((failures + 1))
elif ! grep -qF 'git ls-tree -r --name-only HEAD modules/desktop' <<<"$headless_block"; then
  echo "FAIL the headless job saves no list of the files the module ships" >&2
  failures=$((failures + 1))
elif ! grep -qF 'tests/verify-headless.sh localhost/ultus-atomic:headless' <<<"$headless_block"; then
  echo "FAIL the headless job builds without asserting the image carries no desktop" >&2
  failures=$((failures + 1))
elif ! grep -qF 'tests/verify-image.sh" --headless --no-package-lock' "$repo_root/tests/verify-headless.sh"; then
  echo "FAIL the headless verifier does not run the shared image assertions" >&2
  failures=$((failures + 1))
elif ! grep -qF 'path_list=$3' "$repo_root/tests/verify-headless.sh"; then
  echo "FAIL the headless verifier does not read the module path list the job saves" >&2
  failures=$((failures + 1))
elif ! grep -qF 'tests/verify-headless.sh' "$repo_root/tests/lint.sh"; then
  echo "FAIL tests/lint.sh does not lint the headless verifier" >&2
  failures=$((failures + 1))
elif ! git -C "$repo_root" ls-files -s -- tests/verify-headless.sh | grep -q '^100755 '; then
  # The job runs the verifier directly, so a committed 100644 fails the job with
  # exit 126 before it asserts anything.
  echo "FAIL tests/verify-headless.sh is not committed executable, so the headless job cannot run it" >&2
  failures=$((failures + 1))
else
  echo "ok   ci.yml builds headless without the desktop module and asserts the image"
fi
# Assert the NVIDIA CI job and its gating and flags
if ! grep -qF 'podman build --layers -f Containerfile.nvidia -t localhost/ultus-atomic:nvidia' "$workflow" ||
   # Count the verify invocation only inside the image-nvidia job block so an
   # identical invocation in another job does not false-red this check.
   image_block=$(job_block image-nvidia) && \
   [[ $(grep -cF 'tests/verify-image.sh --no-package-lock' <<<"$image_block") -ne 1 ]] || \
   ! grep -qF "tests/verify-image.sh --no-package-lock localhost/ultus-atomic:nvidia" "$workflow" ||
   ! grep -qF "if: needs.changes.outputs.nvidia == 'true'" "$workflow" ||
   ! grep -qF "^(Containerfile\\.nvidia$|manifests/packages-nvidia\\.txt$|manifests/packages-common\\.txt$|build/|overlay/|tests/verify-image\\.sh$)" "$workflow" ||
   # The variant manifest check reads the manifest on the runner and passes its
   # names to rpm as arguments, so an arch-qualified name resolves and a missing
   # one names itself on stderr.
   ! grep -qF 'mapfile -t names < <(grep -Ev' "$workflow" ||
   ! grep -qF 'podman run --rm localhost/ultus-atomic:nvidia rpm -q "${names[@]}"' "$workflow"; then
  echo "FAIL ci.yml does not carry the gated image-nvidia job, the exact filter regex, or the single --no-package-lock on its verify line" >&2
  failures=$((failures + 1))
elif ! grep -qF 'github.event.before' "$workflow" || ! grep -qF 'if [[ -z "\$before" || "\$before" =~ ^0+$ ]]' "$workflow"; then
  echo "FAIL ci.yml lost the push diff guard: github.event.before or the empty-before fallback is missing" >&2
  failures=$((failures + 1))
else
  echo "ok   ci.yml carries a path-filtered image-nvidia job with the expected verify flag and regex and a push guard"
fi

# A DNS or mirror blip on a hosted runner must not fail a release. Run
# 43033654470 spent 67 minutes in the package install before apt reported
# "Temporary failure resolving", and publish, verify and promote never ran.
# Every job installs through the bounded helper, and no bare apt-get remains.
# apt must also fail over off the mirror that is failing: run 43052107613 spent
# the whole budget on Ign: lines for azure.archive.ubuntu.com and never reached
# archive.ubuntu.com, the second entry in the runner's mirror list. Run
# 44300517908 then failed twice because the list named
# us-east-2.ec2.archive.ubuntu.com while the helper matched only the Azure
# hostname, so the entry is selected by position now (#143).
installer=$repo_root/build/install-packages.sh
mirror_helper=$repo_root/build/apt-mirror.sh
if [[ ! -x $installer ]] ||
   ! grep -qF 'budget=300' "$installer" ||
   ! grep -qF 'deadline=$((SECONDS + budget))' "$installer" ||
   ! grep -qF 'cap=$((deadline - SECONDS))' "$installer" ||
   ! grep -qF 'timeout "$cap" sudo env DEBIAN_FRONTEND=noninteractive' "$installer" ||
   ! grep -qF 'apt-get -o Acquire::Retries=1 -o Acquire::Retries::Delay=false' "$installer" ||
   ! grep -qF 'for attempt in 1 2 3; do' "$installer" ||
   ! grep -qF 'deprioritise_primary_mirror "$mirrors"' "$installer" ||
   ! grep -qF 'apt-mirror.sh' "$installer" ||
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

# The hostname was what broke twice, so the code is checked and not only the
# comment above it.
if [[ ! -f $mirror_helper ]] ||
  grep -vE '^[[:space:]]*#' "$mirror_helper" | grep -qE '[a-z0-9-]+\.archive\.ubuntu\.com'; then
  echo "FAIL the apt mirror failover selects a hostname instead of the list's first entry" >&2
  failures=$((failures + 1))
else
  echo "ok   the apt mirror failover selects the list's first entry, not a hostname"
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
signing_block=$(job_block signing)
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
publish_block=$(job_block publish)
verify_block=$(job_block verify)
promote_block=$(job_block promote)
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
     ! grep -qF -- '--predicate sbom/ultus-atomic.spdx.json --type spdxjson' <<<"$publish_block"; then
  # A legacy tag attachment becomes invisible once any Sigstore bundle
  # references the digest, because cosign then verifies in bundle mode only.
  # Run 43106659542 failed verify that way after the provenance bundle landed.
  echo "FAIL ci.yml attests the SBOM without --new-bundle-format, so the provenance bundle hides it from cosign verify-attestation" >&2
  failures=$((failures + 1))
elif [[ -z $verify_block ]] ||
     ! grep -qF 'gh attestation verify "oci://$IMAGE@$DIGEST"' <<<"$verify_block" ||
     ! grep -qF -- '--bundle-from-oci' <<<"$verify_block" ||
     ! grep -qF -- '--cert-identity "https://github.com/ultus-net/ultus-atomic/.github/workflows/ci.yml@refs/heads/main"' <<<"$verify_block" ||
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
     ! grep -qF '> ultus-atomic.spdx.json' "$workflow" ||
     ! grep -qF 'path: ultus-atomic.spdx.json' "$workflow"; then
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

# Changelog truncation gate: fail if the working tree's CHANGELOG.md has fewer
# lines than the same file on the base branch. Prefer origin/main, fall back to
# main, and emit a clear FAIL if neither resolves.
base_ref=$(git -C "$repo_root" rev-parse --verify origin/main 2>/dev/null || true)
if [[ -z $base_ref ]]; then
  base_ref=$(git -C "$repo_root" rev-parse --verify main 2>/dev/null || true)
fi
if [[ -z $base_ref ]]; then
  echo "FAIL cannot resolve a base ref (origin/main or main); cannot compare CHANGELOG.md" >&2
  failures=$((failures + 1))
else
  # Use a temp file so git show's exit status decides whether the file exists
  # at the base ref. Remove the tempdir on every path.
  tmpd=$(mktemp -d) || tmpd=""
  if [[ -z $tmpd ]]; then
    echo "FAIL cannot create tempdir to compare CHANGELOG.md" >&2
    failures=$((failures + 1))
  else
    if ! git -C "$repo_root" show "${base_ref}:CHANGELOG.md" >"$tmpd/base_changelog" 2>/dev/null; then
      echo "FAIL ${base_ref}:CHANGELOG.md not found; cannot compare changelogs" >&2
      failures=$((failures + 1))
      rm -rf "$tmpd"
    elif [[ ! -f $repo_root/CHANGELOG.md ]]; then
      echo "FAIL CHANGELOG.md is missing from the tree; cannot compare to ${base_ref}" >&2
      failures=$((failures + 1))
      rm -rf "$tmpd"
    else
      base_count=$(wc -l <"$tmpd/base_changelog" || true)
      tree_count=$(wc -l < "$repo_root/CHANGELOG.md" || true)
      rm -rf "$tmpd"
      if [[ $tree_count -lt $base_count ]]; then
        echo "FAIL CHANGELOG.md truncated: ${base_ref} has ${base_count} lines, tree has ${tree_count} lines" >&2
        failures=$((failures + 1))
      else
        echo "ok   CHANGELOG.md is not shorter than ${base_ref} (tree ${tree_count}, base ${base_count})"
      fi
    fi
  fi
fi

# The old repository/image token belongs to the historical record now. A live
# file may still name a historical path, and the upgrade rule must name the /etc
# file it removes, but nothing else may carry the token. git grep reads tracked
# file content only; the binding check above covers symlink targets. The only
# line allowed inside a live script is the definition above, so a stray use in
# this file still reds.
allowed_paths='^(docs/research/|docs/agents/|docs/superpowers/|CHANGELOG\.md:|overlay/usr/lib/tmpfiles\.d/ultus-atomic-upgrade\.conf:|tests/test-static\.sh:[0-9]+:legacy_token=)'
# A live doc cites the approved spec or plan by the filename it was recorded
# under, so that one citation stays.
allowed_citation="docs/superpowers/(specs|plans)/2026-11-09-$legacy_token"
bad=$(git grep -In -F -e "$legacy_token" | grep -Ev "$allowed_paths" | grep -Ev "$allowed_citation" || true)
if [[ -n $bad ]]; then
  echo "FAIL legacy token '${legacy_token}' found outside the historical record:" >&2
  printf "%s\n" "$bad" >&2
  failures=$((failures + 1))
else
  echo "ok   the old token appears only in the historical record and the upgrade rule"
fi

if ((failures > 0)); then
  exit 1
fi
echo "static checks passed"
