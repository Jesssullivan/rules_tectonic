"""tectonic_pdf rule: compile a .tex source into a .pdf via the tectonic toolchain."""

TOOLCHAIN_TYPE = "@rules_tectonic//tectonic:toolchain_type"

def _tectonic_pdf_impl(ctx):
    if ctx.attr.reruns < -1:
        fail("reruns must be -1 to use Tectonic's default behavior, or a non-negative integer")

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    tectonic = toolchain.tectonic_info.tectonic
    tectonic_executable = tectonic.files_to_run.executable

    src = ctx.file.src
    out = ctx.actions.declare_file(ctx.attr.name + ".pdf")
    log_out = ctx.actions.declare_file(ctx.attr.name + ".log")
    synctex_out = ctx.actions.declare_file(ctx.attr.name + ".synctex.gz") if ctx.attr.synctex else None

    inputs = depset(
        direct = [src, ctx.file._stage_cleanup_lib] + ([ctx.file.bundle] if ctx.file.bundle else []),
        transitive = [
            depset(ctx.files.deps),
            depset(ctx.files.data),
        ],
    )

    # tectonic writes <src_basename>.pdf into --outdir. We compile into a
    # private staging directory, then move the result to the declared output
    # path so the Bazel-visible name can differ from the .tex basename.
    src_basename = src.basename
    if src_basename.endswith(".tex"):
        expected_stem = src_basename[:-4]
    else:
        expected_stem = src_basename

    expected_pdf = expected_stem + ".pdf"
    expected_log = expected_stem + ".log"
    expected_synctex = expected_stem + ".synctex.gz"

    outputs = [out, log_out]
    if synctex_out:
        outputs.append(synctex_out)

    ctx.actions.run_shell(
        command = """
set -euo pipefail
STAGE_CLEANUP_LIB="$1"
shift
# shellcheck source=stage_cleanup.sh
source "$STAGE_CLEANUP_LIB"
TECTONIC="$1"
shift
SRC="$1"
shift
OUT="$1"
shift
EXPECTED="$1"
shift
LOG_OUT="$1"
shift
EXPECTED_LOG="$1"
shift
SYNCTEX_OUT="$1"
shift
EXPECTED_SYNCTEX="$1"
shift
BUNDLE="$1"
shift
FORMAT="$1"
shift
RERUNS="$1"
shift
ONLY_CACHED="$1"
shift
SYNCTEX="$1"
shift
UNTRUSTED="$1"
shift
tectonic_stage_prepare
STAGE_PARENT="$TECTONIC_STAGE_PARENT"
STAGE="$TECTONIC_STAGE"
STAGE_TOKEN="$TECTONIC_STAGE_TOKEN"
trap 'tectonic_stage_exit "$?" "$STAGE_PARENT" "$STAGE" "$STAGE_TOKEN"' EXIT

# Tectonic resolves its bundle/format cache from TECTONIC_CACHE_DIR, falling
# back to OS cache dirs derived from the invoking user's home. Inside Bazel
# sandboxes that home is typically absent or mounted read-only, so the first
# cache write fails the compile ("Read-only file system (os error 30)").
# Default to an action-private cache inside the staging dir so the action
# never depends on a writable user home. A TECTONIC_CACHE_DIR threaded in by
# the consumer (e.g. --action_env=TECTONIC_CACHE_DIR=... paired with a
# --sandbox_writable_path for it) still wins, for persistent caching.
if [[ -z "${TECTONIC_CACHE_DIR:-}" ]]; then
  TECTONIC_CACHE_DIR="$STAGE/cache"
fi
export TECTONIC_CACHE_DIR
mkdir -p "$TECTONIC_CACHE_DIR"

# Keep other home-derived lookups (user config, XDG dirs) action-private too,
# so results do not vary with the invoking user's dotfiles.
export HOME="$STAGE/home"
export XDG_CACHE_HOME="$STAGE/home/.cache"
export XDG_CONFIG_HOME="$STAGE/home/.config"
export XDG_DATA_HOME="$STAGE/home/.local/share"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

cmd=("$TECTONIC" -X compile "$SRC" --outdir "$STAGE" --keep-logs)
if [[ -n "$FORMAT" ]]; then
  cmd+=("--format" "$FORMAT")
fi
if [[ -n "$BUNDLE" ]]; then
  cmd+=("--bundle" "$BUNDLE")
fi
if [[ "$ONLY_CACHED" == "1" ]]; then
  cmd+=("--only-cached")
fi
if [[ "$SYNCTEX" == "1" ]]; then
  cmd+=("--synctex")
fi
if [[ "$UNTRUSTED" == "1" ]]; then
  cmd+=("--untrusted")
fi
if [[ "$RERUNS" != "-1" ]]; then
  cmd+=("--reruns" "$RERUNS")
fi
cmd+=("$@")

"${cmd[@]}" >/dev/null
mv "$STAGE/$EXPECTED" "$OUT"
mv "$STAGE/$EXPECTED_LOG" "$LOG_OUT"
if [[ -n "$SYNCTEX_OUT" ]]; then
  mv "$STAGE/$EXPECTED_SYNCTEX" "$SYNCTEX_OUT"
fi
""",
        arguments = [
            ctx.file._stage_cleanup_lib.path,
            tectonic_executable.path,
            src.path,
            out.path,
            expected_pdf,
            log_out.path,
            expected_log,
            synctex_out.path if synctex_out else "",
            expected_synctex,
            ctx.file.bundle.path if ctx.file.bundle else "",
            ctx.attr.format,
            str(ctx.attr.reruns),
            "1" if ctx.attr.only_cached else "0",
            "1" if ctx.attr.synctex else "0",
            "1" if ctx.attr.untrusted else "0",
        ] + ctx.attr.extra_args,
        inputs = inputs,
        outputs = outputs,
        tools = [tectonic.files_to_run],
        mnemonic = "Tectonic",
        progress_message = "Compiling %s with tectonic" % src.short_path,
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(files = depset([out])),
        OutputGroupInfo(
            logs = depset([log_out]),
            synctex = depset([synctex_out] if synctex_out else []),
        ),
    ]

