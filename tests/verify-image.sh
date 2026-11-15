#!/usr/bin/env bash
# Run the built image's own lint and unit verification, then compare the
# installed third-party packages against manifests/packages-common.lock.
#
#   tests/verify-image.sh [--no-package-lock] [image]

set -euo pipefail

# Parse optional leading flags
no_lock=0
while [[ ${1:-} == --* ]]; do
  case "$1" in
    --no-package-lock) no_lock=1; shift ;;
    --*) echo "Usage: ${BASH_SOURCE[0]} [--no-package-lock] [image]" >&2; exit 2 ;;
  esac
done

image=${1:-localhost/dux-atomic:dev}
runtime=${CONTAINER_RUNTIME:-podman}
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

"$runtime" run --rm "$image" bootc container lint
# Contract checks: session entry exists, greeter seed present, compositor
# bindings resolve, and the first-login provisioner/preset pieces are present.
session_entry=$("$runtime" run --rm "$image" bash -c 'find /usr -type f -path "*/dms/session.json" -print -quit' || true)
if [[ -z $session_entry ]]; then
  echo "FAIL no desktop session entry found in image under */dms/session.json" >&2
  exit 1
fi
greeter_seed_present=$("$runtime" run --rm "$image" bash -c 'test -f /usr/share/dux-atomic/greeter/memory.json && grep -q "lastSessionDesktopId" /usr/share/dux-atomic/greeter/memory.json && echo ok || true' || true)
if [[ $greeter_seed_present != ok ]]; then
  echo "FAIL greeter memory seed missing or lacking lastSessionDesktopId in image" >&2
  exit 1
fi
# Compositor binding resolution: any unit wants symlink under /usr/lib/systemd/user/*/.wants must point at an existing unit.
binding_bad=$("$runtime" run --rm "$image" bash -ec '
  bad=0
  while IFS= read -r -d "" link; do
    target=$(readlink "$link")
    if [[ ! -e "${target}" ]]; then
      echo "$link -> $target"
      bad=1
    fi
  done < <(find /usr/lib/systemd/user -type l -path "*/.wants/*" -print0)
  exit $bad
' || true)
if [[ -n $binding_bad ]]; then
  echo "FAIL a compositor/service binding in image points at a missing unit: $binding_bad" >&2
  exit 1
fi
# First-login provisioning pieces: condition script executable and at least one user preset enabling units exists.
if ! "$runtime" run --rm "$image" test -x /usr/libexec/dux-atomic/needs-setup.sh >/dev/null 2>&1; then
  echo "FAIL /usr/libexec/dux-atomic/needs-setup.sh missing or not executable in image" >&2
  exit 1
fi
preset_ok=$("$runtime" run --rm "$image" bash -c 'grep -q "^enable " /usr/lib/systemd/user-preset/*.preset 2>/dev/null && echo ok || true' || true)
if [[ $preset_ok != ok ]]; then
  echo "FAIL no user preset enabling first-login units found in image" >&2
  exit 1
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
# The Fedora base carries no desktop, so every name in the manifest has to
# resolve in the built image. Query all of them in one call, so a silently
# dropped name fails here rather than at the first login, and a new manifest
# entry is covered without touching this script. Two entries are provides
# (dms-greeter, xinit), so query by whatprovides rather than package name.
packages=$(grep -Ev '^[[:space:]]*(#.*)?$' "$repo_root/manifests/packages-common.txt")
# shellcheck disable=SC2086 # Word splitting is intended: the manifest is one name per line.
if ! "$runtime" run --rm "$image" rpm -q --whatprovides $packages >/dev/null; then
  "$runtime" run --rm "$image" rpm -q --whatprovides $packages >&2 || true
  echo "FAIL a name from manifests/packages-common.txt does not resolve in the image" >&2
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
"$runtime" run --rm "$image" grep -qx \
  'org.freedesktop.impl.portal.FileChooser=gtk;' \
  /etc/xdg-desktop-portal/niri-portals.conf \
  || { echo "FAIL the file-chooser portal override is missing or wrong" >&2; exit 1; }
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
