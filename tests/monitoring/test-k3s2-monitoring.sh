#!/bin/bash

# Test script for k3s2 monitoring integration
# This script validates the monitoring configuration before k3s2 is online

set -e

echo "🔍 Testing k3s2 Monitoring Integration"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
        return 1
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "ℹ️  $1"
}

echo
echo "1. Validating YAML Syntax and Kubernetes Resources"
echo "------------------------------------------------"

# Test 1: Validate YAML syntax
if kubectl kustomize infrastructure/monitoring/core/ > /dev/null 2>&1; then
    print_status 0 "YAML syntax validation passed"
else
    print_status 1 "YAML syntax validation failed"
    exit 1
fi

# Test 2: Validate Kubernetes resources
if kubectl kustomize infrastructure/monitoring/core/ | kubectl apply --dry-run=client -f - > /dev/null 2>&1; then
    print_status 0 "Kubernetes resource validation passed"
else
    print_status 1 "Kubernetes resource validation failed"
    exit 1
fi

echo
echo "2. Checking Deployed Monitoring Resources"
echo "---------------------------------------"

# Test 3: Check ServiceMonitors
SERVICEMONITORS=$(kubectl get servicemonitor -n monitoring --no-headers | wc -l)
if [ $SERVICEMONITORS -gt 0 ]; then
    print_status 0 "ServiceMonitors deployed ($SERVICEMONITORS found)"
    kubectl get servicemonitor -n monitoring | grep -E "(multi-node|k3s2)" || print_warning "k3s2-specific ServiceMonitors not found (expected before k3s2 joins)"
else
    print_status 1 "No ServiceMonitors found"
fi

# Test 4: Check PodMonitors
PODMONITORS=$(kubectl get podmonitor -n monitoring --no-headers | wc -l)
if [ $PODMONITORS -gt 0 ]; then
    print_status 0 "PodMonitors deployed ($PODMONITORS found)"
    kubectl get podmonitor -n monitoring | grep -E "(multi-node|flux)" || print_warning "Expected PodMonitors not found"
else
    print_status 1 "No PodMonitors found"
fi

# Test 5: Check PrometheusRules
RULES=$(kubectl get prometheusrule -n monitoring --no-headers | wc -l)
if [ $RULES -gt 0 ]; then
    print_status 0 "PrometheusRules deployed ($RULES found)"
    if kubectl get prometheusrule -n monitoring k3s2-node-alerts > /dev/null 2>&1; then
        print_status 0 "k3s2-specific alert rules found"
    else
        print_status 1 "k3s2-specific alert rules not found"
    fi
else
    print_status 1 "No PrometheusRules found"
fi

# Test 6: Check Grafana Dashboards
DASHBOARDS=$(kubectl get configmap -n monitoring -l grafana_dashboard=1 --no-headers | wc -l)
if [ $DASHBOARDS -gt 0 ]; then
    print_status 0 "Grafana dashboards deployed ($DASHBOARDS found)"
    if kubectl get configmap -n monitoring k3s2-node-dashboard > /dev/null 2>&1; then
        print_status 0 "k3s2-specific dashboard found"
    else
        print_status 1 "k3s2-specific dashboard not found"
    fi
    if kubectl get configmap -n monitoring multi-node-cluster-dashboard > /dev/null 2>&1; then
        print_status 0 "Multi-node cluster dashboard found"
    else
        print_status 1 "Multi-node cluster dashboard not found"
    fi
else
    print_status 1 "No Grafana dashboards found"
fi

echo
echo "3. Testing Prometheus Configuration"
echo "---------------------------------"

# Test 7: Check if Prometheus is running
if kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep -q Running; then
    print_status 0 "Prometheus is running"
    
    # Port forward to Prometheus (if not already running)
    if ! curl -s http://localhost:9090/api/v1/status/config > /dev/null 2>&1; then
        print_info "Starting port-forward to Prometheus..."
        kubectl port-forward -n monitoring svc/prometheus-monitoring-core-prometheus-prometheus 9090:9090 --address=0.0.0.0 > /dev/null 2>&1 &
        PROMETHEUS_PF_PID=$!
        sleep 5
    fi
    
    # Test Prometheus API
    if curl -s http://localhost:9090/api/v1/status/config > /dev/null 2>&1; then
        print_status 0 "Prometheus API accessible"
        
        # Check current targets
        TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length')
        print_info "Current monitoring targets: $TARGETS"
        
        # Check for node-exporter targets
        NODE_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "node-exporter") | .labels.instance' | wc -l)
        print_info "Node-exporter targets: $NODE_TARGETS (k3s1 only, k3s2 will appear when it joins)"
        
    else
        print_status 1 "Prometheus API not accessible"
    fi
