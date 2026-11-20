#!/bin/bash
# Common image build: apply the overlay, install the shared package set, then
# hand over to any module. Runs inside the image with /ctx holding the build
# context.

set -ouex pipefail

cp -avf /ctx/overlay/. /
# A module ships a tree under modules/<name>/ that mirrors /, and each tree is
# copied onto / so a variant replaces a whole module with one directory. The
# copy targets / directly and never copies modules/ itself, so no directory
# named after a module is created. An unmatched glob skips the loop.
for module in /ctx/modules/*/; do
  [[ -d $module ]] || continue
  cp -avf "$module." /
done

# The Fedora base ships dnf5 without its plugins, and `copr` is a plugin
# subcommand. Install it before any repository work.
dnf5 install -y dnf5-plugins

# RPM Fusion free and nonfree replace negativo17's fedora-multimedia repository,
# which the Fedora base does not carry and which states it is not RPM Fusion
# compatible. Its priority=90 let it override Fedora's own packages; RPM Fusion
# is multi-maintainer and replaces none of them, so it needs no priority.
# gpgcheck=True in overlay/etc/dnf/dnf.conf is the trust anchor for both.
release=$(rpm -E %fedora)
release_rpms=$(mktemp -d)
for repo in free nonfree; do
  curl --retry 3 -fsSLo "${release_rpms}/rpmfusion-${repo}-release.rpm" \
    "https://download1.rpmfusion.org/${repo}/fedora/rpmfusion-${repo}-release-${release}.noarch.rpm"
  dnf5 install -y "${release_rpms}/rpmfusion-${repo}-release.rpm"
done
rm -rf "$release_rpms"

manifest=/ctx/manifests/packages-common.txt

# One installer for every manifest, so a variant's extra set takes the same
# read-failure and word-splitting rules as the shared set.
source /ctx/build/manifest.sh

install_manifest "$manifest"

# A variant image installs one extra manifest after the shared set, so its
# Containerfile names a file in this repository instead of repeating the
# installer. Unset is the shared image, which is every other Containerfile here.
if [[ -n ${PACKAGE_MANIFEST_EXTRA:-} ]]; then
  # The variable names a file in manifests/, not a path. The helper turns the
  # name into the path, so a typo and an escape attempt fail the same way.
  extra=$(bash /ctx/build/check-manifest-name.sh "$PACKAGE_MANIFEST_EXTRA")
  install_manifest "$extra"
fi

# akmods builds against the headers of the kernel the image boots, so a devel
# package for another kernel is a build failure instead of an image without a
# module. The shared image ships no kernel-devel, so this does nothing there.
if rpm -q kernel-devel >/dev/null 2>&1; then
  mapfile -t kernels < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel | sort -V)
  mapfile -t devels < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-devel)
  bash /ctx/build/check-kernel-devel.sh "${kernels[-1]}" "${devels[@]}"
fi

# The variant ships akmod-nvidia and the shared image does not, so this block is
# a no-op there. A base that dragged an akmod in would need its headers anyway.
if rpm -q akmod-nvidia >/dev/null 2>&1; then
  bash /ctx/build/build-nvidia-modules.sh
fi

# Fedora's base enables sshd.service. This image documents that a fresh install
# has no console or SSH login, so keep the unit disabled.
systemctl disable sshd.service

# A module may ship build-time steps under /usr/libexec/ultus-atomic/build.d/.
# They run in name order after the shared install, so a module owns its
# repositories, its packages, its presets and its checks, and this build names
# none of them. An unmatched glob leaves the test below to skip the loop.
for step in /usr/libexec/ultus-atomic/build.d/*.sh; do
  [[ -e $step ]] || continue
  bash "$step"
done
