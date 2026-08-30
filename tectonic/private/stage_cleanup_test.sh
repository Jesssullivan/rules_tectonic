#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CLEANUP_LIB="$SCRIPT_DIR/stage_cleanup.sh"
if [[ ! -f "$CLEANUP_LIB" && -n "${TEST_SRCDIR:-}" && -n "${TEST_WORKSPACE:-}" ]]; then
  CLEANUP_LIB="$TEST_SRCDIR/$TEST_WORKSPACE/tectonic/private/stage_cleanup.sh"
fi
# shellcheck source=stage_cleanup.sh
source "$CLEANUP_LIB"

: "${TEST_TMPDIR:?Bazel must provide TEST_TMPDIR}"
export TMPDIR="$TEST_TMPDIR"

fail() {
  printf 'stage_cleanup_test: %s\n' "$*" >&2
  exit 1
}

assert_exists() {
  [[ -e "$1" ]] || fail "expected path to exist: $1"
}

assert_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "expected path to be absent: $1"
}

expect_refusal() {
  local description="$1"
  shift
  local status=0
  set +e
  "$@"
  status=$?
  set -e
  (( status != 0 )) || fail "unsafe cleanup was accepted: $description"
}

OUTSIDE="$(mktemp -d "$TEST_TMPDIR/rules-tectonic-outside.XXXXXXXX")"
OUTSIDE_SENTINEL="$OUTSIDE/sentinel"
printf 'must survive every guarded cleanup\n' >"$OUTSIDE_SENTINEL"

# A successful action exits zero, removes only its fresh parent, and leaves the
# sentinel outside that parent untouched.
SUCCESS_RECORD="$OUTSIDE/success-parent"
set +e
(
  set -e
  tectonic_stage_prepare
  printf '%s\n' "$TECTONIC_STAGE_PARENT" >"$SUCCESS_RECORD"
  trap 'tectonic_stage_exit "$?" "$TECTONIC_STAGE_PARENT" "$TECTONIC_STAGE" "$TECTONIC_STAGE_TOKEN"' EXIT
  printf 'compile output\n' >"$TECTONIC_STAGE/result.pdf"
)
SUCCESS_STATUS=$?
set -e
[[ "$SUCCESS_STATUS" -eq 0 ]] || fail "successful action returned $SUCCESS_STATUS"
IFS= read -r SUCCESS_PARENT <"$SUCCESS_RECORD"
assert_absent "$SUCCESS_PARENT"
assert_exists "$OUTSIDE_SENTINEL"

# A forced compiler failure preserves the compiler's exact status while still
# cleaning the fresh parent.
FAILURE_RECORD="$OUTSIDE/failure-parent"
set +e
(
  set -e
  tectonic_stage_prepare
  printf '%s\n' "$TECTONIC_STAGE_PARENT" >"$FAILURE_RECORD"
  trap 'tectonic_stage_exit "$?" "$TECTONIC_STAGE_PARENT" "$TECTONIC_STAGE" "$TECTONIC_STAGE_TOKEN"' EXIT
  fake_tectonic_compile() { return 37; }
  fake_tectonic_compile
)
FAILURE_STATUS=$?
set -e
[[ "$FAILURE_STATUS" -eq 37 ]] || fail "compile status changed: expected 37, got $FAILURE_STATUS"
IFS= read -r FAILURE_PARENT <"$FAILURE_RECORD"
assert_absent "$FAILURE_PARENT"
assert_exists "$OUTSIDE_SENTINEL"

# Keep one valid action-owned target live while malicious argument shapes are
# attempted. Its sentinel must survive every refusal.
tectonic_stage_prepare
VALID_PARENT="$TECTONIC_STAGE_PARENT"
VALID_STAGE="$TECTONIC_STAGE"
VALID_TOKEN="$TECTONIC_STAGE_TOKEN"
VALID_SENTINEL="$VALID_STAGE/sentinel"
printf 'valid stage sentinel\n' >"$VALID_SENTINEL"

expect_refusal "unset arguments" tectonic_stage_cleanup
expect_refusal "empty parent" tectonic_stage_cleanup "" "$VALID_STAGE" "$VALID_TOKEN"
expect_refusal "parent itself as recursive target" tectonic_stage_cleanup "$VALID_PARENT" "$VALID_PARENT" "$VALID_TOKEN"
expect_refusal "filesystem root" tectonic_stage_cleanup "/" "/stage" "$VALID_TOKEN"

