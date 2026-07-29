#!/usr/bin/env bash
# Integration test for the AppArmor profile installers.
#
# Verifies the full chain: DaemonSet loads profiles into the kernel, test pods
# run under the correct profile, and unprivileged user/mount/pid namespace
# creation succeeds (the operation that fails on Ubuntu 24.04+ with
# kernel.apparmor_restrict_unprivileged_userns=1 when the profile is unconfined).
#
# Requirements:
#   - Linux with AppArmor kernel module
#   - Root (for k3s install, sysctl, reading apparmor profiles)
#   - Helm 3
#
# Usage:
#   sudo .github/test-apparmor.sh            # from repo root
#   sudo .github/test-apparmor.sh --cleanup  # also uninstall k3s when done

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_DIR="$REPO_DIR/charts/retool"
NAMESPACE="apparmor-test"
RELEASE="apparmor-test"
CLEANUP_K3S=false

for arg in "$@"; do
  case "$arg" in
    --cleanup) CLEANUP_K3S=true ;;
  esac
done

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
echo "=== Prerequisites ==="

if [[ "$(uname)" != "Linux" ]]; then
  echo "ERROR: This test must run on Linux (found $(uname))."
  exit 1
fi

if [[ ! -d /sys/kernel/security/apparmor ]]; then
  echo "ERROR: AppArmor kernel module is not loaded."
  exit 1
fi

if ! command -v helm &>/dev/null; then
  echo "ERROR: helm is not installed."
  exit 1
fi

echo "  Linux with AppArmor support detected."

# ---------------------------------------------------------------------------
# k3s setup
# ---------------------------------------------------------------------------
echo "=== k3s setup ==="

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get nodes &>/dev/null; then
  echo "  k3s is already running, skipping install."
else
  echo "  Installing k3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
  echo "  Waiting for k3s to be ready..."
  for i in $(seq 1 60); do
    if kubectl get nodes --no-headers 2>/dev/null | grep -q .; then break; fi
    sleep 2
  done
  kubectl wait --for=condition=Ready node --all --timeout=120s
  echo "  k3s is ready."
fi

# ---------------------------------------------------------------------------
# sysctl — reproduce the Ubuntu 24.04+ restriction
# ---------------------------------------------------------------------------
echo "=== Enabling kernel.apparmor_restrict_unprivileged_userns ==="

sysctl -w kernel.apparmor_restrict_unprivileged_userns=1 || {
  echo "  WARNING: sysctl not available (older kernel?), test may not be meaningful."
}

# ---------------------------------------------------------------------------
# Deploy AppArmor DaemonSets + ConfigMaps via helm template + kubectl apply
# ---------------------------------------------------------------------------
echo "=== Deploying AppArmor profiles ==="

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
helm dependency build "$CHART_DIR" 2>/dev/null || true

# Render only the AppArmor-related manifests (DaemonSets + ConfigMaps).
# We use helm template with --show-only to select specific templates, avoiding
# the need for license keys, Postgres, or Retool images.
COMMON_SETS=(
  --set image.tag=latest
  --set config.encryptionKey=test
  --set config.jwtSecret=test
  --set config.postgresql.host=localhost
  --set config.postgresql.db=retool
  --set config.postgresql.port=5432
  --set workflows.enabled=true
  --set codeExecutor.appArmorProfileInstaller=true
  --set codeExecutor.useSeccompProfile=true
  --set rr.enabled=true
  --set rr.agentSandbox.enabled=true
  --set rr.agentSandbox.appArmorProfileInstaller=true
  --set rr.agentSandbox.jwtPublicKey=test
  --set rr.agentSandbox.jwtPrivateKey=test
  --set rr.agentSandbox.encryptionKey=0000000000000000000000000000000000000000000000000000000000000000
  --set rr.agentSandbox.hostNetwork=false
  --set rr.agentSandbox.initImage.digest=
  --set rr.gitServer.skipBlobStorageValidation=true
  --set nodeSelector=null
)

NSJAIL_TEMPLATES=(
  -s templates/apparmor_nsjail_configmap.yaml
  -s templates/apparmor_nsjail_daemonset.yaml
)

SANDBOX_TEMPLATES=(
  -s templates/apparmor_agent_sandbox_configmap.yaml
  -s templates/agent_sandbox_seccomp.yaml
)

echo "  Rendering and applying nsjail AppArmor manifests..."
helm template "$RELEASE" "$CHART_DIR" "${COMMON_SETS[@]}" "${NSJAIL_TEMPLATES[@]}" \
  | kubectl apply -n "$NAMESPACE" -f -

echo "  Rendering and applying agent-sandbox AppArmor manifests..."
helm template "$RELEASE" "$CHART_DIR" "${COMMON_SETS[@]}" "${SANDBOX_TEMPLATES[@]}" \
  | kubectl apply -n "$NAMESPACE" -f -

