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

# Leave no third-party repo enabled in the final image.
dnf5 -y copr disable duxlabs/dms
dnf5 -y copr disable duxlabs/dux-repo

# Enable the greeter. The package ships /etc/greetd/config.toml already
# pointing at dms-greeter with niri; the enable helper needs a live user.
systemctl enable greetd
