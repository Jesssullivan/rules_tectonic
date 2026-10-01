#!/usr/bin/env bash
# Regression test for the tectonic_pdf action script under a host deletion
# guard: an `rm` earlier on PATH that refuses any operand that is HOME or an
# ancestor of HOME (the shape of a fleet home-root guard). Through 0.2.2 the
# action exported a synthetic HOME inside the stage it deletes on EXIT, so the
# guard refused the cleanup and the action failed after the PDF was produced.
#
# This runs the exact TECTONIC_ACTION_SCRIPT text from tectonic_pdf.bzl the way
# Bazel's run_shell does (bash -c SCRIPT "" ARGS...), with a fake tectonic.
set -euo pipefail

: "${TEST_TMPDIR:?Bazel must provide TEST_TMPDIR}"

fail() {
  printf 'action_home_guard_test: %s\n' "$*" >&2
  exit 1
}

runfile() {
  local rel="$1"
  local candidate=""
  for candidate in \
    "${TEST_SRCDIR:-}/${TEST_WORKSPACE:-_main}/$rel" \
    "${TEST_SRCDIR:-}/_main/$rel" \
    "$rel"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  fail "missing runfile: $rel"
}

ACTION_SCRIPT_FILE="$(runfile tectonic/private/tests/tectonic_action_script.sh)"
CLEANUP_LIB="$(runfile tectonic/private/stage_cleanup.sh)"
ACTION_SCRIPT="$(cat -- "$ACTION_SCRIPT_FILE")"
[[ "$ACTION_SCRIPT" == *'tectonic_stage_exit'* ]] || fail "action script text looks wrong"

WORK="$(cd -P -- "$TEST_TMPDIR" && pwd -P)/work"
mkdir -p "$WORK"
REAL_RM="$(command -v rm)"
[[ -n "$REAL_RM" ]] || fail "no rm on PATH"

# The inherited HOME of the user running the build.
USER_HOME="$WORK/user-home"
mkdir -p "$USER_HOME"

# --- rm guard shim -----------------------------------------------------------
SHIM_DIR="$WORK/shim"
SHIM_LOG="$WORK/rm-shim.log"
mkdir -p "$SHIM_DIR"
cat >"$SHIM_DIR/rm" <<'SHIM'
#!/usr/bin/env bash
# Refuse any operand that resolves to HOME or an ancestor of HOME. When
# RM_SHIM_REFUSE_ALL=1, refuse every call (models a guard that refuses cleanup
# outright). Every call is logged with the HOME it saw.
set -u
log="${RM_SHIM_LOG:?}"
printf 'call HOME=%s args=%s\n' "${HOME-<unset>}" "$*" >>"$log"
if [[ "${RM_SHIM_REFUSE_ALL:-0}" == "1" ]]; then
  printf 'refused-all\n' >>"$log"
  printf 'rm-shim: refusing (refuse-all mode)\n' >&2
  exit 2
fi
resolve() {
  local p="$1"
  if [[ -d "$p" ]]; then
    (cd -P -- "$p" && pwd -P)
  else
    local d b
    d="$(dirname -- "$p")"
    b="$(basename -- "$p")"
    [[ -d "$d" ]] || { printf '%s' "$p"; return; }
    printf '%s/%s' "$(cd -P -- "$d" && pwd -P)" "$b"
  fi
}
home_real=""
if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
  home_real="$(cd -P -- "$HOME" && pwd -P)"
