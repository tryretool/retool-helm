#!/usr/bin/env bash
# Checks that code-executor and js-executor can start nsjail under the
# retool-executor AppArmor profile with the securityContext the chart renders.
#
# nsjail is exec'd from a child shell because the executors spawn it from a
# running process; a process started by `kubectl exec` skips the profile's exec
# rules. Each nsjail path holds a copy of unshare, which asks for the same
# namespaces nsjail creates. seccomp is unconfined because the chart's nsjail
# profile blocks unshare(2) (nsjail uses clone(2)), and procMount is dropped
# because it requires hostUsers: false.
#
# Needs the retool-executor profile loaded on the nodes (test-apparmor.sh does
# this in CI). Uses the current kubectl context, or $KUBE_CONTEXT when set.
# $CHART_DIR renders a different copy of the chart.
#
# Usage:
#   .github/test-executor-nsjail.sh [namespace]
#   KUBE_CONTEXT=my-cluster .github/test-executor-nsjail.sh my-namespace

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART_DIR="$(cd "${CHART_DIR:-$SCRIPT_DIR/../charts/retool}" && pwd)"
NAMESPACE="${1:-apparmor-test}"

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "$KUBE_CONTEXT")
fi

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); }

PODS=()
cleanup() {
  if [[ ${#PODS[@]} -gt 0 ]]; then
    "${KUBECTL[@]}" delete pod -n "$NAMESPACE" "${PODS[@]}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "=== Rendering code-executor and js-executor ==="

RENDERED=$(helm template executor-nsjail-test "$CHART_DIR" \
  -f "$CHART_DIR/ci/test-install-values.yaml" \
  -f "$CHART_DIR/ci/test-apparmor-nsjail-option.yaml" \
  -s templates/deployment_code_executor.yaml \
  -s templates/deployment_js_executor.yaml \
  | "${KUBECTL[@]}" create --dry-run=client -o json -f -)

# Prints a test pod for one executor container, or nothing if the chart didn't render it.
test_pod_spec() {
  local container="$1" nsjail_path="$2"
  echo "$RENDERED" | jq -c --arg c "$container" --arg nsjail "$nsjail_path" '
    (if .kind == "List" then .items[] else . end)
    | select(.kind == "Deployment")
    | .spec.template as $t
    | $t.spec.containers[]
    | select(.name == $c)
    | ($t.metadata.annotations["container.apparmor.security.beta.kubernetes.io/" + $c] // "") as $annotation
    | (.securityContext.appArmorProfile // (
        if ($annotation | startswith("localhost/")) then {type: "Localhost", localhostProfile: ($annotation | ltrimstr("localhost/"))}
        elif $annotation == "runtime/default" then {type: "RuntimeDefault"}
        elif $annotation == "unconfined" then {type: "Unconfined"}
        else null end
      )) as $apparmor
    | {
        apiVersion: "v1",
        kind: "Pod",
        metadata: {name: ("nsjail-" + $c)},
        spec: {
          restartPolicy: "Never",
          terminationGracePeriodSeconds: 0,
          automountServiceAccountToken: false,
          containers: [{
            name: $c,
            image: "ubuntu:24.04",
            command: ["sh", "-c", ("cp /usr/bin/unshare " + $nsjail + " && exec sleep 600")],
            securityContext: (.securityContext
              | del(.procMount)
              | .seccompProfile = {type: "Unconfined"}
              | .appArmorProfile = $apparmor)
          }]
        }
      }'
}

check_executor() {
  local container="$1" nsjail_path="$2"
  local pod="nsjail-$container"

  echo "=== $container: $nsjail_path ==="

  local spec
  spec=$(test_pod_spec "$container" "$nsjail_path")
  if [[ -z "$spec" ]]; then
    fail "chart did not render the $container container"
    return
  fi

  local apparmor
  apparmor=$(echo "$spec" | jq -c '.spec.containers[0].securityContext.appArmorProfile')
  if [[ "$apparmor" != '{"type":"Localhost","localhostProfile":"retool-executor"}' ]]; then
    fail "$container AppArmor profile is $apparmor, expected Localhost retool-executor"
    return
  fi
  echo "  allowPrivilegeEscalation: $(echo "$spec" | jq -r '.spec.containers[0].securityContext.allowPrivilegeEscalation')"

  "${KUBECTL[@]}" delete pod -n "$NAMESPACE" "$pod" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  echo "$spec" | "${KUBECTL[@]}" apply -n "$NAMESPACE" -f - >/dev/null
  PODS+=("$pod")
  if ! "${KUBECTL[@]}" wait -n "$NAMESPACE" --for=condition=Ready "pod/$pod" --timeout=120s >/dev/null 2>&1; then
    fail "$pod did not start: $("${KUBECTL[@]}" get pod -n "$NAMESPACE" "$pod" -o jsonpath='{.status.containerStatuses[0].state}' 2>&1)"
    return
  fi

  local status
  status=$("${KUBECTL[@]}" exec -n "$NAMESPACE" "$pod" -- sh -c 'grep -E "^(NoNewPrivs|Seccomp):" /proc/self/status; cat /proc/self/attr/current' 2>&1 | tr '\n\t' '  ')
  echo "  child shell: $status"

  local out
  if out=$("${KUBECTL[@]}" exec -n "$NAMESPACE" "$pod" -- sh -c "$nsjail_path --user --mount --pid --fork true" 2>&1); then
    pass "$nsjail_path can create user, mount, and pid namespaces"
  else
    fail "$nsjail_path cannot create its namespaces: $(echo "$out" | tr '\n' ' ')"
  fi

  if "${KUBECTL[@]}" exec -n "$NAMESPACE" "$pod" -- sh -c "unshare --user --mount --pid --fork true" >/dev/null 2>&1; then
    fail "/usr/bin/unshare created namespaces; only nsjail should be able to"
  else
    pass "/usr/bin/unshare is denied the same namespaces"
  fi
}

check_executor code-executor /usr/bin/nsjail
check_executor js-executor /usr/local/bin/nsjail

echo ""
echo "=== Executor nsjail results: $passed passed, $failed failed ==="

if [[ $failed -gt 0 ]]; then
  exit 1
fi
