#!/bin/bash
# Monitoring System Health Check Script
#
# This script performs comprehensive health validation of the k3s monitoring system
# including Prometheus, Grafana, ServiceMonitors, and remote access capabilities.
#
# Usage: ./scripts/monitoring-health-check.sh [--remote] [--fix] [--report]
#   --remote: Test remote access via Tailscale
#   --fix: Attempt to fix identified issues
#   --report: Generate detailed health report

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/monitoring-health-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/monitoring-health-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
TEST_REMOTE=false
FIX_ISSUES=false
GENERATE_REPORT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote)
            TEST_REMOTE=true
            shift
            ;;
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
            echo "Usage: $0 [--remote] [--fix] [--report]"
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
# Monitoring System Health Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Health Check Script**: $0
**Remote Testing**: $TEST_REMOTE

## Executive Summary

This report contains the results of automated health validation for the k3s monitoring system.

## Health Check Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}

# Health check functions

check_monitoring_namespace() {
    log "Checking monitoring namespace..."
    local issues=0
    
    add_to_report "### Monitoring Namespace Health"
    add_to_report ""
    
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        success "Monitoring namespace exists"
        add_to_report "✅ Monitoring namespace exists"
        
        # Check namespace status
        local phase=$(kubectl get namespace monitoring -o jsonpath='{.status.phase}')
        if [[ "$phase" == "Active" ]]; then
            success "Monitoring namespace is active"
            add_to_report "✅ Monitoring namespace is active"
        else
            error "Monitoring namespace is in phase: $phase"
            add_to_report "❌ Monitoring namespace phase: $phase"
            issues=$((issues + 1))
        fi
    else
        error "Monitoring namespace not found"
        add_to_report "❌ Monitoring namespace not found"
        issues=$((issues + 1))
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            log "Creating monitoring namespace..."
            kubectl create namespace monitoring
            success "Monitoring namespace created"
            add_to_report "**Fix Applied**: Created monitoring namespace"
        fi
    fi
    
    add_to_report ""
    return $issues
}

check_prometheus_health() {
    log "Checking Prometheus health..."
    local issues=0
    
    add_to_report "### Prometheus Health"
    add_to_report ""
    
    # Check Prometheus pods
    local prometheus_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
    
    if [[ $prometheus_pods -gt 0 ]]; then
        success "Found $prometheus_pods Prometheus pod(s)"
        add_to_report "✅ Prometheus pods: $prometheus_pods"
        
        # Check pod status
        local running_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep Running | wc -l)
        
        if [[ $running_pods -eq $prometheus_pods ]]; then
            success "All Prometheus pods are running"
            add_to_report "✅ All Prometheus pods running"
        else
            error "Only $running_pods/$prometheus_pods Prometheus pods are running"
            add_to_report "❌ Prometheus pods not all running: $running_pods/$prometheus_pods"
            issues=$((issues + 1))
            
            # Show pod details
            kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
        fi
    else
        error "No Prometheus pods found"
        add_to_report "❌ No Prometheus pods found"
        issues=$((issues + 1))
    fi
    
    # Check Prometheus service (look for the main Prometheus service)
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    
    if [[ -n "$prometheus_service" ]]; then
        success "Prometheus service exists: $prometheus_service"
        add_to_report "✅ Prometheus service exists"
        
        # Get service details
        local service_port=$(kubectl get service -n monitoring "$prometheus_service" -o jsonpath='{.spec.ports[0].port}')
        
        log "Prometheus service: $prometheus_service:$service_port"
        add_to_report "**Service**: $prometheus_service:$service_port"
    else
        error "Prometheus service not found"
        add_to_report "❌ Prometheus service not found"
        issues=$((issues + 1))
    fi
    
    add_to_report ""
    return $issues
}

check_grafana_health() {
    log "Checking Grafana health..."
    local issues=0
    
    add_to_report "### Grafana Health"
    add_to_report ""
    
    # Check Grafana pods
    local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | wc -l)
    
    if [[ $grafana_pods -gt 0 ]]; then
        success "Found $grafana_pods Grafana pod(s)"
        add_to_report "✅ Grafana pods: $grafana_pods"
        
        # Check pod status
        local running_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep Running | wc -l)
        
        if [[ $running_pods -eq $grafana_pods ]]; then
            success "All Grafana pods are running"
            add_to_report "✅ All Grafana pods running"
        else
            error "Only $running_pods/$grafana_pods Grafana pods are running"
            add_to_report "❌ Grafana pods not all running: $running_pods/$grafana_pods"
            issues=$((issues + 1))
        fi
    else
        error "No Grafana pods found"
        add_to_report "❌ No Grafana pods found"
        issues=$((issues + 1))
    fi
    
    # Check Grafana service
    if kubectl get service -n monitoring -l app.kubernetes.io/name=grafana >/dev/null 2>&1; then
        success "Grafana service exists"
        add_to_report "✅ Grafana service exists"
        
        # Get service details
        local service_name=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
        local service_port=$(kubectl get service -n monitoring "$service_name" -o jsonpath='{.spec.ports[0].port}')
        
        log "Grafana service: $service_name:$service_port"
        add_to_report "**Service**: $service_name:$service_port"
    else
        error "Grafana service not found"
        add_to_report "❌ Grafana service not found"
        issues=$((issues + 1))
    fi
    
    add_to_report ""
    return $issues
}

