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

# TMPDIR is intentionally unset here. On macOS the /tmp default is a symlink;
# preparation must canonicalize it before creating the owned parent.
UNSET_TMPDIR_RECORD="$OUTSIDE/unset-tmpdir-parent"
set +e
(
  set -e
  unset TMPDIR
  tectonic_stage_prepare
  printf '%s\n' "$TECTONIC_STAGE_PARENT" >"$UNSET_TMPDIR_RECORD"
  trap 'tectonic_stage_exit "$?" "$TECTONIC_STAGE_PARENT" "$TECTONIC_STAGE" "$TECTONIC_STAGE_TOKEN"' EXIT
  printf 'compile output\n' >"$TECTONIC_STAGE/result.pdf"
)
UNSET_TMPDIR_STATUS=$?
set -e
[[ "$UNSET_TMPDIR_STATUS" -eq 0 ]] || fail "unset-TMPDIR action returned $UNSET_TMPDIR_STATUS"
IFS= read -r UNSET_TMPDIR_PARENT <"$UNSET_TMPDIR_RECORD"
assert_absent "$UNSET_TMPDIR_PARENT"
assert_exists "$OUTSIDE_SENTINEL"

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
expect_refusal "empty stage" tectonic_stage_cleanup "$VALID_PARENT" "" "$VALID_TOKEN"
expect_refusal "empty token" tectonic_stage_cleanup "$VALID_PARENT" "$VALID_STAGE" ""
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

# The outer validator succeeds, then this test-only seam mutates the ownership
# marker. The explicit inner recheck must refuse before the recursive child
# delete; both the stage sentinel and the outside sentinel must survive.
INNER_SEAM_RECORD="$OUTSIDE/inner-seam-called"
tectonic_stage_cleanup_test_seam() {
  local parent="$1"
  printf 'called\n' >"$INNER_SEAM_RECORD"
  printf 'mutated-after-validation\n' >"$parent/.rules_tectonic_stage_owner"
}
expect_refusal "post-validation marker mutation" tectonic_stage_cleanup "$VALID_PARENT" "$VALID_STAGE" "$VALID_TOKEN"
assert_exists "$INNER_SEAM_RECORD"
assert_exists "$VALID_SENTINEL"
assert_exists "$OUTSIDE_SENTINEL"
printf '%s\n' "$VALID_TOKEN" >"$VALID_PARENT/.rules_tectonic_stage_owner"
tectonic_stage_cleanup_test_seam() {
  :
}

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

# A symlink substituted for the parent is refused before any marker or child is
# considered.
PARENT_SYMLINK="$OUTSIDE/rules-tectonic-stage.symlink1"
ln -s -- "$SYMLINK_PARENT" "$PARENT_SYMLINK"
expect_refusal "symlink parent" tectonic_stage_cleanup "$PARENT_SYMLINK" "$PARENT_SYMLINK/stage" "$SYMLINK_TOKEN"
assert_exists "$OUTSIDE_SENTINEL"
rm -f -- "$PARENT_SYMLINK" "$SYMLINK_STAGE"
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

