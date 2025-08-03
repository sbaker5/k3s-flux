#!/bin/bash
# Monitoring System Health Assessment Script
# Create monitoring system health assessment script
# Requirements: 1.1, 1.2, 1.4

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/monitoring-health.log"
MONITORING_NAMESPACE="monitoring"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl is required but not installed${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
}

# Assess monitoring namespace health
assess_namespace_health() {
    echo -e "${CYAN}=== Monitoring Namespace Health ===${NC}"
    
    if kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        local ns_status
        ns_status=$(kubectl get namespace "$MONITORING_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local deletion_timestamp
        deletion_timestamp=$(kubectl get namespace "$MONITORING_NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
        
        if [[ "$deletion_timestamp" != "null" ]]; then
            echo -e "${RED}❌ Namespace is stuck in Terminating state${NC}"
            log "ERROR" "Monitoring namespace is stuck in Terminating state"
            return 1
        elif [[ "$ns_status" == "Active" ]]; then
            echo -e "${GREEN}✓ Namespace is Active${NC}"
            log "INFO" "Monitoring namespace is healthy"
            return 0
        else
            echo -e "${YELLOW}⚠ Namespace status: $ns_status${NC}"
            log "WARNING" "Monitoring namespace status: $ns_status"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ Monitoring namespace does not exist${NC}"
        log "WARNING" "Monitoring namespace does not exist"
        return 1
    fi
}

# Assess monitoring pods health
assess_pods_health() {
    echo -e "${CYAN}=== Monitoring Pods Health ===${NC}"
    
    if ! kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}⚠ Cannot assess pods - namespace does not exist${NC}"
        return 1
    fi
    
    local pods_output
    pods_output=$(kubectl get pods -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$pods_output" ]]; then
        echo -e "${YELLOW}⚠ No pods found in monitoring namespace${NC}"
        log "WARNING" "No monitoring pods found"
        return 1
    fi
    
    local total_pods=0
    local ready_pods=0
    local stuck_pods=0
    local failed_pods=()
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            total_pods=$((total_pods + 1))
            local pod_name=$(echo "$line" | awk '{print $1}')
            local ready_status=$(echo "$line" | awk '{print $2}')
            local status=$(echo "$line" | awk '{print $3}')
            
            if [[ "$status" == "Running" && "$ready_status" =~ ^[0-9]+/[0-9]+$ ]]; then
                local ready_count=$(echo "$ready_status" | cut -d'/' -f1)
                local total_count=$(echo "$ready_status" | cut -d'/' -f2)
                if [[ "$ready_count" == "$total_count" ]]; then
                    ready_pods=$((ready_pods + 1))
                    echo -e "  ${GREEN}✓${NC} $pod_name: $status ($ready_status)"
                else
                    echo -e "  ${YELLOW}⚠${NC} $pod_name: $status ($ready_status)"
                    failed_pods+=("$pod_name")
                fi
            elif [[ "$status" =~ ^(Terminating|Unknown|Failed|CrashLoopBackOff|ImagePullBackOff)$ ]]; then
                stuck_pods=$((stuck_pods + 1))
                echo -e "  ${RED}❌${NC} $pod_name: $status ($ready_status)"
                failed_pods+=("$pod_name")
            else
                echo -e "  ${YELLOW}⚠${NC} $pod_name: $status ($ready_status)"
                failed_pods+=("$pod_name")
            fi
        fi
    done <<< "$pods_output"
    
    echo -e "Summary: ${ready_pods}/${total_pods} pods ready, ${stuck_pods} stuck"
    log "INFO" "Monitoring pods: ${ready_pods}/${total_pods} ready, ${stuck_pods} stuck"
    
    if [[ $ready_pods -eq $total_pods && $total_pods -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Assess monitoring services health
assess_services_health() {
    echo -e "${CYAN}=== Monitoring Services Health ===${NC}"
    
    if ! kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}⚠ Cannot assess services - namespace does not exist${NC}"
        return 1
    fi
    
    local services_output
    services_output=$(kubectl get services -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$services_output" ]]; then
        echo -e "${YELLOW}⚠ No services found in monitoring namespace${NC}"
        return 1
    fi
    
    local healthy_services=0
    local total_services=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            total_services=$((total_services + 1))
            local service_name=$(echo "$line" | awk '{print $1}')
            local service_type=$(echo "$line" | awk '{print $2}')
            local cluster_ip=$(echo "$line" | awk '{print $3}')
            
            if [[ "$cluster_ip" != "<none>" && "$cluster_ip" != "<pending>" ]]; then
                healthy_services=$((healthy_services + 1))
                echo -e "  ${GREEN}✓${NC} $service_name ($service_type): $cluster_ip"
            else
                echo -e "  ${YELLOW}⚠${NC} $service_name ($service_type): $cluster_ip"
            fi
        fi
    done <<< "$services_output"
    
    echo -e "Summary: ${healthy_services}/${total_services} services healthy"
    log "INFO" "Monitoring services: ${healthy_services}/${total_services} healthy"
    
    if [[ $healthy_services -eq $total_services && $total_services -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Assess Flux monitoring resources
assess_flux_monitoring() {
    echo -e "${CYAN}=== Flux Monitoring Resources Health ===${NC}"
    
    if ! kubectl get namespace flux-system &>/dev/null; then
        echo -e "${YELLOW}⚠ Flux system not available${NC}"
        return 1
    fi
    
    local flux_monitoring_healthy=true
    
    # Check ServiceMonitor
    if kubectl get servicemonitor -n "$MONITORING_NAMESPACE" flux-controllers-with-services &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Flux ServiceMonitor exists"
        
        # Check if it has targets
        local servicemonitor_targets
        servicemonitor_targets=$(kubectl get servicemonitor -n "$MONITORING_NAMESPACE" flux-controllers-with-services -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null || echo "{}")
        if [[ "$servicemonitor_targets" != "{}" ]]; then
            echo -e "    ${GREEN}✓${NC} ServiceMonitor has target selectors"
        else
            echo -e "    ${YELLOW}⚠${NC} ServiceMonitor missing target selectors"
            flux_monitoring_healthy=false
        fi
    else
        echo -e "  ${RED}❌${NC} Flux ServiceMonitor not found"
        flux_monitoring_healthy=false
    fi
    
    # Check PodMonitor
    if kubectl get podmonitor -n "$MONITORING_NAMESPACE" flux-controllers-pods &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Flux PodMonitor exists"
        
        # Check if it has targets
        local podmonitor_targets
        podmonitor_targets=$(kubectl get podmonitor -n "$MONITORING_NAMESPACE" flux-controllers-pods -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null || echo "{}")
        if [[ "$podmonitor_targets" != "{}" ]]; then
            echo -e "    ${GREEN}✓${NC} PodMonitor has target selectors"
        else
            echo -e "    ${YELLOW}⚠${NC} PodMonitor missing target selectors"
            flux_monitoring_healthy=false
        fi
    else
        echo -e "  ${RED}❌${NC} Flux PodMonitor not found"
        flux_monitoring_healthy=false
    fi
    
    if [[ "$flux_monitoring_healthy" == "true" ]]; then
        log "INFO" "Flux monitoring resources are healthy"
        return 0
    else
        log "WARNING" "Flux monitoring resources have issues"
        return 1
    fi
}

# Test Prometheus connectivity
test_prometheus_connectivity() {
    echo -e "${CYAN}=== Prometheus Connectivity Test ===${NC}"
    
    if ! kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}⚠ Cannot test Prometheus - namespace does not exist${NC}"
        return 1
    fi
    
    # Check if Prometheus service exists
    if ! kubectl get service -n "$MONITORING_NAMESPACE" -l app.kubernetes.io/name=prometheus &>/dev/null; then
        echo -e "${RED}❌ Prometheus service not found${NC}"
        return 1
    fi
    
    # Try to port-forward and test connectivity
    local prometheus_service
    prometheus_service=$(kubectl get service -n "$MONITORING_NAMESPACE" -l app.kubernetes.io/name=prometheus -o name | head -1)
    
    if [[ -n "$prometheus_service" ]]; then
        echo -e "  ${GREEN}✓${NC} Prometheus service found: ${prometheus_service#service/}"
        
        # Test if we can reach the service (without actually port-forwarding)
        local service_endpoints
        service_endpoints=$(kubectl get endpoints -n "$MONITORING_NAMESPACE" "${prometheus_service#service/}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        
        if [[ -n "$service_endpoints" ]]; then
            echo -e "  ${GREEN}✓${NC} Prometheus has active endpoints"
            log "INFO" "Prometheus connectivity test passed"
            return 0
        else
            echo -e "  ${RED}❌${NC} Prometheus has no active endpoints"
            log "ERROR" "Prometheus has no active endpoints"
            return 1
        fi
    else
        echo -e "${RED}❌ No Prometheus service found${NC}"
        return 1
    fi
}

# Generate health report
generate_health_report() {
    echo -e "${BLUE}=== Monitoring System Health Report ===${NC}"
    echo
    
    local overall_health=true
    local issues=()
    
    # Test each component
    if ! assess_namespace_health; then
        overall_health=false
        issues+=("Namespace issues")
    fi
    echo
    
    if ! assess_pods_health; then
        overall_health=false
        issues+=("Pod issues")
    fi
    echo
    
    if ! assess_services_health; then
        overall_health=false
        issues+=("Service issues")
    fi
    echo
    
    if ! assess_flux_monitoring; then
        overall_health=false
        issues+=("Flux monitoring issues")
    fi
    echo
    
    if ! test_prometheus_connectivity; then
        overall_health=false
        issues+=("Prometheus connectivity issues")
    fi
    echo
    
    # Final report
    echo -e "${BLUE}=== Final Health Assessment ===${NC}"
    if [[ "$overall_health" == "true" ]]; then
        echo -e "${GREEN}✓ Monitoring system is healthy${NC}"
        log "INFO" "Monitoring system health assessment: HEALTHY"
        return 0
    else
        echo -e "${RED}❌ Monitoring system has issues:${NC}"
        for issue in "${issues[@]}"; do
            echo -e "  - $issue"
        done
        echo
        echo -e "${YELLOW}Recommendation: Run monitoring cleanup or investigate specific issues${NC}"
        log "WARNING" "Monitoring system health assessment: UNHEALTHY - Issues: ${issues[*]}"
        return 1
    fi
}

# Display usage information
usage() {
    cat << EOF
Monitoring System Health Assessment Tool

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    report                        Generate comprehensive health report (default)
    namespace                     Assess monitoring namespace health
    pods                          Assess monitoring pods health
    services                      Assess monitoring services health
    flux                          Assess Flux monitoring resources
    prometheus                    Test Prometheus connectivity
    
Options:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose logging

Examples:
    $0                            # Generate full health report
    $0 report                     # Generate full health report
    $0 pods                       # Check only pods health
    $0 prometheus                 # Test Prometheus connectivity

Log File: $LOG_FILE

This tool provides comprehensive monitoring system health assessment.
Use it to identify issues before running cleanup operations.
EOF
}

# Main function
main() {
    local command="${1:-report}"
    
    # Handle help
    if [[ "$command" == "-h" || "$command" == "--help" ]]; then
        usage
        exit 0
    fi
    
    # Handle verbose mode
    if [[ "$command" == "-v" || "$command" == "--verbose" ]]; then
        set -x
        command="${2:-report}"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    log "INFO" "Starting monitoring health assessment: $command"
    
    # Execute command
    case "$command" in
        "report")
            generate_health_report
            ;;
        "namespace")
            assess_namespace_health
            ;;
        "pods")
            assess_pods_health
            ;;
        "services")
            assess_services_health
            ;;
        "flux")
            assess_flux_monitoring
            ;;
        "prometheus")
            test_prometheus_connectivity
            ;;
        *)
            echo -e "${RED}Unknown command: $command. Use -h for help.${NC}"
            exit 1
            ;;
    esac
    
    local exit_code=$?
    log "INFO" "Monitoring health assessment completed with exit code: $exit_code"
    exit $exit_code
}

# Run main function
main "$@"