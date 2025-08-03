#!/bin/bash
# Remote Monitoring Connectivity Test Script
#
# This script performs comprehensive end-to-end testing of remote monitoring access
# via Tailscale, including actual HTTP requests and dashboard functionality testing.
#
# Usage: ./scripts/test-remote-monitoring-connectivity.sh [--full-test] [--dashboard-test]
#   --full-test: Perform comprehensive connectivity and functionality testing
#   --dashboard-test: Test Grafana dashboard loading and Prometheus queries

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAILSCALE_IP=""
FULL_TEST=false
DASHBOARD_TEST=false
TEST_TIMEOUT=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full-test)
            FULL_TEST=true
            shift
            ;;
        --dashboard-test)
            DASHBOARD_TEST=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--full-test] [--dashboard-test]"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
}

# Get Tailscale IP
get_tailscale_ip() {
    if command -v tailscale >/dev/null 2>&1; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
        if [[ -n "$TAILSCALE_IP" ]]; then
            log "Tailscale IP: $TAILSCALE_IP"
            return 0
        fi
    fi
    
    error "Cannot determine Tailscale IP"
    return 1
}

# Setup port forwards for testing
setup_port_forwards() {
    log "Setting up port forwards for remote testing..."
    
    # Clean up any existing port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
    
    # Get service names
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    local grafana_service=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$prometheus_service" || -z "$grafana_service" ]]; then
        error "Cannot find required monitoring services"
        return 1
    fi
    
    # Start port forwards
    log "Starting Prometheus port forward..."
    kubectl port-forward -n monitoring "service/$prometheus_service" 9090:9090 --address=0.0.0.0 >/dev/null 2>&1 &
    local prometheus_pid=$!
    
    log "Starting Grafana port forward..."
    kubectl port-forward -n monitoring "service/$grafana_service" 3000:80 --address=0.0.0.0 >/dev/null 2>&1 &
    local grafana_pid=$!
    
    # Wait for port forwards to establish
    sleep 5
    
    # Verify port forwards are running
    if ! kill -0 "$prometheus_pid" 2>/dev/null || ! kill -0 "$grafana_pid" 2>/dev/null; then
        error "Failed to establish port forwards"
        return 1
    fi
    
    success "Port forwards established (Prometheus: $prometheus_pid, Grafana: $grafana_pid)"
    
    # Store PIDs for cleanup
    echo "$prometheus_pid" > /tmp/prometheus_port_forward.pid
    echo "$grafana_pid" > /tmp/grafana_port_forward.pid
    
    return 0
}

# Cleanup port forwards
cleanup_port_forwards() {
    log "Cleaning up port forwards..."
    
    # Kill specific PIDs if available
    if [[ -f /tmp/prometheus_port_forward.pid ]]; then
        local prometheus_pid=$(cat /tmp/prometheus_port_forward.pid)
        kill "$prometheus_pid" 2>/dev/null || true
        rm -f /tmp/prometheus_port_forward.pid
    fi
    
    if [[ -f /tmp/grafana_port_forward.pid ]]; then
        local grafana_pid=$(cat /tmp/grafana_port_forward.pid)
        kill "$grafana_pid" 2>/dev/null || true
        rm -f /tmp/grafana_port_forward.pid
    fi
    
    # Clean up any remaining port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    success "Port forward cleanup completed"
}

