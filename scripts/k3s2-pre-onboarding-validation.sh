#!/bin/bash
# k3s2 Pre-Onboarding Validation Script
#
# This script performs comprehensive validation of cluster prerequisites
# before attempting to onboard the k3s2 node to the existing k3s cluster.
#
# Requirements: 7.1, 7.2 from k3s1-node-onboarding spec
#
# Usage: ./scripts/k3s2-pre-onboarding-validation.sh [--fix] [--report]
#   --fix: Attempt to fix identified issues
#   --report: Generate detailed validation report

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/k3s2-validation-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/k3s2-pre-onboarding-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FIX_ISSUES=false
GENERATE_REPORT=false

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_ISSUES=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--fix] [--report]"
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
    TESTS_WARNING=$((TESTS_WARNING + 1))
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

# Initialize report
init_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        mkdir -p "$REPORT_DIR"
        cat > "$REPORT_FILE" << EOF
# k3s2 Pre-Onboarding Validation Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Validation Script**: $0
**Fix Mode**: $FIX_ISSUES

## Executive Summary

This report contains the results of pre-onboarding validation for k3s2 node addition to the k3s cluster.

## Validation Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}

# Test execution wrapper
run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_name="$1"
    local test_function="$2"
    
    log "Running test: $test_name"
    add_to_report "### $test_name"
    add_to_report ""
    
    local test_result=0
    $test_function || test_result=$?
    
    if [[ $test_result -eq 0 ]]; then
        success "$test_name - PASSED"
        add_to_report "✅ **PASSED**: $test_name"
        return 0
    else
        error "$test_name - FAILED"
        add_to_report "❌ **FAILED**: $test_name"
        return 1
    fi
    
    add_to_report ""
}

# Source individual validation modules
source_validation_modules() {
    local modules=(
        "cluster-readiness-validation.sh"
        "network-connectivity-verification.sh" 
        "storage-health-check.sh"
        "monitoring-validation.sh"
    )
    
    for module in "${modules[@]}"; do
        local module_path="$SCRIPT_DIR/$module"
        if [[ -f "$module_path" ]]; then
            log "Loading validation module: $module"
            # shellcheck source=/dev/null
            if source "$module_path"; then
                log "Successfully loaded: $module"
            else
                error "Failed to load validation module: $module_path"
                exit 1
            fi
        else
            error "Validation module not found: $module_path"
            exit 1
        fi
    done
    
    log "All validation modules loaded successfully"
}

# Main validation function
run_pre_onboarding_validation() {
    log "Starting k3s2 pre-onboarding validation..."
    
    init_report
    add_to_report "## Pre-Onboarding Validation Started"
    add_to_report "**Timestamp**: $(date)"
    add_to_report ""
    
    # Load validation modules
    source_validation_modules
    
    # Run validation tests
    log "=== CLUSTER READINESS VALIDATION ==="
    add_to_report "## Cluster Readiness Validation"
    add_to_report ""
    
    run_test "k3s1 Control Plane Health" "validate_control_plane_health" || true
    run_test "Flux GitOps System Health" "validate_flux_system_health" || true
    run_test "Core Infrastructure Health" "validate_core_infrastructure_health" || true
    run_test "Resource Capacity Check" "validate_resource_capacity" || true
    
    echo ""
    log "=== NETWORK CONNECTIVITY VERIFICATION ==="
    add_to_report "## Network Connectivity Verification"
    add_to_report ""
    
    run_test "Cluster Network Configuration" "verify_cluster_network_config" || true
    run_test "NodePort Service Accessibility" "verify_nodeport_accessibility" || true
    run_test "Ingress Controller Health" "verify_ingress_controller_health" || true
    run_test "DNS Resolution" "verify_dns_resolution" || true
    run_test "External Connectivity" "verify_external_connectivity" || true
    
    echo ""
    log "=== STORAGE SYSTEM HEALTH CHECK ==="
    add_to_report "## Storage System Health Check"
    add_to_report ""
    
    run_test "Longhorn System Health" "check_longhorn_system_health" || true
    run_test "Storage Prerequisites" "check_storage_prerequisites" || true
    run_test "Disk Discovery System" "check_disk_discovery_system" || true
    run_test "Storage Capacity Planning" "check_storage_capacity_planning" || true
    
    echo ""
    log "=== MONITORING SYSTEM VALIDATION ==="
    add_to_report "## Monitoring System Validation"
    add_to_report ""
    
    run_test "Prometheus System Health" "validate_prometheus_health" || true
    run_test "Grafana System Health" "validate_grafana_health" || true
    run_test "ServiceMonitor Configuration" "validate_servicemonitor_config" || true
    run_test "Node Exporter Readiness" "validate_node_exporter_readiness" || true
    
    # Generate summary
    generate_validation_summary
}

