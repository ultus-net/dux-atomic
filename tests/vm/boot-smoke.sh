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
  local pair code vars
  # Fedora, Arch, and Ubuntu layout the OVMF files differently.
  local -a pairs=(
    "/usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd"
    "/usr/share/edk2/x64/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_VARS.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
    "/usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_VARS_4M.fd"
    "/usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd"
  )
  for pair in "${pairs[@]}"; do
    read -r code vars <<<"$pair"
    if [[ -f $code && -f $vars ]]; then
      echo "$code $vars"
      return 0
    fi
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

# KVM where available; TCG on a hosted runner without /dev/kvm. TCG is slow,
# so raise BOOT_TIMEOUT for a hosted run.
accel=${QEMU_ACCEL:-kvm}
if [[ $accel == kvm && ! -e /dev/kvm ]]; then
  echo "no /dev/kvm; falling back to TCG" >&2
  accel=tcg
fi
cpu=${QEMU_CPU:-host}
if [[ $accel == tcg && -z ${QEMU_CPU:-} ]]; then
  cpu=max
fi

qemu=()
qemu+=(qemu-system-x86_64)
qemu+=(-machine "q35,accel=$accel" -cpu "$cpu" -m 4096 -smp 2)
qemu+=(-snapshot)
qemu+=(-drive "if=pflash,format=raw,readonly=on,file=$ovmf_code")
qemu+=(-drive "if=pflash,format=raw,file=$vars")
qemu+=(-drive "file=$disk,if=virtio,format=qcow2")
qemu+=(-nic "user,model=virtio-net-pci")
qemu+=("${display_args[@]}")
qemu+=(-serial "pipe:$run_dir/serial")
qemu+=(-no-reboot)

