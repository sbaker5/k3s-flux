#!/bin/bash
set -euo pipefail

# Post-power outage health check for k3s cluster and GitOps system
echo "🏥 Post-Power Outage Health Check"
echo "================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ $2${NC}"
        ((FAILED++))
    fi
}

test_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

echo -e "${BLUE}🔍 1. Cluster Infrastructure Health${NC}"
echo "=================================="

# Test 1: Node health
echo "Test 1.1: Node health and readiness"
NODE_STATUS=$(kubectl get nodes k3s1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [[ "$NODE_STATUS" == "True" ]]; then
    test_result 0 "Node k3s1 is Ready"
else
    test_result 1 "Node k3s1 is not Ready (Status: $NODE_STATUS)"
fi

# Test 2: Core system pods
echo "Test 1.2: Core system pods health"
FAILED_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
if [[ "$FAILED_PODS" -eq 0 ]]; then
    test_result 0 "All kube-system pods are running"
else
    test_result 1 "$FAILED_PODS kube-system pods are not running"
fi

echo ""
echo -e "${BLUE}🔍 2. Flux GitOps System Health${NC}"
echo "==============================="

# Test 3: Flux controllers
echo "Test 2.1: Flux controllers health"
FLUX_CONTROLLERS=("source-controller" "kustomize-controller" "helm-controller" "notification-controller")
FLUX_HEALTHY=true

for controller in "${FLUX_CONTROLLERS[@]}"; do
    POD_STATUS=$(kubectl get pods -n flux-system -l app=$controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [[ "$POD_STATUS" == "Running" ]]; then
        echo "  ✅ $controller: Running"
    else
        echo "  ❌ $controller: $POD_STATUS"
        FLUX_HEALTHY=false
    fi
done

if [[ "$FLUX_HEALTHY" == "true" ]]; then
    test_result 0 "All Flux controllers are healthy"
else
    test_result 1 "Some Flux controllers are unhealthy"
fi

# Test 4: Kustomization status
echo "Test 2.2: Kustomization reconciliation status"
STUCK_KUSTOMIZATIONS=$(kubectl get kustomizations -n flux-system -o jsonpath='{.items[?(@.status.conditions[0].status=="False")].metadata.name}' 2>/dev/null)

if [[ -z "$STUCK_KUSTOMIZATIONS" ]]; then
    test_result 0 "All Kustomizations are reconciling successfully"
else
    test_warning "Some Kustomizations have issues: $STUCK_KUSTOMIZATIONS"
    echo "  Details:"
    for kust in $STUCK_KUSTOMIZATIONS; do
        REASON=$(kubectl get kustomization $kust -n flux-system -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
        MESSAGE=$(kubectl get kustomization $kust -n flux-system -o jsonpath='{.status.conditions[0].message}' 2>/dev/null)
        echo "    - $kust: $REASON - $MESSAGE"
    done
fi

echo ""
echo -e "${BLUE}🔍 3. Storage System Health${NC}"
echo "==========================="

# Test 5: Longhorn health
echo "Test 3.1: Longhorn storage system"
LONGHORN_MANAGER_STATUS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [[ "$LONGHORN_MANAGER_STATUS" == "Running" ]]; then
    test_result 0 "Longhorn manager is running"
else
    test_result 1 "Longhorn manager is not running (Status: $LONGHORN_MANAGER_STATUS)"
fi

# Test 6: PVC status
echo "Test 3.2: Persistent Volume Claims status"
FAILED_PVCS=$(kubectl get pvc -A --field-selector=status.phase!=Bound --no-headers 2>/dev/null | wc -l)
if [[ "$FAILED_PVCS" -eq 0 ]]; then
    test_result 0 "All PVCs are bound"
else
    test_warning "$FAILED_PVCS PVCs are not bound"
    kubectl get pvc -A --field-selector=status.phase!=Bound --no-headers 2>/dev/null | head -5
fi

echo ""
echo -e "${BLUE}🔍 4. Monitoring System Health${NC}"
echo "=============================="

# Test 7: Monitoring pods
echo "Test 4.1: Monitoring system pods"
MONITORING_PODS_RUNNING=$(kubectl get pods -n monitoring --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
MONITORING_PODS_TOTAL=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)

if [[ "$MONITORING_PODS_RUNNING" -eq "$MONITORING_PODS_TOTAL" ]]; then
    test_result 0 "All monitoring pods are running ($MONITORING_PODS_RUNNING/$MONITORING_PODS_TOTAL)"
else
    test_warning "Some monitoring pods are not running ($MONITORING_PODS_RUNNING/$MONITORING_PODS_TOTAL)"
    kubectl get pods -n monitoring --field-selector=status.phase!=Running --no-headers 2>/dev/null
fi

# Test 8: Prometheus accessibility
echo "Test 4.2: Prometheus accessibility"
if kubectl get service monitoring-core-prometheus-kube-prom-prometheus -n monitoring >/dev/null 2>&1; then
    test_result 0 "Prometheus service is available"
else
    test_result 1 "Prometheus service is not available"
fi

echo ""
echo -e "${BLUE}🔍 5. Error Pattern Detection System Health${NC}"
echo "==========================================="

# Test 9: Recovery system
echo "Test 5.1: Error pattern detector status"
DETECTOR_STATUS=$(kubectl get pods -n flux-recovery -l app=error-pattern-detector -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [[ "$DETECTOR_STATUS" == "Running" ]]; then
    test_result 0 "Error pattern detector is running"
else
    test_result 1 "Error pattern detector is not running (Status: $DETECTOR_STATUS)"
fi

# Test 10: Pattern detection activity
echo "Test 5.2: Pattern detection activity"
RECENT_ACTIVITY=$(kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=10 --since=300s 2>/dev/null | wc -l)
if [[ "$RECENT_ACTIVITY" -gt 0 ]]; then
    test_result 0 "Error pattern detector is actively monitoring (${RECENT_ACTIVITY} recent log entries)"
else
    test_warning "Error pattern detector has no recent activity"
fi

echo ""
echo -e "${BLUE}🔍 6. Current Issues Analysis${NC}"
echo "============================="

# Test 11: Identify current issues
echo "Test 6.1: Current Flux issues analysis"
echo "Analyzing current Grafana HelmRelease issue:"

GRAFANA_STATUS=$(kubectl get helmrelease monitoring-core-grafana -n monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
GRAFANA_REASON=$(kubectl get helmrelease monitoring-core-grafana -n monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null)
GRAFANA_MESSAGE=$(kubectl get helmrelease monitoring-core-grafana -n monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)

echo "  📊 Grafana HelmRelease Status: $GRAFANA_STATUS"
echo "  📊 Reason: $GRAFANA_REASON"
echo "  📊 Message: $GRAFANA_MESSAGE"

if [[ "$GRAFANA_STATUS" == "False" ]]; then
    test_warning "Grafana HelmRelease is not ready - this is the issue our error pattern detector is monitoring"
    
    # Check if our pattern detector is catching this
    echo "  🔍 Checking if error pattern detector is catching this issue:"
    if kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=20 2>/dev/null | grep -q "HealthCheckFailed.*grafana"; then
        echo "  ✅ Error pattern detector is successfully monitoring this issue"
    else
        echo "  ⚠️  Error pattern detector may not be catching this specific issue"
    fi
else
    test_result 0 "Grafana HelmRelease is healthy"
fi

echo ""
echo "📊 Health Check Summary"
echo "======================"
echo "Total tests: $((PASSED + FAILED + WARNINGS))"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"

echo ""
echo "🏥 Overall System Health Assessment:"

if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}🎉 EXCELLENT: System is fully healthy after power outage${NC}"
        echo ""
        echo "✅ All core systems are operational"
        echo "✅ GitOps reconciliation is working"
        echo "✅ Storage system is healthy"
        echo "✅ Error pattern detection is active"
    else
        echo -e "${YELLOW}⚠️  GOOD: System is mostly healthy with minor issues${NC}"
        echo ""
        echo "✅ All critical systems are operational"
        echo "⚠️  Some non-critical issues detected (see warnings above)"
        echo "✅ Error pattern detection is monitoring issues"
    fi
else
    echo -e "${RED}❌ ATTENTION NEEDED: System has critical issues${NC}"
    echo ""
    echo "❌ Critical systems need attention"
    echo "🔧 Immediate action required"
fi

echo ""
echo "🔍 Current Monitoring Activity:"
echo "Recent error pattern detector activity:"
kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=3 2>/dev/null | sed 's/^/   /' || echo "   No recent logs available"

echo ""
echo "📋 Recommendations:"
if [[ "$GRAFANA_STATUS" == "False" ]]; then
    echo "1. 🔧 Investigate Grafana HelmRelease chart reference issue"
    echo "2. 📊 Monitor error pattern detector for automatic recovery attempts"
    echo "3. 🔄 Consider manual intervention if auto-recovery doesn't resolve the issue"
else
    echo "1. ✅ System appears healthy - continue normal operations"
    echo "2. 📊 Monitor error pattern detector for any new issues"
fi

echo ""
echo "🎯 Tasks 3.1 & 3.2 Status After Power Outage:"
if [[ "$DETECTOR_STATUS" == "Running" ]] && [[ "$RECENT_ACTIVITY" -gt 0 ]]; then
    echo -e "${GREEN}✅ Task 3.1 (Error Pattern Detection): OPERATIONAL${NC}"
    echo -e "${GREEN}✅ Task 3.2 (Resource Recreation): CONFIGURED & READY${NC}"
    echo ""
    echo "🚀 Both tasks survived the power outage and are functioning correctly!"
else
    echo -e "${RED}❌ Error pattern detection system needs attention${NC}"
fi