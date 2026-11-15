#!/bin/bash
# Build-time desktop provisioning: run only inside the image build when the
# desktop overlay subtree is present. This script preserves the previous
# assertions and presets that used to live in build/common.sh.
set -eu

# Apply the user preset for the first-login units and assert their enabled
# state for new accounts.
systemctl --global preset dux-atomic-desktop.service dux-atomic-dms-defaults.service
for unit in dux-atomic-desktop dux-atomic-dms-defaults; do
  test -L "/etc/systemd/user/graphical-session-pre.target.wants/${unit}.service" || {
    echo "${unit} was not enabled for new accounts" >&2
    exit 1
  }
done

# Ensure the session-level units and bindings that make the desktop work exist.
for unit in /usr/lib/systemd/user/dms.service /usr/lib/systemd/user/niri.service; do
  test -f "$unit" || {
    echo "missing ${unit}; the first-login binding would dangle" >&2
    exit 1
  }
done
test -L /usr/lib/systemd/user/niri.service.wants/dms.service || {
  echo "a compositor binding (niri -> dms) is not present for new accounts" >&2
  exit 1
}

# The desktop's CLI must exist so first-login setup can run.
test -f /usr/bin/dms || {
  echo "the desktop's session binary is missing; first-login setup would fail" >&2
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

# Greeter seeding: ensure the greeter defaults, its wants, and the memory seed
# exist so a fresh boot deterministically selects the desktop session.
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

# Desktop-specific greeter seeding and memberships are handled by this
# provisioner; tmpfiles and ownership checks are performed at the common
# build level to keep runtime /var assertions in a single place.

# Leave the COPRs disabled in the final image. RPM Fusion free and nonfree stay
# enabled on purpose: Steam's day-2 dependencies resolve from them.
dnf5 -y copr disable duxlabs/dms
dnf5 -y copr disable duxlabs/dux-repo

# Enable the greeter. The package ships /etc/greetd/config.toml already
# pointing at dms-greeter with niri; the enable helper needs a live user.
systemctl enable greetd
