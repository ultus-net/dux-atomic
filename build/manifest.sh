#!/bin/bash
# The one manifest installer, sourced by the shared build and by a module's
# build step so both take the same read-failure and word-splitting rules.

# install_manifest <path>
install_manifest() {
  local path=$1 packages status
  if [[ ! -r $path ]]; then
    echo "cannot read ${path}" >&2
    exit 1
  fi
  # grep exits 1 for an all-comment manifest, which is not an error. Any other
  # non-zero exit is a read failure and must fail the build.
  if packages=$(grep -Ev '^[[:space:]]*(#.*)?$' "$path"); then
    :
  else
    status=$?
    if ((status != 1)); then
      echo "cannot read ${path} (grep exit ${status})" >&2
      exit 1
    fi
    packages=
  fi
  if [[ -n $packages ]]; then
    # Word splitting is intended: the manifest is one package per line.
    dnf5 install -y $packages
  else
    echo "no packages in ${path} yet"
  fi
}