ORIGINAL_HOME="${HOME-}"
FAKE_HOME="$OUTSIDE/fake-home"
mkdir -- "$FAKE_HOME"
HOME="$FAKE_HOME"
export HOME
expect_refusal "HOME" tectonic_stage_cleanup "$HOME" "$HOME/stage" "$VALID_TOKEN"
HOME="$ORIGINAL_HOME"
export HOME

# Build a structurally plausible parent outside the action-owned parent. The
# token/marker and fixed child are valid, so the final same-action ownership
# check is what refuses it.
OUTSIDE_PARENT="$OUTSIDE/rules-tectonic-stage.outside1"
OUTSIDE_STAGE="$OUTSIDE_PARENT/stage"
mkdir -- "$OUTSIDE_PARENT" "$OUTSIDE_STAGE"
printf '%s\n' "$VALID_TOKEN" >"$OUTSIDE_PARENT/.rules_tectonic_stage_owner"
expect_refusal "outside substitution" tectonic_stage_cleanup "$OUTSIDE_PARENT" "$OUTSIDE_STAGE" "$VALID_TOKEN"

assert_exists "$VALID_SENTINEL"
assert_exists "$OUTSIDE_SENTINEL"
rmdir -- "$OUTSIDE_STAGE"
rm -f -- "$OUTSIDE_PARENT/.rules_tectonic_stage_owner"
rmdir -- "$OUTSIDE_PARENT"
tectonic_stage_cleanup "$VALID_PARENT" "$VALID_STAGE" "$VALID_TOKEN"
assert_absent "$VALID_PARENT"

# Replacing the exact child with a symlink must refuse without following it.
tectonic_stage_prepare
SYMLINK_PARENT="$TECTONIC_STAGE_PARENT"
SYMLINK_STAGE="$TECTONIC_STAGE"
SYMLINK_TOKEN="$TECTONIC_STAGE_TOKEN"
rmdir -- "$SYMLINK_STAGE"
ln -s -- "$OUTSIDE" "$SYMLINK_STAGE"
expect_refusal "symlink child" tectonic_stage_cleanup "$SYMLINK_PARENT" "$SYMLINK_STAGE" "$SYMLINK_TOKEN"
assert_exists "$OUTSIDE_SENTINEL"
rm -f -- "$SYMLINK_STAGE"
mkdir -- "$SYMLINK_STAGE"
tectonic_stage_cleanup "$SYMLINK_PARENT" "$SYMLINK_STAGE" "$SYMLINK_TOKEN"
assert_absent "$SYMLINK_PARENT"

# Even if guarded cleanup itself refuses, the original action failure remains
# the result. The refused parent stays intact and is dismantled non-recursively.
REFUSAL_RECORD="$OUTSIDE/refusal-parent"
set +e
(
  set -e
  tectonic_stage_prepare
  printf '%s\n' "$TECTONIC_STAGE_PARENT" >"$REFUSAL_RECORD"
  printf 'unexpected\n' >"$TECTONIC_STAGE_PARENT/unexpected"
  trap 'tectonic_stage_exit "$?" "$TECTONIC_STAGE_PARENT" "$TECTONIC_STAGE" "$TECTONIC_STAGE_TOKEN"' EXIT
  exit 23
)
REFUSAL_STATUS=$?
set -e
[[ "$REFUSAL_STATUS" -eq 23 ]] || fail "cleanup refusal masked action status: expected 23, got $REFUSAL_STATUS"
IFS= read -r REFUSAL_PARENT <"$REFUSAL_RECORD"
assert_exists "$REFUSAL_PARENT/unexpected"
assert_exists "$OUTSIDE_SENTINEL"
rmdir -- "$REFUSAL_PARENT/stage"
rm -f -- "$REFUSAL_PARENT/.rules_tectonic_stage_owner" "$REFUSAL_PARENT/unexpected"
rmdir -- "$REFUSAL_PARENT"

rm -f -- "$SUCCESS_RECORD" "$FAILURE_RECORD" "$REFUSAL_RECORD" "$OUTSIDE_SENTINEL"
rmdir -- "$FAKE_HOME"
rmdir -- "$OUTSIDE"
printf 'stage_cleanup_test: PASS\n'
