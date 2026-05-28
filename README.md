# rules_tectonic

Bazel rules for compiling LaTeX sources to PDF using [tectonic](https://tectonic-typesetting.github.io/).

Tectonic is self-contained, fast, and pulls TeX Live packages on demand — no system TeX install required. `rules_tectonic` wraps the upstream prebuilt binaries as a Bazel toolchain and exposes a single rule, `tectonic_pdf`, that produces a `.pdf` from a `.tex` source.

## Installation (bzlmod)

```python
# MODULE.bazel
bazel_dep(name = "rules_tectonic", version = "0.1.0")
```

During early development you can pin to a git commit via `git_override`:

```python
bazel_dep(name = "rules_tectonic", version = "0.1.0")
git_override(
    module_name = "rules_tectonic",
    remote = "https://github.com/jesssullivan/rules_tectonic.git",
    commit = "<sha>",
)
```

## Usage

```python
# BUILD.bazel
load("@rules_tectonic//tectonic:defs.bzl", "tectonic_pdf")

tectonic_pdf(
    name = "my_paper",
    src = "paper.tex",
    deps = [
        "abstract.tex",
        "intro.tex",
        "sections/methods.tex",
    ],
    data = [
        "figures/plot.pdf",
        "refs.bib",
    ],
)
```

Then:

```sh
bazel build //path/to:my_paper
# -> bazel-bin/path/to/my_paper.pdf
```

## How it works

- A module extension (`tectonic_toolchains_ext` in `//tectonic:extensions.bzl`) creates one external repository per supported host platform: `@tectonic_linux_amd64`, `@tectonic_linux_arm64`, `@tectonic_darwin_amd64`, `@tectonic_darwin_arm64`.
- Each repo downloads the matching prebuilt tectonic binary from `tectonic-typesetting/tectonic` GitHub releases.
- A toolchain is registered per platform; Bazel picks the right one based on the exec platform.
- `tectonic_pdf` is a leaf rule that invokes `tectonic -X compile <src> --outdir <tmpdir>` and moves the resulting PDF to the declared Bazel output.

## Overriding the tectonic version

```python
# MODULE.bazel
tectonic_toolchains = use_extension("@rules_tectonic//tectonic:extensions.bzl", "tectonic_toolchains_ext")
tectonic_toolchains.from_version(version = "0.15.0")
```

You will need to populate matching SRI integrity strings in `tectonic/private/platforms.bzl`'s `RELEASE_INTEGRITY` table — pin requests are welcome.

## Bootstrapping integrity values

For a given tectonic version, the SRI integrity strings of the prebuilt archives can be obtained from `bazel build //examples:hello` itself: with an empty integrity entry, Bazel will fetch the archive and print the actual value. Copy that into `RELEASE_INTEGRITY[version][platform]` for verified, repeatable builds.

You can also compute them directly:

```sh
curl -sL <archive-url> | openssl dgst -sha256 -binary | base64 | sed 's/^/sha256-/'
```

## Dev shell

A `flake.nix` is provided. With direnv:

```sh
direnv allow   # uses nix flake; provides bazelisk, tectonic, buildifier
```

## Smoke test

```sh
bazel build //examples:hello
```

## License

MIT — see [LICENSE](./LICENSE).
