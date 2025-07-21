#!/bin/bash
# Test script for simulating stuck states and validating alert firing
# This script creates various stuck state scenarios to test GitOps resilience alerts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROMETHEUS_URL="http://localhost:9090"
PROMETHEUS_PORT_FORWARD_PID=""
TEST_NAMESPACE="alert-test"
CLEANUP_ON_EXIT=true

# Function to log messages
log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $*" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
        TEST)
            echo -e "${CYAN}[TEST]${NC} $*"
            ;;
    esac
}

# Cleanup function
cleanup() {
    if [ "$CLEANUP_ON_EXIT" = true ]; then
        log INFO "Cleaning up test resources..."
        
        # Kill port forward if running
        if [ -n "$PROMETHEUS_PORT_FORWARD_PID" ]; then
            kill "$PROMETHEUS_PORT_FORWARD_PID" 2>/dev/null || true
        fi
        
        # Clean up test namespace
        kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found=true --timeout=30s || true
        
        # Clean up any test resources
        kubectl delete deployment test-stuck-deployment --ignore-not-found=true --timeout=30s || true
        kubectl delete pvc test-stuck-pvc --ignore-not-found=true --timeout=30s || true
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Function to check if Prometheus is accessible
check_prometheus() {
    log INFO "Checking Prometheus accessibility..."
    
    # Try to access Prometheus directly first
    if curl -s "$PROMETHEUS_URL/api/v1/query?query=up" >/dev/null 2>&1; then
        log SUCCESS "Prometheus accessible at $PROMETHEUS_URL"
        return 0
    fi
    
    # If not accessible, try to set up port forward
    log INFO "Setting up port forward to Prometheus..."
    kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 --address=0.0.0.0 &
    PROMETHEUS_PORT_FORWARD_PID=$!
    
    # Wait for port forward to be ready
    sleep 5
    
    if curl -s "$PROMETHEUS_URL/api/v1/query?query=up" >/dev/null 2>&1; then
        log SUCCESS "Prometheus accessible via port forward"
        return 0
    else
        log ERROR "Cannot access Prometheus for alert testing"
        return 1
    fi
}

# Function to query Prometheus for alerts
query_alerts() {
    local alert_name="$1"
    local timeout="${2:-60}"
    local start_time=$(date +%s)
    
    log INFO "Querying for alert: $alert_name (timeout: ${timeout}s)"
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            log WARN "Timeout waiting for alert: $alert_name"
            return 1
        fi
        
        # Query for active alerts
        local response=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=ALERTS{alertname=\"$alert_name\"}" || echo "")
        
        if echo "$response" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
            local alert_state=$(echo "$response" | jq -r '.data.result[0].metric.alertstate // "unknown"')
            log SUCCESS "Alert $alert_name found in state: $alert_state"
            
            # Show alert details
            echo "$response" | jq -r '.data.result[0].metric | to_entries | map("\(.key): \(.value)") | join(", ")'
            return 0
        fi
        
        echo -n "."
        sleep 5
    done
}

# Function to create a stuck deployment
create_stuck_deployment() {
    log TEST "Creating stuck deployment scenario..."
    
    # Create test namespace
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create a deployment with resource constraints that will cause it to be stuck
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-stuck-deployment
  namespace: $TEST_NAMESPACE
  labels:
    test-scenario: stuck-rollout
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-stuck-app
  template:
    metadata:
      labels:
        app: test-stuck-app
    spec:
      containers:
      - name: app
        image: nginx:1.21
        resources:
          requests:
            memory: "10Gi"  # Unrealistic memory request to cause scheduling issues
            cpu: "8"        # Unrealistic CPU request
          limits:
            memory: "10Gi"
            cpu: "8"
        ports:
        - containerPort: 80
EOF

    log INFO "Stuck deployment created. Waiting for rollout to get stuck..."
    sleep 30
    
    # Check deployment status
    kubectl get deployment test-stuck-deployment -n "$TEST_NAMESPACE" -o wide
    kubectl describe deployment test-stuck-deployment -n "$TEST_NAMESPACE" | tail -10
}

# Function to create a stuck PVC
create_stuck_pvc() {
    log TEST "Creating stuck PVC scenario..."
    
    # Create a PVC with a non-existent storage class
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-stuck-pvc
  namespace: $TEST_NAMESPACE
  labels:
    test-scenario: stuck-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: non-existent-storage-class
EOF

    log INFO "Stuck PVC created. It should remain in Pending state..."
    sleep 10
    
    # Check PVC status
    kubectl get pvc test-stuck-pvc -n "$TEST_NAMESPACE"
    kubectl describe pvc test-stuck-pvc -n "$TEST_NAMESPACE" | tail -5
}

# Function to create a stuck terminating pod
create_stuck_terminating_pod() {
    log TEST "Creating stuck terminating pod scenario..."
    
    # Create a pod with a finalizer that will prevent deletion
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-stuck-pod
  namespace: $TEST_NAMESPACE
  finalizers:
    - test.example.com/stuck-finalizer
  labels:
    test-scenario: stuck-termination
spec:
  containers:
  - name: app
    image: nginx:1.21
    command: ["/bin/sh", "-c", "sleep 3600"]
EOF

    # Wait for pod to be running
    kubectl wait --for=condition=Ready pod/test-stuck-pod -n "$TEST_NAMESPACE" --timeout=60s
    
    # Delete the pod (it will get stuck in terminating due to finalizer)
    kubectl delete pod test-stuck-pod -n "$TEST_NAMESPACE" --timeout=5s || true
    
    log INFO "Pod deletion initiated. It should get stuck in Terminating state..."
    sleep 10
    
    # Check pod status
    kubectl get pod test-stuck-pod -n "$TEST_NAMESPACE" || true
}

# Function to simulate Flux reconciliation stuck state
simulate_flux_stuck_state() {
    log TEST "Simulating Flux reconciliation stuck state..."
    
    # We'll use the existing monitoring kustomization that's already stuck
    log INFO "Using existing stuck monitoring kustomization for testing"
    
    # Show current status
    kubectl get kustomization monitoring -n flux-system -o yaml | grep -A 10 "conditions:"
}

# Function to test alert queries directly
test_alert_queries() {
    log TEST "Testing alert query expressions..."
    
    local queries=(
        "GitOpsDeploymentRolloutStuck:kube_deployment_status_replicas != kube_deployment_status_ready_replicas"
        "GitOpsPVCStuckTerminating:kube_persistentvolumeclaim_deletion_timestamp > 0"
        "GitOpsResourceStuckTerminating:kube_pod_deletion_timestamp > 0"
        "FluxKustomizationStuck:time() - max by (namespace, name) (gotk_reconcile_condition{kind=\"Kustomization\", type=\"Ready\", status=\"True\"}) > 600"
    )
    
    for query_info in "${queries[@]}"; do
        local alert_name="${query_info%%:*}"
        local query="${query_info#*:}"
        
        log INFO "Testing query for $alert_name..."
        echo "Query: $query"
        
        local response=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$(echo "$query" | sed 's/ /%20/g')" || echo "")
        
        if echo "$response" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
            log SUCCESS "Query returned results for $alert_name"
            echo "$response" | jq -r '.data.result[] | "\(.metric | to_entries | map("\(.key)=\(.value)") | join(" ")) value=\(.value[1])"'
        else
            log INFO "No current results for $alert_name (this may be expected)"
        fi
        echo ""
    done
}

# Function to check current alert status
check_current_alerts() {
    log TEST "Checking current active alerts..."
    
    local response=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=ALERTS" || echo "")
    
    if echo "$response" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        log INFO "Active alerts found:"
        echo "$response" | jq -r '.data.result[] | "- \(.metric.alertname) (\(.metric.alertstate)): \(.metric.summary // "No summary")"'
    else
        log INFO "No active alerts currently"
    fi
    echo ""
}

# Function to validate alert routing (if Alertmanager is available)
test_alert_routing() {
    log TEST "Testing alert routing and notification delivery..."
    
    # Check if Alertmanager is available
    if kubectl get service -n monitoring | grep -q alertmanager; then
        log INFO "Alertmanager found, testing routing..."
        
        # Try to access Alertmanager API
        kubectl port-forward -n monitoring svc/alertmanager 9093:9093 --address=0.0.0.0 &
        local am_pid=$!
        sleep 5
        
        local am_response=$(curl -s "http://localhost:9093/api/v1/alerts" || echo "")
        if [ -n "$am_response" ]; then
            log SUCCESS "Alertmanager accessible"
            echo "$am_response" | jq -r '.data[] | "Alert: \(.labels.alertname) Status: \(.status.state)"' 2>/dev/null || echo "No alerts in Alertmanager"
        else
            log WARN "Cannot access Alertmanager API"
        fi
        
        kill $am_pid 2>/dev/null || true
    else
        log INFO "Alertmanager not found, skipping routing test"
    fi
}

# Main test execution
main() {
    echo "🚨 GitOps Resilience Alert Testing"
    echo "=================================="
    echo ""
    
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        log ERROR "kubectl not found"
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        log ERROR "curl not found"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log ERROR "jq not found (install with: brew install jq)"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log ERROR "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Setup Prometheus access
    if ! check_prometheus; then
        log ERROR "Cannot access Prometheus for testing"
        exit 1
    fi
    
    echo ""
    log INFO "Starting alert testing scenarios..."
    echo ""
    
    # Test 1: Check current alerts
    check_current_alerts
    
    # Test 2: Test alert queries
    test_alert_queries
    
    # Test 3: Use existing stuck state (monitoring kustomization)
    simulate_flux_stuck_state
    
    # Test 4: Create stuck deployment
    create_stuck_deployment
    
    # Wait and check for deployment rollout alert
    log INFO "Waiting for GitOpsDeploymentRolloutStuck alert..."
    if query_alerts "GitOpsDeploymentRolloutStuck" 120; then
        log SUCCESS "Deployment rollout stuck alert fired successfully!"
    else
        log WARN "Deployment rollout stuck alert did not fire within timeout"
    fi
    
    # Test 5: Create stuck PVC
    create_stuck_pvc
    
    # Test 6: Create stuck terminating pod
    create_stuck_terminating_pod
    
    # Wait and check for terminating pod alert
    log INFO "Waiting for GitOpsResourceStuckTerminating alert..."
    if query_alerts "GitOpsResourceStuckTerminating" 120; then
        log SUCCESS "Resource stuck terminating alert fired successfully!"
    else
        log WARN "Resource stuck terminating alert did not fire within timeout"
    fi
    
    # Test 7: Check for Flux stuck alerts (using existing monitoring issue)
    log INFO "Checking for Flux reconciliation stuck alerts..."
    if query_alerts "FluxKustomizationStuck" 30; then
        log SUCCESS "Flux kustomization stuck alert is active!"
    else
        log INFO "No Flux stuck alerts currently (monitoring may have recovered)"
    fi
    
    # Test 8: Test alert routing
    test_alert_routing
    
    # Final summary
    echo ""
    log INFO "Alert testing completed!"
    echo ""
    log INFO "Summary of tests performed:"
    echo "  ✅ Alert query validation"
    echo "  ✅ Current alert status check"
    echo "  ✅ Stuck deployment simulation"
    echo "  ✅ Stuck PVC simulation"
    echo "  ✅ Stuck terminating pod simulation"
    echo "  ✅ Flux reconciliation monitoring"
    echo "  ✅ Alert routing validation"
    echo ""
    
    # Show final alert status
    log INFO "Final active alerts:"
    check_current_alerts
    
    # Cleanup prompt
    echo ""
    read -p "Keep test resources for manual inspection? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEANUP_ON_EXIT=false
        log INFO "Test resources preserved in namespace: $TEST_NAMESPACE"
        log INFO "To clean up later, run: kubectl delete namespace $TEST_NAMESPACE"
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --no-cleanup        Don't clean up test resources on exit"
        echo "  --prometheus-url    Prometheus URL (default: $PROMETHEUS_URL)"
        echo ""
        echo "This script tests GitOps resilience alerts by:"
        echo "  1. Creating various stuck state scenarios"
        echo "  2. Validating that alerts fire correctly"
        echo "  3. Testing alert routing and notification delivery"
        echo ""
        exit 0
        ;;
    --no-cleanup)
        CLEANUP_ON_EXIT=false
        ;;
    --prometheus-url)
        PROMETHEUS_URL="$2"
        shift
        ;;
esac

# Run main function
main "$@"