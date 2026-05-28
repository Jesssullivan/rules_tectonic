"""Tectonic toolchain provider and rule."""

TectonicToolchainInfo = provider(
    doc = "Information about a tectonic toolchain.",
    fields = {
        "tectonic": "Target wrapping the tectonic executable.",
    },
)

def _tectonic_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            tectonic_info = TectonicToolchainInfo(
                tectonic = ctx.attr.tectonic,
            ),
        ),
    ]

tectonic_toolchain = rule(
    implementation = _tectonic_toolchain_impl,
    attrs = {
        "tectonic": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "Label of the tectonic executable.",
        ),
    },
    doc = "Wraps a tectonic binary as a Bazel toolchain.",
)