check_servicemonitors() {
    log "Checking ServiceMonitors and PodMonitors..."
    local issues=0
    
    add_to_report "### ServiceMonitor and PodMonitor Health"
    add_to_report ""
    
    # Check ServiceMonitors
    local servicemonitors=$(kubectl get servicemonitors -n monitoring --no-headers 2>/dev/null | wc -l)
    
    if [[ $servicemonitors -gt 0 ]]; then
        success "Found $servicemonitors ServiceMonitor(s)"
        add_to_report "✅ ServiceMonitors: $servicemonitors"
        
        # List key ServiceMonitors
        log "Key ServiceMonitors:"
        kubectl get servicemonitors -n monitoring --no-headers | while read -r sm _; do
            log "  - $sm"
            add_to_report "  - $sm"
        done
    else
        warn "No ServiceMonitors found"
        add_to_report "⚠️ No ServiceMonitors found"
    fi
    
    # Check PodMonitors
    local podmonitors=$(kubectl get podmonitors -n monitoring --no-headers 2>/dev/null | wc -l)
    
    if [[ $podmonitors -gt 0 ]]; then
        success "Found $podmonitors PodMonitor(s)"
        add_to_report "✅ PodMonitors: $podmonitors"
        
        # List PodMonitors
        log "PodMonitors:"
        kubectl get podmonitors -n monitoring --no-headers | while read -r pm _; do
            log "  - $pm"
            add_to_report "  - $pm"
        done
    else
        warn "No PodMonitors found"
        add_to_report "⚠️ No PodMonitors found"
    fi
    
    # Check Flux-specific monitoring
    if kubectl get podmonitors -n monitoring flux-controllers-pods >/dev/null 2>&1; then
        success "Flux controllers PodMonitor exists"
        add_to_report "✅ Flux controllers monitoring configured"
    else
        warn "Flux controllers PodMonitor not found"
        add_to_report "⚠️ Flux controllers monitoring not configured"
    fi
    
    add_to_report ""
    return $issues
}

