#!/bin/bash

# Monitoring System Health Assessment Script
# This script identifies stuck monitoring resources and configuration conflicts

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

# Check monitoring namespace
check_monitoring_namespace() {
    log_info "Checking monitoring namespace..."
    
    if kubectl get namespace monitoring &> /dev/null; then
        local phase=$(kubectl get namespace monitoring -o jsonpath='{.status.phase}')
        if [[ "$phase" == "Active" ]]; then
            log_success "Monitoring namespace exists and is Active"
        else
            log_warning "Monitoring namespace exists but phase is: $phase"
        fi
        
        # Check for deletion timestamp
        local deletion_timestamp=$(kubectl get namespace monitoring -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "")
        if [[ -n "$deletion_timestamp" ]]; then
            log_error "Monitoring namespace is being deleted (deletionTimestamp: $deletion_timestamp)"
            return 1
        fi
    else
        log_error "Monitoring namespace does not exist"
        return 1
    fi
}

# Check for stuck resources with deletion timestamps
check_stuck_resources() {
    log_info "Checking for stuck resources with deletion timestamps..."
    
    local stuck_found=false
    
    # Check pods
    local stuck_pods=$(kubectl get pods -n monitoring -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' 2>/dev/null || echo "")
    if [[ -n "$stuck_pods" ]]; then
        log_error "Found stuck pods being deleted:"
        echo "$stuck_pods" | while read -r pod; do
            echo "  - $pod"
        done
        stuck_found=true
    fi
    
    # Check PVCs
    local stuck_pvcs=$(kubectl get pvc -n monitoring -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' 2>/dev/null || echo "")
    if [[ -n "$stuck_pvcs" ]]; then
        log_error "Found stuck PVCs being deleted:"
        echo "$stuck_pvcs" | while read -r pvc; do
            echo "  - $pvc"
        done
        stuck_found=true
    fi
    
    # Check HelmReleases
    local stuck_helmreleases=$(kubectl get helmrelease -n monitoring -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' 2>/dev/null || echo "")
    if [[ -n "$stuck_helmreleases" ]]; then
        log_error "Found stuck HelmReleases being deleted:"
        echo "$stuck_helmreleases" | while read -r hr; do
            echo "  - $hr"
        done
        stuck_found=true
    fi
    
    if [[ "$stuck_found" == "false" ]]; then
        log_success "No stuck resources found"
    fi
}

# Check PVC status
check_pvc_status() {
    log_info "Checking PVC status..."
    
    local pvcs=$(kubectl get pvc -n monitoring -o json 2>/dev/null || echo '{"items":[]}')
    local pvc_count=$(echo "$pvcs" | jq '.items | length')
    
    if [[ "$pvc_count" -eq 0 ]]; then
        log_info "No PVCs found in monitoring namespace"
        return 0
    fi
    
    echo "$pvcs" | jq -r '.items[] | "\(.metadata.name) - Status: \(.status.phase) - Storage: \(.spec.resources.requests.storage // "unknown")"' | while read -r line; do
        if [[ "$line" == *"Pending"* ]]; then
            log_warning "PVC: $line"
        elif [[ "$line" == *"Bound"* ]]; then
            log_success "PVC: $line"
        else
            log_error "PVC: $line"
        fi
    done
}

# Check pod status
check_pod_status() {
    log_info "Checking pod status..."
    
    local pods=$(kubectl get pods -n monitoring -o json 2>/dev/null || echo '{"items":[]}')
    local pod_count=$(echo "$pods" | jq '.items | length')
    
    if [[ "$pod_count" -eq 0 ]]; then
        log_warning "No pods found in monitoring namespace"
        return 0
    fi
    
    echo "$pods" | jq -r '.items[] | "\(.metadata.name) - Status: \(.status.phase) - Ready: \(.status.conditions[] | select(.type=="Ready") | .status)"' | while read -r line; do
        if [[ "$line" == *"Running"* && "$line" == *"True"* ]]; then
            log_success "Pod: $line"
        elif [[ "$line" == *"Running"* && "$line" == *"False"* ]]; then
            log_warning "Pod: $line (Running but not Ready)"
        else
            log_error "Pod: $line"
        fi
    done
}

# Check HelmRelease status
check_helmrelease_status() {
    log_info "Checking HelmRelease status..."
    
    local helmreleases=$(kubectl get helmrelease -n monitoring -o json 2>/dev/null || echo '{"items":[]}')
    local hr_count=$(echo "$helmreleases" | jq '.items | length')
    
    if [[ "$hr_count" -eq 0 ]]; then
        log_warning "No HelmReleases found in monitoring namespace"
        return 0
    fi
    
    echo "$helmreleases" | jq -r '.items[] | "\(.metadata.name) - Ready: \(.status.conditions[] | select(.type=="Ready") | .status) - Message: \(.status.conditions[] | select(.type=="Ready") | .message)"' | while read -r line; do
        if [[ "$line" == *"True"* ]]; then
            log_success "HelmRelease: $line"
        else
            log_error "HelmRelease: $line"
        fi
    done
}

# Check for configuration conflicts
check_configuration_conflicts() {
    log_info "Checking for configuration conflicts..."
    
    # Check for duplicate HelmRepositories
    local helm_repos=$(kubectl get helmrepository -n monitoring -o json 2>/dev/null || echo '{"items":[]}')
    local repo_urls=$(echo "$helm_repos" | jq -r '.items[] | "\(.metadata.name): \(.spec.url)"')
    
    if [[ -n "$repo_urls" ]]; then
        log_info "Found HelmRepositories:"
        echo "$repo_urls" | while read -r line; do
            echo "  - $line"
        done
        
        # Check for duplicate URLs
        local duplicate_urls=$(echo "$repo_urls" | cut -d: -f2- | sort | uniq -d)
        if [[ -n "$duplicate_urls" ]]; then
            log_warning "Found duplicate HelmRepository URLs:"
            echo "$duplicate_urls" | while read -r url; do
                echo "  - $url"
            done
        fi
    fi
    
    # Check HelmRelease source references
    local hr_sources=$(kubectl get helmrelease -n monitoring -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.name) -> \(.spec.chart.spec.sourceRef.name)"' || echo "")
    if [[ -n "$hr_sources" ]]; then
        log_info "HelmRelease source references:"
        echo "$hr_sources" | while read -r line; do
            echo "  - $line"
        done
    fi
}

# Check recent events
check_recent_events() {
    log_info "Checking recent events in monitoring namespace..."
    
    local events=$(kubectl get events -n monitoring --sort-by='.lastTimestamp' --no-headers 2>/dev/null | tail -10 || echo "")
    if [[ -n "$events" ]]; then
        echo "$events" | while read -r line; do
            if [[ "$line" == *"Warning"* || "$line" == *"Error"* ]]; then
                log_warning "Event: $line"
            else
                log_info "Event: $line"
            fi
        done
    else
        log_info "No recent events found"
    fi
}

# Check CRD status
check_crd_status() {
    log_info "Checking monitoring-related CRDs..."
    
    local monitoring_crds=("prometheuses.monitoring.coreos.com" "servicemonitors.monitoring.coreos.com" "podmonitors.monitoring.coreos.com" "helmreleases.helm.toolkit.fluxcd.io" "helmrepositories.source.toolkit.fluxcd.io")
    
    for crd in "${monitoring_crds[@]}"; do
        if kubectl get crd "$crd" &> /dev/null; then
            log_success "CRD exists: $crd"
        else
            log_error "CRD missing: $crd"
        fi
    done
}

# Generate cleanup recommendations
generate_cleanup_recommendations() {
    log_info "Generating cleanup recommendations..."
    
    echo ""
    echo "=== CLEANUP RECOMMENDATIONS ==="
    echo ""
    
    # Check for stuck resources
    local stuck_pods=$(kubectl get pods -n monitoring -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' 2>/dev/null || echo "")
    if [[ -n "$stuck_pods" ]]; then
        echo "1. Remove stuck pods:"
        echo "$stuck_pods" | while read -r pod; do
            echo "   kubectl delete pod $pod -n monitoring --force --grace-period=0"
        done
        echo ""
    fi
    
    local stuck_pvcs=$(kubectl get pvc -n monitoring -o json | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' 2>/dev/null || echo "")
    if [[ -n "$stuck_pvcs" ]]; then
        echo "2. Remove stuck PVCs:"
        echo "$stuck_pvcs" | while read -r pvc; do
            echo "   kubectl patch pvc $pvc -n monitoring -p '{\"metadata\":{\"finalizers\":null}}'"
            echo "   kubectl delete pvc $pvc -n monitoring --force --grace-period=0"
        done
        echo ""
    fi
    
    # Check for failed HelmReleases
    local failed_hrs=$(kubectl get helmrelease -n monitoring -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="False")) | .metadata.name' 2>/dev/null || echo "")
    if [[ -n "$failed_hrs" ]]; then
        echo "3. Fix failed HelmReleases:"
        echo "$failed_hrs" | while read -r hr; do
            echo "   # Check HelmRelease: $hr"
            echo "   kubectl describe helmrelease $hr -n monitoring"
            echo "   # Consider reconciling:"
            echo "   flux reconcile helmrelease $hr -n monitoring"
        done
        echo ""
    fi
    
    # Check for configuration issues
    local grafana_hr_source=$(kubectl get helmrelease monitoring-core-grafana -n monitoring -o jsonpath='{.spec.chart.spec.sourceRef.name}' 2>/dev/null || echo "")
    if [[ "$grafana_hr_source" == "grafana-core" ]]; then
        echo "4. Fix Grafana HelmRelease source reference:"
        echo "   # The Grafana HelmRelease should reference 'prometheus-community' repository"
        echo "   # Edit infrastructure/monitoring/core/grafana-core.yaml"
        echo "   # Change sourceRef.name from 'grafana-core' to 'prometheus-community'"
        echo ""
    fi
    
    echo "5. General cleanup commands:"
    echo "   # Force delete monitoring namespace if stuck:"
    echo "   kubectl patch namespace monitoring -p '{\"metadata\":{\"finalizers\":null}}'"
    echo "   kubectl delete namespace monitoring --force --grace-period=0"
    echo ""
    echo "   # Recreate monitoring namespace:"
    echo "   kubectl create namespace monitoring"
    echo ""
    echo "   # Reconcile monitoring infrastructure:"
    echo "   flux reconcile kustomization monitoring -n flux-system"
    echo ""
}

# Main execution
main() {
    echo "=== Monitoring System Health Assessment ==="
    echo "Timestamp: $(date)"
    echo ""
    
    check_kubectl
    echo ""
    
    check_monitoring_namespace
    echo ""
    
    check_stuck_resources
    echo ""
    
    check_pvc_status
    echo ""
    
    check_pod_status
    echo ""
    
    check_helmrelease_status
    echo ""
    
    check_configuration_conflicts
    echo ""
    
    check_recent_events
    echo ""
    
    check_crd_status
    echo ""
    
    generate_cleanup_recommendations
    
    echo "=== Assessment Complete ==="
}

# Run main function
main "$@"