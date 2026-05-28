"""Platform metadata for tectonic prebuilt binaries.

Each entry maps a logical platform name to:
  - triple: the rust-style target triple used in tectonic release archive filenames
  - ext: archive extension (tar.gz vs zip)
  - exec_compatible_with: Bazel platform constraints the toolchain matches
"""

PLATFORMS = {
    "linux_amd64": {
        "triple": "x86_64-unknown-linux-musl",
        "ext": "tar.gz",
        "exec_compatible_with": [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    },
    "linux_arm64": {
        "triple": "aarch64-unknown-linux-musl",
        "ext": "tar.gz",
        "exec_compatible_with": [
            "@platforms//os:linux",
            "@platforms//cpu:aarch64",
        ],
    },
    "darwin_amd64": {
        "triple": "x86_64-apple-darwin",
        "ext": "tar.gz",
        "exec_compatible_with": [
            "@platforms//os:macos",
            "@platforms//cpu:x86_64",
        ],
    },
    "darwin_arm64": {
        "triple": "aarch64-apple-darwin",
        "ext": "tar.gz",
        "exec_compatible_with": [
            "@platforms//os:macos",
            "@platforms//cpu:aarch64",
        ],
    },
}

# Known release integrity strings (SRI format), keyed by version then platform.
# Empty strings let Bazel report the actual hash on first download attempt;
# update this table as new versions are pinned.
RELEASE_INTEGRITY = {
    "0.16.0": {
        "linux_amd64": "sha256-u7dymLnRorkR5yXLBExdkkncZ0PwzUifTQzzSKShhJE=",
        "linux_arm64": "sha256-YPhCHB2jBQzHZuJasHAVMelYPM+gbWoYT9TtkCHGtCc=",
        "darwin_amd64": "sha256-BzG/VFkduy3LBuskzEImzzNWzGntO9+vul97sq9+wSY=",
        "darwin_arm64": "sha256-VnjinNE+srbZhWatmkKOnj/6fVxos5KOlEy9Nj0zrDY=",
    },
}
