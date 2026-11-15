#!/usr/bin/env bash
# Run the built image's own lint and unit verification, then compare the
# installed third-party packages against manifests/packages-common.lock.
#
#   tests/verify-image.sh [--no-package-lock] [--headless] [image]

set -euo pipefail

# Parse optional leading flags
no_lock=0
headless=0
while [[ ${1:-} == --* ]]; do
  case "$1" in
    --no-package-lock) no_lock=1; shift ;;
    --headless) headless=1; shift ;;
    --*) echo "Usage: ${BASH_SOURCE[0]} [--no-package-lock] [--headless] [image]" >&2; exit 2 ;;
  esac
done

image=${1:-localhost/dux-atomic:dev}
runtime=${CONTAINER_RUNTIME:-podman}
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

"$runtime" run --rm "$image" bootc container lint
# The desktop contract, expressed in terms any desktop satisfies: every unit the
# image ships outside a package, and every unit its own preset enables, verifies;
# every binding resolves; the greeter command and a session entry name
# executables; and first-login setup is gated, ordered, bounded and marks
# completion. Nothing below names the shipped desktop, so these assertions
# survive a swap. A headless image has none of it, so --headless skips the block.
if ((!headless)); then
"$runtime" run --rm -i "$image" bash -s <<'IN_IMAGE'
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }

