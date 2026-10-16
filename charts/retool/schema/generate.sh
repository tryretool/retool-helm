#!/usr/bin/env bash
#
# Generates values.schema.json and README.md for the retool chart from the
# annotations in values.yaml, so the two never drift from the values they
# describe.
#
#   values.schema.json  helm-values-schema-json (`# @schema` annotations,
#                       descriptions from `# --` comments)
#   README.md           helm-docs (`# --` comments, README.md.gotmpl)
#
# It also copies values.yaml to the repo root, which is kept in sync by the
# values-yaml-synced workflow.
#
# See CONTRIBUTING.md for the annotation conventions.
#
# Usage:
#   ./generate.sh           # regenerate in place
#   ./generate.sh --check   # generate to a temp dir + diff against checked-in files
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CHART_DIR}/../.." && pwd)"
BIN_DIR="${SCRIPT_DIR}/.bin"

# ---------------------------------------------------------------------------
# Tool pins. Bump the version and every checksum together; checksums come from
# each release's published checksum file.
# ---------------------------------------------------------------------------
HELM_DOCS_VERSION="1.14.2"
HELM_SCHEMA_VERSION="2.6.0"

helm_docs_sha256() {
  case "$1" in
    Darwin_arm64)  echo "2d8399db5b33d240d5f8985241bcf5483563150b968e3229823822979f3e4b8b" ;;
    Darwin_x86_64) echo "b2f1ffd0feef8dc0901a38a2053481d1d67b63ca30da4ac774166c6b52fa2245" ;;
    Linux_arm64)   echo "c3787212332386dcd122debef7848feb165aa701467ae3e3442df7638f3ac4e4" ;;
    Linux_x86_64)  echo "a8cf72ada34fad93285ba2a452b38bdc5bd52cc9a571236244ec31022928d6cc" ;;
    *) echo "ERROR: no helm-docs checksum pinned for $1" >&2; exit 1 ;;
  esac
}

helm_schema_sha256() {
  case "$1" in
    darwin_arm64) echo "270d6212b8f01d5639288168e0ebb70fd82fdc8bda1b87c22762bbfe93874e90" ;;
    darwin_amd64) echo "2efefae69eb445670d74760313274e803f5556dc4bd5a20b8fea1d97d8ed7c71" ;;
    linux_arm64)  echo "baf7c867fb4cb6903f49e5698b74a850912b6af9c84108668351e312b59e0e4f" ;;
    linux_amd64)  echo "c3447c1be91b987678e70996451b6cf2169b9f44fea8fe670dc0f340281f11e8" ;;
    *) echo "ERROR: no helm-values-schema-json checksum pinned for $1" >&2; exit 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
sha256_of() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# fetch <url> <expected-sha256> <dest>
fetch() {
  local url="$1" want="$2" dest="$3" got
  echo "Downloading ${url}..." >&2
  curl -fsSL "$url" -o "$dest"
  got="$(sha256_of "$dest")"
  if [[ "$got" != "$want" ]]; then
    echo "ERROR: checksum mismatch for ${url}" >&2
    echo "  want ${want}" >&2
    echo "  got  ${got}" >&2
    rm -f "$dest"
    exit 1
  fi
}

install_tools() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  [[ "$arch" == "aarch64" ]] && arch="arm64"

  local helm_docs="${BIN_DIR}/helm-docs-${HELM_DOCS_VERSION}"
  local helm_schema="${BIN_DIR}/helm-schema-${HELM_SCHEMA_VERSION}"
  mkdir -p "$BIN_DIR"

  if [[ ! -x "$helm_docs" ]]; then
    local platform="${os}_$([[ "$arch" == "x86_64" ]] && echo x86_64 || echo "$arch")"
    local archive="${BIN_DIR}/helm-docs.tar.gz"
    fetch "https://github.com/norwoodj/helm-docs/releases/download/v${HELM_DOCS_VERSION}/helm-docs_${HELM_DOCS_VERSION}_${platform}.tar.gz" \
      "$(helm_docs_sha256 "$platform")" "$archive"
    tar -xzf "$archive" -C "$BIN_DIR" helm-docs
    mv "${BIN_DIR}/helm-docs" "$helm_docs"
    rm -f "$archive"
  fi

  if [[ ! -x "$helm_schema" ]]; then
    local platform
    platform="$(echo "$os" | tr '[:upper:]' '[:lower:]')_$([[ "$arch" == "x86_64" ]] && echo amd64 || echo "$arch")"
    local archive="${BIN_DIR}/helm-schema.tgz"
    fetch "https://github.com/losisin/helm-values-schema-json/releases/download/v${HELM_SCHEMA_VERSION}/helm-values-schema-json_${HELM_SCHEMA_VERSION}_${platform}.tgz" \
      "$(helm_schema_sha256 "$platform")" "$archive"
    tar -xzf "$archive" -C "$BIN_DIR" schema
    mv "${BIN_DIR}/schema" "$helm_schema"
    rm -f "$archive"
  fi

  HELM_DOCS="$helm_docs"
  HELM_SCHEMA="$helm_schema"
}

