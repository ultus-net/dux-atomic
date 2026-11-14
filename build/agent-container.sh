#!/usr/bin/env bash
set -euo pipefail

# Run a project-scoped rootless container for agent work.
# - mounts only the project path, writable, at /work inside the container
# - uses an isolated HOME and XDG_CACHE_HOME inside a tmpdir
# - forbids mounting host HOME, ~/.ssh, podman socket, docker socket
# - prints the exact podman run invocation when AGENT_CONTAINER_DRY_RUN=1
#
# The project is mounted at /work, not at its host path. A bind mount makes
# podman create the missing parent directories of the container path, so
# mounting at /home/<user>/... would create that scaffolding inside the image
# and the "no host home" check would stop meaning anything.

usage(){
  cat <<EOF
Usage: $0 [IMAGE] PROJECT_PATH -- [COMMAND...]
Defaults: IMAGE=localhost/dux-atomic:dev
The project is mounted writable at /work and the command starts there.
Environment:
  AGENT_CONTAINER_DRY_RUN=1  Print the podman command without running it
  AGENT_CONTAINER_KEEP=1     Keep temporary dirs (for debugging)
  AGENT_CONTAINER_EXTRA      Extra podman flags, deny-by-default allowlist
                             (see docs/agent-container.md)
EOF
  exit 2
}

IMAGE=${1:-localhost/dux-atomic:dev}
PROJECT=${2:-}

if [[ "$PROJECT" == "" ]]; then
  echo "ERROR: project path is required as second argument" >&2
  usage
fi

