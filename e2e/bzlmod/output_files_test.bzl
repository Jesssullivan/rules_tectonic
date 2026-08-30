"""Test rule for validating generated files in the dependency-bare consumer."""

def _output_files_test_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".sh")
    expected = "\n".join([
        "  '%s'" % name
        for name in ctx.attr.expected_files
    ])
    ctx.actions.write(
        output = executable,
        content = """#!/usr/bin/env bash
set -euo pipefail

runfiles="${RUNFILES_DIR:-${TEST_SRCDIR:-}}"
if [[ -z "$runfiles" ]]; then
  printf 'TEST_SRCDIR or RUNFILES_DIR must be set\\n' >&2
  exit 1
fi

expected=(
""" + expected + """
)

status=0
for name in "${expected[@]}"; do
  match=""
  count=0
  while IFS= read -r path; do
    match="$path"
    count=$((count + 1))
  done < <(find -L "$runfiles" -type f -name "$name" -print)

  if [[ "$count" -ne 1 ]]; then
    printf 'expected exactly one runfile named %s, found %s\\n' "$name" "$count" >&2
    status=1
    continue
  fi
  if [[ ! -s "$match" ]]; then
    printf '%s exists but is empty\\n' "$name" >&2
    status=1
    continue
  fi

  case "$name" in
    *.pdf)
      if ! head -c 5 "$match" | grep -q '%PDF-'; then
        printf '%s does not look like a PDF\\n' "$name" >&2
        status=1
      fi
      ;;
    *.log)
      if ! grep -q 'LaTeX2e' "$match"; then
        printf '%s does not look like a LaTeX compile log\\n' "$name" >&2
        status=1
      fi
      ;;
  esac
done

exit "$status"
""",
        is_executable = True,
    )
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = ctx.files.data),
    )]

output_files_test = rule(
    implementation = _output_files_test_impl,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "expected_files": attr.string_list(mandatory = True),
    },
    test = True,
)
