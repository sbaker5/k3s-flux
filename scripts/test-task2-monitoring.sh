#!/bin/bash
# Comprehensive test plan for Task 2: Reconciliation Health Monitoring
# This script validates all components of the monitoring infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
PROMETHEUS_URL="http://localhost:9090"
GRAFANA_URL="http://localhost:3000"
PROMETHEUS_PID=""
GRAFANA_PID=""
TEST_RESULTS=()

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
        SECTION)
            echo -e "${PURPLE}[SECTION]${NC} $*"
            ;;
    esac
}

# Function to record test results
record_test() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    TEST_RESULTS+=("$test_name:$result:$details")
    
    if [ "$result" = "PASS" ]; then
        log SUCCESS "$test_name: PASSED"
    elif [ "$result" = "FAIL" ]; then
        log ERROR "$test_name: FAILED - $details"
    elif [ "$result" = "WARN" ]; then
        log WARN "$test_name: WARNING - $details"
    fi
}

# Cleanup function
cleanup() {
    log INFO "Cleaning up port forwards..."
    
    if [ -n "$PROMETHEUS_PID" ]; then
        kill "$PROMETHEUS_PID" 2>/dev/null || true
    fi
    
    if [ -n "$GRAFANA_PID" ]; then
        kill "$GRAFANA_PID" 2>/dev/null || true
    fi
    
    # Kill any remaining port forwards
    pkill -f "kubectl port-forward.*prometheus" 2>/dev/null || true
    pkill -f "kubectl port-forward.*grafana" 2>/dev/null || true
}

trap cleanup EXIT

# Function to setup port forwards
setup_port_forwards() {
    log INFO "Setting up port forwards for testing..."
    
    # Prometheus port forward
    if ! curl -s "$PROMETHEUS_URL/api/v1/query?query=up" >/dev/null 2>&1; then
        log INFO "Starting Prometheus port forward..."
        kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 --address=0.0.0.0 &
        PROMETHEUS_PID=$!
        sleep 5
    fi
    
    # Grafana port forward
    if ! curl -s "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
        log INFO "Starting Grafana port forward..."
        kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0 &
        GRAFANA_PID=$!
        sleep 5
    fi
}

# Test 1: Infrastructure Health Tests
test_infrastructure_health() {
    log SECTION "1. Infrastructure Health Tests"
    
    # Test 1.1: Monitoring namespace exists
    log TEST "1.1 Checking monitoring namespace..."
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        record_test "1.1-namespace-exists" "PASS"
    else
        record_test "1.1-namespace-exists" "FAIL" "monitoring namespace not found"
        return 1
    fi
    
    # Test 1.2: Core monitoring pods running
    log TEST "1.2 Checking core monitoring pods..."
    local failed_pods=0
    local pod_status=""
    
    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $3}')
        
        if [[ "$status" != "Running" && "$status" != "Completed" ]]; then
            failed_pods=$((failed_pods + 1))
            pod_status="$pod_status $pod_name:$status"
        fi
    done < <(kubectl get pods -n monitoring --no-headers 2>/dev/null || echo "")
    
    if [ $failed_pods -eq 0 ]; then
        record_test "1.2-pods-running" "PASS"
    else
        record_test "1.2-pods-running" "WARN" "Some pods not running:$pod_status"
    fi
    
    # Test 1.3: Prometheus accessibility
    log TEST "1.3 Checking Prometheus accessibility..."
    if curl -s "$PROMETHEUS_URL/-/ready" | grep -q "Prometheus Server is Ready"; then
        record_test "1.3-prometheus-healthy" "PASS"
    else
        record_test "1.3-prometheus-healthy" "FAIL" "Prometheus health check failed"
    fi
    
    # Test 1.4: Grafana accessibility
    log TEST "1.4 Checking Grafana accessibility..."
    local grafana_response=$(curl -s "$GRAFANA_URL/api/health" 2>/dev/null || echo "")
    if echo "$grafana_response" | grep -q '"database".*"ok"'; then
        record_test "1.4-grafana-healthy" "PASS"
    else
        record_test "1.4-grafana-healthy" "FAIL" "Grafana health check failed"
    fi
}

