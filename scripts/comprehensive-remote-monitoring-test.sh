#!/bin/bash
# Comprehensive Remote Monitoring Test Suite
#
# This script orchestrates all remote monitoring access validation tests,
# combining health checks, connectivity tests, and functionality validation.
#
# Usage: ./scripts/comprehensive-remote-monitoring-test.sh [--full] [--report]
#   --full: Run all tests including performance and dashboard tests
#   --report: Generate comprehensive test report

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/comprehensive-monitoring-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/comprehensive-monitoring-test-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FULL_TEST=false
GENERATE_REPORT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_TEST=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--full] [--report]"
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

# Initialize report
init_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        mkdir -p "$REPORT_DIR"
        cat > "$REPORT_FILE" << EOF
# Comprehensive Remote Monitoring Test Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Test Suite**: Comprehensive Remote Monitoring Validation
**Full Test Mode**: $FULL_TEST

## Executive Summary

This report contains the results of comprehensive remote monitoring access validation,
including health checks, connectivity tests, and functionality validation.

## Test Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}

# Run monitoring health check with remote access
run_health_check() {
    log "Running monitoring system health check with remote access validation..."
    
    add_to_report "### Monitoring System Health Check"
    add_to_report ""
    
    local health_args="--remote"
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        health_args="$health_args --report"
    fi
    
    if "$SCRIPT_DIR/monitoring-health-check.sh" $health_args; then
        success "Monitoring system health check passed"
        add_to_report "✅ **Health Check**: PASSED"
        
        # Extract key metrics from health check
        local tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
        add_to_report "- **Tailscale IP**: $tailscale_ip"
        add_to_report "- **Remote Access**: Validated"
        
        return 0
    else
        error "Monitoring system health check failed"
        add_to_report "❌ **Health Check**: FAILED"
        return 1
    fi
    
    add_to_report ""
}

# Run remote access validation
run_remote_access_validation() {
    log "Running remote access validation..."
    
    add_to_report "### Remote Access Validation"
    add_to_report ""
    
    if "$SCRIPT_DIR/validate-remote-monitoring-access.sh" --test-connectivity; then
        success "Remote access validation passed"
        add_to_report "✅ **Remote Access Validation**: PASSED"
        add_to_report "- **Port Forwarding**: Functional"
        add_to_report "- **Service Discovery**: Working"
        add_to_report "- **HTTP Connectivity**: Verified"
        
        return 0
    else
        error "Remote access validation failed"
        add_to_report "❌ **Remote Access Validation**: FAILED"
        return 1
    fi
    
    add_to_report ""
}

# Run connectivity tests
run_connectivity_tests() {
    log "Running comprehensive connectivity tests..."
    
    add_to_report "### Connectivity Tests"
    add_to_report ""
    
    local connectivity_args=""
    if [[ "$FULL_TEST" == "true" ]]; then
        connectivity_args="--full-test --dashboard-test"
    fi
    
    if "$SCRIPT_DIR/test-remote-monitoring-connectivity.sh" $connectivity_args; then
        success "Connectivity tests passed"
        add_to_report "✅ **Connectivity Tests**: PASSED"
        add_to_report "- **Prometheus API**: Accessible"
        add_to_report "- **Grafana Interface**: Accessible"
        
        if [[ "$FULL_TEST" == "true" ]]; then
            add_to_report "- **Performance Tests**: Completed"
            add_to_report "- **Dashboard Tests**: Completed"
        fi
        
        return 0
    else
        error "Connectivity tests failed"
        add_to_report "❌ **Connectivity Tests**: FAILED"
        return 1
    fi
    
    add_to_report ""
}

