#!/usr/bin/env bash
#
# Renders the chart with every values file in charts/retool/ci/ on a base ref
# and on the working tree, and diffs the output. Use it when annotating
# values.yaml: documentation and schema changes must not change what the chart
# renders.
#
# The base is rendered with the working tree's chart version, so a version bump
# does not show up as a change. Lines holding randomly generated secrets are
# ignored.
#
# Usage:
#   ./compare-render.sh            # compare against origin/main
#   ./compare-render.sh <ref>      # compare against <ref>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CHART_DIR}/../.." && pwd)"
BASE_REF="${1:-origin/main}"

tmp="$(mktemp -d)"
cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "${tmp}/base" &>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

git -C "$REPO_ROOT" worktree add --quiet --detach "${tmp}/base" "$BASE_REF"
# Subchart archives are gitignored; reuse the working tree's.
cp "${CHART_DIR}"/charts/*.tgz "${tmp}/base/charts/retool/charts/" 2>/dev/null || true
version="$(grep '^version:' "${CHART_DIR}/Chart.yaml")"
sed -i.bak "s/^version:.*/${version}/" "${tmp}/base/charts/retool/Chart.yaml"

# render <chart-dir> <values-file> <out-file>
render() {
  helm template retool "$1" -f "$2" 2>&1 \
    | grep -vE '(password|jwt-secret|encryption-key|oauthIntrospectionAuthToken)"?: ' \
    > "$3" || true
}

rc=0
while IFS= read -r values; do
  name="${values#"${CHART_DIR}/"}"
  render "${tmp}/base/charts/retool" "$values" "${tmp}/base.out"
  render "$CHART_DIR" "$values" "${tmp}/head.out"
  if diff -u --label "${BASE_REF}" --label "working tree" "${tmp}/base.out" "${tmp}/head.out" > "${tmp}/diff"; then
    echo "same     ${name}"
  else
    echo "CHANGED  ${name}"
    cat "${tmp}/diff"
    rc=1
  fi
done < <(find "${CHART_DIR}/ci" -name '*.yaml' | sort)

exit $rc
