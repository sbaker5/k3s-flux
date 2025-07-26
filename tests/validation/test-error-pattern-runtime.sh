#!/bin/bash
set -euo pipefail

# Runtime test script for error pattern detection system
# This script tests the actual functionality of the error pattern detection system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🧪 Testing Error Pattern Detection Runtime Functionality"
echo "========================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    ((TESTS_FAILED++))
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_TOTAL++))
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Test 1: Check if recovery namespace exists and is active
test_recovery_namespace() {
    kubectl get namespace flux-recovery >/dev/null 2>&1 && \
    [[ "$(kubectl get namespace flux-recovery -o jsonpath='{.status.phase}')" == "Active" ]]
}

# Test 2: Check if error pattern detector pod is running
test_detector_pod_running() {
    local pod_status
    pod_status=$(kubectl get pods -n flux-recovery -l app=error-pattern-detector -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    [[ "$pod_status" == "Running" ]]
}

# Test 3: Check if detector is processing events (has recent logs)
test_detector_processing_events() {
    local recent_logs
    recent_logs=$(kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=10 --since=5m 2>/dev/null | wc -l)
    [[ "$recent_logs" -gt 0 ]]
}

# Test 4: Check if configuration is loaded properly
test_configuration_loaded() {
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=100 2>/dev/null | \
    grep -q "Configuration loaded" && \
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=100 2>/dev/null | \
    grep -q "Patterns:"
}

# Test 5: Check if detector is monitoring real events
test_real_event_monitoring() {
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=100 2>/dev/null | \
    grep -q "Starting real-time Kubernetes event monitoring"
}

# Test 6: Check if detector has RBAC permissions
test_rbac_permissions() {
    kubectl auth can-i get events --as=system:serviceaccount:flux-recovery:error-pattern-detector >/dev/null 2>&1 && \
    kubectl auth can-i list kustomizations.kustomize.toolkit.fluxcd.io --as=system:serviceaccount:flux-recovery:error-pattern-detector >/dev/null 2>&1
}

# Test 7: Simulate an error pattern and check detection
test_pattern_detection_simulation() {
    log_info "Creating test deployment with immutable field conflict..."
    
    # Create a test deployment
    kubectl apply -f - <<EOF >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-pattern-detection
  namespace: default
  labels:
    test: error-pattern-detection
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

    sleep 2

    # Try to update with immutable field change (this should fail and generate an event)
    kubectl patch deployment test-pattern-detection -n default --type='merge' -p='{"spec":{"selector":{"matchLabels":{"app":"different-app"}}}}' >/dev/null 2>&1 || true

    sleep 5

    # Check if the error pattern detector caught this
    local pattern_detected=false
    if kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=50 --since=30s 2>/dev/null | grep -q "immutable\|selector"; then
        pattern_detected=true
    fi

    # Cleanup
    kubectl delete deployment test-pattern-detection -n default >/dev/null 2>&1 || true

    [[ "$pattern_detected" == "true" ]]
}

# Test 8: Check if recovery patterns config is accessible
test_recovery_patterns_config() {
    kubectl get configmap recovery-patterns-config -n flux-recovery >/dev/null 2>&1 && \
    [[ "$(kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' | wc -c)" -gt 100 ]]
}

# Test 9: Verify controller script is present
test_controller_script_present() {
    kubectl get configmap error-pattern-controller-script -n flux-recovery >/dev/null 2>&1 && \
    kubectl get configmap error-pattern-controller-script -n flux-recovery -o jsonpath='{.data.controller\.py}' | grep -q "class ErrorPatternDetector"
}

# Test 10: Check if detector is handling Flux events specifically
test_flux_event_handling() {
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=100 2>/dev/null | \
    grep -q "Real Flux event\|Processing event.*Flux"
}

# Test 11: Verify resource recreation capabilities (check RBAC for resource management)
test_resource_recreation_rbac() {
    kubectl auth can-i delete deployments --as=system:serviceaccount:flux-recovery:error-pattern-detector >/dev/null 2>&1 && \
    kubectl auth can-i create deployments --as=system:serviceaccount:flux-recovery:error-pattern-detector >/dev/null 2>&1 && \
    kubectl auth can-i patch deployments --as=system:serviceaccount:flux-recovery:error-pattern-detector >/dev/null 2>&1
}

# Test 12: Check if detector is tracking recovery state
test_recovery_state_tracking() {
    # Check if the detector logs show any recovery state information
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=200 2>/dev/null | \
    grep -q "recovery\|Recovery\|pattern.*match\|Pattern.*match" || \
    # If no recovery events yet, check if the system is ready to track them
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=50 2>/dev/null | \
    grep -q "Auto-recovery.*enabled\|recovery.*enabled"
}

echo ""
echo "🚀 Starting Runtime Tests..."
echo ""

# Run all tests
run_test "Recovery namespace exists and is active" "test_recovery_namespace"
run_test "Error pattern detector pod is running" "test_detector_pod_running"
run_test "Detector is processing events" "test_detector_processing_events"
run_test "Configuration loaded properly" "test_configuration_loaded"
run_test "Real-time event monitoring active" "test_real_event_monitoring"
run_test "RBAC permissions configured" "test_rbac_permissions"
run_test "Recovery patterns config accessible" "test_recovery_patterns_config"
run_test "Controller script present and valid" "test_controller_script_present"
run_test "Flux event handling active" "test_flux_event_handling"
run_test "Resource recreation RBAC configured" "test_resource_recreation_rbac"
run_test "Recovery state tracking active" "test_recovery_state_tracking"

echo ""
log_info "Running pattern detection simulation test..."
run_test "Pattern detection simulation" "test_pattern_detection_simulation"

echo ""
echo "📊 Test Results Summary"
echo "======================"
echo "Total tests: $TESTS_TOTAL"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    log_success "🎉 All runtime tests passed! Error Pattern Detection System is working correctly."
    echo ""
    echo "📋 System Status:"
    echo "   - Error pattern detection: ✅ Active"
    echo "   - Real-time event monitoring: ✅ Active"
    echo "   - Configuration: ✅ Loaded"
    echo "   - RBAC permissions: ✅ Configured"
    echo "   - Resource recreation capabilities: ✅ Available"
    echo ""
    echo "🔍 Recent Activity:"
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=5 2>/dev/null | sed 's/^/   /'
    exit 0
else
    echo ""
    log_error "❌ $TESTS_FAILED test(s) failed. Please check the system configuration."
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   - Check pod logs: kubectl logs -n flux-recovery -l app=error-pattern-detector"
    echo "   - Check pod status: kubectl get pods -n flux-recovery"
    echo "   - Check RBAC: kubectl describe clusterrole error-pattern-detector"
    exit 1
fi