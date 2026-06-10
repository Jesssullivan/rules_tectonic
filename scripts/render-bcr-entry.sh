#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/render-bcr-entry.sh <version> <integrity> [output-dir] [owner] [repo]

Renders a Bazel Central Registry module entry from the checked-in templates.

Example:
  scripts/render-bcr-entry.sh 0.2.0 sha256-... dist/bcr

Output:
  dist/bcr/modules/rules_tectonic/metadata.json
  dist/bcr/modules/rules_tectonic/0.2.0/MODULE.bazel
  dist/bcr/modules/rules_tectonic/0.2.0/source.json
  dist/bcr/modules/rules_tectonic/0.2.0/presubmit.yml

This is a local staging helper only. It does not clone, push, or open a BCR PR.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 5 ]]; then
  usage
  exit 2
fi

version="$1"
integrity="$2"
out_dir="${3:-dist/bcr}"
owner="${4:-Jesssullivan}"
repo="${5:-rules_tectonic}"

if [[ ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+([.-][A-Za-z0-9]+)*$ ]]; then
  echo "version must look like 0.2.0, got: $version" >&2
  exit 2
fi

if [[ ! "$integrity" =~ ^sha256-[A-Za-z0-9+/=]+$ ]]; then
  echo "integrity must be an SRI sha256 value, got: $integrity" >&2
  exit 2
fi

for required in MODULE.bazel .bcr/metadata.template.json .bcr/source.template.json .bcr/presubmit.yml; do
  if [[ ! -f "$required" ]]; then
    echo "missing required file: $required" >&2
    exit 1
  fi
done

module_root="${out_dir}/modules/${repo}"
version_root="${module_root}/${version}"
mkdir -p "$version_root"

awk -v version="$version" '
  /"versions": \[\]/ {
    print "  \"versions\": ["
    print "    \"" version "\""
    print "  ],"
    next
  }
  { print }
' .bcr/metadata.template.json > "${module_root}/metadata.json"

sed \
  -e "s|{OWNER}|${owner}|g" \
  -e "s|{REPO}|${repo}|g" \
  -e "s|{VERSION}|${version}|g" \
  -e "s|{TAG}|v${version}|g" \
  -e "s|\"integrity\": \"\"|\"integrity\": \"${integrity}\"|" \
  .bcr/source.template.json > "${version_root}/source.json"

cp MODULE.bazel "${version_root}/MODULE.bazel"
cp .bcr/presubmit.yml "${version_root}/presubmit.yml"

echo "$version_root"
