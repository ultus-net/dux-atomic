#!/usr/bin/env bash
# Boot the candidate qcow2 under QEMU and wait for the greeter session.
#
# Needs qemu-system-x86_64 and edk2-ovmf. The image writes kernel and systemd
# output to ttyS0 through overlay/usr/lib/bootc/kargs.d/. The test asserts on
# that log: the graphical target, greetd, and a greeter session scope that is
# still running after a settle period.
#
# The VNC display lets a human watch the boot. QEMU's display-only virtio-gpu
# has no render node, so the greeter compositor cannot paint here; check
# rendering on a GL-capable display or real hardware.
#
#   tests/vm/boot-smoke.sh [disk.qcow2] [boot.log]

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
disk=${1:-$repo_root/output/qcow2/disk.qcow2}
log=${2:-$repo_root/.vm/boot.log}
timeout_s=${BOOT_TIMEOUT:-300}
grace_s=${BOOT_GRACE:-60}
settle_s=${BOOT_SETTLE:-15}
run_dir=$(dirname -- "$log")
mkdir -p "$run_dir"

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
[[ -w $disk ]] || {
  echo "disk is not writable: $disk" >&2
  echo "rebuild with make-disk.sh, or copy the disk to a writable path" >&2
  exit 2
}
read -r ovmf_code ovmf_vars < <(find_ovmf) || {
  echo "missing OVMF firmware; install edk2-ovmf" >&2
  exit 2
}

vars=$(mktemp)
cp "$ovmf_vars" "$vars"
rm -f "$log"

qemu=(qemu-system-x86_64
  -machine q35,accel=kvm -cpu host -m 4096 -smp 2
  -snapshot
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code"
  -drive if=pflash,format=raw,file="$vars"
  -drive file="$disk",if=virtio,format=qcow2
  -nic user,model=virtio-net-pci
  -vga virtio
  -display "vnc=127.0.0.1:${VNC_DISPLAY:-1}"
  -serial file:"$log"
  -no-reboot)

"${qemu[@]}" &
pid=$!
cleanup() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$vars"
}
trap cleanup EXIT

wait_for() {
  local pattern=$1 deadline=$((SECONDS + $2))
  while ((SECONDS < deadline)); do
    # systemd colors the unit name, so allow bytes between the words.
    if [[ -f $log ]] && grep -qE "$pattern" "$log"; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "qemu exited while waiting for: $pattern" >&2
      return 1
    fi
    sleep 2
  done
  return 1
}

if ! wait_for 'Reached target .*graphical\.target' "$timeout_s"; then
  echo "boot failed: graphical target not reached in ${timeout_s}s" >&2
  tail -40 "$log" >&2 || true
  exit 1
fi

if ! wait_for 'Started .*greetd\.service' "$grace_s"; then
  echo "boot failed: greetd did not start in ${grace_s}s" >&2
  exit 1
fi

if ! wait_for 'Session c[0-9]+ of User greeter' "$grace_s"; then
  echo "boot failed: no greeter session started in ${grace_s}s" >&2
  exit 1
fi

sleep "$settle_s"
if ! kill -0 "$pid" 2>/dev/null; then
  echo "boot failed: qemu exited during the ${settle_s}s settle period" >&2
  tail -40 "$log" >&2 || true
  exit 1
fi
if grep -qE 'Stopped .*session-c[0-9]+\.scope' "$log"; then
  echo "boot failed: the greeter session stopped within ${settle_s}s" >&2
  tail -40 "$log" >&2 || true
  exit 1
fi

echo "boot ok: graphical target, greetd, and a live greeter session are up"
echo "log: $log"
