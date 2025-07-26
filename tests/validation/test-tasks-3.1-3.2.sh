#!/bin/bash
set -euo pipefail

# Simple test script for Tasks 3.1 and 3.2
echo "🧪 Testing Tasks 3.1 and 3.2 - Error Pattern Detection and Resource Recreation"
echo "=============================================================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ $2${NC}"
        ((FAILED++))
    fi
}

echo -e "${BLUE}📋 Task 3.1: Error Pattern Detection System${NC}"
echo "============================================="

# Test 1: Check if namespace exists
echo "Test 1: Recovery namespace exists"
kubectl get namespace flux-recovery >/dev/null 2>&1
test_result $? "Recovery namespace exists"

# Test 2: Check if pod is running
echo "Test 2: Error pattern detector pod is running"
POD_STATUS=$(kubectl get pods -n flux-recovery -l app=error-pattern-detector -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [[ "$POD_STATUS" == "Running" ]]; then
    test_result 0 "Error pattern detector pod is running"
else
    test_result 1 "Error pattern detector pod is running (Status: $POD_STATUS)"
fi

# Test 3: Check if configuration is loaded
echo "Test 3: Configuration loaded properly"
kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=50 2>/dev/null | grep -q "Configuration loaded"
test_result $? "Configuration loaded properly"

# Test 4: Check if patterns are loaded
echo "Test 4: Error patterns loaded"
kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=50 2>/dev/null | grep -q "Loaded.*error patterns"
test_result $? "Error patterns loaded"

# Test 5: Check if real-time monitoring is active
echo "Test 5: Real-time event monitoring active"
kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=50 2>/dev/null | grep -q "Starting real-time Kubernetes event monitoring"
test_result $? "Real-time event monitoring active"

# Test 6: Check if Flux events are being processed
echo "Test 6: Flux events being processed"
kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=50 2>/dev/null | grep -q "Real Flux event\|Processing event"
test_result $? "Flux events being processed"

echo ""
echo -e "${BLUE}📋 Task 3.2: Resource Recreation Automation${NC}"
echo "============================================="

# Test 7: Check if recovery patterns config exists
echo "Test 7: Recovery patterns configuration exists"
kubectl get configmap recovery-patterns-config -n flux-recovery >/dev/null 2>&1
test_result $? "Recovery patterns configuration exists"

# Test 8: Check if recovery actions are defined
echo "Test 8: Recovery actions defined"
kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' 2>/dev/null | grep -q "recovery_actions:"
test_result $? "Recovery actions defined"

# Test 9: Check if immutable field patterns are configured
echo "Test 9: Immutable field patterns configured"
kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' 2>/dev/null | grep -q "immutable-field-conflict"
test_result $? "Immutable field patterns configured"

# Test 10: Check RBAC permissions for resource recreation
echo "Test 10: RBAC permissions for resource recreation"
kubectl auth can-i delete deployments --as=system:serviceaccount:flux-recovery:error-pattern-detector >/dev/null 2>&1 && \
kubectl auth can-i create deployments --as=system:serviceaccount:flux-recovery:error-pattern-detector >/dev/null 2>&1
test_result $? "RBAC permissions for resource recreation"

# Test 11: Check if auto-recovery is configured
echo "Test 11: Auto-recovery settings configured"
kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' 2>/dev/null | grep -q "auto_recovery_enabled:"
test_result $? "Auto-recovery settings configured"

# Test 12: Check if HelmRelease recovery actions exist
echo "Test 12: HelmRelease recovery actions configured"
kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' 2>/dev/null | grep -q "rollback_helm_release:"
test_result $? "HelmRelease recovery actions configured"

echo ""
echo "📊 Test Results Summary"
echo "======================"
echo "Total tests: $((PASSED + FAILED))"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ $FAILED -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 All tests passed! Tasks 3.1 and 3.2 are working correctly.${NC}"
    echo ""
    echo "📋 System Status:"
    echo "   - Task 3.1 (Error Pattern Detection): ✅ WORKING"
    echo "   - Task 3.2 (Resource Recreation): ✅ CONFIGURED"
    echo ""
    echo "🔍 Current Activity:"
    echo "Recent error pattern detector logs:"
    kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=3 2>/dev/null | sed 's/^/   /'
    echo ""
    echo "📈 Pattern Detection Stats:"
    PATTERN_COUNT=$(kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' 2>/dev/null | grep -c "name:" || echo "0")
    ACTION_COUNT=$(kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' 2>/dev/null | grep -A1 "recovery_actions:" | grep -c ":" || echo "0")
    echo "   - Error patterns configured: $PATTERN_COUNT"
    echo "   - Recovery actions available: $ACTION_COUNT"
    exit 0
else
    echo ""
    echo -e "${RED}❌ $FAILED test(s) failed.${NC}"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   - Check pod status: kubectl get pods -n flux-recovery"
    echo "   - Check logs: kubectl logs -n flux-recovery -l app=error-pattern-detector"
    echo "   - Check config: kubectl get configmap recovery-patterns-config -n flux-recovery -o yaml"
    exit 1
fi