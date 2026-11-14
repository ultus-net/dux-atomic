#!/bin/bash
# Common image build: apply the overlay, enable the Dux COPRs, then install the
# shared package set. Runs inside the image with /ctx holding the build context.

set -ouex pipefail

cp -avf /ctx/overlay/. /

# The Fedora base ships dnf5 without its plugins, and `copr` is a plugin
# subcommand. Install it before any repository work.
dnf5 install -y dnf5-plugins

# Dux shell and greeter come from duxlabs. duxlabs/dms pulls duxlabs/dux-repo,
# which also carries ghostty and quickshell.
dnf5 -y copr enable duxlabs/dms
dnf5 -y copr enable duxlabs/dux-repo

# Steam ships only from negativo17's multimedia repository, which the Fedora
# base does not carry. Keep the priority the Universal Blue base used.
curl --retry 3 -fsSLo /etc/yum.repos.d/fedora-multimedia.repo \
  https://negativo17.org/repos/fedora-multimedia.repo
sed -i '/^\[fedora-multimedia\]$/a priority=90' /etc/yum.repos.d/fedora-multimedia.repo

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
  install_manifest "/ctx/manifests/${PACKAGE_MANIFEST_EXTRA}"
fi

# akmods builds against the headers of the kernel the image boots, so a devel
# package for another kernel is a first-boot failure instead of a build failure.
# The shared image ships no kernel-devel, so this does nothing there.
if rpm -q kernel-devel >/dev/null 2>&1; then
  mapfile -t kernels < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel | sort -V)
  mapfile -t devels < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-devel)
  bash /ctx/build/check-kernel-devel.sh "${kernels[-1]}" "${devels[@]}"
fi

# Fedora's base enables sshd.service. This image documents that a fresh install
# has no console or SSH login, so keep the unit disabled.
systemctl disable sshd.service

# The Universal Blue base shipped the Flathub remote, and the Dux documentation
# installs user applications from it. Seed the same remote here.
install -d /etc/flatpak/remotes.d
curl --retry 3 -fsSLo /etc/flatpak/remotes.d/flathub.flatpakrepo \
  https://dl.flathub.org/repo/flathub.flatpakrepo

# A new account gets the Dux desktop on its first graphical login. A user
# preset enables both units, and the image-level niri.service.wants link keeps
# dms running for an account that already owns a niri config and skips setup.
# The Xfce fallback never starts niri.service.
systemctl --global preset dux-atomic-desktop.service dux-atomic-dms-defaults.service
for unit in dux-atomic-desktop dux-atomic-dms-defaults; do
  test -L "/etc/systemd/user/graphical-session-pre.target.wants/${unit}.service" || {
    echo "${unit} was not enabled for new accounts" >&2
    exit 1
  }
done
for unit in /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service; do
  test -f "$unit" || {
    echo "missing ${unit}; the first-login binding would dangle" >&2
    exit 1
  }
done
test -L /usr/lib/systemd/user/niri.service.wants/dms.service || {
  echo "dms is not bound to niri.service for new accounts" >&2
  exit 1
}
test -f /usr/bin/dms || {
  echo "the dms CLI is missing; first-login setup would fail" >&2
  exit 1
}
test -x /usr/libexec/dux-atomic/needs-setup.sh || {
  echo "the first-login condition script is missing or not executable" >&2
  exit 1
}
unit=/usr/lib/systemd/user/dux-atomic-desktop.service
grep -qx 'ExecCondition=/usr/libexec/dux-atomic/needs-setup.sh' "$unit" || {
  echo "the first-login unit does not use the setup condition" >&2
  exit 1
}
grep -qx 'ExecStartPost=/usr/bin/install -Dm0644 /dev/null %S/dux-atomic/desktop-setup.done' "$unit" || {
  echo "the first-login unit has no completion marker" >&2
  exit 1
}
test -f /usr/share/dux-atomic/dms/session.json || {
  echo "the DMS session seed is missing" >&2
  exit 1
}

# The greeter picks session index 0 when it has no memory, and the desktop-file
# order is asynchronous. Seed niri as the first-login session.
for path in \
  /usr/lib/systemd/system/dux-atomic-greeter-defaults.service \
  /usr/lib/systemd/system/greetd.service.wants/dux-atomic-greeter-defaults.service \
  /usr/share/dux-atomic/greeter/memory.json; do
  test -e "$path" || {
    echo "missing ${path}; the greeter default would be undefined" >&2
    exit 1
  }
done
getent passwd greeter >/dev/null || {
  echo "the greeter account is missing; the session seed cannot be owned" >&2
  exit 1
}

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

# Leave the COPRs disabled in the final image. The negativo17 multimedia repo
# stays enabled on purpose: Steam's day-2 dependencies resolve from it, and the
# Universal Blue base shipped it enabled too.
dnf5 -y copr disable duxlabs/dms
dnf5 -y copr disable duxlabs/dux-repo

# Enable the greeter. The package ships /etc/greetd/config.toml already
# pointing at dms-greeter with niri; the enable helper needs a live user.
systemctl enable greetd
