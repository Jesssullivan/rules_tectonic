# Releasing

This repository publishes releases from the `Jesssullivan/rules_tectonic`
repository only. Do not open pull requests or push branches to outside
repositories from automation.

## Preconditions

- `MODULE.bazel` version matches the release version.
- `CHANGELOG.md` has a dated entry for the release.
- `.bcr/metadata.template.json`, `.bcr/source.template.json`, and
  `.bcr/presubmit.yml` match the intended public surface.
- `docs/defs.md` is regenerated from `//docs:defs_doc`.
- CI is green on Linux and macOS.

## Local Checks

```sh
bazel run //:buildifier.check
bazel build //...
bazel test //...
bazel test //docs:defs_doc_test
bazel build //examples:hello --output_groups=logs
(cd e2e/bzlmod && bazel build //...)
(cd e2e/bzlmod && bazel test //...)
```

## Source Archive

After committing the release changes, create the BCR-compatible source archive
locally:

```sh
scripts/make-release-archive.sh 0.2.0 dist
```

This creates `dist/rules_tectonic-v0.2.0.tar.gz` with the archive prefix
`rules_tectonic-0.2.0/`, matching `.bcr/source.template.json`.

The archive is generated from committed `HEAD`, matching the tag-driven GitHub
release workflow. Uncommitted local edits are intentionally not included.

## GitHub Release

Create and push a tag:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The `release` workflow validates the repo, builds the source archive, and
uploads it as a release asset to this repository.

## BCR Submission Boundary

The BCR entry can be generated from `.bcr/` templates after the GitHub release
asset exists. Submission to `bazelbuild/bazel-central-registry` is manual and
owner-driven; repository automation must not open that outside pull request.

After the release asset exists, compute its SRI value and render a local staging
tree:

```sh
scripts/render-bcr-entry.sh 0.2.0 sha256-... dist/bcr
```

This writes `dist/bcr/modules/rules_tectonic/0.2.0/` for inspection or manual
copying into a BCR fork. It does not push or open a PR.
