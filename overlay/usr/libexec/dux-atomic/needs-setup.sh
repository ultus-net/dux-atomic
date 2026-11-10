#!/bin/sh
# Decide whether the first-login Dux setup must run.
#
# Exit 0 to run the setup, non-zero to skip it. A user-authored niri config is
# left alone. A dms-generated config without the completion marker is a partial
# first login, so retry it and fill the missing files.
set -eu

config=$HOME/.config/niri/config.kdl
marker=$HOME/.local/state/dux-atomic/desktop-setup.done

if [ -f "$config" ]; then
  if [ -f "$marker" ] || ! grep -q 'include optional=true "dms/' "$config"; then
    exit 1
  fi
fi
exit 0
