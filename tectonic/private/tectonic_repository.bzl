"""Repository rule that downloads a prebuilt tectonic binary for one host platform.

The downloaded archive is unpacked into the repo root; we expect it to contain a
single `tectonic` executable. The generated BUILD.bazel exposes that binary as
`@tectonic_<platform>//:tectonic`, which the parent module's toolchain target
references.
"""

load(":platforms.bzl", "PLATFORMS")

_RELEASE_URL = "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic@{version}/tectonic-{version}-{triple}.{ext}"

_BUILD_FILE = """\
package(default_visibility = ["//visibility:public"])

exports_files(["tectonic"])
"""

def _tectonic_repository_impl(rctx):
    spec = PLATFORMS[rctx.attr.platform]
    url = _RELEASE_URL.format(
        version = rctx.attr.version,
        triple = spec["triple"],
        ext = spec["ext"],
    )
    rctx.download_and_extract(
        url = [url],
        integrity = rctx.attr.integrity,
        type = spec["ext"],
    )

    # Make sure the binary is executable. tectonic releases ship a single file
    # at the archive root, so it lands at `tectonic` after extraction.
    rctx.execute(["chmod", "+x", "tectonic"])

    rctx.file("BUILD.bazel", _BUILD_FILE)

tectonic_repository = repository_rule(
    implementation = _tectonic_repository_impl,
    attrs = {
        "platform": attr.string(
            mandatory = True,
            values = sorted(PLATFORMS.keys()),
            doc = "Logical platform name (linux_amd64, linux_arm64, darwin_amd64, darwin_arm64).",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Tectonic release version (e.g. 0.16.0).",
        ),
        "integrity": attr.string(
            default = "",
            doc = "Expected SRI integrity string for the archive (e.g. sha256-<base64>). Empty string disables verification; useful for bootstrap.",
        ),
    },
)