rm -f -- "$UNSET_TMPDIR_RECORD" "$SUCCESS_RECORD" "$FAILURE_RECORD" "$REFUSAL_RECORD" "$INNER_SEAM_RECORD" "$OUTSIDE_SENTINEL"
rmdir -- "$FAKE_HOME"
rmdir -- "$OUTSIDE"
# The synthetic HOME lives in its own root. At the moment the guarded stage
# delete runs, HOME must already be the inherited value, not the temp home,
# and both roots must be gone afterwards with the outside sentinel intact.
HOME_OUTSIDE="$(mktemp -d "$TEST_TMPDIR/rules-tectonic-home-outside.XXXXXXXX")"
HOME_OUTSIDE_SENTINEL="$HOME_OUTSIDE/sentinel"
printf 'must survive the home cleanup\n' >"$HOME_OUTSIDE_SENTINEL"
HOME_RECORD="$HOME_OUTSIDE/home-record"
INHERITED_HOME="$HOME_OUTSIDE/inherited-home"
mkdir -- "$INHERITED_HOME"
set +e
(
  set -e
  HOME="$INHERITED_HOME"
  export HOME
  tectonic_stage_prepare
  tectonic_home_prepare
  printf '%s\n%s\n' "$TECTONIC_STAGE_PARENT" "$TECTONIC_HOME_ROOT" >"$HOME_RECORD"
  export HOME="$TECTONIC_HOME_ROOT/home"
  mkdir -p "$HOME/.cache"
  [[ "$HOME" != "$TECTONIC_STAGE"/* ]] || exit 91
  tectonic_stage_cleanup_test_seam() {
    [[ "${HOME-}" == "$INHERITED_HOME" ]] || exit 92
    [[ "${HOME-}" != "$TECTONIC_HOME_ROOT"* ]] || exit 93
  }
  trap 'tectonic_stage_exit "$?" "$TECTONIC_STAGE_PARENT" "$TECTONIC_STAGE" "$TECTONIC_STAGE_TOKEN"' EXIT
  printf 'compile output\n' >"$TECTONIC_STAGE/result.pdf"
)
HOME_STATUS=$?
set -e
[[ "$HOME_STATUS" -eq 0 ]] || fail "independent-home action returned $HOME_STATUS (91 home under stage, 92 HOME not restored, 93 HOME still inside temp root)"
{ IFS= read -r HOME_STAGE_PARENT; IFS= read -r HOME_ROOT_RECORDED; } <"$HOME_RECORD"
assert_absent "$HOME_STAGE_PARENT"
assert_absent "$HOME_ROOT_RECORDED"
assert_exists "$HOME_OUTSIDE_SENTINEL"
assert_exists "$INHERITED_HOME"

# A home root that is still the current HOME must be refused, and a root not
# prepared by this action must be refused.
tectonic_home_prepare
FAKE_HOME_ROOT="$TECTONIC_HOME_ROOT"
FAKE_HOME_TOKEN="$TECTONIC_HOME_TOKEN"
ORIGINAL_HOME="${HOME-}"
HOME="$FAKE_HOME_ROOT/home"
export HOME
expect_refusal "home root that is current HOME" tectonic_home_cleanup "$FAKE_HOME_ROOT" "$FAKE_HOME_TOKEN"
HOME="$ORIGINAL_HOME"
export HOME
expect_refusal "home root with wrong token" tectonic_home_cleanup "$FAKE_HOME_ROOT" "not-the-token"
tectonic_home_cleanup "$FAKE_HOME_ROOT" "$FAKE_HOME_TOKEN"
assert_absent "$FAKE_HOME_ROOT"
assert_exists "$HOME_OUTSIDE_SENTINEL"
rm -rf -- "$HOME_OUTSIDE"

# A successful action whose guarded cleanup refuses still succeeds: the
# outputs already exist, so the refusal is a loud warning, not a failure.
SOFT_OUTSIDE="$(mktemp -d "$TEST_TMPDIR/rules-tectonic-soft-outside.XXXXXXXX")"
SOFT_RECORD="$SOFT_OUTSIDE/soft-parent"
SOFT_STDERR="$SOFT_OUTSIDE/stderr"
set +e
(
  set -e
  tectonic_stage_prepare
  printf '%s\n' "$TECTONIC_STAGE_PARENT" >"$SOFT_RECORD"
  printf 'unexpected\n' >"$TECTONIC_STAGE_PARENT/unexpected"
  trap 'tectonic_stage_exit "$?" "$TECTONIC_STAGE_PARENT" "$TECTONIC_STAGE" "$TECTONIC_STAGE_TOKEN"' EXIT
  printf 'compile output\n' >"$TECTONIC_STAGE/result.pdf"
) 2>"$SOFT_STDERR"
SOFT_STATUS=$?
set -e
[[ "$SOFT_STATUS" -eq 0 ]] || fail "refused cleanup failed a successful action: got $SOFT_STATUS"
grep -q 'rules_tectonic: warning: could not remove action temp roots' "$SOFT_STDERR" || fail "refused cleanup after success was silent"
IFS= read -r SOFT_PARENT <"$SOFT_RECORD"
assert_exists "$SOFT_PARENT/unexpected"
rm -rf -- "$SOFT_PARENT" "$SOFT_OUTSIDE"

printf 'stage_cleanup_test: PASS\n'

