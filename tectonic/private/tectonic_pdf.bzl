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
        direct = [src] + ([ctx.file.bundle] if ctx.file.bundle else []),
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
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

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
    doc = "Compile a LaTeX source into a PDF using tectonic.",
)