# Test basic HTTP connectivity
test_basic_connectivity() {
    log "Testing basic HTTP connectivity..."
    local issues=0
    
    # Test Prometheus
    log "Testing Prometheus connectivity..."
    if curl -s --max-time "$TEST_TIMEOUT" "http://localhost:9090/api/v1/query?query=up" >/dev/null 2>&1; then
        success "Prometheus HTTP endpoint accessible locally"
    else
        error "Prometheus HTTP endpoint not accessible locally"
        issues=$((issues + 1))
    fi
    
    # Test Prometheus via Tailscale IP
    if [[ -n "$TAILSCALE_IP" ]]; then
        log "Testing Prometheus via Tailscale IP..."
        if curl -s --max-time "$TEST_TIMEOUT" "http://$TAILSCALE_IP:9090/api/v1/query?query=up" >/dev/null 2>&1; then
            success "Prometheus accessible via Tailscale IP: $TAILSCALE_IP:9090"
        else
            error "Prometheus not accessible via Tailscale IP"
            issues=$((issues + 1))
        fi
    fi
    
    # Test Grafana
    log "Testing Grafana connectivity..."
    if curl -s --max-time "$TEST_TIMEOUT" "http://localhost:3000/api/health" >/dev/null 2>&1; then
        success "Grafana HTTP endpoint accessible locally"
    elif curl -s --max-time "$TEST_TIMEOUT" "http://localhost:3000/" >/dev/null 2>&1; then
        success "Grafana HTTP endpoint accessible locally (via root path)"
    else
        error "Grafana HTTP endpoint not accessible locally"
        issues=$((issues + 1))
    fi
    
    # Test Grafana via Tailscale IP
    if [[ -n "$TAILSCALE_IP" ]]; then
        log "Testing Grafana via Tailscale IP..."
        if curl -s --max-time "$TEST_TIMEOUT" "http://$TAILSCALE_IP:3000/api/health" >/dev/null 2>&1; then
            success "Grafana accessible via Tailscale IP: $TAILSCALE_IP:3000"
        elif curl -s --max-time "$TEST_TIMEOUT" "http://$TAILSCALE_IP:3000/" >/dev/null 2>&1; then
            success "Grafana accessible via Tailscale IP: $TAILSCALE_IP:3000 (via root path)"
        else
            error "Grafana not accessible via Tailscale IP"
            issues=$((issues + 1))
        fi
    fi
    
    return $issues
}

# Test Prometheus functionality
test_prometheus_functionality() {
    log "Testing Prometheus functionality..."
    local issues=0
    
    # Test basic query
    log "Testing basic Prometheus query..."
    local response=$(curl -s --max-time "$TEST_TIMEOUT" "http://localhost:9090/api/v1/query?query=up" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]] && echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        local result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo "0")
        success "Prometheus query successful - found $result_count targets"
        
        # Test specific metrics
        log "Testing Flux controller metrics..."
        local flux_response=$(curl -s --max-time "$TEST_TIMEOUT" "http://localhost:9090/api/v1/query?query=controller_runtime_active_workers" 2>/dev/null || echo "")
        
        if [[ -n "$flux_response" ]] && echo "$flux_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
            local flux_count=$(echo "$flux_response" | jq -r '.data.result | length' 2>/dev/null || echo "0")
            success "Flux controller metrics available - found $flux_count controller metrics"
        else
            warn "Flux controller metrics not found or not accessible"
        fi
        
    else
        error "Prometheus query failed or returned invalid response"
        issues=$((issues + 1))
    fi
    
    # Test targets endpoint
    log "Testing Prometheus targets endpoint..."
    local targets_response=$(curl -s --max-time "$TEST_TIMEOUT" "http://localhost:9090/api/v1/targets" 2>/dev/null || echo "")
    
    if [[ -n "$targets_response" ]] && echo "$targets_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        local active_targets=$(echo "$targets_response" | jq -r '.data.activeTargets | length' 2>/dev/null || echo "0")
        success "Prometheus targets endpoint accessible - found $active_targets active targets"
    else
        error "Prometheus targets endpoint not accessible"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Test Grafana functionality
test_grafana_functionality() {
    log "Testing Grafana functionality..."
    local issues=0
    
    # Test health endpoint
    log "Testing Grafana health endpoint..."
    local health_response=$(curl -s --max-time "$TEST_TIMEOUT" "http://localhost:3000/api/health" 2>/dev/null || echo "")
    
    if [[ -n "$health_response" ]]; then
        if echo "$health_response" | jq -e '.database == "ok"' >/dev/null 2>&1; then
            success "Grafana health check passed"
        else
            warn "Grafana health check returned non-optimal status"
        fi
    else
        # Try alternative health check
        if curl -s --max-time "$TEST_TIMEOUT" "http://localhost:3000/" | grep -q "Grafana" 2>/dev/null; then
            success "Grafana web interface accessible"
        else
            error "Grafana not accessible"
            issues=$((issues + 1))
        fi
    fi
    
    # Test datasources endpoint (may require auth, so just check if endpoint exists)
    log "Testing Grafana datasources endpoint..."
    local ds_response=$(curl -s --max-time "$TEST_TIMEOUT" "http://localhost:3000/api/datasources" 2>/dev/null || echo "")
    
    if [[ -n "$ds_response" ]]; then
        if echo "$ds_response" | grep -q "Unauthorized" 2>/dev/null; then
            success "Grafana datasources endpoint accessible (auth required as expected)"
        elif echo "$ds_response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            local ds_count=$(echo "$ds_response" | jq -r 'length' 2>/dev/null || echo "0")
            success "Grafana datasources endpoint accessible - found $ds_count datasources"
        else
            warn "Grafana datasources endpoint returned unexpected response"
        fi
    else
        warn "Grafana datasources endpoint not accessible"
    fi
    
    return $issues
}