shift 2 || true
CMD=("$@")
if [[ ${#CMD[@]} -eq 0 ]]; then
  CMD=(/bin/bash -lc "exec \"/bin/bash\"")
fi

# If caller used -- to separate args, drop it
if [[ ${CMD[0]:-} == "--" ]]; then
  CMD=("${CMD[@]:1}")
fi

forbidden_paths=("$HOME" "$HOME/.ssh" "/var/run/docker.sock" "/run/user/$(id -u)/podman/podman.sock")

# Validate project path
if [[ ! -e "$PROJECT" ]]; then
  echo "ERROR: project path '$PROJECT' does not exist" >&2
  exit 3
fi

# Refuse if the project path would include a forbidden path (for example PROJECT=/home and forbidden=/home/.ssh)
for p in "${forbidden_paths[@]}"; do
  if [[ "$p" == "$PROJECT" || "$p" == "$PROJECT"/* ]]; then
    echo "ERROR: project path '$PROJECT' would expose forbidden path '$p' inside the container" >&2
    exit 4
  fi
done

# Parse AGENT_CONTAINER_EXTRA with a deny-by-default allowlist.
# Accept only a small, audited set of flags and values. Any unknown token
# or a disallowed value causes an error and aborts.
extra_raw=${AGENT_CONTAINER_EXTRA:-}
allowed_extra_tokens=()
if [[ -n "$extra_raw" ]]; then
  # split into fields (caller must quote as needed)
  read -r -a fields <<< "$extra_raw"
  i=0
  n=${#fields[@]}
  while [[ $i -lt $n ]]; do
    tok=${fields[$i]}
    case "$tok" in
      -d|--detach)
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      --name)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for --name" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        if [[ ! $val =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA invalid --name value: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok" "$val")
        i=$((i+2))
        ;;
      --name=*)
        val=${tok#--name=}
        if [[ ! $val =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA invalid --name value: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      -e|--env)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for $tok" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        # allow KEY or KEY=VALUE where KEY matches env var name
        name=${val%%=*}
        if [[ ! $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA invalid env name: $name" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok" "$val")
        i=$((i+2))
        ;;
      --env=*)
        val=${tok#--env=}
        name=${val%%=*}
        if [[ ! $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA invalid env name: $name" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      --network)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for --network" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        case "$val" in
          none|bridge|slirp4netns)
            allowed_extra_tokens+=("$tok" "$val")
            ;;
          *)
            echo "ERROR: AGENT_CONTAINER_EXTRA disallowed --network value: $val" >&2
            exit 9
            ;;
        esac
        i=$((i+2))
        ;;
      --network=*)
        val=${tok#--network=}
        case "$val" in
          none|bridge|slirp4netns)
            allowed_extra_tokens+=("$tok")
            ;;
          *)
            echo "ERROR: AGENT_CONTAINER_EXTRA disallowed --network value: $val" >&2
            exit 9
            ;;
        esac
        i=$((i+1))
        ;;
      --net|--net=*)
        echo "ERROR: AGENT_CONTAINER_EXTRA disallowed token: $tok" >&2
        exit 9
        ;;
      --memory|--cpus|--pids-limit)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for $tok" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        if [[ ! $val =~ ^[0-9]+([kKmMgG])?$ ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA invalid numeric value: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok" "$val")
        i=$((i+2))
        ;;
      --memory=*|--cpus=*|--pids-limit=*)
        val=${tok#*=}
        if [[ ! $val =~ ^[0-9]+([kKmMgG])?$ ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA invalid numeric value: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      --read-only)
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      --cap-drop)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for --cap-drop" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        allowed_extra_tokens+=("$tok" "$val")
        i=$((i+2))
        ;;
      --cap-drop=*)
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      --security-opt)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for --security-opt" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        if [[ "$val" != "no-new-privileges" ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA disallowed security-opt: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok" "$val")
        i=$((i+2))
        ;;
      --security-opt=*)
        val=${tok#--security-opt=}
        if [[ "$val" != "no-new-privileges" ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA disallowed security-opt: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      --tmpfs)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for --tmpfs" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        if [[ "$val" != /* || "$val" != /tmp/* ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA tmpfs path must be under /tmp: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok" "$val")
        i=$((i+2))
        ;;
      --tmpfs=*)
        val=${tok#--tmpfs=}
        if [[ "$val" != /* || "$val" != /tmp/* ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA tmpfs path must be under /tmp: $val" >&2
          exit 9
        fi
        allowed_extra_tokens+=("$tok")
        i=$((i+1))
        ;;
      -w|--workdir)
        if [[ $((i+1)) -ge $n ]]; then
          echo "ERROR: AGENT_CONTAINER_EXTRA missing value for $tok" >&2
          exit 9
        fi
        val=${fields[$((i+1))]}
        # The project is /work inside; a workdir outside it is a mount bypass.
        case "$val" in
          /work|/work/*)
            allowed_extra_tokens+=("$tok" "$val")
            ;;
          *)
            echo "ERROR: AGENT_CONTAINER_EXTRA workdir must be /work or under it: $val" >&2
            exit 9
            ;;
        esac
        i=$((i+2))
        ;;
      --workdir=*)
        val=${tok#--workdir=}
        case "$val" in
          /work|/work/*)
            allowed_extra_tokens+=("$tok")
            ;;
          *)
            echo "ERROR: AGENT_CONTAINER_EXTRA workdir must be /work or under it: $val" >&2
            exit 9
            ;;
        esac
        i=$((i+1))
        ;;
      -w=* )
        val=${tok#-w=}
        case "$val" in
          /work|/work/*)
            allowed_extra_tokens+=("$tok")
            ;;
          *)
            echo "ERROR: AGENT_CONTAINER_EXTRA workdir must be /work or under it: $val" >&2
            exit 9
            ;;
        esac
        i=$((i+1))
        ;;
      --name|-d|-e|--env|--network|--memory|--cpus|--pids-limit|--read-only|--cap-drop|--security-opt|--tmpfs|--workdir|-w)
        # already handled above when present in full; fallthrough safety
        echo "ERROR: AGENT_CONTAINER_EXTRA disallowed token or bad form: $tok" >&2
        exit 9
        ;;
      *)
        echo "ERROR: AGENT_CONTAINER_EXTRA disallowed token: $tok" >&2
        exit 9
        ;;
    esac
  done
fi

# Make a quoted copy for appending to podman_cmd
extra_fields_to_append=("${allowed_extra_tokens[@]:-}")

# Build podman run args
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dux-atomic-agent.XXXXXX")
HOME_IN_CONTAINER=/home/agent
XDG_CACHE=/tmp/agent-cache
PROJECT_IN_CONTAINER=/work

mkdir -p "$TMP_ROOT${HOME_IN_CONTAINER}"
mkdir -p "$TMP_ROOT${XDG_CACHE}"
mount_args=("-v" "$PROJECT:$PROJECT_IN_CONTAINER:Z")
mount_args+=("-v" "$TMP_ROOT${HOME_IN_CONTAINER}:$HOME_IN_CONTAINER:Z")
mount_args+=("-v" "$TMP_ROOT${XDG_CACHE}:$XDG_CACHE:Z")

# Security defaults
extra_args=(--rm --userns=keep-id)

podman_cmd=(podman run)
podman_cmd+=("${extra_args[@]}")
podman_cmd+=(-e "HOME=${HOME_IN_CONTAINER}" -e "XDG_CACHE_HOME=${XDG_CACHE}")
podman_cmd+=("${mount_args[@]}")
if [[ -n "$extra_raw" ]]; then
  for f in "${extra_fields_to_append[@]:-}"; do
    podman_cmd+=("${f}")
  done
fi
podman_cmd+=(-w "$PROJECT_IN_CONTAINER" "$IMAGE")
podman_cmd+=("${CMD[@]}")

# Final command string for dry run
printf -v PODMAN_CMD_STR "%q " "${podman_cmd[@]}"

if [[ "${AGENT_CONTAINER_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY RUN: $PODMAN_CMD_STR"
  if [[ "${AGENT_CONTAINER_KEEP:-0}" != "1" ]]; then
    rm -rf "$TMP_ROOT"
  else
    echo "Temp kept: $TMP_ROOT"
  fi
  exit 0
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman not found" >&2
  exit 5
fi

# A detached container keeps reading its mounted home after this script exits,
# so only a foreground run may delete the temporary tree.
detached=0
for t in "${allowed_extra_tokens[@]:-}"; do
  if [[ "$t" == "-d" || "$t" == "--detach" ]]; then
    detached=1
  fi
done

rc=0
"${podman_cmd[@]}" || rc=$?
if [[ "${AGENT_CONTAINER_KEEP:-0}" == "1" || $detached -eq 1 ]]; then
  echo "Temp kept: $TMP_ROOT" >&2
else
  rm -rf "$TMP_ROOT"
fi
exit "$rc"