# check_explicit_types <values.yaml>
#
# Every key with a `# --` description must declare its type with
# `# @schema type:` instead of relying on inference from its default -- also
# when it uses `$ref:`, since the generator still infers a type next to the
# reference. Keys under a top-level `# @schema hidden` section are skipped.
check_explicit_types() {
  awk '
    function indent_of(s) { match(s, /^ */); return RLENGTH }
    /^[[:space:]]*#/ { block[++n] = $0; next }
    {
      if (match($0, /^ *[A-Za-z0-9_][A-Za-z0-9_.\/-]*:/)) {
        ind = indent_of($0); doc = 0; typed = 0; hidden = 0
        for (i = 1; i <= n; i++) {
          if (indent_of(block[i]) != ind) continue
          l = block[i]; sub(/^ */, "", l)
          if (l ~ /^# -- /) doc = 1
          if (l ~ /^# @schema/ && l ~ /(@schema|;)[[:space:]]*type:/) typed = 1
          if (l ~ /^# @schema hidden/) hidden = 1
        }
        if (ind == 0) hidden_section = hidden
        if (doc && !typed && !hidden_section) {
          printf "%s:%d: \"%s\" has a # -- description but no explicit # @schema type\n", FILENAME, NR, $0 > "/dev/stderr"
          bad = 1
        }
      }
      n = 0
    }
    END { exit bad }
  ' "$1" || {
    echo "ERROR: add \`# @schema type: ...\` above the \`# --\` line of each key listed above (see CONTRIBUTING.md)." >&2
    exit 1
  }
}

# generate <chart-dir>
generate() {
  local chart="$1"
  echo "Generating values.schema.json..." >&2
  (
    cd "$chart"
    # draft 7: the newest draft Helm 3 validates (Helm 4 accepts it too).
    "$HELM_SCHEMA" \
      --values values.yaml \
      --output values.schema.json \
      --draft 7 \
      --indent 2 \
      --use-helm-docs \
      --bundle \
      --bundle-without-id \
      --bundle-root . \
      --schema-root.title "Retool Helm chart values" \
      --schema-root.additional-properties >/dev/null
  )

  echo "Generating README.md..." >&2
  "$HELM_DOCS" \
    --log-level warning \
    --chart-search-root "$chart" \
    --chart-to-generate "$chart" \
    --template-files README.md.gotmpl \
    --sort-values-order file \
    --ignore-non-descriptions
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
install_tools
check_explicit_types "${CHART_DIR}/values.yaml"

if [[ "${1:-}" == "--check" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  rsync -a --exclude schema/.bin "${CHART_DIR}/" "${tmp}/retool/"
  generate "${tmp}/retool"

  rc=0
  for f in values.schema.json README.md; do
    if ! diff -u "${CHART_DIR}/${f}" "${tmp}/retool/${f}"; then
      rc=1
    fi
  done
  if [[ $rc -ne 0 ]]; then
    echo "" >&2
    echo "ERROR: generated files are out of date. Run charts/retool/schema/generate.sh and commit the result." >&2
    exit 1
  fi
  echo "values.schema.json and README.md are up to date." >&2
else
  generate "$CHART_DIR"
  cp "${CHART_DIR}/values.yaml" "${REPO_ROOT}/values.yaml"
  echo "Done. Also copied values.yaml to the repo root." >&2
fi
