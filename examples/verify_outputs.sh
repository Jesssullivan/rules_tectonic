#!/usr/bin/env bash
set -euo pipefail

runfiles="${RUNFILES_DIR:-${TEST_SRCDIR:-}}"
if [[ -z "$runfiles" ]]; then
  echo "TEST_SRCDIR or RUNFILES_DIR must be set" >&2
  exit 1
fi

status=0

for expected in "$@"; do
  match=""
  count=0
  while IFS= read -r path; do
    match="$path"
    count=$((count + 1))
  done < <(find -L "$runfiles" -type f -name "$expected" -print)

  if [[ "$count" -ne 1 ]]; then
    echo "expected exactly one runfile named $expected, found $count" >&2
    status=1
    continue
  fi

  path="$match"
  if [[ ! -s "$path" ]]; then
    echo "$expected exists but is empty" >&2
    status=1
    continue
  fi

  case "$expected" in
    *.pdf)
      if ! head -c 5 "$path" | grep -q "%PDF-"; then
        echo "$expected does not look like a PDF" >&2
        status=1
      fi
      ;;
    *.log)
      if ! grep -q "LaTeX2e" "$path"; then
        echo "$expected does not look like a LaTeX compile log" >&2
        status=1
      fi
      ;;
  esac
done

exit "$status"
