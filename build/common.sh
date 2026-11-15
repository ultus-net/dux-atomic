#!/bin/bash
# Common image build: apply the overlay, enable the Dux COPRs, then install the
# shared package set. Runs inside the image with /ctx holding the build context.

set -ouex pipefail

cp -avf /ctx/overlay/. /
# If a desktop subtree is present, copy it separately so a variant can replace
# the desktop wholesale by providing overlay/desktop/ instead of files at the
# overlay root.
if [[ -d /ctx/overlay/desktop ]]; then
  cp -avf /ctx/overlay/desktop/. /
fi

# The Fedora base ships dnf5 without its plugins, and `copr` is a plugin
# subcommand. Install it before any repository work.
dnf5 install -y dnf5-plugins

# Dux shell and greeter come from duxlabs. duxlabs/dms pulls duxlabs/dux-repo,
# which also carries ghostty and quickshell.
dnf5 -y copr enable duxlabs/dms
dnf5 -y copr enable duxlabs/dux-repo

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
install_manifest() {
  local path=$1 packages status
  if [[ ! -r $path ]]; then
    echo "cannot read ${path}" >&2
    exit 1
  fi
  # grep exits 1 for an all-comment manifest, which is not an error. Any other
  # non-zero exit is a read failure and must fail the build.
  if packages=$(grep -Ev '^[[:space:]]*(#.*)?$' "$path"); then
    :
  else
    status=$?
    if ((status != 1)); then
      echo "cannot read ${path} (grep exit ${status})" >&2
      exit 1
    fi
    packages=
  fi
  if [[ -n $packages ]]; then
    # Word splitting is intended: the manifest is one package per line.
    dnf5 install -y $packages
  else
    echo "no packages in ${path} yet"
  fi
}

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

# The Universal Blue base shipped the Flathub remote, and the Dux documentation
# installs user applications from it. Seed the same remote here.
install -d /etc/flatpak/remotes.d
curl --retry 3 -fsSLo /etc/flatpak/remotes.d/flathub.flatpakrepo \
  https://dl.flathub.org/repo/flathub.flatpakrepo

if [[ -f /usr/libexec/dux-atomic/desktop-provision.sh ]]; then
  bash /usr/libexec/dux-atomic/desktop-provision.sh
fi

# Check the greeter tmpfiles rule in a scratch root, so the image keeps no
# runtime /var content. The passwd and group copies let tmpfiles resolve owner
# names against the scratch root. This is a build-level check, not a desktop
# product assertion, so keep it in the common build path.
check_root=$(mktemp -d)
# Remove the scratch root on any exit, including a failed assertion.
trap 'rm -rf "$check_root"' EXIT
mkdir -p "$check_root/etc"
cp /etc/passwd /etc/group "$check_root/etc/"
systemd-tmpfiles --create --root="$check_root" /usr/lib/tmpfiles.d/dux-atomic-greetd.conf || {
  echo "greeter tmpfiles rule failed" >&2
  exit 1
}
portal_mask=$check_root/var/lib/greeter/.config/systemd/user/xdg-desktop-portal.service
test -L "$portal_mask" || {
  echo "greeter portal mask was not created" >&2
  exit 1
}
test "$(readlink "$portal_mask")" = /dev/null || {
  echo "greeter portal mask does not point at /dev/null" >&2
  exit 1
}
test "$(stat -c %U:%G "$check_root/var/lib/greeter")" = "greeter:greeter" || {
  echo "greeter home is not owned by greeter" >&2
  exit 1
}

# Leave the COPRs disabled in the final image. RPM Fusion free and nonfree stay
# enabled on purpose: Steam's day-2 dependencies resolve from them.
dnf5 -y copr disable duxlabs/dms
dnf5 -y copr disable duxlabs/dux-repo

# Enable the greeter. The package ships /etc/greetd/config.toml already
# pointing at dms-greeter with niri; the enable helper needs a live user.
systemctl enable greetd
