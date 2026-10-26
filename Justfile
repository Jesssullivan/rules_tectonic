# rules_tectonic maintainer checks.
#
# No flywheel lane is enrolled for this repo and Tectonic compile actions run
# locally by design. Every Bazel recipe here is local, non-qualifying
# (TIN-5770, R471). Each workspace's .bazelrc sets startup --max_idle_secs=120,
# so the root and e2e/bzlmod servers exit after 120 s idle (R470).

bazel := env("BAZEL", "bazelisk")

# The first recipe lists recipes and starts no Bazel server (R472).
default:
    @just --list

# Print tool versions without starting a Bazel server.
versions:
    @echo "bazel $(cat .bazelversion) (.bazelversion)"
    @buildifier --version
    @tectonic --version

# Build every root target (local, non-qualifying).
build: _local
    {{ bazel }} build //...

# Test every root target (local, non-qualifying).
test: _local
    {{ bazel }} test //...

# Check Bazel formatting (local, non-qualifying).
fmt-check: _local
    {{ bazel }} run //:buildifier.check

# Check the generated API docs (local, non-qualifying).
docs-check: _local
    {{ bazel }} test //docs:defs_doc_test

# Build the example PDF (local, non-qualifying).
example: _local
    {{ bazel }} build //examples:hello

# Build and test the bzlmod consumer smoke module (local, non-qualifying).
e2e: _local
    cd e2e/bzlmod && {{ bazel }} build //... && {{ bazel }} test //...

# Run the full maintainer check set (local, non-qualifying).
check: build test fmt-check docs-check example e2e

_local:
    @echo "rules_tectonic: local, non-qualifying Bazel run (no flywheel lane enrolled)"
