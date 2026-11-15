#!/bin/bash
# Build-time desktop step. The shared build runs every script under
# /usr/libexec/dux-atomic/build.d/ in name order, so the desktop's repositories,
# packages, presets and checks travel with the desktop and the shared build
# names none of them. A variant replaces this file with the rest of
# overlay/desktop/.
set -ouex pipefail

# The desktop packages come from the Dux COPRs. duxlabs/dms pulls
# duxlabs/dux-repo, which also carries the terminal and the shell. They are
# third-party, so they stay enabled only while this step needs them: the trap
# below disables them on every exit, including a failed check, so no layer
# commits with them enabled.
dnf5 -y copr enable duxlabs/dms
dnf5 -y copr enable duxlabs/dux-repo

check_root=
desktop_cleanup() {
  [[ -z ${check_root:-} ]] || rm -rf "$check_root"
  dnf5 -y copr disable duxlabs/dms >/dev/null || true
  dnf5 -y copr disable duxlabs/dux-repo >/dev/null || true
}
trap desktop_cleanup EXIT

source /ctx/build/manifest.sh
install_manifest /ctx/manifests/packages-desktop.txt

# A new account gets the desktop on its first graphical login. A user preset
# enables both units, and the image-level compositor binding keeps the shell
# running for an account that already owns a config and skips setup. The
# fallback session never starts the compositor.
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
  echo "the shell is not bound to the compositor for new accounts" >&2
  exit 1
}
test -f /usr/bin/dms || {
  echo "the desktop CLI is missing; first-login setup would fail" >&2
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
  echo "the session state seed is missing" >&2
  exit 1
}

# The greeter picks session index 0 when it has no memory, and the desktop-file
# order is asynchronous. Seed the compositor's session as the first login.
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
rm -rf "$check_root"
check_root=

# Enable the greeter. The package ships /etc/greetd/config.toml already
# pointing at the greeter with the compositor; the enable helper needs a live
# user. The exit trap then disables the COPRs.
systemctl enable greetd
