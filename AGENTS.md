# Repository Instructions

These instructions apply to the whole repository.

## Project Shape

`rules_tectonic` is a public Bazel ruleset for compiling TeX/LaTeX documents
with the Tectonic engine. Keep the public API small, documented, and stable:

- Public loads live in `//tectonic:defs.bzl` and `//tectonic:extensions.bzl`.
- Implementation details stay under `//tectonic/private`.
- Examples and e2e modules should exercise behavior as external users consume it.

## Validation

Run the closest relevant checks before claiming completion:

- `bazel build //...`
- `bazel test //...`
- `bazel run //:buildifier.check`
- `bazel test //docs:defs_doc_test`
- `bazel build //examples:hello`
- `cd e2e/bzlmod && bazel build //...`
- `cd e2e/bzlmod && bazel test //...`

If Bazel cannot create its output base in the local sandbox, rerun the same
command with the normal repo-managed environment rather than changing build
flags in source files.

## Public Release Discipline

- Keep `MODULE.bazel` bzlmod-compatible and avoid WORKSPACE-only setup.
- Keep archive integrity values pinned for every supported Tectonic binary.
- Do not remove or rewrite existing BCR module versions after publication.
- Update `.bcr/presubmit.yml` when platform or Bazel-version support changes.
- Keep `LICENSE`, `README.md`, `CHANGELOG.md`, and `docs/RELEASING.md`
  aligned with the shipped public surface.
- Keep generated API docs current with `bazel build //docs:defs_doc` and
  `cp bazel-bin/docs/defs.generated.md docs/defs.md`.
- Do not open pull requests or push branches to repositories outside
  `Jesssullivan/*` or `tinyland-inc/*`; the repo owner handles outside PRs.

## Safety

- Do not commit secrets, tokens, `.env` files, or local Bazel output trees.
- Do not commit private planning or self-talk documents.
- Do not add broad generated-file churn unless it is required for release.
- Prefer targeted rule changes with a consumer-facing test or example.
