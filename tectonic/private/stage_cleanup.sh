#!/usr/bin/env bash
# Private action helper for tectonic_pdf. Recursive cleanup is permitted only
# for the fixed child of a fresh, action-owned parent created by prepare.
#
# This file is sourced by the Bazel action and by its adversarial shell tests.

TECTONIC_STAGE_PARENT=""
TECTONIC_STAGE=""
TECTONIC_STAGE_TOKEN=""

tectonic_stage_prepare() {
  local tmp_root="${TMPDIR:-/tmp}"
  local parent=""
  local stage=""
  local marker=""
  local token=""

  if [[ -z "$tmp_root" || "$tmp_root" != /* || "$tmp_root" == "/" ]]; then
    printf 'rules_tectonic: refusing unsafe temporary root: %q\n' "$tmp_root" >&2
    return 70
  fi
  if [[ -n "${HOME:-}" && "$tmp_root" == "$HOME" ]]; then
    printf 'rules_tectonic: refusing HOME as temporary root\n' >&2
    return 70
  fi
  if [[ ! -d "$tmp_root" ]]; then
    printf 'rules_tectonic: temporary root must be a directory: %q\n' "$tmp_root" >&2
    return 70
  fi

  # /tmp is a symlink on macOS. Resolve the existing root first, then create
  # the fresh parent under that canonical path; cleanup later requires the
  # parent spelling to remain canonical before it can recurse into ./stage.
  tmp_root="$(cd -P -- "$tmp_root" && pwd -P)" || return 70
  if [[ -z "$tmp_root" || "$tmp_root" == "/" ]]; then
    printf 'rules_tectonic: refusing unresolved temporary root\n' >&2
    return 70
  fi
  if [[ -n "${HOME:-}" && "$tmp_root" == "$HOME" ]]; then
    printf 'rules_tectonic: refusing resolved HOME as temporary root\n' >&2
    return 70
  fi

  parent="$(mktemp -d "${tmp_root%/}/rules-tectonic-stage.XXXXXXXX")" || return 70
  if [[ -z "$parent" || "$parent" == "/" || "$parent" == "$tmp_root" || -L "$parent" || ! -d "$parent" ]]; then
    printf 'rules_tectonic: mktemp returned an unsafe parent: %q\n' "$parent" >&2
    [[ -n "$parent" && -d "$parent" && ! -L "$parent" ]] && rmdir -- "$parent" 2>/dev/null
    return 70
  fi
  case "${parent##*/}" in
    rules-tectonic-stage.????????) ;;
    *)
      printf 'rules_tectonic: mktemp parent has unexpected name: %q\n' "$parent" >&2
      rmdir -- "$parent" 2>/dev/null
      return 70
      ;;
  esac

  stage="$parent/stage"
  marker="$parent/.rules_tectonic_stage_owner"
  token="rules-tectonic-$$-${RANDOM:-0}-${RANDOM:-0}"
  if [[ -z "$stage" || -z "$token" || "$stage" != "$parent/stage" || "$stage" == "$parent" ]]; then
    printf 'rules_tectonic: invalid fixed child or ownership token\n' >&2
    rmdir -- "$parent" 2>/dev/null
    return 70
  fi
  if ! mkdir -- "$stage"; then
    rmdir -- "$parent" 2>/dev/null
    return 70
  fi
  if ! printf '%s\n' "$token" >"$marker"; then
    rmdir -- "$stage" 2>/dev/null
    rmdir -- "$parent" 2>/dev/null
    return 70
  fi

  TECTONIC_STAGE_PARENT="$parent"
  TECTONIC_STAGE="$stage"
  TECTONIC_STAGE_TOKEN="$token"
  export TECTONIC_STAGE_PARENT TECTONIC_STAGE TECTONIC_STAGE_TOKEN
}