# Run service reference validation
run_service_reference_validation() {
    log "Running service reference validation..."
    
    add_to_report "### Service Reference Validation"
    add_to_report ""
    
    local service_args=""
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        service_args="--report"
    fi
    
    if "$SCRIPT_DIR/validate-monitoring-service-references.sh" $service_args; then
        success "Service reference validation passed"
        add_to_report "✅ **Service Reference Validation**: PASSED"
        add_to_report "- **Documentation Consistency**: Verified"
        add_to_report "- **Service Discovery**: Dynamic"
        add_to_report "- **Reference Accuracy**: Confirmed"
        
        return 0
    else
        error "Service reference validation failed"
        add_to_report "❌ **Service Reference Validation**: FAILED"
        return 1
    fi
    
    add_to_report ""
}

# Generate access summary
generate_access_summary() {
    log "Generating remote access summary..."
    
    add_to_report "### Remote Access Summary"
    add_to_report ""
    
    # Get current service information
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "not-found")
    local grafana_service=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    local tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
    
    add_to_report "#### Current Configuration"
    add_to_report ""
    add_to_report "- **Prometheus Service**: $prometheus_service"
    add_to_report "- **Grafana Service**: $grafana_service"
    add_to_report "- **Tailscale IP**: $tailscale_ip"
    add_to_report ""
    
    add_to_report "#### Access Commands"
    add_to_report ""
    add_to_report "\`\`\`bash"
    add_to_report "# Start port forwards"
    add_to_report "kubectl port-forward -n monitoring service/$prometheus_service 9090:9090 --address=0.0.0.0 &"
    add_to_report "kubectl port-forward -n monitoring service/$grafana_service 3000:80 --address=0.0.0.0 &"
    add_to_report ""
    add_to_report "# Access URLs"
    add_to_report "echo \"Prometheus: http://$tailscale_ip:9090\""
    add_to_report "echo \"Grafana: http://$tailscale_ip:3000\""
    add_to_report ""
    add_to_report "# Clean up when done"
    add_to_report "pkill -f 'kubectl port-forward'"
    add_to_report "\`\`\`"
    add_to_report ""
    
    # Check if access commands file exists
    if [[ -f /tmp/monitoring-remote-access-commands.sh ]]; then
        add_to_report "#### Generated Access Script"
        add_to_report ""
        add_to_report "Ready-to-use access commands available at: \`/tmp/monitoring-remote-access-commands.sh\`"
        add_to_report ""
        add_to_report "\`\`\`bash"
        add_to_report "# Execute generated commands"
        add_to_report "source /tmp/monitoring-remote-access-commands.sh"
        add_to_report "\`\`\`"
        add_to_report ""
    fi
}

# Generate troubleshooting guide
generate_troubleshooting_guide() {
    add_to_report "### Troubleshooting Guide"
    add_to_report ""
    add_to_report "If remote monitoring access fails, check the following:"
    add_to_report ""
    add_to_report "#### 1. Tailscale Connectivity"
    add_to_report "\`\`\`bash"
    add_to_report "tailscale status"
    add_to_report "tailscale ip -4"
    add_to_report "\`\`\`"
    add_to_report ""
    add_to_report "#### 2. Kubernetes Cluster Access"
    add_to_report "\`\`\`bash"
    add_to_report "kubectl cluster-info"
    add_to_report "kubectl get nodes"
    add_to_report "\`\`\`"
    add_to_report ""
    add_to_report "#### 3. Monitoring Services"
    add_to_report "\`\`\`bash"
    add_to_report "kubectl get pods -n monitoring"
    add_to_report "kubectl get services -n monitoring"
    add_to_report "\`\`\`"
    add_to_report ""
    add_to_report "#### 4. Port Forward Issues"
    add_to_report "\`\`\`bash"
    add_to_report "# Check existing port forwards"
    add_to_report "ps aux | grep 'kubectl port-forward'"
    add_to_report ""
    add_to_report "# Clean up stuck port forwards"
    add_to_report "pkill -f 'kubectl port-forward'"
    add_to_report ""
    add_to_report "# Check port availability"
    add_to_report "lsof -i :9090"
    add_to_report "lsof -i :3000"
    add_to_report "\`\`\`"
    add_to_report ""
    add_to_report "#### 5. Network Connectivity"
    add_to_report "\`\`\`bash"
    add_to_report "# Test local connectivity"
    add_to_report "curl -s http://localhost:9090/api/v1/query?query=up"
    add_to_report "curl -s http://localhost:3000/api/health"
    add_to_report ""
    add_to_report "# Test remote connectivity (replace with your Tailscale IP)"
    add_to_report "curl -s http://100.x.x.x:9090/api/v1/query?query=up"
    add_to_report "curl -s http://100.x.x.x:3000/api/health"
    add_to_report "\`\`\`"
    add_to_report ""
}

