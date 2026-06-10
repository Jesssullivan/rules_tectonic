#!/usr/bin/env bash
set -euo pipefail

runfiles="${RUNFILES_DIR:-${TEST_SRCDIR:-}}"
if [[ -z "$runfiles" ]]; then
  echo "TEST_SRCDIR or RUNFILES_DIR must be set" >&2
  exit 1
fi

committed=""
generated=""

while IFS= read -r path; do
  case "$path" in
    */docs/defs.md)
      committed="$path"
      ;;
    */docs/defs.generated.md)
      generated="$path"
      ;;
  esac
done < <(find -L "$runfiles" -type f \( -name "defs.md" -o -name "defs.generated.md" \) -print)

if [[ -z "$committed" ]]; then
  echo "committed docs/defs.md was not found in runfiles" >&2
  exit 1
fi

if [[ -z "$generated" ]]; then
  echo "generated docs/defs.generated.md was not found in runfiles" >&2
  exit 1
fi

if ! cmp -s "$committed" "$generated"; then
  echo "docs/defs.md is stale; run: bazel build //docs:defs_doc && cp bazel-bin/docs/defs.generated.md docs/defs.md" >&2
  diff -u "$committed" "$generated" >&2 || true
  exit 1
fi
