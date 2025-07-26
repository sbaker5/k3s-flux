#!/bin/bash
# Emergency Resource Cleanup Tool
# Provides safe emergency cleanup procedures for stuck Kubernetes resources
# Requirements: 7.2, 7.3

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/emergency-cleanup.log"
BACKUP_DIR="${SCRIPT_DIR}/emergency-backups/$(date +%Y%m%d-%H%M%S)"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Warning with confirmation
warn_and_confirm() {
    local message="$1"
    log "WARNING" "$message"
    echo -e "${YELLOW}WARNING: ${message}${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is required but not installed"
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to Kubernetes cluster"
    fi
    
    # Check permissions
    if ! kubectl auth can-i delete pods --all-namespaces &> /dev/null; then
        error_exit "Insufficient permissions for emergency cleanup operations"
    fi
    
    log "INFO" "Prerequisites check passed"
}

# Create backup directory
create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    log "INFO" "Created backup directory: $BACKUP_DIR"
}

# Backup resource before deletion
backup_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    
    local backup_file="${BACKUP_DIR}/${resource_type}-${resource_name}"
    if [[ -n "$namespace" ]]; then
        backup_file="${backup_file}-${namespace}"
    fi
    backup_file="${backup_file}.yaml"
    
    log "INFO" "Backing up ${resource_type}/${resource_name} to ${backup_file}"
    
    if [[ -n "$namespace" ]]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" -o yaml > "$backup_file" 2>/dev/null || {
            log "WARNING" "Failed to backup ${resource_type}/${resource_name} in namespace ${namespace}"
            return 1
        }
    else
        kubectl get "$resource_type" "$resource_name" -o yaml > "$backup_file" 2>/dev/null || {
            log "WARNING" "Failed to backup ${resource_type}/${resource_name}"
            return 1
        }
    fi
    
    log "INFO" "Successfully backed up ${resource_type}/${resource_name}"
}

# Remove finalizers from a resource
remove_finalizers() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    
    log "INFO" "Removing finalizers from ${resource_type}/${resource_name}"
    
    # Backup first
    backup_resource "$resource_type" "$resource_name" "$namespace"
    
    local patch='{"metadata":{"finalizers":null}}'
    
    if [[ -n "$namespace" ]]; then
        kubectl patch "$resource_type" "$resource_name" -n "$namespace" -p "$patch" --type=merge || {
            log "ERROR" "Failed to remove finalizers from ${resource_type}/${resource_name} in namespace ${namespace}"
            return 1
        }
    else
        kubectl patch "$resource_type" "$resource_name" -p "$patch" --type=merge || {
            log "ERROR" "Failed to remove finalizers from ${resource_type}/${resource_name}"
            return 1
        }
    fi
    
    log "INFO" "Successfully removed finalizers from ${resource_type}/${resource_name}"
}

# Force delete a resource
force_delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    
    log "INFO" "Force deleting ${resource_type}/${resource_name}"
    
    # Backup first
    backup_resource "$resource_type" "$resource_name" "$namespace"
    
    # Try graceful deletion first
    if [[ -n "$namespace" ]]; then
        kubectl delete "$resource_type" "$resource_name" -n "$namespace" --timeout=30s 2>/dev/null || {
            log "WARNING" "Graceful deletion failed, attempting force deletion"
            kubectl delete "$resource_type" "$resource_name" -n "$namespace" --force --grace-period=0 || {
                log "ERROR" "Force deletion failed for ${resource_type}/${resource_name} in namespace ${namespace}"
                return 1
            }
        }
    else
        kubectl delete "$resource_type" "$resource_name" --timeout=30s 2>/dev/null || {
            log "WARNING" "Graceful deletion failed, attempting force deletion"
            kubectl delete "$resource_type" "$resource_name" --force --grace-period=0 || {
                log "ERROR" "Force deletion failed for ${resource_type}/${resource_name}"
                return 1
            }
        }
    fi
    
    log "INFO" "Successfully deleted ${resource_type}/${resource_name}"
}