# Test dashboard functionality
test_dashboard_functionality() {
    if [[ "$DASHBOARD_TEST" != "true" ]]; then
        log "Skipping dashboard tests (use --dashboard-test to enable)"
        return 0
    fi
    
    log "Testing Grafana dashboard functionality..."
    local issues=0
    
    # Test dashboard search endpoint
    log "Testing dashboard search..."
    local search_response=$(curl -s --max-time "$TEST_TIMEOUT" "http://localhost:3000/api/search" 2>/dev/null || echo "")
    
    if [[ -n "$search_response" ]]; then
        if echo "$search_response" | grep -q "Unauthorized" 2>/dev/null; then
            success "Dashboard search endpoint accessible (auth required as expected)"
        elif echo "$search_response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            local dashboard_count=$(echo "$search_response" | jq -r 'length' 2>/dev/null || echo "0")
            success "Dashboard search accessible - found $dashboard_count dashboards"
        else
            warn "Dashboard search returned unexpected response"
        fi
    else
        warn "Dashboard search endpoint not accessible"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Test network latency and performance
test_network_performance() {
    if [[ "$FULL_TEST" != "true" ]]; then
        log "Skipping network performance tests (use --full-test to enable)"
        return 0
    fi
    
    log "Testing network performance via Tailscale..."
    local issues=0
    
    if [[ -n "$TAILSCALE_IP" ]]; then
        # Test response time
        log "Testing response time to Prometheus..."
        local start_time=$(date +%s%N)
        if curl -s --max-time "$TEST_TIMEOUT" "http://$TAILSCALE_IP:9090/api/v1/query?query=up" >/dev/null 2>&1; then
            local end_time=$(date +%s%N)
            local response_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
            
            if [[ $response_time -lt 1000 ]]; then
                success "Prometheus response time: ${response_time}ms (excellent)"
            elif [[ $response_time -lt 3000 ]]; then
                success "Prometheus response time: ${response_time}ms (good)"
            else
                warn "Prometheus response time: ${response_time}ms (slow)"
            fi
        else
            error "Failed to measure Prometheus response time"
            issues=$((issues + 1))
        fi
        
        # Test Grafana response time
        log "Testing response time to Grafana..."
        start_time=$(date +%s%N)
        if curl -s --max-time "$TEST_TIMEOUT" "http://$TAILSCALE_IP:3000/" >/dev/null 2>&1; then
            end_time=$(date +%s%N)
            response_time=$(( (end_time - start_time) / 1000000 ))
            
            if [[ $response_time -lt 2000 ]]; then
                success "Grafana response time: ${response_time}ms (excellent)"
            elif [[ $response_time -lt 5000 ]]; then
                success "Grafana response time: ${response_time}ms (good)"
            else
                warn "Grafana response time: ${response_time}ms (slow)"
            fi
        else
            error "Failed to measure Grafana response time"
            issues=$((issues + 1))
        fi
    else
        warn "Cannot test network performance - Tailscale IP not available"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Generate connectivity report
generate_connectivity_report() {
    log "Generating connectivity test report..."
    
    local report_file="/tmp/remote-monitoring-connectivity-report.md"
    
    cat > "$report_file" << EOF
# Remote Monitoring Connectivity Test Report

**Date**: $(date)
**Tailscale IP**: $TAILSCALE_IP
**Test Script**: $0

## Test Configuration

- **Full Test**: $FULL_TEST
- **Dashboard Test**: $DASHBOARD_TEST
- **Test Timeout**: ${TEST_TIMEOUT}s

## Connectivity Summary

### Prometheus Access
- **Local**: http://localhost:9090
- **Remote**: http://$TAILSCALE_IP:9090
- **API Endpoint**: /api/v1/query
- **Targets Endpoint**: /api/v1/targets

### Grafana Access
- **Local**: http://localhost:3000
- **Remote**: http://$TAILSCALE_IP:3000
- **Health Endpoint**: /api/health
- **Datasources Endpoint**: /api/datasources

## Remote Access Commands

\`\`\`bash
# Start port forwards
kubectl port-forward -n monitoring service/monitoring-core-prometheus-prometheus 9090:9090 --address=0.0.0.0 &
kubectl port-forward -n monitoring service/monitoring-core-grafana 3000:80 --address=0.0.0.0 &

# Access URLs
echo "Prometheus: http://$TAILSCALE_IP:9090"
echo "Grafana: http://$TAILSCALE_IP:3000"

# Clean up
pkill -f 'kubectl port-forward'
\`\`\`

## Troubleshooting

If connectivity tests fail:

1. **Check Tailscale**: \`tailscale status\`
2. **Check port forwards**: \`ps aux | grep kubectl\`
3. **Check services**: \`kubectl get svc -n monitoring\`
4. **Check pods**: \`kubectl get pods -n monitoring\`

---
*Report generated by test-remote-monitoring-connectivity.sh*
EOF
    
    success "Connectivity report generated: $report_file"
}

# Main test function
run_connectivity_tests() {
    log "Starting comprehensive remote monitoring connectivity tests..."
    
    local total_issues=0
    
    # Get Tailscale IP
    if ! get_tailscale_ip; then
        error "Cannot proceed without Tailscale connectivity"
        return 1
    fi
    
    # Setup port forwards
    if ! setup_port_forwards; then
        error "Cannot proceed without port forwards"
        return 1
    fi
    
    # Ensure cleanup happens on exit
    trap cleanup_port_forwards EXIT
    
    # Run tests
    test_basic_connectivity
    total_issues=$((total_issues + $?))
    
    test_prometheus_functionality
    total_issues=$((total_issues + $?))
    
    test_grafana_functionality
    total_issues=$((total_issues + $?))
    
    test_dashboard_functionality
    total_issues=$((total_issues + $?))
    
    test_network_performance
    total_issues=$((total_issues + $?))
    
    # Generate report
    generate_connectivity_report
    
    # Summary
    if [[ $total_issues -eq 0 ]]; then
        success "All remote monitoring connectivity tests passed!"
        success "Remote monitoring access is fully functional via Tailscale"
    elif [[ $total_issues -le 3 ]]; then
        warn "Remote monitoring connectivity tests completed with $total_issues minor issues"
        warn "Most functionality is working, but some features may be limited"
    else
        error "Remote monitoring connectivity tests found $total_issues issues"
        error "Remote access may not be fully functional"
    fi
    
    return $total_issues
}

# Dependency checks
check_dependencies() {
    local missing_deps=0
    
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        error "curl not found - please install curl"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        error "jq not found - please install jq (brew install jq)"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v tailscale >/dev/null 2>&1; then
        error "tailscale not found - please install tailscale"
        missing_deps=$((missing_deps + 1))
    fi
    
    if [[ $missing_deps -gt 0 ]]; then
        error "Missing $missing_deps required dependencies"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check Tailscale connectivity
    if ! tailscale status >/dev/null 2>&1; then
        error "Tailscale is not connected - run 'tailscale up'"
        exit 1
    fi
}

# Main execution
main() {
    log "Remote Monitoring Connectivity Test v1.0"
    log "========================================"
    
    check_dependencies
    
    # Run the tests
    run_connectivity_tests
    exit_code=$?
    
    log "========================================"
    if [[ $exit_code -eq 0 ]]; then
        success "Remote monitoring connectivity is fully functional!"
    else
        error "Remote monitoring connectivity has $exit_code issue(s) - see details above"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"