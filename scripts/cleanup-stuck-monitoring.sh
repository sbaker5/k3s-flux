#!/bin/bash

# Cleanup Stuck Monitoring Resources Script
# This script removes stuck monitoring resources that prevent clean deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "kubectl is available and cluster is accessible"
}

# Remove stuck PVCs
cleanup_stuck_pvcs() {
    log_info "Cleaning up stuck PVCs..."
    
    # Get unused PVCs in monitoring namespace
    local unused_pvcs=$(kubectl get pvc -n monitoring -o json | jq -r '.items[] | select(.status.phase == "Bound") | select(.metadata.name | test("prometheus-monitoring-monitoring")) | .metadata.name' 2>/dev/null || echo "")
    
    if [[ -n "$unused_pvcs" ]]; then
        echo "$unused_pvcs" | while read -r pvc; do
            log_info "Checking PVC: $pvc"
            
            # Check if PVC is actually unused
            local used_by=$(kubectl describe pvc "$pvc" -n monitoring | grep "Used By:" | awk '{print $3}')
            if [[ "$used_by" == "<none>" ]]; then
                log_warning "Removing unused PVC: $pvc"
                
                # Remove finalizers if stuck
                kubectl patch pvc "$pvc" -n monitoring -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
                
                # Delete the PVC
                kubectl delete pvc "$pvc" -n monitoring --force --grace-period=0 2>/dev/null || true
                
                log_success "Removed PVC: $pvc"
            else
                log_info "PVC $pvc is in use by: $used_by"
            fi
        done
    else
        log_info "No stuck PVCs found"
    fi
}

# Remove stuck pods with deletion timestamps
cleanup_stuck_pods() {
    log_info "Cleaning up stuck pods..."
    
    local stuck_pods=$(kubectl get pods -n monitoring -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' 2>/dev/null || echo "")
    
    if [[ -n "$stuck_pods" ]]; then
        echo "$stuck_pods" | while read -r pod; do
            log_warning "Removing stuck pod: $pod"
            kubectl delete pod "$pod" -n monitoring --force --grace-period=0 2>/dev/null || true
            log_success "Removed stuck pod: $pod"
        done
    else
        log_info "No stuck pods found"
    fi
}

# Remove stuck HelmReleases with deletion timestamps
cleanup_stuck_helmreleases() {
    log_info "Cleaning up stuck HelmReleases..."
    
    local stuck_hrs=$(kubectl get helmrelease -n monitoring -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' 2>/dev/null || echo "")
    
    if [[ -n "$stuck_hrs" ]]; then
        echo "$stuck_hrs" | while read -r hr; do
            log_warning "Removing stuck HelmRelease: $hr"
            kubectl patch helmrelease "$hr" -n monitoring -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
            kubectl delete helmrelease "$hr" -n monitoring --force --grace-period=0 2>/dev/null || true
            log_success "Removed stuck HelmRelease: $hr"
        done
    else
        log_info "No stuck HelmReleases found"
    fi
}

# Suspend problematic HelmReleases temporarily
suspend_problematic_helmreleases() {
    log_info "Suspending problematic HelmReleases..."
    
    # Check if Grafana HelmRelease is failing
    local grafana_ready=$(kubectl get helmrelease monitoring-core-grafana -n monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    
    if [[ "$grafana_ready" == "False" ]]; then
        log_warning "Suspending failing Grafana HelmRelease"
        kubectl patch helmrelease monitoring-core-grafana -n monitoring -p '{"spec":{"suspend":true}}' 2>/dev/null || true
        log_success "Suspended monitoring-core-grafana HelmRelease"
    fi
}

# Resume HelmReleases after cleanup
resume_helmreleases() {
    log_info "Resuming HelmReleases..."
    
    # Resume Grafana HelmRelease
    local grafana_suspended=$(kubectl get helmrelease monitoring-core-grafana -n monitoring -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "false")
    
    if [[ "$grafana_suspended" == "true" ]]; then
        log_info "Resuming Grafana HelmRelease"
        kubectl patch helmrelease monitoring-core-grafana -n monitoring -p '{"spec":{"suspend":false}}' 2>/dev/null || true
        log_success "Resumed monitoring-core-grafana HelmRelease"
    fi
}

# Force reconcile monitoring kustomization
force_reconcile_monitoring() {
    log_info "Force reconciling monitoring kustomization..."
    
    # Check if flux CLI is available
    if command -v flux &> /dev/null; then
        flux reconcile kustomization monitoring -n flux-system --force 2>/dev/null || true
        log_success "Triggered monitoring kustomization reconciliation"
    else
        log_warning "flux CLI not available, skipping reconciliation trigger"
    fi
}

# Wait for system to stabilize
wait_for_stabilization() {
    log_info "Waiting for system to stabilize..."
    sleep 30
    
    # Check pod status
    local running_pods=$(kubectl get pods -n monitoring --no-headers | grep -c "Running" || echo "0")
    local total_pods=$(kubectl get pods -n monitoring --no-headers | wc -l || echo "0")
    
    log_info "Pod status: $running_pods/$total_pods running"
    
    # Check HelmRelease status
    local ready_hrs=$(kubectl get helmrelease -n monitoring -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | .metadata.name' 2>/dev/null | wc -l || echo "0")
    local total_hrs=$(kubectl get helmrelease -n monitoring --no-headers | wc -l || echo "0")
    
    log_info "HelmRelease status: $ready_hrs/$total_hrs ready"
}

# Main cleanup function
main() {
    echo "=== Monitoring System Cleanup ==="
    echo "Timestamp: $(date)"
    echo ""
    
    check_kubectl
    echo ""
    
    log_warning "This script will clean up stuck monitoring resources"
    log_warning "Make sure you have a backup of your monitoring configuration"
    echo ""
    
    # Ask for confirmation
    read -p "Do you want to proceed with cleanup? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    log_info "Starting cleanup process..."
    echo ""
    
    suspend_problematic_helmreleases
    echo ""
    
    cleanup_stuck_pods
    echo ""
    
    cleanup_stuck_helmreleases
    echo ""
    
    cleanup_stuck_pvcs
    echo ""
    
    force_reconcile_monitoring
    echo ""
    
    wait_for_stabilization
    echo ""
    
    resume_helmreleases
    echo ""
    
    log_success "Cleanup process completed"
    echo ""
    echo "Next steps:"
    echo "1. Run the monitoring health assessment: ./scripts/monitoring-health-assessment.sh"
    echo "2. Check Flux reconciliation: flux get all -A"
    echo "3. Monitor pod status: kubectl get pods -n monitoring -w"
    echo ""
}

# Run main function
main "$@"