fi
end_of_opts=0
for arg in "$@"; do
  if (( end_of_opts == 0 )); then
    case "$arg" in
      --) end_of_opts=1; continue ;;
      -*) continue ;;
    esac
  fi
  [[ -e "$arg" || -L "$arg" ]] || continue
  target="$(resolve "$arg")"
  if [[ -n "$home_real" && ( "$target" == "$home_real" || "$home_real" == "$target"/* ) ]]; then
    printf 'refused %s (HOME=%s)\n' "$target" "$home_real" >>"$log"
    printf 'rm-shim: refusing to remove HOME or an ancestor of HOME: %s\n' "$target" >&2
    exit 2
  fi
done
exec "${RM_SHIM_REAL:?}" "$@"
SHIM
chmod 0755 "$SHIM_DIR/rm"

# --- fake tectonic -----------------------------------------------------------
FAKE_TECTONIC="$WORK/fake-tectonic"
FAKE_ENV_LOG="$WORK/fake-tectonic.env"
cat >"$FAKE_TECTONIC" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
src=""
outdir=""
while (( $# > 0 )); do
  case "$1" in
    -X|compile|--keep-logs|--only-cached|--synctex|--untrusted) shift ;;
    --outdir) outdir="$2"; shift 2 ;;
    --format|--bundle|--reruns) shift 2 ;;
    *) src="$1"; shift ;;
  esac
done
[[ -n "$src" && -n "$outdir" ]] || { echo "fake-tectonic: bad args" >&2; exit 64; }
{
  printf 'HOME=%s\n' "${HOME-}"
  printf 'XDG_CACHE_HOME=%s\n' "${XDG_CACHE_HOME-}"
  printf 'XDG_CONFIG_HOME=%s\n' "${XDG_CONFIG_HOME-}"
  printf 'XDG_DATA_HOME=%s\n' "${XDG_DATA_HOME-}"
  printf 'TECTONIC_CACHE_DIR=%s\n' "${TECTONIC_CACHE_DIR-}"
} >"${FAKE_TECTONIC_ENV_LOG:?}"
# Prove the action-private home and cache are writable.
printf 'cache\n' >"$XDG_CACHE_HOME/probe"
printf 'cache\n' >"$TECTONIC_CACHE_DIR/probe"
stem="$(basename -- "$src" .tex)"
printf '%%PDF-1.5 fake\n' >"$outdir/$stem.pdf"
printf 'fake log\n' >"$outdir/$stem.log"
FAKE
chmod 0755 "$FAKE_TECTONIC"

SRC="$WORK/hello.tex"
printf '\\documentclass{article}\\begin{document}x\\end{document}\n' >"$SRC"

TMP_ROOT="$WORK/tmp"
mkdir -p "$TMP_ROOT"

# run_action <out-dir> [extra env assignments...]
run_action() {
  local outdir="$1"
  shift
  mkdir -p "$outdir"
  env -i \
    PATH="$SHIM_DIR:/bin:/usr/bin:/usr/local/bin" \
    HOME="$USER_HOME" \
    TMPDIR="$TMP_ROOT" \
    RM_SHIM_LOG="$SHIM_LOG" \
    RM_SHIM_REAL="$REAL_RM" \
    FAKE_TECTONIC_ENV_LOG="$FAKE_ENV_LOG" \
    "$@" \
    bash -c "$ACTION_SCRIPT" "" \
    "$CLEANUP_LIB" "$FAKE_TECTONIC" "$SRC" \
    "$outdir/hello.pdf" hello.pdf \
    "$outdir/hello.log" hello.log \
    "" hello.synctex.gz \
    "" latex -1 0 0 0
}

assert_no_temp_roots() {
  local leftovers=()
  shopt -s nullglob
  leftovers=("$TMP_ROOT"/rules-tectonic-*)
  shopt -u nullglob
  (( ${#leftovers[@]} == 0 )) || fail "temp roots left behind: ${leftovers[*]}"
}

env_value() {
  sed -n "s/^$1=//p" "$FAKE_ENV_LOG"
}

# --- case 1: guarded rm on PATH, build succeeds, cleanup sees inherited HOME --
: >"$SHIM_LOG"
set +e
run_action "$WORK/out1" 2>"$WORK/case1.stderr"
status=$?
set -e
[[ "$status" -eq 0 ]] || { cat "$WORK/case1.stderr" >&2; cat "$SHIM_LOG" >&2; fail "action failed under the rm guard: status $status"; }
[[ -s "$WORK/out1/hello.pdf" && -s "$WORK/out1/hello.log" ]] || fail "outputs missing"
grep -q '^call ' "$SHIM_LOG" || fail "rm shim was never invoked; PATH shim not exercised"
if grep -q '^refused' "$SHIM_LOG"; then
  cat "$SHIM_LOG" >&2
  fail "rm guard refused a cleanup operand"
fi
while IFS= read -r line; do
  [[ "$line" == "call HOME=$USER_HOME args="* ]] || fail "rm saw a HOME other than the inherited one: $line"
done < <(grep '^call ' "$SHIM_LOG")
[[ "$(env_value HOME)" == "$TMP_ROOT"/rules-tectonic-home.*/home ]] || fail "tectonic HOME not action-private: $(env_value HOME)"
[[ "$(env_value XDG_CACHE_HOME)" == "$(env_value HOME)/.cache" ]] || fail "XDG_CACHE_HOME not scoped under tectonic HOME"
[[ "$(env_value TECTONIC_CACHE_DIR)" == "$TMP_ROOT"/rules-tectonic-stage.*/stage/cache ]] || fail "default TECTONIC_CACHE_DIR not in stage: $(env_value TECTONIC_CACHE_DIR)"
assert_no_temp_roots
[[ -d "$USER_HOME" ]] || fail "inherited HOME disappeared"

# --- case 2: a consumer TECTONIC_CACHE_DIR still wins --------------------------
PERSISTENT_CACHE="$WORK/persistent-cache"
: >"$SHIM_LOG"
run_action "$WORK/out2" TECTONIC_CACHE_DIR="$PERSISTENT_CACHE" 2>"$WORK/case2.stderr" || {
  cat "$WORK/case2.stderr" >&2
  fail "action with consumer TECTONIC_CACHE_DIR failed"
}
[[ "$(env_value TECTONIC_CACHE_DIR)" == "$PERSISTENT_CACHE" ]] || fail "consumer TECTONIC_CACHE_DIR was overridden"
[[ -f "$PERSISTENT_CACHE/probe" ]] || fail "consumer cache not used"
assert_no_temp_roots

# --- case 3: cleanup refused outright; a successful build still succeeds -------
: >"$SHIM_LOG"
set +e
run_action "$WORK/out3" RM_SHIM_REFUSE_ALL=1 2>"$WORK/case3.stderr"
status=$?
set -e
[[ "$status" -eq 0 ]] || { cat "$WORK/case3.stderr" >&2; fail "refused cleanup failed a successful build: status $status"; }
[[ -s "$WORK/out3/hello.pdf" ]] || fail "outputs missing when cleanup was refused"
grep -q 'refused-all' "$SHIM_LOG" || fail "refuse-all shim was not exercised"
grep -q 'rules_tectonic: warning: could not remove action temp roots' "$WORK/case3.stderr" || {
  cat "$WORK/case3.stderr" >&2
  fail "refused cleanup was silent"
}
# Clean up what the refused run left behind, with the real rm.
"$REAL_RM" -rf -- "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

# --- case 4: a failing compile keeps its status under the guard ----------------
FAILING_TECTONIC="$WORK/failing-tectonic"
printf '#!/usr/bin/env bash\nexit 37\n' >"$FAILING_TECTONIC"
chmod 0755 "$FAILING_TECTONIC"
set +e
env -i PATH="$SHIM_DIR:/bin:/usr/bin:/usr/local/bin" HOME="$USER_HOME" TMPDIR="$TMP_ROOT" \
  RM_SHIM_LOG="$SHIM_LOG" RM_SHIM_REAL="$REAL_RM" \
  bash -c "$ACTION_SCRIPT" "" "$CLEANUP_LIB" "$FAILING_TECTONIC" "$SRC" \
  "$WORK/out4/hello.pdf" hello.pdf "$WORK/out4/hello.log" hello.log \
  "" hello.synctex.gz "" latex -1 0 0 0 2>"$WORK/case4.stderr"
status=$?
set -e
[[ "$status" -eq 37 ]] || { cat "$WORK/case4.stderr" >&2; fail "compile failure status changed: expected 37, got $status"; }
assert_no_temp_roots

printf 'action_home_guard_test: PASS\n'