# A file in the preset or unit directories that no package owns is the image's
# own, which is the product-neutral way to find the desktop's wiring.
image_own() {
  local dir=$1 file
  for file in "$dir"/*; do
    [[ -f $file ]] || continue
    rpm -qf "$file" >/dev/null 2>&1 || echo "$file"
  done
}

mapfile -t own_presets < <(image_own /usr/lib/systemd/user-preset)
((${#own_presets[@]} > 0)) || fail "FAIL the image ships no user preset of its own"
mapfile -t preset_units < <(awk '$1 == "enable" { print $2 }' "${own_presets[@]}")
((${#preset_units[@]} > 0)) || fail "FAIL the image's own user preset enables no unit"
for unit in "${preset_units[@]}"; do
  [[ -f /usr/lib/systemd/user/$unit ]] || fail "FAIL the preset enables $unit, which the image does not ship"
done

# Every unit the image ships outside a package must verify, and so must every
# unit its own preset enables. This covers the module's units by ownership
# rather than by name, so a swapped desktop is verified without the verifier
# naming it.
mapfile -t own_system_units < <(image_own /usr/lib/systemd/system)
mapfile -t own_user_units < <(image_own /usr/lib/systemd/user)
verify_units=("${own_system_units[@]}" "${own_user_units[@]}" "${preset_units[@]/#//usr/lib/systemd/user/}")
((${#verify_units[@]} > 0)) || fail "FAIL the image ships no unit of its own"
systemd-analyze verify "${verify_units[@]}" ||
  fail "FAIL a unit the image ships or enables does not verify"

# Every binding in the image resolves, so no session starts against a missing
# unit.
bad=
while IFS= read -r -d '' link; do
  target=$(readlink "$link")
  [[ -e $target ]] || bad+="$link -> $target"$'\n'
done < <(find /usr/lib/systemd/system /usr/lib/systemd/user -type l \
  \( -path '*/.wants/*' -o -path '*/.requires/*' \) -print0)
[[ -z $bad ]] || fail "FAIL bindings point at missing units:"$'\n'"$bad"

# The greeter is configured and its command resolves.
[[ -f /etc/greetd/config.toml ]] || fail "FAIL the image ships no greeter configuration"
greeter_cmd=$(sed -n 's/^[[:space:]]*command[[:space:]]*=[[:space:]]*//p' /etc/greetd/config.toml | head -1)
greeter_cmd=${greeter_cmd//\"/}
greeter_cmd=${greeter_cmd%% *}
[[ -n $greeter_cmd ]] || fail "FAIL the greeter configuration names no command"
command -v "$greeter_cmd" >/dev/null || fail "FAIL the greeter command '$greeter_cmd' does not resolve"

# A session entry exists and names an executable, so the greeter can start one.
session=
for dir in /usr/share/wayland-sessions /usr/share/xsessions; do
  for entry in "$dir"/*.desktop; do
    [[ -f $entry ]] || continue
    session_cmd=$(sed -n 's/^Exec=//p' "$entry" | head -1)
    session_cmd=${session_cmd%% *}
    if [[ -n $session_cmd ]] && command -v "$session_cmd" >/dev/null 2>&1; then
      session=$entry
    fi
  done
done
[[ -n $session ]] || fail "FAIL no session entry names an executable"

# First-login setup is gated on a condition script, ordered, bounded and marks
# completion, so a crash retries and a hang cannot hold the session open.
setup_unit=
for unit in "${own_user_units[@]}"; do
  grep -q '^ExecCondition=' "$unit" && setup_unit=$unit
done
[[ -n $setup_unit ]] || fail "FAIL no user unit gates first-login setup on a condition"
condition=$(sed -n 's/^ExecCondition=//p' "$setup_unit" | head -1)
[[ -x $condition ]] || fail "FAIL the first-login condition $condition is not executable"
grep -q '^Before=graphical-session-pre.target' "$setup_unit" ||
  fail "FAIL the first-login unit is not ordered before the session"
grep -q '^TimeoutStartSec=' "$setup_unit" || fail "FAIL the first-login unit has no start timeout"
grep -q '^ExecStartPost=' "$setup_unit" || fail "FAIL the first-login unit writes no completion marker"
IN_IMAGE
echo "ok   the desktop contract holds: image units verify, bindings resolve, the greeter and a session start, first-login is bounded"
fi

# Every path the module ships must be present in the image, so the relocated
# overlay is proven to land where systemd and the session look. The paths come
# from the tree, not from a list of product names, so a swapped desktop is
# covered by the same assertion.
module_overlay=$repo_root/modules/desktop
if ((!headless)) && [[ -d $module_overlay ]]; then
  mapfile -t module_paths < <(cd "$module_overlay" && find . \( -type f -o -type l \) -printf '/%P\n' | sort)
  ((${#module_paths[@]} > 0)) || { echo "FAIL modules/desktop/ is empty" >&2; exit 1; }
  missing=$(printf '%s\n' "${module_paths[@]}" |
    "$runtime" run --rm -i "$image" bash -c 'while read -r path; do [[ -e $path ]] || echo "$path"; done')
  if [[ -n $missing ]]; then
    echo "FAIL the desktop module ships paths the image does not carry:"$'\n'"$missing" >&2
    exit 1
  fi
  echo "ok   every path in modules/desktop/ is present in the image (${#module_paths[@]} paths)"
fi
# The pinned base's /etc/dnf/dnf.conf carries only a comment and [main], and the
# overlay replaces it with the linutil Configure DNF defaults (#111). Ask dnf5
# for the values it resolves, so a file that parses but is not read still reds.
dnf_conf=$("$runtime" run --rm "$image" dnf5 --dump-main-config) \
  || { echo "FAIL dnf5 cannot dump the main configuration in the image" >&2; exit 1; }
for want in 'max_parallel_downloads = 10' 'fastestmirror = 1' 'defaultyes = 1' 'gpgcheck = 1'; do
  if ! grep -qxF "$want" <<<"$dnf_conf"; then
    echo "FAIL dnf5 does not resolve '${want}' from overlay/etc/dnf/dnf.conf" >&2
    exit 1
  fi
done
echo "ok   dnf5 resolves the four overlay defaults (#111)"
# firewalld is enabled in the image and the overlay replaces the public zone with
# a closed baseline (#116). Assert the file parses and that the effective service
# set is exactly that baseline, so a distro default change or an added service
# reds here instead of widening the image silently.
"$runtime" run --rm "$image" firewall-offline-cmd --check-config \
  || { echo "FAIL the firewalld configuration does not parse in the image" >&2; exit 1; }
zone_services=$("$runtime" run --rm "$image" firewall-offline-cmd --zone=public --list-services) \
  || { echo "FAIL firewall-offline-cmd cannot list the public zone services" >&2; exit 1; }
if [[ $zone_services != 'dhcpv6-client ssh' ]]; then
  echo "FAIL the public zone allows '${zone_services}', expected 'dhcpv6-client ssh'" >&2
  exit 1
fi
echo "ok   the public zone allows exactly dhcpv6-client and ssh (#116)"
# Every name in every manifest has to resolve in the built image. Query them in
# one call, so a silently dropped name fails here rather than at the first
# login, and a new manifest entry is covered without touching this script. Some
# entries are provides rather than package names (xinit), so query by
# whatprovides.
manifests=("$repo_root/manifests/packages-common.txt")
desktop_manifest=$repo_root/manifests/packages-desktop.txt
# A headless build installs the shared set only, so the module's manifest is not
# part of what has to resolve.
[[ -f $desktop_manifest && $headless -eq 0 ]] && manifests+=("$desktop_manifest")
packages=$(grep -hEv '^[[:space:]]*(#.*)?$' "${manifests[@]}")
# shellcheck disable=SC2086 # Word splitting is intended: the manifest is one name per line.
if ! "$runtime" run --rm "$image" rpm -q --whatprovides $packages >/dev/null; then
  "$runtime" run --rm "$image" rpm -q --whatprovides $packages >&2 || true
  echo "FAIL a name from a manifest does not resolve in the image" >&2
  exit 1
fi
# The Fedora base enables sshd.service, and this image documents that a fresh
# install has no console or SSH login. A base bump must not restore it.
state=$("$runtime" run --rm "$image" systemctl is-enabled sshd.service 2>&1 || true)
if [[ $state != disabled ]]; then
  echo "FAIL sshd.service is '${state}', expected disabled" >&2
  exit 1
fi
# Secure Boot needs no per-machine enrollment only while the base keeps Fedora's
# kernel and modules. The signature is the whole difference between that base
# and a base that ships its own signed kernel, so check the issuer here (#65).
# The repository mounts at /opt because /mnt is a symlink in this base and an
# older crun cannot create a bind mount over it (run 43174150389).
"$runtime" run --rm -v "$repo_root:/opt:ro" "$image" \
  bash /opt/tests/verify-kernel-signature.sh
# xdg-desktop-portal reads /etc before /usr/share, so the override is what
# routes FileChooser to gtk instead of nautilus, which this image does not ship.
# The override is a module file, so a headless image has none.
if ((!headless)); then
  "$runtime" run --rm "$image" grep -qx \
    'org.freedesktop.impl.portal.FileChooser=gtk;' \
    /etc/xdg-desktop-portal/niri-portals.conf \
    || { echo "FAIL the file-chooser portal override is missing or wrong" >&2; exit 1; }
fi
# Steam pulls the 32-bit graphics stack through its own dependencies, so this
# driver is not a manifest name and needs its own assertion.
"$runtime" run --rm "$image" rpm -q mesa-vulkan-drivers.i686 \
  || { echo "FAIL the 32-bit mesa Vulkan driver is not installed" >&2; exit 1; }
# The dotfiles bootstrap installs its npm globals only when npm exists, and it
# needs Node's TypeScript type stripping, on by default from 22.18. Fedora
# splits npm into its own package, so both the runtime and npm are checked (#67).
node_version=$("$runtime" run --rm "$image" node --version) \
  || { echo "FAIL node is not runnable in the image" >&2; exit 1; }
node_semver=${node_version#v}
node_major=${node_semver%%.*}
node_minor=${node_semver#*.}
node_minor=${node_minor%%.*}
if (( node_major < 22 || (node_major == 22 && node_minor < 18) )); then
  echo "FAIL node ${node_version} predates the 22.18 the dotfiles require" >&2
  exit 1
fi
"$runtime" run --rm "$image" npm --version >/dev/null \
  || { echo "FAIL npm is not runnable in the image" >&2; exit 1; }
# The lock records every package whose origin repository is not a Fedora
# repository. The comparison is a post-build drift gate: the build installs
# from live repositories and the lock records what landed in the image, so a
# Fedora updates bump must not red this gate. A +git build tracks an upstream
# branch and cannot be pinned; the generator leaves it out and the VM boot
# test covers a broken one.
if (( no_lock == 1 )); then
  echo "ok   package lock comparison skipped (--no-package-lock)"
else
  lock=$repo_root/manifests/packages-common.lock
  expected=$(grep -vE '^(#|$)' "$lock" || true)
  if [[ -z $expected ]]; then
    echo "FAIL the package lock has no third-party lines to compare" >&2
    exit 1
  fi
  # A nonzero status here means the generator or the image is broken, not that the
  # lock drifted, so keep the two diagnoses apart. The comparison lives in
  # build/compare-lock.sh so tests/test-lock-drift.sh can exercise it with no
  # image: its status 2 is the failed measurement, its status 1 is drift.
  if ! raw=$(CONTAINER_RUNTIME=$runtime "$repo_root/build/package-lock.sh" "$image"); then
    echo "FAIL the lock measurement failed; the generator or the image is broken" >&2
    exit 1
  fi
  compare_status=0
  compare_detail=$("$repo_root/build/compare-lock.sh" "$lock" <(printf '%s\n' "$raw") 2>&1) || compare_status=$?
  if ((compare_status == 1)); then
    echo "FAIL the third-party package lock drifted; run 'just lock'" >&2
    printf '%s\n' "$compare_detail" >&2
    exit 1
  elif ((compare_status != 0)); then
    echo "FAIL the lock measurement failed; the generator or the image is broken" >&2
    exit 1
  fi
fi
