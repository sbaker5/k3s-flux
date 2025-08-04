#!/bin/bash
set -euo pipefail

# Enhanced Storage Discovery Validation Script
# This script validates the enhanced storage discovery and configuration automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/storage-discovery-validation.log"
VALIDATION_TIMEOUT=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Initialize logging
init_logging() {
    echo "Enhanced Storage Discovery Validation - $(date)" > "$LOG_FILE"
    log_info "Starting enhanced storage discovery validation"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not available"
        return 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Kubernetes cluster is not accessible"
        return 1
    fi
    
    # Check if longhorn-system namespace exists
    if ! kubectl get namespace longhorn-system >/dev/null 2>&1; then
        log_error "longhorn-system namespace does not exist"
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

# Validate enhanced disk discovery DaemonSet
validate_disk_discovery_daemonset() {
    log_info "Validating enhanced disk discovery DaemonSet..."
    
    # Check if DaemonSet exists
    if ! kubectl get daemonset longhorn-disk-discovery -n longhorn-system >/dev/null 2>&1; then
        log_error "longhorn-disk-discovery DaemonSet not found"
        return 1
    fi
    
    # Check DaemonSet status
    local desired_pods
    desired_pods=$(kubectl get daemonset longhorn-disk-discovery -n longhorn-system -o jsonpath='{.status.desiredNumberScheduled}')
    local ready_pods
    ready_pods=$(kubectl get daemonset longhorn-disk-discovery -n longhorn-system -o jsonpath='{.status.numberReady}')
    
    if [ "$ready_pods" -eq "$desired_pods" ] && [ "$ready_pods" -gt 0 ]; then
        log_success "Disk discovery DaemonSet is running ($ready_pods/$desired_pods pods ready)"
    else
        log_warning "Disk discovery DaemonSet not fully ready ($ready_pods/$desired_pods pods ready)"
        
        # Show pod status for debugging
        log_info "Pod status:"
        kubectl get pods -n longhorn-system -l app=longhorn-disk-discovery -o wide | tee -a "$LOG_FILE"
        
        # Show recent events
        log_info "Recent events:"
        kubectl get events -n longhorn-system --field-selector involvedObject.name=longhorn-disk-discovery --sort-by='.lastTimestamp' | tail -5 | tee -a "$LOG_FILE"
    fi
    
    return 0
}

# Validate RBAC configuration
validate_rbac_configuration() {
    log_info "Validating RBAC configuration..."
    
    # Check ServiceAccount
    if kubectl get serviceaccount longhorn-disk-discovery -n longhorn-system >/dev/null 2>&1; then
        log_success "ServiceAccount longhorn-disk-discovery exists"
    else
        log_error "ServiceAccount longhorn-disk-discovery not found"
        return 1
    fi
    
    # Check ClusterRole
    if kubectl get clusterrole longhorn-disk-discovery >/dev/null 2>&1; then
        log_success "ClusterRole longhorn-disk-discovery exists"
    else
        log_error "ClusterRole longhorn-disk-discovery not found"
        return 1
    fi
    
    # Check ClusterRoleBinding
    if kubectl get clusterrolebinding longhorn-disk-discovery >/dev/null 2>&1; then
        log_success "ClusterRoleBinding longhorn-disk-discovery exists"
    else
        log_error "ClusterRoleBinding longhorn-disk-discovery not found"
        return 1
    fi
    
    return 0
}

# Validate storage health validator
validate_storage_health_validator() {
    log_info "Validating storage health validator..."
    
    # Check ConfigMap
    if kubectl get configmap storage-health-validator -n longhorn-system >/dev/null 2>&1; then
        log_success "Storage health validator ConfigMap exists"
    else
        log_error "Storage health validator ConfigMap not found"
        return 1
    fi
    
    # Run storage health validation job
    log_info "Running storage health validation job..."
    
    # Delete existing job if it exists
    kubectl delete job storage-health-validation -n longhorn-system --ignore-not-found=true
    
    # Create and run the job
    if kubectl create job storage-health-validation-test --from=job/storage-health-validation -n longhorn-system >/dev/null 2>&1; then
        log_info "Storage health validation job created"
        
        # Wait for job completion
        local timeout=60
        local elapsed=0
        
        while [ $elapsed -lt $timeout ]; do
            local job_status
            job_status=$(kubectl get job storage-health-validation-test -n longhorn-system -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
            
            if [ "$job_status" = "Complete" ]; then
                log_success "Storage health validation job completed successfully"
                
                # Show job logs
                log_info "Storage health validation logs:"
                kubectl logs job/storage-health-validation-test -n longhorn-system | tail -10 | tee -a "$LOG_FILE"
                
                # Clean up
                kubectl delete job storage-health-validation-test -n longhorn-system >/dev/null 2>&1
                return 0
            elif [ "$job_status" = "Failed" ]; then
                log_error "Storage health validation job failed"
                kubectl logs job/storage-health-validation-test -n longhorn-system | tail -10 | tee -a "$LOG_FILE"
                kubectl delete job storage-health-validation-test -n longhorn-system >/dev/null 2>&1
                return 1
            fi
            
            sleep 5
            elapsed=$((elapsed + 5))
        done
        
        log_warning "Storage health validation job timed out"
        kubectl delete job storage-health-validation-test -n longhorn-system >/dev/null 2>&1
        return 1
    else
        log_error "Failed to create storage health validation job"
        return 1
    fi
}

# Validate Longhorn node validator
validate_longhorn_node_validator() {
    log_info "Validating Longhorn node validator..."
    
    # Check ConfigMap
    if kubectl get configmap longhorn-node-validator -n longhorn-system >/dev/null 2>&1; then
        log_success "Longhorn node validator ConfigMap exists"
    else
        log_error "Longhorn node validator ConfigMap not found"
        return 1
    fi
    
    # Run Longhorn node validation job
    log_info "Running Longhorn node validation job..."
    
    # Delete existing job if it exists
    kubectl delete job longhorn-node-validation -n longhorn-system --ignore-not-found=true
    
    # Create and run the job
    if kubectl create job longhorn-node-validation-test --from=job/longhorn-node-validation -n longhorn-system >/dev/null 2>&1; then
        log_info "Longhorn node validation job created"
        
        # Wait for job completion
        local timeout=120
        local elapsed=0
        
        while [ $elapsed -lt $timeout ]; do
            local job_status
            job_status=$(kubectl get job longhorn-node-validation-test -n longhorn-system -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
            
            if [ "$job_status" = "Complete" ]; then
                log_success "Longhorn node validation job completed successfully"
                
                # Show job logs
                log_info "Longhorn node validation logs:"
                kubectl logs job/longhorn-node-validation-test -n longhorn-system | tail -15 | tee -a "$LOG_FILE"
                
                # Clean up
                kubectl delete job longhorn-node-validation-test -n longhorn-system >/dev/null 2>&1
                return 0
            elif [ "$job_status" = "Failed" ]; then
                log_warning "Longhorn node validation job failed (this may be expected if Longhorn is not fully ready)"
                kubectl logs job/longhorn-node-validation-test -n longhorn-system | tail -15 | tee -a "$LOG_FILE"
                kubectl delete job longhorn-node-validation-test -n longhorn-system >/dev/null 2>&1
                return 1
            fi
            
            sleep 5
            elapsed=$((elapsed + 5))
        done
        
        log_warning "Longhorn node validation job timed out"
        kubectl delete job longhorn-node-validation-test -n longhorn-system >/dev/null 2>&1
        return 1
    else
        log_error "Failed to create Longhorn node validation job"
        return 1
    fi
}

# Check disk discovery logs and status
check_disk_discovery_status() {
    log_info "Checking disk discovery status..."
    
    # Get disk discovery pods
    local pods
    pods=$(kubectl get pods -n longhorn-system -l app=longhorn-disk-discovery --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
    
    if [ -z "$pods" ]; then
        log_warning "No disk discovery pods found"
        return 1
    fi
    
    for pod in $pods; do
        log_info "Checking status for pod: $pod"
        
        # Check pod status
        local pod_status
        pod_status=$(kubectl get pod "$pod" -n longhorn-system -o jsonpath='{.status.phase}')
        
        if [ "$pod_status" = "Running" ]; then
            log_success "Pod $pod is running"
            
            # Check recent logs
            log_info "Recent logs from $pod:"
            kubectl logs "$pod" -n longhorn-system --tail=10 | tee -a "$LOG_FILE"
            
            # Try to get status file if available
            log_info "Attempting to get discovery status from $pod:"
            kubectl exec "$pod" -n longhorn-system -- cat /var/log/longhorn-discovery-status.json 2>/dev/null | jq . 2>/dev/null | tee -a "$LOG_FILE" || log_info "Status file not available or not readable"
            
        else
            log_warning "Pod $pod is not running (status: $pod_status)"
            kubectl describe pod "$pod" -n longhorn-system | tail -10 | tee -a "$LOG_FILE"
        fi
    done
    
    return 0
}

# Validate Longhorn nodes
validate_longhorn_nodes() {
    log_info "Validating Longhorn nodes..."
    
    # Check if any Longhorn nodes exist
    local nodes
    nodes=$(kubectl get nodes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l)
    
    if [ "$nodes" -eq 0 ]; then
        log_warning "No Longhorn nodes found - this may be expected during initial setup"
        return 1
    fi
    
    log_info "Found $nodes Longhorn node(s)"
    
    # Show node details
    log_info "Longhorn node details:"
    kubectl get nodes.longhorn.io -n longhorn-system -o wide | tee -a "$LOG_FILE"
    
    # Check each node's readiness
    local ready_nodes=0
    for node in $(kubectl get nodes.longhorn.io -n longhorn-system --no-headers -o custom-columns=":metadata.name" 2>/dev/null); do
        local node_ready
        node_ready=$(kubectl get nodes.longhorn.io "$node" -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$node_ready" = "True" ]; then
            log_success "Longhorn node $node is ready"
            ready_nodes=$((ready_nodes + 1))
        else
            log_warning "Longhorn node $node is not ready (status: $node_ready)"
        fi
    done
    
    log_info "Ready Longhorn nodes: $ready_nodes/$nodes"
    return 0
}

# Generate validation report
generate_report() {
    log_info "Generating validation report..."
    
    local report_file="/tmp/storage-discovery-validation-report.json"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "validation_type": "enhanced_storage_discovery",
  "cluster_info": {
    "context": "$(kubectl config current-context)",
    "nodes": $(kubectl get nodes --no-headers | wc -l),
    "longhorn_nodes": $(kubectl get nodes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l || echo 0)
  },
  "components": {
    "disk_discovery_daemonset": {
      "desired_pods": $(kubectl get daemonset longhorn-disk-discovery -n longhorn-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0),
      "ready_pods": $(kubectl get daemonset longhorn-disk-discovery -n longhorn-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
    },
    "rbac_configured": $(kubectl get serviceaccount longhorn-disk-discovery -n longhorn-system >/dev/null 2>&1 && echo true || echo false),
    "validators_available": {
      "storage_health": $(kubectl get configmap storage-health-validator -n longhorn-system >/dev/null 2>&1 && echo true || echo false),
      "longhorn_node": $(kubectl get configmap longhorn-node-validator -n longhorn-system >/dev/null 2>&1 && echo true || echo false)
    }
  },
  "log_file": "$LOG_FILE"
}
EOF
    
    log_success "Validation report generated: $report_file"
    cat "$report_file" | jq . | tee -a "$LOG_FILE"
}

# Main validation function
main() {
    init_logging
    
    local overall_status="passed"
    local checks_run=0
    local checks_passed=0
    
    # List of validation functions
    local validations=(
        "check_prerequisites"
        "validate_disk_discovery_daemonset"
        "validate_rbac_configuration"
        "validate_storage_health_validator"
        "validate_longhorn_node_validator"
        "check_disk_discovery_status"
        "validate_longhorn_nodes"
    )
    
    log_info "Running ${#validations[@]} validation checks..."
    echo ""
    
    # Run each validation
    for validation_func in "${validations[@]}"; do
        checks_run=$((checks_run + 1))
        log_info "Running validation: $validation_func"
        
        if $validation_func; then
            checks_passed=$((checks_passed + 1))
            log_success "✅ $validation_func passed"
        else
            log_warning "⚠️  $validation_func failed"
            overall_status="warning"
        fi
        echo ""
    done
    
    # Generate final report
    generate_report
    
    # Print summary
    echo ""
    log_info "=== VALIDATION SUMMARY ==="
    log_info "Checks run: $checks_run"
    log_info "Checks passed: $checks_passed"
    log_info "Overall status: $overall_status"
    
    if [ "$overall_status" = "passed" ]; then
        log_success "🎉 All enhanced storage discovery validations passed!"
        return 0
    else
        log_warning "⚠️  Some validations failed or had warnings. Check the log for details."
        log_info "Log file: $LOG_FILE"
        return 1
    fi
}

# Handle script arguments
case "${1:-validate}" in
    "validate")
        main
        ;;
    "report")
        generate_report
        ;;
    "logs")
        if [ -f "$LOG_FILE" ]; then
            cat "$LOG_FILE"
        else
            echo "Log file not found: $LOG_FILE"
            exit 1
        fi
        ;;
    "help")
        echo "Usage: $0 [validate|report|logs|help]"
        echo "  validate: Run full validation (default)"
        echo "  report:   Generate validation report only"
        echo "  logs:     Show validation logs"
        echo "  help:     Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac