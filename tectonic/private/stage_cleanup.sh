#!/usr/bin/env bash
# Private action helper for tectonic_pdf. Recursive cleanup is permitted only
# for the fixed child of a fresh, action-owned parent created by prepare.
#
# This file is sourced by the Bazel action and by its adversarial shell tests.

TECTONIC_STAGE_PARENT=""
TECTONIC_STAGE=""
TECTONIC_STAGE_TOKEN=""

# The synthetic HOME the action exports lives in its own temp root, never
# under the stage. A deletion guard on a host (lab's tinyland-home-root-guard
# refuses to remove a path whose realpath is HOME or an ancestor of it) would
# otherwise refuse the stage cleanup, because HOME pointed inside it. The
# original HOME is recorded so it can be restored before any recursive delete.
TECTONIC_HOME_ROOT=""
TECTONIC_HOME_TOKEN=""
TECTONIC_ORIGINAL_HOME=""
TECTONIC_ORIGINAL_HOME_WAS_SET=0

tectonic_resolved_tmp_root() {
  local tmp_root="${TMPDIR:-/tmp}"
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
  tmp_root="$(cd -P -- "$tmp_root" && pwd -P)" || return 70
  if [[ -z "$tmp_root" || "$tmp_root" == "/" ]]; then
    printf 'rules_tectonic: refusing unresolved temporary root\n' >&2
    return 70
  fi
  if [[ -n "${HOME:-}" && "$tmp_root" == "$HOME" ]]; then
    printf 'rules_tectonic: refusing resolved HOME as temporary root\n' >&2
    return 70
  fi
  printf '%s' "$tmp_root"
}

tectonic_home_prepare() {
  local tmp_root=""
  local root=""
  tmp_root="$(tectonic_resolved_tmp_root)" || return $?
  root="$(mktemp -d "${tmp_root%/}/rules-tectonic-home.XXXXXXXX")" || return 70
  if [[ -z "$root" || "$root" == "/" || "$root" == "$tmp_root" || -L "$root" || ! -d "$root" ]]; then
    printf 'rules_tectonic: mktemp returned an unsafe home root: %q\n' "$root" >&2
    [[ -n "$root" && -d "$root" && ! -L "$root" ]] && rmdir -- "$root" 2>/dev/null
    return 70
  fi
  case "${root##*/}" in
    rules-tectonic-home.????????) ;;
    *)
      printf 'rules_tectonic: mktemp home root has unexpected name: %q\n' "$root" >&2
      rmdir -- "$root" 2>/dev/null
      return 70
      ;;
  esac
  if [[ -n "${HOME+x}" ]]; then
    TECTONIC_ORIGINAL_HOME="$HOME"
    TECTONIC_ORIGINAL_HOME_WAS_SET=1
  else
    TECTONIC_ORIGINAL_HOME=""
    TECTONIC_ORIGINAL_HOME_WAS_SET=0
  fi
  TECTONIC_HOME_ROOT="$root"
  TECTONIC_HOME_TOKEN="rules-tectonic-home-$$-${RANDOM:-0}-${RANDOM:-0}"
  printf '%s\n' "$TECTONIC_HOME_TOKEN" >"$root/.rules_tectonic_home_owner" || {
    rmdir -- "$root" 2>/dev/null
    return 70
  }
  export TECTONIC_HOME_ROOT TECTONIC_HOME_TOKEN TECTONIC_ORIGINAL_HOME TECTONIC_ORIGINAL_HOME_WAS_SET
}

# Put HOME back to what the action inherited. Runs before any recursive
# delete, so a host guard keyed on HOME never sees a temp root as HOME.
tectonic_home_restore() {
  # Nothing was recorded unless tectonic_home_prepare ran; leave HOME alone.
  [[ -n "${TECTONIC_HOME_ROOT:-}" ]] || return 0
  if (( TECTONIC_ORIGINAL_HOME_WAS_SET == 1 )); then
    HOME="$TECTONIC_ORIGINAL_HOME"
    export HOME
  else
    unset HOME
  fi
}

tectonic_home_cleanup() {
  local root="${1-}"
  local token="${2-}"
  local marker_token=""
  local physical_root=""

  if [[ -z "$root" || -z "$token" ]]; then
    printf 'rules_tectonic: refusing home cleanup with empty root or token\n' >&2
    return 70
  fi
  if [[ "$root" != /* || "$root" == "/" ]]; then
    printf 'rules_tectonic: refusing unsafe home root: %q\n' "$root" >&2
    return 70
  fi
  if [[ -n "${HOME:-}" && ( "$root" == "$HOME" || "$HOME" == "$root"/* ) ]]; then
    printf 'rules_tectonic: refusing to remove the current HOME: %q\n' "$root" >&2
    return 70
  fi
  case "${root##*/}" in
    rules-tectonic-home.????????) ;;
    *)
      printf 'rules_tectonic: refusing home root without owned mktemp shape: %q\n' "$root" >&2
      return 70
      ;;
  esac
  if [[ -L "$root" || ! -d "$root" ]]; then
    printf 'rules_tectonic: refusing symlink or missing home root: %q\n' "$root" >&2
    return 70
  fi
  if [[ "$root" != "${TECTONIC_HOME_ROOT:-}" || "$token" != "${TECTONIC_HOME_TOKEN:-}" ]]; then
    printf 'rules_tectonic: refusing home root not prepared by this action\n' >&2
    return 70
  fi
  (
    cd -P -- "$root" || exit 70
    physical_root="$(pwd -P)" || exit 70
    [[ "$physical_root" == "$root" ]] || exit 70
    [[ ! -L "./.rules_tectonic_home_owner" && -f "./.rules_tectonic_home_owner" ]] || exit 70
    IFS= read -r marker_token <"./.rules_tectonic_home_owner" || exit 70
    [[ -n "$marker_token" && "$marker_token" == "$token" ]] || exit 70
    [[ ! -L "./home" ]] || exit 70
    if [[ -d "./home" ]]; then
      rm -rf -- "./home" || exit 70
    fi
    rm -f -- "./.rules_tectonic_home_owner" || exit 70
    exit 0
  ) || {
    printf 'rules_tectonic: guarded home cleanup failed\n' >&2
    return 70
  }
  rmdir -- "$root" || {
    printf 'rules_tectonic: non-recursive home root cleanup failed: %q\n' "$root" >&2
    return 70
  }
}

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

# Tests override this no-op only to force a state change between the outer
# validator and the immediately-before-delete recheck.
tectonic_stage_cleanup_test_seam() {
  :
}

tectonic_stage_cleanup() {
  local parent="${1-}"
  local stage="${2-}"
  local token="${3-}"
  local marker_token=""
  local physical_parent=""

  tectonic_stage_validate_cleanup_target "$parent" "$stage" "$token" || return $?
  tectonic_stage_cleanup_test_seam "$parent" "$stage" "$token" || {
    printf 'rules_tectonic: post-validation cleanup seam failed\n' >&2
    return 70
  }

  # Bash disables errexit inside compound commands that are the left operand
  # of ||, including functions reached from that context. Every operation here
  # therefore has its own explicit failure branch. Re-establish and re-check
  # the exact relationship immediately before the only recursive delete.
  (
    cd -P -- "$parent" || exit 70
    physical_parent="$(pwd -P)" || exit 70
    [[ "$physical_parent" == "$parent" ]] || exit 70
    [[ ! -L "./stage" && -d "./stage" ]] || exit 70
    [[ ! -L "./.rules_tectonic_stage_owner" && -f "./.rules_tectonic_stage_owner" ]] || exit 70
    IFS= read -r marker_token <"./.rules_tectonic_stage_owner" || exit 70
    [[ -n "$marker_token" && "$marker_token" == "$token" ]] || exit 70
    rm -rf -- "./stage" || exit 70
    rm -f -- "./.rules_tectonic_stage_owner" || exit 70
    exit 0
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
  # Cleanup failures are collected explicitly below; errexit must not turn one
  # into the action's status.
  trap - EXIT
  set +e
  # The action script never exports the synthetic HOME (it is scoped to the
  # tectonic process), so this is defense in depth: HOME is the inherited value
  # before anything is deleted, and a host guard keyed on HOME cannot mistake a
  # temp root for the home root.
  tectonic_home_restore
  tectonic_stage_cleanup "$parent" "$stage" "$token" || cleanup_status=$?
  if [[ -n "${TECTONIC_HOME_ROOT:-}" ]]; then
    tectonic_home_cleanup "$TECTONIC_HOME_ROOT" "$TECTONIC_HOME_TOKEN" || cleanup_status=$?
  fi

  if [[ ! "$action_status" =~ ^[0-9]+$ || "$action_status" -gt 255 ]]; then
    printf 'rules_tectonic: invalid action status: %q\n' "$action_status" >&2
    exit 65
  fi
  if (( action_status != 0 )); then
    exit "$action_status"
  fi
  if (( cleanup_status != 0 )); then
    # The outputs were already produced and moved into place. A refused or
    # failed temp cleanup is reported loudly but does not fail the build.
    printf 'rules_tectonic: warning: could not remove action temp roots %q and %q (cleanup status %s); outputs are complete\n' \
      "$parent" "${TECTONIC_HOME_ROOT:-}" "$cleanup_status" >&2
  fi
  exit 0
}
