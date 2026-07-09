# Changelog

## Unreleased

- Fix `tectonic_pdf` failing with `Read-only file system (os error 30)` inside
  Bazel sandboxes: the compile action now points `TECTONIC_CACHE_DIR`, `HOME`,
  and the XDG dirs at an action-private staging directory instead of relying on
  a writable user home. An externally provided `TECTONIC_CACHE_DIR` (e.g. via
  `--action_env`) still takes precedence for persistent caching.

## 0.2.0 - 2026-06-09

- Add BCR templates and a standalone bzlmod consumer smoke module.
- Add Bazel-managed `buildifier` formatting targets.
- Add Stardoc-generated API docs with a freshness test.
- Add release archive generation for BCR-compatible source artifacts.
- Expand `tectonic_pdf` with common Tectonic compile options and output groups.
- Update the default Tectonic toolchain to `0.16.9`.

## 0.1.0

- Initial `rules_tectonic` release.
- Add bzlmod module setup, Tectonic toolchain repositories, and `tectonic_pdf`.
- Support Linux and macOS on `x86_64` and `aarch64`.