tectonic_stage_validate_cleanup_target() {
  local parent="${1-}"
  local stage="${2-}"
  local token="${3-}"
  local marker=""
  local marker_token=""
  local parent_name=""
  local entry=""
  local -a entries=()
  local restore_dotglob=0
  local restore_nullglob=0

  if [[ -z "$parent" || -z "$stage" || -z "$token" ]]; then
    printf 'rules_tectonic: refusing cleanup with empty target or token\n' >&2
    return 70
  fi
  if [[ "$parent" != /* || "$stage" != /* ]]; then
    printf 'rules_tectonic: refusing non-absolute cleanup target\n' >&2
    return 70
  fi
  if [[ "$parent" == "/" || "$stage" == "/" ]]; then
    printf 'rules_tectonic: refusing root cleanup target\n' >&2
    return 70
  fi
  if [[ -n "${HOME:-}" && ( "$parent" == "$HOME" || "$stage" == "$HOME" ) ]]; then
    printf 'rules_tectonic: refusing HOME cleanup target\n' >&2
    return 70
  fi

  parent_name="${parent##*/}"
  case "$parent_name" in
    rules-tectonic-stage.????????) ;;
    *)
      printf 'rules_tectonic: refusing parent without owned mktemp shape: %q\n' "$parent" >&2
      return 70
      ;;
  esac
  if [[ -L "$parent" || ! -d "$parent" ]]; then
    printf 'rules_tectonic: refusing symlink or missing parent: %q\n' "$parent" >&2
    return 70
  fi
  if [[ "$stage" != "$parent/stage" || "$stage" == "$parent" ]]; then
    printf 'rules_tectonic: refusing non-child stage: parent=%q stage=%q\n' "$parent" "$stage" >&2
    return 70
  fi
  if [[ -L "$stage" || ! -d "$stage" ]]; then
    printf 'rules_tectonic: refusing symlink or missing stage: %q\n' "$stage" >&2
    return 70
  fi

  marker="$parent/.rules_tectonic_stage_owner"
  if [[ -L "$marker" || ! -f "$marker" ]]; then
    printf 'rules_tectonic: refusing parent without regular ownership marker\n' >&2
    return 70
  fi
  IFS= read -r marker_token <"$marker" || {
    printf 'rules_tectonic: unable to read ownership marker\n' >&2
    return 70
  }
  if [[ -z "$marker_token" || "$marker_token" != "$token" ]]; then
    printf 'rules_tectonic: refusing mismatched ownership marker\n' >&2
    return 70
  fi

  shopt -q dotglob || { shopt -s dotglob; restore_dotglob=1; }
  shopt -q nullglob || { shopt -s nullglob; restore_nullglob=1; }
  entries=("$parent"/*)
  (( restore_dotglob == 0 )) || shopt -u dotglob
  (( restore_nullglob == 0 )) || shopt -u nullglob
  for entry in "${entries[@]}"; do
    if [[ "$entry" != "$stage" && "$entry" != "$marker" ]]; then
      printf 'rules_tectonic: refusing parent with unexpected entry: %q\n' "$entry" >&2
      return 70
    fi
  done

  if [[ "$parent" != "${TECTONIC_STAGE_PARENT:-}" ||
        "$stage" != "${TECTONIC_STAGE:-}" ||
        "$token" != "${TECTONIC_STAGE_TOKEN:-}" ]]; then
    printf 'rules_tectonic: refusing target not prepared by this action\n' >&2
    return 70
  fi
}

tectonic_stage_cleanup() {
  local parent="${1-}"
  local stage="${2-}"
  local token="${3-}"
  local marker_token=""

  tectonic_stage_validate_cleanup_target "$parent" "$stage" "$token" || return $?

  # Re-establish and re-check the exact relationship immediately before the
  # only recursive delete. The recursive operand is a fixed relative child;
  # the fresh parent itself is removed only with non-recursive rmdir.
  (
    set -e
    cd -P -- "$parent"
    [[ "$(pwd -P)" == "$parent" ]]
    [[ ! -L "./stage" && -d "./stage" ]]
    [[ ! -L "./.rules_tectonic_stage_owner" && -f "./.rules_tectonic_stage_owner" ]]
    IFS= read -r marker_token <"./.rules_tectonic_stage_owner"
    [[ -n "$marker_token" && "$marker_token" == "$token" ]]
    rm -rf -- "./stage"
    rm -f -- "./.rules_tectonic_stage_owner"
  ) || {
    printf 'rules_tectonic: guarded child cleanup failed\n' >&2
    return 70
  }

  rmdir -- "$parent" || {
    printf 'rules_tectonic: non-recursive parent cleanup failed: %q\n' "$parent" >&2
    return 70
  }
}

tectonic_stage_exit() {
  local action_status="${1-}"
  local parent="${2-}"
  local stage="${3-}"
  local token="${4-}"
  local cleanup_status=0

  # Prevent recursion before cleanup and preserve the status that triggered EXIT.
  trap - EXIT
  tectonic_stage_cleanup "$parent" "$stage" "$token" || cleanup_status=$?

  if [[ ! "$action_status" =~ ^[0-9]+$ || "$action_status" -gt 255 ]]; then
    printf 'rules_tectonic: invalid action status: %q\n' "$action_status" >&2
    exit 65
  fi
  if (( action_status != 0 )); then
    exit "$action_status"
  fi
  exit "$cleanup_status"
}