# Clean up stuck namespace
cleanup_stuck_namespace() {
    local namespace="$1"
    
    warn_and_confirm "This will force cleanup namespace '$namespace' and all its resources"
    
    log "INFO" "Starting emergency cleanup of namespace: $namespace"
    
    # Backup namespace definition
    backup_resource "namespace" "$namespace"
    
    # Get all resources in the namespace
    log "INFO" "Discovering resources in namespace $namespace"
    local resources
    resources=$(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | xargs -n 1 kubectl get --show-kind --ignore-not-found -n "$namespace" 2>/dev/null | grep -v "No resources found" | awk '{print $1}' | grep -v "NAME" || true)
    
    # Remove finalizers from all resources
    if [[ -n "$resources" ]]; then
        log "INFO" "Removing finalizers from resources in namespace $namespace"
        while IFS= read -r resource; do
            if [[ -n "$resource" ]]; then
                local resource_type="${resource%/*}"
                local resource_name="${resource#*/}"
                remove_finalizers "$resource_type" "$resource_name" "$namespace" || true
            fi
        done <<< "$resources"
    fi
    
    # Force delete the namespace
    log "INFO" "Force deleting namespace $namespace"
    kubectl delete namespace "$namespace" --timeout=60s 2>/dev/null || {
        log "WARNING" "Graceful namespace deletion failed, removing finalizers"
        remove_finalizers "namespace" "$namespace"
        
        # Wait a bit and check if it's gone
        sleep 5
        if kubectl get namespace "$namespace" &>/dev/null; then
            log "ERROR" "Namespace $namespace still exists after cleanup attempts"
            return 1
        fi
    }
    
    log "INFO" "Successfully cleaned up namespace: $namespace"
}

# Clean up stuck pods
cleanup_stuck_pods() {
    local namespace="${1:-}"
    local selector="${2:-}"
    
    local kubectl_args=()
    if [[ -n "$namespace" ]]; then
        kubectl_args+=("-n" "$namespace")
        log "INFO" "Cleaning up stuck pods in namespace: $namespace"
    else
        kubectl_args+=("--all-namespaces")
        log "INFO" "Cleaning up stuck pods in all namespaces"
    fi
    
    if [[ -n "$selector" ]]; then
        kubectl_args+=("-l" "$selector")
        log "INFO" "Using selector: $selector"
    fi
    
    warn_and_confirm "This will force delete stuck pods"
    
    # Find stuck pods (Terminating, Unknown, or old Failed pods)
    local stuck_pods
    stuck_pods=$(kubectl get pods "${kubectl_args[@]}" --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -E "(Terminating|Unknown|Failed)" || true)
    
    if [[ -z "$stuck_pods" ]]; then
        log "INFO" "No stuck pods found"
        return 0
    fi
    
    log "INFO" "Found stuck pods:"
    echo "$stuck_pods"
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local pod_namespace=$(echo "$line" | awk '{print $1}')
            local pod_name=$(echo "$line" | awk '{print $2}')
            local pod_phase=$(echo "$line" | awk '{print $3}')
            
            log "INFO" "Force deleting stuck pod: $pod_name in namespace $pod_namespace (phase: $pod_phase)"
            force_delete_resource "pod" "$pod_name" "$pod_namespace" || true
        fi
    done <<< "$stuck_pods"
    
    log "INFO" "Completed stuck pods cleanup"
}

# Clean up stuck PVCs
cleanup_stuck_pvcs() {
    local namespace="${1:-}"
    
    local kubectl_args=()
    if [[ -n "$namespace" ]]; then
        kubectl_args+=("-n" "$namespace")
        log "INFO" "Cleaning up stuck PVCs in namespace: $namespace"
    else
        kubectl_args+=("--all-namespaces")
        log "INFO" "Cleaning up stuck PVCs in all namespaces"
    fi
    
    warn_and_confirm "This will force delete stuck PVCs (data may be lost)"
    
    # Find PVCs in Terminating state
    local stuck_pvcs
    stuck_pvcs=$(kubectl get pvc "${kubectl_args[@]}" -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1 " " $2}' || true)
    
    if [[ -z "$stuck_pvcs" ]]; then
        log "INFO" "No stuck PVCs found"
        return 0
    fi
    
    log "INFO" "Found stuck PVCs:"
    echo "$stuck_pvcs"
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local pvc_namespace=$(echo "$line" | awk '{print $1}')
            local pvc_name=$(echo "$line" | awk '{print $2}')
            
            log "INFO" "Removing finalizers from stuck PVC: $pvc_name in namespace $pvc_namespace"
            remove_finalizers "pvc" "$pvc_name" "$pvc_namespace" || true
        fi
    done <<< "$stuck_pvcs"
    
    log "INFO" "Completed stuck PVCs cleanup"
}

