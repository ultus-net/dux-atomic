#!/usr/bin/env bash
# Boot the candidate qcow2 under QEMU, wait for the greeter, then log in.
#
# Needs qemu-system-x86_64 and edk2-ovmf. The image writes kernel and systemd
# output to ttyS0 through overlay/usr/lib/bootc/kargs.d/, and this script keeps
# that console bidirectional: it captures the log and types into it.
#
# The greeter itself needs a DRM render node to paint, which the default
# display-only virtio-gpu does not provide. Set VIRTIO_GL=1 to boot with
# virtio-vga-gl and an offscreen GL display, which gives the guest a render
# node; the script then also asserts the node exists.
#
# The login stage needs an account. make-disk.sh creates one, and the same
# TEST_USER and TEST_PASSWORD must be exported to this script. Set BOOT_LOGIN=0
# for a disk built with NO_TEST_USER=1.
#
#   tests/vm/boot-smoke.sh [disk.qcow2] [boot.log]

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
disk=${1:-$repo_root/output/qcow2/disk.qcow2}
log=${2:-$repo_root/.vm/boot.log}
timeout_s=${BOOT_TIMEOUT:-300}
grace_s=${BOOT_GRACE:-60}
settle_s=${BOOT_SETTLE:-15}
test_user=${TEST_USER:-dux}
test_password=${TEST_PASSWORD:-dux-test}
login=${BOOT_LOGIN:-1}
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

# QEMU does not create the pipe pair, and the reader must exist before the
# guest writes, or the first console output is lost or blocks.
pipe_in=$run_dir/serial.in
pipe_out=$run_dir/serial.out
rm -f "$pipe_in" "$pipe_out"
mkfifo "$pipe_in" "$pipe_out"
cat "$pipe_out" >"$log" &
reader_pid=$!

if [[ ${VIRTIO_GL:-0} == 1 ]]; then
  display_args=(-device virtio-vga-gl -display egl-headless)
else
  display_args=(-vga virtio -display "vnc=127.0.0.1:${VNC_DISPLAY:-1}")
fi

qemu=(qemu-system-x86_64
  -machine q35,accel=kvm -cpu host -m 4096 -smp 2
  -snapshot
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code"
  -drive if=pflash,format=raw,file="$vars"
  -drive file="$disk",if=virtio,format=qcow2
  -nic user,model=virtio-net-pci
  "${display_args[@]}"
  -serial "pipe:$run_dir/serial"
  -no-reboot)

"${qemu[@]}" &
pid=$!
# QEMU opens the far end at startup, so this connect finishes immediately.
exec 7>"$pipe_in"
cleanup() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  kill "$reader_pid" 2>/dev/null || true
  exec 7>&-
  rm -f "$vars" "$pipe_in" "$pipe_out"
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

serial_write() {
  printf '%s\n' "$1" >&7
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

if [[ $login == 1 ]]; then
  if ! wait_for 'login: *$' "$grace_s"; then
    echo "login failed: no getty prompt on the serial console" >&2
    exit 1
  fi

  serial_write "$test_user"
  if ! wait_for 'Password:' 20; then
    echo "login failed: no password prompt for ${test_user}" >&2
    tail -20 "$log" >&2 || true
    exit 1
  fi
  serial_write "$test_password"
  sleep 3

  serial_write 'echo "DUX_USER:$(id -un)"'
  serial_write 'loginctl list-sessions --no-legend | grep -q "$(id -un)" && echo DUX_SESSION_OK || echo DUX_SESSION_MISSING'
  serial_write 'test -e /dev/dri/renderD128 && echo DUX_RENDER_OK || echo DUX_RENDER_NONE'
  serial_write 'echo DUX_PROBE_END'

  if ! wait_for 'DUX_USER:' 20; then
    echo "login failed: ${test_user} did not reach a shell" >&2
    tail -20 "$log" >&2 || true
    exit 1
  fi
  if ! grep -q "DUX_USER:${test_user}" "$log"; then
    echo "login failed: the shell is not running as ${test_user}" >&2
    grep -a 'DUX_USER:' "$log" >&2 || true
    exit 1
  fi
  if ! wait_for 'DUX_PROBE_END' 20; then
    echo "login failed: the session probe did not finish" >&2
    exit 1
  fi
  if ! grep -q 'DUX_SESSION_OK' "$log"; then
    echo "login failed: loginctl does not list ${test_user}" >&2
    exit 1
  fi
  if [[ ${VIRTIO_GL:-0} == 1 ]] && ! grep -q 'DUX_RENDER_OK' "$log"; then
    echo "render failed: no /dev/dri/renderD128 under virtio-vga-gl" >&2
    exit 1
  fi
  echo "login ok: ${test_user} authenticated on the console and owns a session"
fi

echo "boot ok: graphical target, greetd, and a live greeter session are up"
echo "log: $log"