else
    print_status 1 "Prometheus is not running"
fi

echo
echo "4. Testing Alert Rule Syntax"
echo "---------------------------"

# Test 8: Validate alert expressions
print_info "Validating k3s2 alert rule expressions..."

# Extract and test a few key alert expressions
ALERT_RULES=$(kubectl get prometheusrule -n monitoring k3s2-node-alerts -o jsonpath='{.spec.groups[0].rules[*].expr}')

if [ ! -z "$ALERT_RULES" ]; then
    print_status 0 "Alert rule expressions extracted successfully"
    print_info "Found $(echo $ALERT_RULES | wc -w) alert expressions"
else
    print_status 1 "Failed to extract alert rule expressions"
fi

echo
echo "5. Simulating k3s2 Metrics Query"
echo "-------------------------------"

# Test 9: Test queries that will work when k3s2 joins
print_info "Testing queries that will activate when k3s2 joins..."

# These queries will return empty results now but should work when k3s2 joins
QUERIES=(
    'up{instance=~".*k3s2.*", job="node-exporter"}'
    'node_cpu_seconds_total{instance=~".*k3s2.*"}'
    'kube_pod_info{node="k3s2"}'
    'longhorn_node_status{node="k3s2"}'
)

for query in "${QUERIES[@]}"; do
    ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$query'))")
    RESPONSE=$(curl -s "http://localhost:9090/api/v1/query?query=$ENCODED_QUERY")
    if echo $RESPONSE | jq -e '.status == "success"' > /dev/null 2>&1; then
        RESULT_COUNT=$(echo $RESPONSE | jq '.data.result | length')
        if [ "$RESULT_COUNT" -eq 0 ]; then
            print_status 0 "Query syntax valid (no results expected): $query"
        else
            print_status 0 "Query syntax valid ($RESULT_COUNT results): $query"
        fi
    else
        print_status 1 "Query syntax invalid: $query"
    fi
done

echo
echo "6. Testing Grafana Dashboard Access"
echo "----------------------------------"

# Test 10: Check Grafana accessibility
if kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep -q Running; then
    print_status 0 "Grafana is running"
    
    # Port forward to Grafana (if not already running)
    if ! curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        print_info "Starting port-forward to Grafana..."
        kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0 > /dev/null 2>&1 &
        GRAFANA_PF_PID=$!
        sleep 5
    fi
    
    # Test Grafana API
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        print_status 0 "Grafana API accessible"
        print_info "Grafana available at: http://localhost:3000"
        print_info "Default credentials: admin/admin"
    else
        print_status 1 "Grafana API not accessible"
    fi
else
    print_status 1 "Grafana is not running"
fi

echo
echo "7. Summary and Next Steps"
echo "-----------------------"

print_info "✨ Monitoring configuration is ready for k3s2 integration!"
echo
echo "When k3s2 joins the cluster, the following will happen automatically:"
echo "• ServiceMonitors will discover k3s2 node-exporter endpoint"
echo "• PodMonitors will collect kubelet metrics from k3s2"
echo "• Prometheus will start scraping k3s2 metrics"
echo "• Grafana dashboards will display k3s2 data"
echo "• Alert rules will monitor k3s2 health"
echo
echo "To verify after k3s2 joins:"
echo "1. Check Prometheus targets: http://localhost:9090/targets"
echo "2. View k3s2 dashboard: http://localhost:3000 → Node Monitoring folder"
echo "3. Check alerts: http://localhost:9090/alerts"
echo
echo "Manual verification commands:"
echo "kubectl get nodes"
echo "kubectl get pods -n monitoring"
echo "kubectl get servicemonitor,podmonitor -n monitoring"
echo "kubectl get prometheusrule -n monitoring"

# Cleanup port forwards if we started them
if [ ! -z "$PROMETHEUS_PF_PID" ]; then
    kill $PROMETHEUS_PF_PID 2>/dev/null || true
fi
if [ ! -z "$GRAFANA_PF_PID" ]; then
    kill $GRAFANA_PF_PID 2>/dev/null || true
fi

echo
print_status 0 "k3s2 monitoring integration test completed successfully!"