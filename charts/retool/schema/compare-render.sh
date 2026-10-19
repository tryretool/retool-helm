#!/usr/bin/env bash
#
# Renders the chart the way .github/kubeconform.sh does -- every
# charts/retool/ci/**/*values.yaml on its own and combined with each
# *option.yaml -- on a base ref and on the working tree, and diffs the output.
# Use it when annotating values.yaml: documentation and schema changes must
# not change what the chart renders.
#
# The base is rendered with the working tree's chart version, so a version bump
# does not show up as a change. Lines holding randomly generated secrets are
# ignored.
#
# Usage:
#   ./compare-render.sh            # compare against the merge base with origin/main
#   ./compare-render.sh <ref>      # compare against <ref>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CHART_DIR}/../.." && pwd)"
# The merge base, not origin/main itself: changes merged to main since this
# branch was cut would otherwise show up as differences.
BASE_REF="${1:-$(git -C "$REPO_ROOT" merge-base origin/main HEAD)}"

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

# render <chart-dir> <out-file> <values-file>...
#
# Fails (and prints Helm's error) if the chart does not render, so two
# identical errors are never reported as "same".
render() {
  local chart="$1" out="$2"
  shift 2
  local args=()
  for f in "$@"; do args+=(-f "$f"); done
  if ! helm template retool "$chart" "${args[@]}" > "${out}.raw" 2> "${out}.err"; then
    echo "ERROR    helm template failed for ${chart#"${tmp}/"} with: $*" >&2
    sed 's/^/         /' "${out}.err" >&2
    echo "         (missing subcharts? run: helm dependency build charts/retool)" >&2
    exit 1
  fi
  grep -vE '(password|jwt-secret|encryption-key|oauthIntrospectionAuthToken)"?: ' "${out}.raw" > "$out" || true
}

# compare <values-file>...
compare() {
  local name="${*#"${CHART_DIR}/"}"
  name="${name// ${CHART_DIR}\// + }"
  render "${tmp}/base/charts/retool" "${tmp}/base.out" "$@"
  render "$CHART_DIR" "${tmp}/head.out" "$@"
  if diff -u --label "${BASE_REF}" --label "working tree" "${tmp}/base.out" "${tmp}/head.out" > "${tmp}/diff"; then
    echo "same     ${name}"
  else
    echo "CHANGED  ${name}"
    cat "${tmp}/diff"
    rc=1
  fi
}

rc=0
options=()
while IFS= read -r f; do options+=("$f"); done < <(find "${CHART_DIR}/ci" -name '*option.yaml' | sort)
while IFS= read -r values; do
  compare "$values"
  for option in "${options[@]}"; do
    compare "$values" "$option"
  done
done < <(find "${CHART_DIR}/ci" -name '*values.yaml' | sort)

exit $rc
