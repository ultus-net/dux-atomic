#!/usr/bin/env bash
# Boot the candidate qcow2 under QEMU and wait for a login prompt.
#
# Needs qemu-system-x86_64 and edk2-ovmf on the host. The image writes console
# output to ttyS0 through overlay/usr/lib/bootc/kargs.d/10-console.toml.
#
#   tests/vm/boot-smoke.sh [disk.qcow2] [boot.log]

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
disk=${1:-$repo_root/output/qcow2/disk.qcow2}
log=${2:-$repo_root/output/boot.log}
timeout_s=${BOOT_TIMEOUT:-240}

find_ovmf() {
  local dir suffix
  for dir in /usr/share/edk2/x64 /usr/share/edk2-ovmf/x64; do
    for suffix in 4m.fd fd; do
      if [[ -f $dir/OVMF_CODE.$suffix && -f $dir/OVMF_VARS.$suffix ]]; then
        echo "$dir/OVMF_CODE.$suffix $dir/OVMF_VARS.$suffix"
        return 0
      fi
    done
  done
  return 1
}

[[ -f $disk ]] || { echo "missing disk: $disk" >&2; exit 2; }
read -r ovmf_code ovmf_vars < <(find_ovmf) || {
  echo "missing OVMF firmware; install edk2-ovmf" >&2
  exit 2
}

vars=$(mktemp)
cp "$ovmf_vars" "$vars"
rm -f "$log"

qemu=(qemu-system-x86_64
  -machine q35,accel=kvm -cpu host -m 4096 -smp 2
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code"
  -drive if=pflash,format=raw,file="$vars"
  -drive file="$disk",if=virtio,format=qcow2
  -nic user,model=virtio-net-pci
  -display none
  -serial file:"$log"
  -no-reboot)

"${qemu[@]}" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -f "$vars"' EXIT

deadline=$((SECONDS + timeout_s))
while ((SECONDS < deadline)); do
  if [[ -f $log ]] && grep -qE 'login:|dux-atomic:' "$log"; then
    echo "boot ok: login prompt reached"
    exit 0
  fi
  sleep 2
done

echo "boot failed: no login prompt in ${timeout_s}s" >&2
tail -40 "$log" >&2 || true
exit 1
