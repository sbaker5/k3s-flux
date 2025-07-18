#!/bin/bash

# Cleanup script for stuck monitoring resources
# This script removes stuck PVCs and failed HelmReleases to allow clean hybrid monitoring deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    esac
}

# Function to remove finalizers from PVCs
cleanup_stuck_pvcs() {
    log INFO "Checking for stuck PVCs in monitoring namespace..."
    
    local stuck_pvcs
    stuck_pvcs=$(kubectl get pvc -n monitoring --no-headers 2>/dev/null | grep -E "(Terminating|Pending)" | awk '{print $1}' || true)
    
    if [[ -n "$stuck_pvcs" ]]; then
        log WARN "Found stuck PVCs, removing finalizers..."
        for pvc in $stuck_pvcs; do
            log INFO "Removing finalizers from PVC: $pvc"
            kubectl patch pvc "$pvc" -n monitoring -p '{"metadata":{"finalizers":null}}' --type=merge || true
        done
        
        # Wait a moment for cleanup
        sleep 5
        
        # Force delete any remaining PVCs
        for pvc in $stuck_pvcs; do
            if kubectl get pvc "$pvc" -n monitoring >/dev/null 2>&1; then
                log WARN "Force deleting PVC: $pvc"
                kubectl delete pvc "$pvc" -n monitoring --force --grace-period=0 || true
            fi
        done
    else
        log SUCCESS "No stuck PVCs found"
    fi
}

# Function to cleanup failed HelmReleases
cleanup_failed_helmreleases() {
    log INFO "Checking for failed HelmReleases in monitoring namespace..."
    
    local failed_releases
    failed_releases=$(kubectl get helmrelease -n monitoring --no-headers 2>/dev/null | grep -E "(Failed|Stalled)" | awk '{print $1}' || true)
    
    if [[ -n "$failed_releases" ]]; then
        log WARN "Found failed HelmReleases, cleaning up..."
        for release in $failed_releases; do
            log INFO "Deleting failed HelmRelease: $release"
            kubectl delete helmrelease "$release" -n monitoring --force --grace-period=0 || true
        done
    else
        log SUCCESS "No failed HelmReleases found"
    fi
}

# Function to cleanup stuck secrets
cleanup_stuck_secrets() {
    log INFO "Checking for stuck Helm secrets in monitoring namespace..."
    
    local helm_secrets
    helm_secrets=$(kubectl get secrets -n monitoring --no-headers 2>/dev/null | grep "sh.helm.release" | awk '{print $1}' || true)
    
    if [[ -n "$helm_secrets" ]]; then
        log WARN "Found Helm secrets, cleaning up..."
        for secret in $helm_secrets; do
            log INFO "Deleting Helm secret: $secret"
            kubectl delete secret "$secret" -n monitoring --force --grace-period=0 || true
        done
    else
        log SUCCESS "No stuck Helm secrets found"
    fi
}

# Function to suspend monitoring kustomization
suspend_monitoring_kustomization() {
    log INFO "Suspending monitoring kustomization to prevent interference..."
    kubectl patch kustomization monitoring -n flux-system -p '{"spec":{"suspend":true}}' --type=merge || true
    sleep 2
}

# Function to resume monitoring kustomization
resume_monitoring_kustomization() {
    log INFO "Resuming monitoring kustomization..."
    kubectl patch kustomization monitoring -n flux-system -p '{"spec":{"suspend":false}}' --type=merge || true
}

# Main cleanup function
main() {
    log INFO "Starting cleanup of stuck monitoring resources..."
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log ERROR "kubectl is required but not installed"
        exit 1
    fi
    
    # Check if monitoring namespace exists
    if ! kubectl get namespace monitoring >/dev/null 2>&1; then
        log INFO "Monitoring namespace doesn't exist, nothing to clean up"
        exit 0
    fi
    
    # Suspend monitoring kustomization
    suspend_monitoring_kustomization
    
    # Cleanup in order
    cleanup_failed_helmreleases
    cleanup_stuck_pvcs
    cleanup_stuck_secrets
    
    # Wait for cleanup to complete
    log INFO "Waiting for cleanup to complete..."
    sleep 10
    
    # Resume monitoring kustomization
    resume_monitoring_kustomization
    
    log SUCCESS "Cleanup completed successfully!"
    log INFO "You can now deploy the hybrid monitoring stack"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi