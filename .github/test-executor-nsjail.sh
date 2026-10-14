#!/usr/bin/env bash
# Runs the real code-executor and js-executor images with the pod spec the chart
# renders (useSeccompProfile and appArmorProfileInstaller on) and checks that:
#   - code-executor starts, which it only does once nsjail works,
#   - js-executor runs a real request in nsjail,
#   - nsjail at its real path can build a sandbox, and a copy of it anywhere
#     else is denied, so the AppArmor rights stay with that one path,
#   - allowPrivilegeEscalation: false is still in force (NoNewPrivs: 1), and
#   - every process except nsjail carries the retool-executor-restricted layer,
#     PID 1 included. The profile only narrows processes started by an exec, so
#     an image whose entrypoint is the service itself would run unrestricted.
#
# Needs the retool-executor profile loaded on the nodes (test-apparmor.sh does
# this in CI). Uses the newest X.Y.Z-edge tag both images have, or
# $EXECUTOR_IMAGE_TAG. Uses the current kubectl context, or $KUBE_CONTEXT when
# set. $CHART_DIR renders a different copy of the chart.
#
# Usage:
#   .github/test-executor-nsjail.sh [namespace]
#   EXECUTOR_IMAGE_TAG=4.34.8-stable .github/test-executor-nsjail.sh my-namespace

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART_DIR="$(cd "${CHART_DIR:-$SCRIPT_DIR/../charts/retool}" && pwd)"
NAMESPACE="${1:-apparmor-test}"
RELEASE="executor-nsjail-test"
CODE_EXECUTOR="$RELEASE-retool-code-executor"
JS_EXECUTOR="$RELEASE-retool-js-executor"
RESTRICTED="retool-executor//&retool-executor-restricted (enforce)"
NSJAIL_PROFILE="retool-executor (enforce)"
LOCAL_PORT=39000

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "$KUBE_CONTEXT")
fi

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); }

# Prints a JSON array of an image's X.Y.Z-edge tags on Docker Hub, newest first.
edge_tags() {
  curl -fsS "https://hub.docker.com/v2/repositories/tryretool/$1/tags?page_size=100&ordering=last_updated" \
    | jq -c '[.results[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+-edge$"))]'
}

if [[ -z "${EXECUTOR_IMAGE_TAG:-}" ]]; then
  EXECUTOR_IMAGE_TAG=$(jq -rn \
    --argjson js "$(edge_tags js-executor-service)" \
    --argjson ce "$(edge_tags code-executor-service)" \
    '[$js[] | select(. as $tag | $ce | index($tag))][0] // empty')
fi
if [[ -z "$EXECUTOR_IMAGE_TAG" ]]; then
  echo "ERROR: no X.Y.Z-edge tag found for both executor images; set EXECUTOR_IMAGE_TAG."
  exit 1
fi

echo "=== Running the executor images at $EXECUTOR_IMAGE_TAG ==="

MANIFESTS=$(helm template "$RELEASE" "$CHART_DIR" \
  -f "$CHART_DIR/ci/test-install-values.yaml" \
  -f "$CHART_DIR/ci/test-apparmor-nsjail-option.yaml" \
  --set image.tag="$EXECUTOR_IMAGE_TAG" \
  -s templates/serviceaccount.yaml \
  -s templates/configmap_code_executor.yaml \
  -s templates/configmap_js_executor.yaml \
  -s templates/deployment_code_executor.yaml \
  -s templates/deployment_js_executor.yaml)

PORT_FORWARD_PID=""
cleanup() {
  if [[ -n "$PORT_FORWARD_PID" ]]; then
    kill "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
  echo "$MANIFESTS" | "${KUBECTL[@]}" delete -n "$NAMESPACE" -f - --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "$MANIFESTS" | "${KUBECTL[@]}" apply -n "$NAMESPACE" -f - >/dev/null

# Waits for a Deployment to be ready, printing its pods and recent logs if it isn't.
wait_ready() {
  local deploy="$1"
  if "${KUBECTL[@]}" rollout status -n "$NAMESPACE" "deploy/$deploy" --timeout=600s >/dev/null 2>&1; then
    pass "$deploy is ready"
    return 0
  fi
  fail "$deploy did not become ready"
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -l "retoolService=$deploy" 2>&1 | sed 's/^/    /' || true
  "${KUBECTL[@]}" logs -n "$NAMESPACE" "deploy/$deploy" --all-containers --tail=20 2>&1 | sed 's/^/    /' || true
  return 1
}

# Checks NoNewPrivs on PID 1 and the AppArmor label of every process in the container.
check_processes() {
  local deploy="$1" container="$2"
  local out
  # The listing shell is started by kubectl exec, so it runs unrestricted; skip it.
  if ! out=$("${KUBECTL[@]}" exec -n "$NAMESPACE" "deploy/$deploy" -c "$container" -- sh -c '
      for d in /proc/[0-9]*; do
        pid=${d#/proc/}
        [ "$pid" = "$$" ] && continue
        label=$(cat "$d/attr/current" 2>/dev/null) || continue
        echo "$pid|$label|$(tr "\0" " " < "$d/cmdline" 2>/dev/null | cut -c1-100)"
      done' 2>&1); then
    fail "could not list processes in $deploy: $out"
    return
  fi
  local table
  table=$(echo "$out" | grep -E '^[0-9]+\|' || true)

  local nnp
  nnp=$("${KUBECTL[@]}" exec -n "$NAMESPACE" "deploy/$deploy" -c "$container" -- grep NoNewPrivs /proc/1/status 2>&1 || true)
  if [[ "$nnp" =~ NoNewPrivs:[[:space:]]+1 ]]; then
    pass "$deploy PID 1 has NoNewPrivs: 1"
  else
    fail "$deploy PID 1 should have NoNewPrivs: 1, got: $nnp"
  fi

  local pid label cmd argv0 expected wrong=0 total=0
  while IFS='|' read -r pid label cmd; do
    [[ -z "$pid" ]] && continue
    total=$((total + 1))
    argv0=${cmd%% *}
    if [[ "${argv0##*/}" == "nsjail" ]]; then
      expected="$NSJAIL_PROFILE"
    else
      expected="$RESTRICTED"
    fi
    if [[ "$label" != "$expected" ]]; then
      wrong=$((wrong + 1))
      echo "    pid $pid is '$label', expected '$expected': $cmd"
    fi
  done <<< "$table"

  echo "    PID 1: $(echo "$table" | grep '^1|' | cut -d'|' -f2- || true)"
  if [[ $wrong -eq 0 && $total -gt 0 ]]; then
    pass "$deploy: all $total processes have the expected label; only nsjail runs without retool-executor-restricted"
  else
    fail "$deploy: $wrong of $total processes have the wrong AppArmor label"
  fi
}

# Runs nsjail as retool_user from a narrowed shell, the way the service starts it. At its real path it
# must build a sandbox; a copy elsewhere must be denied by AppArmor, so the rights stay with the real path.
check_nsjail_path() {
  local deploy="$1" container="$2" nsjail_path="$3"
  local exec_in=("${KUBECTL[@]}" exec -n "$NAMESPACE" "deploy/$deploy" -c "$container" --)
  local out

  # --disable_proc: a fresh /proc needs procMount: Unmasked, which only code-executor sets; AppArmor isn't involved.
  if out=$("${exec_in[@]}" sh -c "runuser -u retool_user -- $nsjail_path -Mo --chroot / --disable_proc -- /bin/sh -c true" 2>&1); then
    pass "$deploy: $nsjail_path can build a sandbox"
  else
    fail "$deploy: $nsjail_path could not build a sandbox: $(echo "$out" | tr '\n' ' ')"
  fi

  if ! out=$("${exec_in[@]}" cp "$nsjail_path" /tmp/nsjail-copy 2>&1); then
    fail "$deploy: could not copy $nsjail_path: $out"
    return
  fi
  if out=$("${exec_in[@]}" sh -c "runuser -u retool_user -- /tmp/nsjail-copy -Mo --chroot / --disable_proc -- /bin/sh -c true" 2>&1); then
    fail "$deploy: a copy of nsjail at /tmp/nsjail-copy built a sandbox; only $nsjail_path should be able to"
  # nsjail logs the denied mount or clone as an [E] line ending in the EACCES that AppArmor returns.
  elif [[ "$out" == *"[E]["*"Permission denied"* ]]; then
    pass "$deploy: a copy of nsjail at /tmp/nsjail-copy is denied"
  else
    fail "$deploy: the nsjail copy failed for another reason: $(echo "$out" | tr '\n' ' ')"
  fi
}

echo "=== code-executor ==="
if wait_ready "$CODE_EXECUTOR"; then
  logs=$("${KUBECTL[@]}" logs -n "$NAMESPACE" "deploy/$CODE_EXECUTOR" -c code-executor 2>&1 || true)
  if [[ "$logs" == *"can use nsjail: true"* ]]; then
    pass "code-executor reports 'can use nsjail: true'"
  else
    fail "code-executor did not report 'can use nsjail: true'"
  fi
  check_processes "$CODE_EXECUTOR" code-executor
  check_nsjail_path "$CODE_EXECUTOR" code-executor /usr/bin/nsjail
fi

echo "=== js-executor ==="
if wait_ready "$JS_EXECUTOR"; then
  check_processes "$JS_EXECUTOR" js-executor
  check_nsjail_path "$JS_EXECUTOR" js-executor /usr/local/bin/nsjail

  "${KUBECTL[@]}" port-forward -n "$NAMESPACE" "deploy/$JS_EXECUTOR" "$LOCAL_PORT:3000" >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://127.0.0.1:$LOCAL_PORT/api/health" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  # Headers match the integration test's placeholder sandbox credentials.
  response=$(curl -sS -m 60 -X POST "http://127.0.0.1:$LOCAL_PORT/api/executeJS" \
    -H 'Content-Type: application/octet-stream' \
    -H 'x-retool-jse-origin: R2' \
    -H 'x-retool-sandbox-token: integration-test-token' \
    -H 'x-retool-sandbox-backend-host: http://sandbox-proxy.invalid' \
    --data-binary 'return 40 + 2;' 2>&1 | LC_ALL=C tr -c '[:print:]' ' ' || true)
  kill "$PORT_FORWARD_PID" 2>/dev/null || true
  PORT_FORWARD_PID=""

  if [[ "$response" == *'"outputAsJSON":"42"'* ]]; then
    pass "js-executor ran 'return 40 + 2' in nsjail and returned 42"
  else
    fail "js-executor request failed: ${response:0:300}"
  fi
fi

echo ""
echo "=== Executor nsjail results: $passed passed, $failed failed ==="

if [[ $failed -gt 0 ]]; then
  exit 1
fi