# Generate validation summary
generate_validation_summary() {
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNING))
    
    add_to_report "## Validation Summary"
    add_to_report ""
    add_to_report "**Total Tests**: $total_tests"
    add_to_report "**Passed**: $TESTS_PASSED"
    add_to_report "**Failed**: $TESTS_FAILED"
    add_to_report "**Warnings**: $TESTS_WARNING"
    add_to_report ""
    
    echo ""
    log "=== VALIDATION SUMMARY ==="
    log "Total tests: $total_tests"
    success "Passed: $TESTS_PASSED"
    error "Failed: $TESTS_FAILED"
    warn "Warnings: $TESTS_WARNING"
    
    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        if [[ $TESTS_WARNING -eq 0 ]]; then
            success "🎉 EXCELLENT: Cluster is fully ready for k3s2 onboarding"
            add_to_report "**Overall Status**: ✅ READY FOR ONBOARDING"
            echo ""
            log "✅ All prerequisites met"
            log "✅ All systems healthy"
            log "✅ No blocking issues found"
            log ""
            log "🚀 Proceed with k3s2 node onboarding!"
        else
            warn "⚠️  GOOD: Cluster is ready with minor warnings"
            add_to_report "**Overall Status**: ⚠️ READY WITH WARNINGS"
            echo ""
            log "✅ All critical prerequisites met"
            log "⚠️  Some non-critical issues detected"
            log "🚀 Safe to proceed with k3s2 onboarding"
        fi
    else
        error "❌ ATTENTION NEEDED: Cluster has blocking issues"
        add_to_report "**Overall Status**: ❌ NOT READY - ISSUES FOUND"
        echo ""
        log "❌ Critical issues must be resolved before onboarding"
        log "🔧 Review failed tests and fix issues"
        log "🛑 DO NOT proceed with k3s2 onboarding until issues are resolved"
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by k3s2-pre-onboarding-validation.sh*"
        log "Validation report generated: $REPORT_FILE"
    fi
}

# Dependency checks
check_dependencies() {
    local missing_deps=0
    
    log "Checking dependencies..."
    
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v flux >/dev/null 2>&1; then
        error "flux CLI not found - please install flux (brew install fluxcd/tap/flux)"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        error "jq not found - please install jq (brew install jq)"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        error "curl not found - please install curl"
        missing_deps=$((missing_deps + 1))
    fi
    
    if [[ $missing_deps -gt 0 ]]; then
        error "Missing $missing_deps required dependencies"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        error "Please check your kubeconfig and cluster connectivity"
        exit 1
    fi
    
    success "All dependencies available"
}

# Main execution
main() {
    log "k3s2 Pre-Onboarding Validation v1.0"
    log "===================================="
    
    check_dependencies
    
    # Verify we're not trying to onboard k3s2 if it already exists
    log "Checking if k3s2 node already exists..."
    if kubectl get node k3s2 >/dev/null 2>&1; then
        warn "k3s2 node already exists in cluster"
        log "Node status:"
        kubectl get node k3s2
        echo ""
        log "This validation is for pre-onboarding checks."
        log "If you need to validate an existing k3s2 node, use:"
        log "  ./tests/validation/test-k3s2-node-onboarding.sh"
        exit 1
    else
        log "k3s2 node not found - proceeding with pre-onboarding validation"
    fi
    
    # Run the validation
    run_pre_onboarding_validation
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo ""
        log "Pre-onboarding validation report available at: $REPORT_FILE"
    fi
    
    log "===================================="
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        success "Pre-onboarding validation completed successfully!"
        exit 0
    else
        error "Pre-onboarding validation found $TESTS_FAILED blocking issue(s)"
        exit 1
    fi
}

# Run main function
main "$@"