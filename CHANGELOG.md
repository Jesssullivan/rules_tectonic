# Changelog

## Unreleased

## 0.2.3 - 2026-10-01

- Fix `tectonic_pdf` failing on hosts with a home-root deletion guard (an `rm`
  on `PATH` that refuses `$HOME` or any ancestor of it) when the action runs
  with `use_default_shell_env = True` and no strict action env. Through 0.2.2
  the action exported a synthetic `HOME` inside the stage its EXIT cleanup
  removes, so the guard refused the cleanup and the action failed after the PDF
  was produced. The synthetic `HOME`, the XDG dirs and `TECTONIC_CACHE_DIR` are
  now passed only to the Tectonic process; the action script keeps the
  inherited `HOME`, and the synthetic home lives in its own temp root.
- A successful compile no longer fails when temp cleanup is refused: the EXIT
  handler prints a `rules_tectonic: warning:` line naming the leftover roots
  and exits zero. A failing compile still keeps its exact status.
- Add `//tectonic/private/tests:action_home_guard_test`, which runs the exact
  action script with an `rm` guard shim and a fake Tectonic, and asserts the
  build succeeds, the shim saw the inherited `HOME`, a consumer
  `TECTONIC_CACHE_DIR` still wins, a refused cleanup only warns, and a failing
  compile keeps its status.

## 0.2.2 - 2026-08-30

- Guard `tectonic_pdf` action cleanup behind a fresh-parent ownership marker,
  exact fixed-child containment checks, symlink/root/HOME refusal, and
  non-recursive parent removal. The EXIT handler preserves the original compile
  status even if cleanup refuses.
- Add adversarial shell coverage for successful and failed actions plus empty,
  parent-as-target, outside, root, HOME, and symlink cleanup substitutions.
- Align the module, consumer example, installation, and release documentation
  on version `0.2.2`.

## 0.2.1 - 2026-07-14

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