tectonic_pdf = rule(
    implementation = _tectonic_pdf_impl,
    attrs = {
        "_stage_cleanup_lib": attr.label(
            default = Label("//tectonic/private:stage_cleanup_lib"),
            allow_single_file = True,
        ),
        "src": attr.label(
            mandatory = True,
            allow_single_file = [".tex"],
            doc = "The main .tex source.",
        ),
        "deps": attr.label_list(
            allow_files = True,
            doc = "Additional TeX sources (chapters, packages) the main source includes.",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Non-TeX inputs the source references (images, fonts, bib files, etc.).",
        ),
        "bundle": attr.label(
            allow_single_file = True,
            doc = "Optional pinned Tectonic bundle file to use instead of the default network bundle.",
        ),
        "extra_args": attr.string_list(
            doc = "Additional arguments passed to `tectonic -X compile`.",
        ),
        "format": attr.string(
            default = "latex",
            doc = "Tectonic format name or path passed with `--format`.",
        ),
        "only_cached": attr.bool(
            default = False,
            doc = "Pass `--only-cached` so Tectonic uses only locally cached bundle resources.",
        ),
        "reruns": attr.int(
            default = -1,
            doc = "Pass `--reruns` when non-negative. The default -1 leaves Tectonic's default rerun behavior unchanged.",
        ),
        "synctex": attr.bool(
            default = False,
            doc = "Generate SyncTeX data and expose it via the `synctex` output group.",
        ),
        "untrusted": attr.bool(
            default = False,
            doc = "Pass `--untrusted` to disable known-insecure TeX features for untrusted inputs.",
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
    doc = """Compile a LaTeX source into a PDF using tectonic.

The compile action gives Tectonic an action-private, writable cache and home
(`TECTONIC_CACHE_DIR`, `HOME`, and XDG dirs point into the action's staging
directory), so it works inside Bazel sandboxes where the user home is absent or
read-only. Bundle resources are fetched per action unless a consumer threads a
persistent `TECTONIC_CACHE_DIR` through `--action_env` (with a matching
`--sandbox_writable_path`), or pins resources via `bundle`/`only_cached`.""",
)