# Main test orchestration function
run_comprehensive_tests() {
    log "Starting comprehensive remote monitoring test suite..."
    
    init_report
    add_to_report "## Test Execution Started"
    add_to_report "**Timestamp**: $(date)"
    add_to_report ""
    
    local total_issues=0
    
    # Run all test phases
    run_health_check
    total_issues=$((total_issues + $?))
    
    run_remote_access_validation
    total_issues=$((total_issues + $?))
    
    run_connectivity_tests
    total_issues=$((total_issues + $?))
    
    run_service_reference_validation
    total_issues=$((total_issues + $?))
    
    # Generate summary and troubleshooting
    generate_access_summary
    generate_troubleshooting_guide
    
    # Final summary
    add_to_report "## Test Summary"
    add_to_report ""
    add_to_report "**Total Issues Found**: $total_issues"
    add_to_report "**Test Completed**: $(date)"
    add_to_report ""
    
    if [[ $total_issues -eq 0 ]]; then
        success "All comprehensive remote monitoring tests passed!"
        add_to_report "**Overall Status**: ✅ ALL TESTS PASSED"
        add_to_report ""
        add_to_report "Remote monitoring access is fully functional and ready for use."
    elif [[ $total_issues -le 2 ]]; then
        warn "Comprehensive remote monitoring tests completed with $total_issues minor issues"
        add_to_report "**Overall Status**: ⚠️ PASSED WITH WARNINGS"
        add_to_report ""
        add_to_report "Most functionality is working, but some features may be limited."
    else
        error "Comprehensive remote monitoring tests found $total_issues issues"
        add_to_report "**Overall Status**: ❌ ATTENTION REQUIRED"
        add_to_report ""
        add_to_report "Remote monitoring access may not be fully functional. Please review the issues above."
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by comprehensive-remote-monitoring-test.sh*"
        log "Comprehensive test report generated: $REPORT_FILE"
    fi
    
    return $total_issues
}

# Dependency checks
check_dependencies() {
    local missing_deps=0
    
    # Check for required scripts
    local required_scripts=(
        "monitoring-health-check.sh"
        "validate-remote-monitoring-access.sh"
        "test-remote-monitoring-connectivity.sh"
        "validate-monitoring-service-references.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            error "Required script not found: $script"
            missing_deps=$((missing_deps + 1))
        elif [[ ! -x "$SCRIPT_DIR/$script" ]]; then
            error "Script not executable: $script"
            missing_deps=$((missing_deps + 1))
        fi
    done
    
    # Check for required commands
    local required_commands=("kubectl" "tailscale" "curl" "jq")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "$cmd not found - please install $cmd"
            missing_deps=$((missing_deps + 1))
        fi
    done
    
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
    log "Comprehensive Remote Monitoring Test Suite v1.0"
    log "================================================"
    
    check_dependencies
    
    # Run the comprehensive tests
    run_comprehensive_tests
    exit_code=$?
    
    log "================================================"
    if [[ $exit_code -eq 0 ]]; then
        success "Comprehensive remote monitoring test suite completed successfully!"
        success "Remote monitoring access is fully validated and functional!"
    else
        error "Comprehensive remote monitoring test suite found $exit_code issue(s)"
        error "Please review the test results and address any issues"
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo
        log "Comprehensive test report available at: $REPORT_FILE"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"