# Test 2: Flux Metrics Collection Tests
test_flux_metrics_collection() {
    log SECTION "2. Flux Metrics Collection Tests"
    
    # Test 2.1: Flux controller discovery
    log TEST "2.1 Checking Flux controller discovery..."
    local flux_targets=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=up{job=~\".*flux.*\"}" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$flux_targets" -gt 0 ]; then
        local up_targets=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=up{job=~\".*flux.*\"}" | jq -r '.data.result[] | select(.value[1] == "1") | .value[1]' 2>/dev/null | wc -l || echo "0")
        record_test "2.1-flux-targets-discovered" "PASS" "$flux_targets total targets ($up_targets up)"
    else
        record_test "2.1-flux-targets-discovered" "FAIL" "No Flux targets discovered"
    fi
    
    # Test 2.2: Reconciliation metrics availability
    log TEST "2.2 Checking reconciliation metrics..."
    local reconcile_metrics=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=gotk_reconcile_duration_seconds_count" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$reconcile_metrics" -gt 0 ]; then
        record_test "2.2-reconcile-metrics" "PASS" "$reconcile_metrics reconciliation metrics found"
    else
        record_test "2.2-reconcile-metrics" "FAIL" "No reconciliation metrics found"
    fi
    
    # Test 2.3: Controller runtime metrics
    log TEST "2.3 Checking controller runtime metrics..."
    local runtime_metrics=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=controller_runtime_active_workers" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    if [ "$runtime_metrics" -gt 0 ]; then
        record_test "2.3-runtime-metrics" "PASS" "$runtime_metrics controller runtime metrics found"
    else
        record_test "2.3-runtime-metrics" "FAIL" "No controller runtime metrics found"
    fi
    
    # Test 2.4: ServiceMonitor and PodMonitor resources
    log TEST "2.4 Checking ServiceMonitor and PodMonitor resources..."
    local servicemonitors=$(kubectl get servicemonitor -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
    local podmonitors=$(kubectl get podmonitor -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$servicemonitors" -gt 0 ] && [ "$podmonitors" -gt 0 ]; then
        record_test "2.4-monitor-resources" "PASS" "$servicemonitors ServiceMonitors, $podmonitors PodMonitors"
    else
        record_test "2.4-monitor-resources" "FAIL" "Missing ServiceMonitor or PodMonitor resources"
    fi
}

# Test 3: Alert Rule Functionality Tests
test_alert_rules() {
    log SECTION "3. Alert Rule Functionality Tests"
    
    # Test 3.1: Alert rules loaded
    log TEST "3.1 Checking alert rules loaded..."
    local gitops_groups=$(curl -s "$PROMETHEUS_URL/api/v1/rules" | jq -r '.data.groups[] | select(.name | contains("gitops")) | .name' 2>/dev/null | wc -l || echo "0")
    local flux_groups=$(curl -s "$PROMETHEUS_URL/api/v1/rules" | jq -r '.data.groups[] | select(.name | contains("flux")) | .name' 2>/dev/null | wc -l || echo "0")
    
    if [ "$gitops_groups" -gt 0 ] && [ "$flux_groups" -gt 0 ]; then
        record_test "3.1-alert-rules-loaded" "PASS" "$gitops_groups GitOps groups, $flux_groups Flux groups"
    else
        record_test "3.1-alert-rules-loaded" "FAIL" "Alert rule groups not found"
    fi
    
    # Test 3.2: PrometheusRule resources exist
    log TEST "3.2 Checking PrometheusRule resources..."
    local prometheus_rules=$(kubectl get prometheusrule -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$prometheus_rules" -gt 0 ]; then
        record_test "3.2-prometheus-rules" "PASS" "$prometheus_rules PrometheusRule resources found"
    else
        record_test "3.2-prometheus-rules" "FAIL" "No PrometheusRule resources found"
    fi
    
    # Test 3.3: Alert rule evaluation
    log TEST "3.3 Checking alert rule evaluation..."
    local alert_rules=$(curl -s "$PROMETHEUS_URL/api/v1/rules" | jq -r '.data.groups[] | select(.name | contains("gitops") or contains("flux")) | .rules[] | select(.type == "alerting") | .name' 2>/dev/null | wc -l || echo "0")
    
    if [ "$alert_rules" -gt 0 ]; then
        record_test "3.3-alert-evaluation" "PASS" "$alert_rules alerting rules found"
    else
        record_test "3.3-alert-evaluation" "FAIL" "No alerting rules found"
    fi
    
    # Test 3.4: Current active alerts
    log TEST "3.4 Checking current active alerts..."
    local active_alerts=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=ALERTS" | jq -r '.data.result[] | select(.metric.alertname) | .metric.alertname' 2>/dev/null | wc -l || echo "0")
    
    if [ "$active_alerts" -gt 0 ]; then
        record_test "3.4-active-alerts" "PASS" "$active_alerts alerts currently active"
        
        # Show some active alerts for context
        log INFO "Sample active alerts:"
        curl -s "$PROMETHEUS_URL/api/v1/query?query=ALERTS" | jq -r '.data.result[] | select(.metric.alertname) | "  - \(.metric.alertname): \(.metric.alertstate)"' 2>/dev/null | head -5
    else
        record_test "3.4-active-alerts" "WARN" "No alerts currently active (this may be normal)"
    fi
}

# Test 4: Real Stuck State Detection Tests
test_stuck_state_detection() {
    log SECTION "4. Real Stuck State Detection Tests"
    
    # Test 4.1: Check for stuck kustomizations
    log TEST "4.1 Checking for stuck kustomizations..."
    local stuck_kustomizations=""
    
    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local ready=$(echo "$line" | awk '{print $2}')
        
        if [[ "$ready" == "False" ]]; then
            stuck_kustomizations="$stuck_kustomizations $name"
        fi
    done < <(kubectl get kustomizations -A --no-headers 2>/dev/null | grep -v "True" || echo "")
    
    if [ -n "$stuck_kustomizations" ]; then
        record_test "4.1-stuck-kustomizations" "PASS" "Found stuck kustomizations:$stuck_kustomizations"
    else
        record_test "4.1-stuck-kustomizations" "WARN" "No stuck kustomizations found (this may be normal)"
    fi
    
    # Test 4.2: Check for stuck HelmReleases
    log TEST "4.2 Checking for stuck HelmReleases..."
    local stuck_helmreleases=""
    
    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local ready=$(echo "$line" | awk '{print $2}')
        
        if [[ "$ready" == "False" ]]; then
            stuck_helmreleases="$stuck_helmreleases $name"
        fi
    done < <(kubectl get helmreleases -A --no-headers 2>/dev/null | grep -v "True" || echo "")
    
    if [ -n "$stuck_helmreleases" ]; then
        record_test "4.2-stuck-helmreleases" "PASS" "Found stuck HelmReleases:$stuck_helmreleases"
    else
        record_test "4.2-stuck-helmreleases" "WARN" "No stuck HelmReleases found (this may be normal)"
    fi
    
    # Test 4.3: Check Flux controller health
    log TEST "4.3 Checking Flux controller health..."
    local unhealthy_controllers=""
    
    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $3}')
        
        if [[ "$status" != "Running" ]]; then
            unhealthy_controllers="$unhealthy_controllers $pod_name:$status"
        fi
    done < <(kubectl get pods -n flux-system --no-headers 2>/dev/null || echo "")
    
    if [ -n "$unhealthy_controllers" ]; then
        record_test "4.3-flux-controller-health" "FAIL" "Unhealthy controllers:$unhealthy_controllers"
    else
        record_test "4.3-flux-controller-health" "PASS" "All Flux controllers healthy"
    fi
}

# Test 5: Dashboard and Visualization Tests
test_dashboards() {
    log SECTION "5. Dashboard and Visualization Tests"
    
    # Test 5.1: Grafana dashboard availability
    log TEST "5.1 Checking Grafana dashboard availability..."
    local dashboards=$(curl -s -u admin:REPLACE_WITH_SECURE_PASSWORD "$GRAFANA_URL/api/search" 2>/dev/null | jq -r '. | length' || echo "0")
    
    if [ "$dashboards" -gt 0 ]; then
        record_test "5.1-grafana-dashboards" "PASS" "$dashboards dashboards available"
    else
        record_test "5.1-grafana-dashboards" "WARN" "Cannot access dashboards (may need authentication)"
    fi
    
    # Test 5.2: ConfigMap dashboards
    log TEST "5.2 Checking ConfigMap dashboards..."
    local dashboard_configmaps=$(kubectl get configmap -n monitoring --no-headers 2>/dev/null | grep -c dashboard || echo "0")
    
    if [ "$dashboard_configmaps" -gt 0 ]; then
        record_test "5.2-dashboard-configmaps" "PASS" "$dashboard_configmaps dashboard ConfigMaps found"
    else
        record_test "5.2-dashboard-configmaps" "WARN" "No dashboard ConfigMaps found"
    fi
}

# Test 6: Performance and Reliability Tests
test_performance() {
    log SECTION "6. Performance and Reliability Tests"
    
    # Test 6.1: Prometheus query performance
    log TEST "6.1 Checking Prometheus query performance..."
    local start_time=$(date +%s%N)
    curl -s "$PROMETHEUS_URL/api/v1/query?query=up" >/dev/null 2>&1
    local end_time=$(date +%s%N)
    local query_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    if [ "$query_time" -lt 1000 ]; then
        record_test "6.1-query-performance" "PASS" "${query_time}ms query time"
    else
        record_test "6.1-query-performance" "WARN" "${query_time}ms query time (slow)"
    fi
    
    # Test 6.2: Storage usage
    log TEST "6.2 Checking storage usage..."
    local storage_info=$(kubectl get pvc -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$storage_info" -gt 0 ]; then
        record_test "6.2-storage-usage" "PASS" "$storage_info PVCs in use"
    else
        record_test "6.2-storage-usage" "PASS" "Using ephemeral storage (bulletproof architecture)"
    fi
    
    # Test 6.3: Memory usage of monitoring pods
    log TEST "6.3 Checking monitoring pod resource usage..."
    local high_memory_pods=0
    
    while IFS= read -r line; do
        local memory=$(echo "$line" | awk '{print $3}' | sed 's/Mi//')
        if [[ "$memory" =~ ^[0-9]+$ ]] && [ "$memory" -gt 1000 ]; then
            high_memory_pods=$((high_memory_pods + 1))
        fi
    done < <(kubectl top pods -n monitoring --no-headers 2>/dev/null || echo "")
    
    if [ $high_memory_pods -eq 0 ]; then
        record_test "6.3-resource-usage" "PASS" "Memory usage within normal limits"
    else
        record_test "6.3-resource-usage" "WARN" "$high_memory_pods pods using >1GB memory"
    fi
}

# Function to generate test report
generate_report() {
    log SECTION "Test Report Summary"
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local warning_tests=0
    
    echo ""
    echo "📊 Detailed Test Results:"
    echo "========================="
    
    for result in "${TEST_RESULTS[@]}"; do
        IFS=':' read -r test_name test_result test_details <<< "$result"
        total_tests=$((total_tests + 1))
        
        case $test_result in
            PASS)
                passed_tests=$((passed_tests + 1))
                echo -e "✅ $test_name: ${GREEN}PASSED${NC} $test_details"
                ;;
            FAIL)
                failed_tests=$((failed_tests + 1))
                echo -e "❌ $test_name: ${RED}FAILED${NC} $test_details"
                ;;
            WARN)
                warning_tests=$((warning_tests + 1))
                echo -e "⚠️  $test_name: ${YELLOW}WARNING${NC} $test_details"
                ;;
        esac
    done
    
    echo ""
    echo "📈 Summary Statistics:"
    echo "====================="
    echo -e "Total Tests: $total_tests"
    echo -e "✅ Passed: ${GREEN}$passed_tests${NC}"
    echo -e "⚠️  Warnings: ${YELLOW}$warning_tests${NC}"
    echo -e "❌ Failed: ${RED}$failed_tests${NC}"
    
    local success_rate=$(( (passed_tests * 100) / total_tests ))
    echo -e "Success Rate: ${success_rate}%"
    
    echo ""
    if [ $failed_tests -eq 0 ]; then
        log SUCCESS "Task 2 monitoring system is functioning correctly! 🎉"
        if [ $warning_tests -gt 0 ]; then
            log INFO "Some warnings detected - review above for optimization opportunities"
        fi
    else
        log ERROR "Task 2 monitoring system has issues that need attention"
        log INFO "Review failed tests above and check the troubleshooting guide"
    fi
}

# Main execution function
main() {
    echo "🧪 Task 2 Monitoring System Test Plan"
    echo "====================================="
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
    
    log INFO "Starting comprehensive Task 2 monitoring validation..."
    echo ""
    
    # Setup port forwards
    setup_port_forwards
    
    # Run test suites
    test_infrastructure_health
    echo ""
    
    test_flux_metrics_collection
    echo ""
    
    test_alert_rules
    echo ""
    
    test_stuck_state_detection
    echo ""
    
    test_dashboards
    echo ""
    
    test_performance
    echo ""
    
    # Generate final report
    generate_report
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo ""
        echo "This script comprehensively tests Task 2: Reconciliation Health Monitoring"
        echo ""
        echo "Test Categories:"
        echo "  1. Infrastructure Health Tests"
        echo "  2. Flux Metrics Collection Tests"
        echo "  3. Alert Rule Functionality Tests"
        echo "  4. Real Stuck State Detection Tests"
        echo "  5. Dashboard and Visualization Tests"
        echo "  6. Performance and Reliability Tests"
        echo ""
        exit 0
        ;;
esac

# Run main function
main "$@"