check_metrics_collection() {
    log "Checking metrics collection..."
    local issues=0
    
    add_to_report "### Metrics Collection Health"
    add_to_report ""
    
    # Try to access Prometheus metrics endpoint
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    
    if [[ -n "$prometheus_service" ]]; then
        log "Testing Prometheus metrics endpoint..."
        
        # Port forward to test metrics
        local port_forward_pid=""
        kubectl port-forward -n monitoring "service/$prometheus_service" 9090:9090 >/dev/null 2>&1 &
        port_forward_pid=$!
        
        # Wait for port forward to establish
        sleep 3
        
        # Test metrics endpoint
        if curl -s http://localhost:9090/api/v1/query?query=up >/dev/null 2>&1; then
            success "Prometheus metrics endpoint accessible"
            add_to_report "✅ Prometheus metrics endpoint working"
            
            # Test specific metrics
            local up_targets=$(curl -s http://localhost:9090/api/v1/query?query=up | jq -r '.data.result | length' 2>/dev/null || echo "0")
            log "Found $up_targets active metric targets"
            add_to_report "**Active Targets**: $up_targets"
            
        else
            error "Cannot access Prometheus metrics endpoint"
            add_to_report "❌ Prometheus metrics endpoint not accessible"
            issues=$((issues + 1))
        fi
        
        # Clean up port forward
        if [[ -n "$port_forward_pid" ]]; then
            kill $port_forward_pid 2>/dev/null || true
        fi
    else
        error "Cannot find Prometheus service for metrics testing"
        add_to_report "❌ Cannot test metrics - no Prometheus service"
        issues=$((issues + 1))
    fi
    
    add_to_report ""
    return $issues
}

check_remote_access() {
    if [[ "$TEST_REMOTE" != "true" ]]; then
        log "Skipping remote access tests (use --remote to enable)"
        return 0
    fi
    
    log "Checking remote access capabilities..."
    local issues=0
    
    add_to_report "### Remote Access Health"
    add_to_report ""
    
    # Check Tailscale connectivity
    if command -v tailscale >/dev/null 2>&1; then
        if tailscale status >/dev/null 2>&1; then
            success "Tailscale is connected"
            add_to_report "✅ Tailscale connected"
            
            # Get Tailscale status
            local tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
            log "Tailscale IP: $tailscale_ip"
            add_to_report "**Tailscale IP**: $tailscale_ip"
            
        else
            error "Tailscale is not connected"
            add_to_report "❌ Tailscale not connected"
            issues=$((issues + 1))
        fi
    else
        warn "Tailscale CLI not available for remote testing"
        add_to_report "⚠️ Tailscale CLI not available"
    fi
    
    # Test remote port forwarding capability
    log "Testing remote port forwarding setup..."
    
    # Check if we can establish port forwards
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    local grafana_service=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$prometheus_service" && -n "$grafana_service" ]]; then
        success "Key services available for remote access:"
        success "  - Prometheus: kubectl port-forward -n monitoring service/$prometheus_service 9090:9090 --address=0.0.0.0"
        success "  - Grafana: kubectl port-forward -n monitoring service/$grafana_service 3000:80 --address=0.0.0.0"
        
        add_to_report "✅ Remote access services available:"
        add_to_report "  - **Prometheus**: \`kubectl port-forward -n monitoring service/$prometheus_service 9090:9090 --address=0.0.0.0\`"
        add_to_report "  - **Grafana**: \`kubectl port-forward -n monitoring service/$grafana_service 3000:80 --address=0.0.0.0\`"
    else
        error "Cannot find services for remote access testing"
        add_to_report "❌ Services not available for remote access"
        issues=$((issues + 1))
    fi
    
    add_to_report ""
    return $issues
}

check_storage_health() {
    log "Checking monitoring storage health..."
    local issues=0
    
    add_to_report "### Storage Health"
    add_to_report ""
    
    # Check for PVCs (should be minimal due to ephemeral design)
    local pvcs=$(kubectl get pvc -n monitoring --no-headers 2>/dev/null | wc -l)
    
    if [[ $pvcs -eq 0 ]]; then
        success "No PVCs found - using ephemeral storage as designed"
        add_to_report "✅ Ephemeral storage design - no PVCs (bulletproof architecture)"
    else
        log "Found $pvcs PVC(s) in monitoring namespace:"
        kubectl get pvc -n monitoring --no-headers | while read -r pvc status _; do
            if [[ "$status" == "Bound" ]]; then
                success "  - $pvc: $status"
                add_to_report "✅ PVC $pvc: $status"
            else
                error "  - $pvc: $status"
                add_to_report "❌ PVC $pvc: $status"
                issues=$((issues + 1))
            fi
        done
    fi
    
    # Check volume mounts in pods
    log "Checking volume mount types..."
    local pods_with_emptydir=$(kubectl get pods -n monitoring -o json | jq -r '.items[] | select(.spec.volumes[]?.emptyDir) | .metadata.name' | wc -l)
    
    if [[ $pods_with_emptydir -gt 0 ]]; then
        success "Found $pods_with_emptydir pod(s) using emptyDir volumes (ephemeral design)"
        add_to_report "✅ Pods using emptyDir volumes: $pods_with_emptydir"
    fi
    
    add_to_report ""
    return $issues
}

# Process management for port forwards
cleanup_port_forwards() {
    log "Cleaning up any existing port forwards..."
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 1
}

# Main health check function
run_monitoring_health_check() {
    log "Starting comprehensive monitoring system health check..."
    
    init_report
    add_to_report "## Health Check Started"
    add_to_report "**Timestamp**: $(date)"
    add_to_report ""
    
    local total_issues=0
    
    # Run all health checks
    check_monitoring_namespace
    total_issues=$((total_issues + $?))
    
    check_prometheus_health
    total_issues=$((total_issues + $?))
    
    check_grafana_health
    total_issues=$((total_issues + $?))
    
    check_servicemonitors
    total_issues=$((total_issues + $?))
    
    check_metrics_collection
    total_issues=$((total_issues + $?))
    
    check_storage_health
    total_issues=$((total_issues + $?))
    
    check_remote_access
    total_issues=$((total_issues + $?))
    
    # Clean up any port forwards we created
    cleanup_port_forwards
    
    # Summary
    add_to_report "## Health Check Summary"
    add_to_report ""
    add_to_report "**Total Issues Found**: $total_issues"
    add_to_report "**Health Check Completed**: $(date)"
    
    if [[ $total_issues -eq 0 ]]; then
        success "Monitoring system health check completed successfully - no issues found"
        add_to_report "**Overall Status**: ✅ HEALTHY"
    elif [[ $total_issues -le 3 ]]; then
        warn "Monitoring system health check completed with $total_issues minor issues"
        add_to_report "**Overall Status**: ⚠️ HEALTHY WITH WARNINGS"
    else
        error "Monitoring system health check found $total_issues issues requiring attention"
        add_to_report "**Overall Status**: ❌ ATTENTION REQUIRED"
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        log "Health report generated: $REPORT_FILE"
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by monitoring-health-check.sh*"
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
}

# Main execution
main() {
    log "Monitoring System Health Check v1.0"
    log "======================================"
    
    check_dependencies
    
    # Run the health check
    run_monitoring_health_check
    exit_code=$?
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo
        log "Monitoring health report available at: $REPORT_FILE"
        
        # If running in CI/CD, also output to stdout
        if [[ -n "${CI:-}" ]]; then
            echo "## Monitoring Health Report"
            cat "$REPORT_FILE"
        fi
    fi
    
    log "======================================"
    if [[ $exit_code -eq 0 ]]; then
        success "Monitoring system is healthy!"
    else
        error "Monitoring system has $exit_code issue(s) - see details above"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"