"${qemu[@]}" 2>"$run_dir/qemu.err" &
pid=$!
# Open the write side read-write so this never blocks, even if QEMU fails to
# start (no KVM, EGL, or firmware) and never opens its end of the pipe.
exec 7<>"$pipe_in"
cleanup() {
  status=$?
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  kill "$reader_pid" 2>/dev/null || true
  exec 7>&-
  rm -f "$vars" "$pipe_in" "$pipe_out"
  if (( status != 0 )) && [[ -s $run_dir/qemu.err ]]; then
    echo "qemu stderr:" >&2
    tail -20 "$run_dir/qemu.err" >&2 || true
  fi
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

# A boot can lose its console output while the guest keeps running. Ask the
# getty for a fresh prompt before treating a missing log line as a dead system.
console_alive() {
  local before after
  before=$(grep -ac 'login:' "$log" 2>/dev/null || true)
  serial_write ''
  sleep 6
  after=$(grep -ac 'login:' "$log" 2>/dev/null || true)
  (( after > before ))
}

if ! wait_for 'Reached target .*graphical\.target' "$timeout_s"; then
  if grep -qE 'Session c[0-9]+ of User greeter' "$log" && console_alive; then
    echo "warning: no graphical.target line, but the greeter session is live and the console answers" >&2
    target_seen=0
  else
    echo "boot failed: graphical target not reached in ${timeout_s}s" >&2
    tail -40 "$log" >&2 || true
    exit 1
  fi
else
  target_seen=1
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
  # Wait for the login shell's prompt instead of a fixed sleep. A missing
  # prompt means the login failed, so do not send probes into an unknown state.
  if ! wait_for "${test_user}@" 20; then
    echo "login failed: no shell prompt for ${test_user}" >&2
    tail -20 "$log" >&2 || true
    exit 1
  fi

  serial_write 'printf "DUX_USER:%s\n" "$(id -un)"'
  serial_write 'loginctl list-sessions --no-legend | grep -q "$(id -un)" && printf "DUX_SESSION:%s\n" ok || printf "DUX_SESSION:%s\n" missing'
  serial_write 'test -e /dev/dri/renderD128 && printf "DUX_RENDER:%s\n" ok || printf "DUX_RENDER:%s\n" none'
  serial_write 'echo "DUX_GREETER_GROUPS:$(id -nG greeter | tr " " ",")"'
  serial_write 'echo "DUX_KARGS:$(ls /usr/lib/bootc/kargs.d/ | tr "\n" ",")"'
  serial_write 'echo "DUX_DEPLOYMENT:$(ostree admin status 2>/dev/null | head -2 | tr "\n" " ")"'
  # Run the first-login units the way graphical-session-pre.target would, then
  # check the provisioned files. The unit conditions skip a provisioned home.
  serial_write 'systemctl --user start dux-atomic-desktop.service dux-atomic-dms-defaults.service; printf "DUX_UNITS:%s\n" "$?"'
  serial_write 'printf "DUX_NIRI_CONFIG:%s\n" "$(test -f "$HOME/.config/niri/config.kdl" && echo ok || echo missing)"'
  serial_write 'printf "DUX_DMS_BINDS:%s\n" "$(test -f "$HOME/.config/niri/dms/binds.kdl" && echo ok || echo missing)"'
  serial_write 'printf "DUX_SESSION_SEED:%s\n" "$(grep -q 101418 "$HOME/.local/state/dms/session.json" 2>/dev/null && echo ok || echo missing)"'
  serial_write 'printf "DUX_SETUP_MARKER:%s\n" "$(test -f "${XDG_STATE_HOME:-$HOME/.local/state}/dux-atomic/desktop-setup.done" && echo ok || echo missing)"'
  serial_write 'printf "DUX_USER_DMS_LINK:%s\n" "$(test -L "$HOME/.config/systemd/user/niri.service.wants/dms.service" && echo ok || echo missing)"'
  serial_write 'printf "DUX_DMS_WANTED:%s\n" "$(systemctl --user show -p Wants niri.service | grep -q dms.service && echo ok || echo missing)"'
  serial_write 'printf "DUX_PRE_WANTED:%s\n" "$(systemctl --user show -p Wants niri.service | grep -q graphical-session-pre.target && echo ok || echo missing)"'
  serial_write 'printf "DUX_DESKTOP_ENABLED:%s\n" "$(systemctl --user is-enabled dux-atomic-desktop.service 2>/dev/null | grep -qx enabled && echo ok || echo missing)"'
  # The greeter cache is 0750 greeter:greeter, so the test user cannot read
  # memory.json. Assert the seed unit's state over the system bus instead.
  serial_write 'probe=$(systemctl show -p ConditionResult -p Result dux-atomic-greeter-defaults.service); printf "DUX_GREETER_SEED:%s\n" "$(echo "$probe" | grep -q "ConditionResult=yes" && echo "$probe" | grep -q "Result=success" && echo ok || echo missing)"'
  serial_write 'printf "DUX_PROBE_END:%s\n" ok'

  if ! wait_for "DUX_USER:${test_user}" 20; then
    echo "login failed: ${test_user} did not reach a shell" >&2
    tail -20 "$log" >&2 || true
    exit 1
  fi
  if ! wait_for 'DUX_PROBE_END:ok' 90; then
    echo "login failed: the session probe did not finish" >&2
    exit 1
  fi
  # The command text holds "DUX_SESSION:%s", so only real output matches the
  # literal marker.
  if ! grep -q 'DUX_SESSION:ok' "$log"; then
    echo "login failed: loginctl does not list ${test_user}" >&2
    exit 1
  fi
  if ! grep -q 'DUX_UNITS:0' "$log"; then
    echo "first login failed: the provisioning units did not both succeed" >&2
    grep -a 'DUX_UNITS:' "$log" >&2 || true
    exit 1
  fi
  for marker in DUX_NIRI_CONFIG DUX_DMS_BINDS DUX_SESSION_SEED DUX_SETUP_MARKER DUX_USER_DMS_LINK DUX_DMS_WANTED DUX_PRE_WANTED DUX_DESKTOP_ENABLED DUX_GREETER_SEED; do
    if ! grep -q "${marker}:ok" "$log"; then
      echo "first login failed: ${marker} is not ok" >&2
      grep -a "${marker}:" "$log" >&2 || true
      exit 1
    fi
  done
  if [[ ${VIRTIO_GL:-0} == 1 ]] && ! grep -q 'DUX_RENDER:ok' "$log"; then
    echo "render failed: no /dev/dri/renderD128 under virtio-vga-gl" >&2
    exit 1
  fi
  greeter_groups=$(grep -a -m1 -E 'DUX_GREETER_GROUPS:[a-z]' "$log" || true)
  for group in video render input; do
    if [[ $greeter_groups != *"$group"* ]]; then
      echo "boot failed: greeter is not in the ${group} group on the running system" >&2
      echo "$greeter_groups" >&2
      exit 1
    fi
  done
  echo "login ok: ${test_user} authenticated on the console and owns a session"
fi

if [[ $target_seen == 1 ]]; then
  echo "boot ok: graphical target, greetd, and a live greeter session are up"
else
  echo "boot ok with graphical.target unverified: greetd and a live greeter session are up, but the console lost the target line"
fi
echo "log: $log"
