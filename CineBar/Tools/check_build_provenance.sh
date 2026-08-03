#!/bin/bash
set -euo pipefail

repo_root=${1:?Repository root is required}
version=${2:?Version is required}
build=${3:?Build number is required}
shift 3

if [[ $# -eq 0 ]]; then
  echo "At least one build input path is required" >&2
  exit 2
fi

dirty_inputs=$(git -C "$repo_root" status --porcelain=v1 \
  --untracked-files=all -- "$@")
if [[ -n "$dirty_inputs" ]]; then
  echo "Refusing to build from dirty source inputs:" >&2
  echo "$dirty_inputs" >&2
  exit 1
fi

commit=$(git -C "$repo_root" rev-parse HEAD)
source_tree=$(git -C "$repo_root" rev-parse 'HEAD^{tree}')

printf '{"commit":"%s","sourceTree":"%s","version":"%s","build":"%s","sourceTreeStatus":"clean"}\n' \
  "$commit" "$source_tree" "$version" "$build"