# Clean up stuck Flux resources
cleanup_stuck_flux_resources() {
    local namespace="${1:-flux-system}"
    
    log "INFO" "Cleaning up stuck Flux resources in namespace: $namespace"
    warn_and_confirm "This will force cleanup stuck Flux Kustomizations and HelmReleases"
    
    # Clean up stuck Kustomizations
    local stuck_kustomizations
    stuck_kustomizations=$(kubectl get kustomizations -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1}' || true)
    
    if [[ -n "$stuck_kustomizations" ]]; then
        log "INFO" "Found stuck Kustomizations: $stuck_kustomizations"
        while IFS= read -r kustomization; do
            if [[ -n "$kustomization" ]]; then
                log "INFO" "Removing finalizers from Kustomization: $kustomization"
                remove_finalizers "kustomization" "$kustomization" "$namespace" || true
            fi
        done <<< "$stuck_kustomizations"
    fi
    
    # Clean up stuck HelmReleases
    local stuck_helmreleases
    stuck_helmreleases=$(kubectl get helmreleases -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1}' || true)
    
    if [[ -n "$stuck_helmreleases" ]]; then
        log "INFO" "Found stuck HelmReleases: $stuck_helmreleases"
        while IFS= read -r helmrelease; do
            if [[ -n "$helmrelease" ]]; then
                log "INFO" "Removing finalizers from HelmRelease: $helmrelease"
                remove_finalizers "helmrelease" "$helmrelease" "$namespace" || true
            fi
        done <<< "$stuck_helmreleases"
    fi
    
    log "INFO" "Completed Flux resources cleanup"
}

# Display usage information
usage() {
    cat << EOF
Emergency Resource Cleanup Tool

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    namespace <name>              Clean up stuck namespace and all its resources
    pods [namespace] [selector]   Clean up stuck pods (optionally in specific namespace/with selector)
    pvcs [namespace]              Clean up stuck PVCs (optionally in specific namespace)
    flux [namespace]              Clean up stuck Flux resources (default: flux-system)
    finalizers <type> <name> [ns] Remove finalizers from specific resource
    force-delete <type> <name> [ns] Force delete specific resource

Options:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose logging

Examples:
    $0 namespace stuck-namespace
    $0 pods default app=nginx
    $0 pvcs longhorn-system
    $0 flux
    $0 finalizers deployment nginx-deployment default
    $0 force-delete pod stuck-pod kube-system

Backup Location: $BACKUP_DIR
Log File: $LOG_FILE

WARNING: These are emergency procedures that can cause data loss.
Always ensure you have proper backups before running these commands.
EOF
}

# Main function
main() {
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    # Handle help
    if [[ "$command" == "-h" || "$command" == "--help" ]]; then
        usage
        exit 0
    fi
    
    # Initialize
    check_prerequisites
    create_backup_dir
    
    log "INFO" "Starting emergency cleanup operation: $command"
    
    # Execute command
    case "$command" in
        "namespace")
            if [[ $# -ne 1 ]]; then
                error_exit "Usage: $0 namespace <namespace-name>"
            fi
            cleanup_stuck_namespace "$1"
            ;;
        "pods")
            cleanup_stuck_pods "${1:-}" "${2:-}"
            ;;
        "pvcs")
            cleanup_stuck_pvcs "${1:-}"
            ;;
        "flux")
            cleanup_stuck_flux_resources "${1:-flux-system}"
            ;;
        "finalizers")
            if [[ $# -lt 2 ]]; then
                error_exit "Usage: $0 finalizers <resource-type> <resource-name> [namespace]"
            fi
            remove_finalizers "$1" "$2" "${3:-}"
            ;;
        "force-delete")
            if [[ $# -lt 2 ]]; then
                error_exit "Usage: $0 force-delete <resource-type> <resource-name> [namespace]"
            fi
            force_delete_resource "$1" "$2" "${3:-}"
            ;;
        *)
            error_exit "Unknown command: $command. Use -h for help."
            ;;
    esac
    
    log "INFO" "Emergency cleanup operation completed successfully"
    echo -e "${GREEN}Emergency cleanup completed. Backups saved to: $BACKUP_DIR${NC}"
}

# Run main function
main "$@"