"""tectonic_pdf rule: compile a .tex source into a .pdf via the tectonic toolchain."""

TOOLCHAIN_TYPE = "@rules_tectonic//tectonic:toolchain_type"

def _tectonic_pdf_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    tectonic = toolchain.tectonic_info.tectonic
    tectonic_executable = tectonic.files_to_run.executable

    src = ctx.file.src
    out = ctx.actions.declare_file(ctx.attr.name + ".pdf")

    inputs = depset(
        direct = [src],
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
        expected = src_basename[:-4] + ".pdf"
    else:
        expected = src_basename + ".pdf"

    ctx.actions.run_shell(
        command = """
set -euo pipefail
TECTONIC="$1"
SRC="$2"
OUT="$3"
EXPECTED="$4"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
"$TECTONIC" -X compile "$SRC" --outdir "$STAGE" --keep-logs --keep-intermediates >/dev/null
mv "$STAGE/$EXPECTED" "$OUT"
""",
        arguments = [
            tectonic_executable.path,
            src.path,
            out.path,
            expected,
        ],
        inputs = inputs,
        outputs = [out],
        tools = [tectonic.files_to_run],
        mnemonic = "Tectonic",
        progress_message = "Compiling %s with tectonic" % src.short_path,
        use_default_shell_env = True,
    )

    return [DefaultInfo(files = depset([out]))]

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
    },
    toolchains = [TOOLCHAIN_TYPE],
    doc = "Compile a LaTeX source into a PDF using tectonic.",
)
