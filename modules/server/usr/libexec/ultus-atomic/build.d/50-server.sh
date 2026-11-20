#!/bin/bash
# Build-time server step. The shared build runs every script under
# /usr/libexec/ultus-atomic/build.d/ in name order, so the server's unit
# enablement travels with the server module and the shared build names none
# of it.
set -ouex pipefail

# The unit file's [Install] section enables nothing by itself, and the base's
# preset scripts do not know this unit. A mount that is not enabled is a data
# disk that never appears, so assert the enabled state at build time rather
# than trust the symlink.
systemctl enable var-srv.mount
enabled=$(systemctl is-enabled var-srv.mount || true)
[[ $enabled == enabled ]] || {
  echo "var-srv.mount is not enabled (got: ${enabled:-nothing}); the data disk would not mount" >&2
  exit 1
}