# ---------------------------------------------------------------------------
# Wait for DaemonSets
# ---------------------------------------------------------------------------
echo "=== Waiting for DaemonSets ==="

for ds in $(kubectl get daemonsets -n "$NAMESPACE" -o name); do
  kubectl rollout status "$ds" -n "$NAMESPACE" --timeout=120s
  echo "  $ds ready."
done

# ---------------------------------------------------------------------------
# Verify profiles are loaded in the kernel
# ---------------------------------------------------------------------------
echo "=== Checking loaded AppArmor profiles ==="

PROFILES=$(cat /sys/kernel/security/apparmor/profiles)

if echo "$PROFILES" | grep -q "retool-executor (enforce)"; then
  pass "retool-executor profile loaded"
else
  fail "retool-executor profile NOT found in kernel"
fi

# nsjail profile uses flags=(unconfined), so it appears as "(unconfined)" in the kernel
if echo "$PROFILES" | grep -q "/usr/bin/nsjail"; then
  pass "usr.bin.nsjail profile loaded"
else
  fail "usr.bin.nsjail profile NOT found in kernel"
fi

if echo "$PROFILES" | grep -q "retool-agent-sandbox (enforce)"; then
  pass "retool-agent-sandbox profile loaded"
else
  fail "retool-agent-sandbox profile NOT found in kernel"
fi

# ---------------------------------------------------------------------------
# Test pod: retool-executor profile
# ---------------------------------------------------------------------------
echo "=== Testing retool-executor profile ==="

kubectl run test-executor -n "$NAMESPACE" --image=busybox:1.37 --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "test-executor",
        "image": "busybox:1.37",
        "command": ["sleep", "120"],
        "securityContext": {
          "appArmorProfile": {"type": "Localhost", "localhostProfile": "retool-executor"}
        }
      }]
    }
  }' -- sleep 120 2>/dev/null || true

kubectl wait --for=condition=Ready pod/test-executor -n "$NAMESPACE" --timeout=60s

CURRENT=$(kubectl exec test-executor -n "$NAMESPACE" -- cat /proc/self/attr/current 2>/dev/null || echo "UNKNOWN")
if echo "$CURRENT" | grep -q "retool-executor (enforce)"; then
  pass "test-executor pod running under retool-executor profile"
else
  fail "test-executor pod profile is '$CURRENT', expected 'retool-executor (enforce)'"
fi

if kubectl exec test-executor -n "$NAMESPACE" -- unshare --user --mount --pid --fork echo "OK" 2>/dev/null; then
  pass "unshare --user --mount --pid --fork succeeds under retool-executor"
else
  fail "unshare --user --mount --pid --fork FAILED under retool-executor"
fi

# ---------------------------------------------------------------------------
# Test pod: retool-agent-sandbox profile
# ---------------------------------------------------------------------------
echo "=== Testing retool-agent-sandbox profile ==="

kubectl run test-sandbox -n "$NAMESPACE" --image=busybox:1.37 --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "test-sandbox",
        "image": "busybox:1.37",
        "command": ["sleep", "120"],
        "securityContext": {
          "appArmorProfile": {"type": "Localhost", "localhostProfile": "retool-agent-sandbox"}
        }
      }]
    }
  }' -- sleep 120 2>/dev/null || true

kubectl wait --for=condition=Ready pod/test-sandbox -n "$NAMESPACE" --timeout=60s

CURRENT=$(kubectl exec test-sandbox -n "$NAMESPACE" -- cat /proc/self/attr/current 2>/dev/null || echo "UNKNOWN")
if echo "$CURRENT" | grep -q "retool-agent-sandbox (enforce)"; then
  pass "test-sandbox pod running under retool-agent-sandbox profile"
else
  fail "test-sandbox pod profile is '$CURRENT', expected 'retool-agent-sandbox (enforce)'"
fi

if kubectl exec test-sandbox -n "$NAMESPACE" -- unshare --user --mount --pid --fork echo "OK" 2>/dev/null; then
  pass "unshare --user --mount --pid --fork succeeds under retool-agent-sandbox"
else
  fail "unshare --user --mount --pid --fork FAILED under retool-agent-sandbox"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
echo "=== Cleanup ==="

kubectl delete pod test-executor test-sandbox -n "$NAMESPACE" --grace-period=0 --force 2>/dev/null || true
kubectl delete namespace "$NAMESPACE" --wait=false 2>/dev/null || true

if $CLEANUP_K3S; then
  echo "  Uninstalling k3s..."
  /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $passed passed, $failed failed ==="

if [[ $failed -gt 0 ]]; then
  exit 1
fi
