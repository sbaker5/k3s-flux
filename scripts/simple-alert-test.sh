#!/bin/bash
# Simple alert testing script to validate stuck state alerts
set -euo pipefail

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in kubectl curl jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please install missing tools and try again"
        exit 1
    fi
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Configuration constants
TEST_NS="alert-test"
PROMETHEUS_URL="http://localhost:9090"
PROMETHEUS_PORT="9090"
PROMETHEUS_SVC="monitoring-core-prometheus-prometheus"
PROMETHEUS_NS="monitoring"
WAIT_TIMEOUT_MINUTES=12
POLL_INTERVAL_SECONDS=60
INITIAL_WAIT_SECONDS=30
PORT_FORWARD_WAIT=5

# Cleanup function
cleanup() {
    log "Cleaning up test resources..."
    kubectl delete namespace "$TEST_NS" --ignore-not-found=true --timeout=30s || true
    pkill -f "kubectl port-forward.*prometheus" 2>/dev/null || true
}

# Create test deployment with unrealistic resource requirements
create_stuck_deployment() {
    log "Creating stuck deployment..."
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stuck-test
  namespace: $TEST_NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: stuck-test
  template:
    metadata:
      labels:
        app: stuck-test
    spec:
      containers:
      - name: app
        image: nginx:1.21
        resources:
          requests:
            memory: "16Gi"  # Unrealistic request to cause scheduling failure
            cpu: "10"
          limits:
            memory: "16Gi"
            cpu: "10"
EOF
}

# Setup Prometheus port forward if needed
setup_prometheus_access() {
    if ! curl -s "${PROMETHEUS_URL}/api/v1/query?query=up" >/dev/null 2>&1; then
        log "Setting up Prometheus port forward..."
        kubectl port-forward -n "$PROMETHEUS_NS" "svc/$PROMETHEUS_SVC" "${PROMETHEUS_PORT}:${PROMETHEUS_PORT}" --address=0.0.0.0 &
        sleep "$PORT_FORWARD_WAIT"
        
        # Verify connection
        if ! curl -s "${PROMETHEUS_URL}/api/v1/query?query=up" >/dev/null 2>&1; then
            error "Failed to establish Prometheus connection"
            return 1
        fi
    fi
}

# Query Prometheus with error handling
query_prometheus() {
    local query="$1"
    local response
    
    if ! response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=${query}" 2>/dev/null); then
        error "Failed to query Prometheus: $query"
        return 1
    fi
    
    echo "$response"
}

# Check for specific alert
check_alert() {
    local alert_name="$1"
    local response
    
    if ! response=$(query_prometheus "ALERTS{alertname=\"${alert_name}\"}"); then
        return 1
    fi
    
    if echo "$response" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        success "${alert_name} alert is firing!"
        echo "$response" | jq -r '.data.result[0].metric | "Namespace: \(.namespace), Deployment: \(.deployment), State: \(.alertstate)"'
        return 0
    fi
    
    return 1
}

# Display diagnostic information when alert doesn't fire
show_diagnostics() {
    local alert_name="$1"
    
    error "Alert did not fire within $WAIT_TIMEOUT_MINUTES minutes"
    
    log "Current alert rules state:"
    if response=$(curl -s "${PROMETHEUS_URL}/api/v1/rules" 2>/dev/null); then
        echo "$response" | jq -r ".data.groups[] | select(.name == \"gitops.deployment.health\") | .rules[] | select(.name == \"${alert_name}\") | \"State: \(.state), Health: \(.health)\""
    else
        error "Failed to fetch alert rules"
    fi
    
    log "Checking deployment metrics:"
    if response=$(query_prometheus "kube_deployment_status_replicas{namespace=\"$TEST_NS\"}"); then
        echo "$response" | jq -r '.data.result[] | "Desired: \(.value[1]), Deployment: \(.metric.deployment)"'
    fi
    
    if response=$(query_prometheus "kube_deployment_status_ready_replicas{namespace=\"$TEST_NS\"}"); then
        echo "$response" | jq -r '.data.result[] | "Ready: \(.value[1]), Deployment: \(.metric.deployment)"'
    fi
}

# Main execution function
main() {
    echo "🧪 Simple Alert Testing"
    echo "======================"
    
    # Check dependencies first
    check_dependencies
    
    # Create test namespace
    log "Creating test namespace..."
    kubectl create namespace "$TEST_NS" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create stuck deployment
    create_stuck_deployment
    
    log "Waiting for deployment to get stuck..."
    sleep "$INITIAL_WAIT_SECONDS"
    
    # Check deployment status
    log "Deployment status:"
    kubectl get deployment stuck-test -n "$TEST_NS" -o wide
    
    # Check if pods are pending
    log "Pod status:"
    kubectl get pods -n "$TEST_NS"
    
    # Setup Prometheus access
    if ! setup_prometheus_access; then
        error "Failed to setup Prometheus access"
        exit 1
    fi
    
    # Check for deployment rollout stuck alert
    log "Checking for GitOpsDeploymentRolloutStuck alert..."
    local alert_fired=false
    
    for i in $(seq 1 "$WAIT_TIMEOUT_MINUTES"); do
        if check_alert "GitOpsDeploymentRolloutStuck"; then
            alert_fired=true
            break
        else
            echo -n "."
            sleep "$POLL_INTERVAL_SECONDS"
        fi
    done
    
    if [ "$alert_fired" = false ]; then
        show_diagnostics "GitOpsDeploymentRolloutStuck"
        exit 1
    fi
    
    echo ""
    log "Test completed successfully!"
}

# Set up cleanup and run main function
trap cleanup EXIT
main "$@"