#!/usr/bin/env bash
# Comment out the highest-priority mirror in an apt mirror list.
#
# The runner reads its list from /etc/apt/apt-mirrors.txt, and the host of its
# first entry moves with the runner image: azure.archive.ubuntu.com in 2026-11,
# us-east-2.ec2.archive.ubuntu.com later. Match the position, never the
# hostname, or a renamed host disables the failover silently (#143).
#
#   deprioritise_primary_mirror <file>
#
# Prints the commented entry and returns 0 when it changed the file. Returns 1
# and changes nothing when the file is missing, has fewer than two active
# entries, has no active entry, or the write itself fails, so a short list is
# never emptied and a failed write is never reported as a change.

deprioritise_primary_mirror() {
  local file=${1:-}
  [[ -n $file && -f $file ]] || return 1

  local active
  active=$(grep -cE '^[[:space:]]*https?://[^[:space:]]+' "$file" || true)
  ((active > 1)) || return 1

  local target line entry
  target=$(grep -nE -m1 '^[[:space:]]*https?://[^[:space:]]+' "$file") || return 1
  line=${target%%:*}
  sudo sed -i -E "${line}s|^([[:space:]]*)(https?://)|\1# \2|" "$file" || return 1
  entry=${target#*:}
  printf '%s\n' "${entry#"${entry%%[![:space:]]*}"}"
}
