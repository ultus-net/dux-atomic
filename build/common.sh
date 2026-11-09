#!/bin/bash
# Common image build: apply the overlay, enable the Dux COPRs, then install the
# shared package set. Runs inside the image with /ctx holding the build context.

set -ouex pipefail

cp -avf /ctx/overlay/. /

# Dux shell and greeter come from duxlabs. duxlabs/dms pulls duxlabs/dux-repo,
# which also carries ghostty and quickshell.
dnf5 -y copr enable duxlabs/dms
dnf5 -y copr enable duxlabs/dux-repo

packages=$(grep -Ev '^[[:space:]]*(#.*)?$' /ctx/manifests/packages-common.txt || true)
if [[ -n $packages ]]; then
  # Word splitting is intended: the manifest is one package per line.
  dnf5 install -y $packages
else
  echo "no packages in manifests/packages-common.txt yet"
fi

# The greeter compositor needs the video, render, and input device groups.
# shadow-utils reads only /etc/group, so copy the vendor groups from
# /usr/lib/group into /etc/group first. usermod exits 0 for a group it cannot
# find, so assert the membership afterwards.
for group in video render input; do
  grep -q "^${group}:" /etc/group || grep "^${group}:" /usr/lib/group >> /etc/group
done
usermod -aG video,render,input greeter
for group in video render input; do
  id -nG greeter | tr ' ' '\n' | grep -qx "$group" || {
    echo "greeter is not in the ${group} group" >&2
    exit 1
  }
done

# Check the greeter tmpfiles rule in a scratch root, so the image keeps no
# runtime /var content. The passwd and group copies let tmpfiles resolve owner
# names against the scratch root.
check_root=$(mktemp -d)
mkdir -p "$check_root/etc"
cp /etc/passwd /etc/group "$check_root/etc/"
systemd-tmpfiles --create --root="$check_root" /usr/lib/tmpfiles.d/dux-atomic-greetd.conf || {
  echo "greeter tmpfiles rule failed" >&2
  exit 1
}
test -L "$check_root/var/lib/greeter/.config/systemd/user/xdg-desktop-portal.service" || {
  echo "greeter portal mask was not created" >&2
  exit 1
}
test "$(stat -c %U:%G "$check_root/var/lib/greeter")" = "greeter:greeter" || {
  echo "greeter home is not owned by greeter" >&2
  exit 1
}
rm -rf "$check_root"

# Leave no third-party repo enabled in the final image.
dnf5 -y copr disable duxlabs/dms
dnf5 -y copr disable duxlabs/dux-repo

# Enable the greeter. The package ships /etc/greetd/config.toml already
# pointing at dms-greeter with niri; the enable helper needs a live user.
systemctl enable greetd
