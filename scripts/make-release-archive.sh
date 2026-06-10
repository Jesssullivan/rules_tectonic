#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/make-release-archive.sh <version> [output-dir]

Creates a BCR-compatible source archive from committed HEAD.

Example:
  scripts/make-release-archive.sh 0.1.0 dist

Output:
  dist/rules_tectonic-v0.1.0.tar.gz

The archive prefix is rules_tectonic-0.1.0/, matching .bcr/source.template.json.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

version="$1"
out_dir="${2:-dist}"
repo="rules_tectonic"
tag="v${version}"
archive="${repo}-${tag}.tar.gz"
prefix="${repo}-${version}/"

if [[ ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+([.-][A-Za-z0-9]+)*$ ]]; then
  echo "version must look like 0.1.0, got: $version" >&2
  exit 2
fi

mkdir -p "$out_dir"

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "warning: archiving committed HEAD; uncommitted worktree changes are not included" >&2
fi

git archive \
  --format=tar.gz \
  --prefix="$prefix" \
  --output="${out_dir}/${archive}" \
  HEAD

echo "${out_dir}/${archive}"
