"""Module extension that registers per-platform tectonic toolchain repositories.

A consumer module declares the version once via:

    tectonic_toolchains = use_extension("@rules_tectonic//tectonic:extensions.bzl", "tectonic_toolchains_ext")
    tectonic_toolchains.from_version(version = "0.16.9")

Per-platform repos `@tectonic_linux_amd64`, `@tectonic_linux_arm64`,
`@tectonic_darwin_amd64`, `@tectonic_darwin_arm64` are then created, each
holding the prebuilt tectonic binary for that target. The parent module
references those repos from its toolchain declarations.
"""

load("//tectonic/private:platforms.bzl", "PLATFORMS", "RELEASE_INTEGRITY")
load("//tectonic/private:tectonic_repository.bzl", "tectonic_repository")

_DEFAULT_VERSION = "0.16.9"

def _tectonic_toolchains_impl(mctx):
    version = _DEFAULT_VERSION
    for mod in mctx.modules:
        for tag in mod.tags.from_version:
            if tag.version:
                version = tag.version

    integrities = RELEASE_INTEGRITY.get(version, {})
    for plat in PLATFORMS.keys():
        tectonic_repository(
            name = "tectonic_" + plat,
            platform = plat,
            version = version,
            integrity = integrities.get(plat, ""),
        )

tectonic_toolchains_ext = module_extension(
    implementation = _tectonic_toolchains_impl,
    tag_classes = {
        "from_version": tag_class(
            attrs = {
                "version": attr.string(
                    doc = "Tectonic release version to install (e.g. 0.16.0).",
                ),
            },
        ),
    },
)
