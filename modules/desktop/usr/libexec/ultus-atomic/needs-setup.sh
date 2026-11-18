#!/bin/sh
# Decide whether the first-login Dux setup must run.
#
# Exit 0 to run the setup, non-zero to skip it. A user-authored Hyprland config
# is left alone. A dms-generated config without the completion marker is a
# partial first login, so retry it and fill the missing files.
set -eu

config=$HOME/.config/hypr/hyprland.lua
# Match the unit's %S specifier, which honours XDG_STATE_HOME. A fixed
# $HOME/.local/state path would diverge for a home that sets it.
marker=${XDG_STATE_HOME:-$HOME/.local/state}/ultus-atomic/desktop-setup.done

if [ -f "$config" ]; then
  if [ -f "$marker" ] || ! grep -q 'require("dms\.' "$config"; then
    exit 1
  fi
fi
exit 0
