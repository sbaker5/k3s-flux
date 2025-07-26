#!/bin/bash
# Force Delete Namespace Tool
# Specialized tool for removing stuck namespaces with finalizers
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
LOG_FILE="${SCRIPT_DIR}/force-delete-namespace.log"
BACKUP_DIR="${SCRIPT_DIR}/namespace-backups/$(date +%Y%m%d-%H%M%S)"

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

# Check if namespace exists
namespace_exists() {
    local namespace="$1"
    kubectl get namespace "$namespace" &>/dev/null
}

# Check if namespace is stuck in terminating state
is_namespace_terminating() {
    local namespace="$1"
    local deletion_timestamp
    deletion_timestamp=$(kubectl get namespace "$namespace" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
    [[ "$deletion_timestamp" != "null" && "$deletion_timestamp" != "" ]]
}

# Backup namespace and its resources
backup_namespace() {
    local namespace="$1"
    
    mkdir -p "$BACKUP_DIR"
    log "INFO" "Creating backup of namespace $namespace in $BACKUP_DIR"
    
    # Backup namespace definition
    kubectl get namespace "$namespace" -o yaml > "$BACKUP_DIR/namespace-${namespace}.yaml" 2>/dev/null || {
        log "WARNING" "Failed to backup namespace definition"
    }
    
    # Backup all resources in the namespace
    log "INFO" "Backing up all resources in namespace $namespace"
    
    # Get all API resources that are namespaced
    local api_resources
    api_resources=$(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null || true)
    
    if [[ -n "$api_resources" ]]; then
        while IFS= read -r resource_type; do
            if [[ -n "$resource_type" ]]; then
                local resources
                resources=$(kubectl get "$resource_type" -n "$namespace" -o name 2>/dev/null || true)
                
                if [[ -n "$resources" ]]; then
                    log "INFO" "Backing up $resource_type resources"
                    kubectl get "$resource_type" -n "$namespace" -o yaml > "$BACKUP_DIR/${resource_type}-${namespace}.yaml" 2>/dev/null || {
                        log "WARNING" "Failed to backup $resource_type resources"
                    }
                fi
            fi
        done <<< "$api_resources"
    fi
    
    log "INFO" "Backup completed for namespace $namespace"
}

# Remove finalizers from all resources in namespace
remove_resource_finalizers() {
    local namespace="$1"
    
    log "INFO" "Removing finalizers from all resources in namespace $namespace"
    
    # Get all API resources that are namespaced and support finalizers
    local api_resources
    api_resources=$(kubectl api-resources --verbs=list,patch --namespaced -o name 2>/dev/null || true)
    
    if [[ -n "$api_resources" ]]; then
        while IFS= read -r resource_type; do
            if [[ -n "$resource_type" ]]; then
                local resources
                resources=$(kubectl get "$resource_type" -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
                
                if [[ -n "$resources" ]]; then
                    while IFS= read -r resource_name; do
                        if [[ -n "$resource_name" ]]; then
                            log "INFO" "Removing finalizers from ${resource_type}/${resource_name}"
                            kubectl patch "$resource_type" "$resource_name" -n "$namespace" \
                                -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || {
                                log "WARNING" "Failed to remove finalizers from ${resource_type}/${resource_name}"
                            }
                        fi
                    done <<< "$resources"
                fi
            fi
        done <<< "$api_resources"
    fi
    
    log "INFO" "Completed finalizer removal for resources in namespace $namespace"
}

# Remove finalizers from namespace itself
remove_namespace_finalizers() {
    local namespace="$1"
    
    log "INFO" "Removing finalizers from namespace $namespace"
    
    # Get current finalizers
    local finalizers
    finalizers=$(kubectl get namespace "$namespace" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "[]")
    
    if [[ "$finalizers" != "[]" && "$finalizers" != "" ]]; then
        log "INFO" "Current finalizers: $finalizers"
        
        # Remove all finalizers
        kubectl patch namespace "$namespace" -p '{"metadata":{"finalizers":null}}' --type=merge || {
            log "ERROR" "Failed to remove finalizers from namespace $namespace"
            return 1
        }
        
        log "INFO" "Successfully removed finalizers from namespace $namespace"
    else
        log "INFO" "No finalizers found on namespace $namespace"
    fi
}

# Force delete namespace using direct API call
force_delete_namespace_api() {
    local namespace="$1"
    
    log "INFO" "Attempting force deletion via Kubernetes API"
    
    # Get the namespace UID for the API call
    local namespace_uid
    namespace_uid=$(kubectl get namespace "$namespace" -o jsonpath='{.metadata.uid}' 2>/dev/null || echo "")
    
    if [[ -z "$namespace_uid" ]]; then
        log "ERROR" "Could not get namespace UID"
        return 1
    fi
    
    # Create a temporary file with the finalize request
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << EOF
{
  "kind": "Namespace",
  "apiVersion": "v1",
  "metadata": {
    "name": "$namespace",
    "uid": "$namespace_uid"
  },
  "spec": {
    "finalizers": []
  }
}
EOF
    
    # Make the API call to finalize the namespace
    kubectl replace --raw "/api/v1/namespaces/$namespace/finalize" -f "$temp_file" || {
        log "ERROR" "Failed to finalize namespace via API"
        rm -f "$temp_file"
        return 1
    }
    
    rm -f "$temp_file"
    log "INFO" "Successfully finalized namespace $namespace via API"
}

# Main force delete function
force_delete_namespace() {
    local namespace="$1"
    local skip_backup="${2:-false}"
    
    # Check if namespace exists
    if ! namespace_exists "$namespace"; then
        log "INFO" "Namespace $namespace does not exist"
        return 0
    fi
    
    log "INFO" "Starting force deletion of namespace: $namespace"
    
    # Create backup unless skipped
    if [[ "$skip_backup" != "true" ]]; then
        backup_namespace "$namespace"
    fi
    
    # Check if namespace is already terminating
    if is_namespace_terminating "$namespace"; then
        log "INFO" "Namespace $namespace is already in terminating state"
    else
        log "INFO" "Initiating deletion of namespace $namespace"
        kubectl delete namespace "$namespace" --timeout=30s &>/dev/null || {
            log "WARNING" "Initial deletion command failed or timed out"
        }
    fi
    
    # Wait a moment for normal deletion to potentially complete
    sleep 5
    
    # Check if namespace still exists
    if ! namespace_exists "$namespace"; then
        log "INFO" "Namespace $namespace successfully deleted"
        return 0
    fi
    
    log "INFO" "Namespace still exists, proceeding with force deletion"
    
    # Step 1: Remove finalizers from all resources in the namespace
    remove_resource_finalizers "$namespace"
    
    # Step 2: Remove finalizers from the namespace itself
    remove_namespace_finalizers "$namespace"
    
    # Step 3: Wait and check if deletion completed
    log "INFO" "Waiting for namespace deletion to complete..."
    local attempts=0
    local max_attempts=12  # 1 minute total
    
    while [[ $attempts -lt $max_attempts ]]; do
        if ! namespace_exists "$namespace"; then
            log "INFO" "Namespace $namespace successfully deleted"
            return 0
        fi
        
        sleep 5
        ((attempts++))
        log "INFO" "Waiting... (attempt $attempts/$max_attempts)"
    done
    
    # Step 4: If still stuck, try API finalization
    if namespace_exists "$namespace"; then
        log "WARNING" "Namespace still exists after finalizer removal, trying API finalization"
        force_delete_namespace_api "$namespace" || {
            log "ERROR" "API finalization failed"
        }
        
        # Final check
        sleep 5
        if namespace_exists "$namespace"; then
            log "ERROR" "Namespace $namespace could not be deleted. Manual intervention may be required."
            log "ERROR" "Check for remaining resources or contact cluster administrator."
            return 1
        fi
    fi
    
    log "INFO" "Successfully force deleted namespace: $namespace"
    return 0
}

# List stuck namespaces
list_stuck_namespaces() {
    log "INFO" "Scanning for stuck namespaces..."
    
    local stuck_namespaces
    stuck_namespaces=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1}' || true)
    
    if [[ -z "$stuck_namespaces" ]]; then
        echo -e "${GREEN}No stuck namespaces found${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Found stuck namespaces:${NC}"
    while IFS= read -r namespace; do
        if [[ -n "$namespace" ]]; then
            local age
            age=$(kubectl get namespace "$namespace" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "unknown")
            echo -e "  ${RED}$namespace${NC} (created: $age)"
        fi
    done <<< "$stuck_namespaces"
    
    return 0
}

# Display usage information
usage() {
    cat << EOF
Force Delete Namespace Tool

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    delete <namespace>            Force delete a specific namespace
    list                          List all stuck (terminating) namespaces
    cleanup-all                   Force delete all stuck namespaces

Options:
    --skip-backup                 Skip backup creation (faster but less safe)
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose logging

Examples:
    $0 delete stuck-namespace
    $0 list
    $0 cleanup-all
    $0 delete test-namespace --skip-backup

Backup Location: $BACKUP_DIR
Log File: $LOG_FILE

WARNING: This tool will permanently delete namespaces and all their resources.
Always ensure you have proper backups before running these commands.
EOF
}

# Cleanup all stuck namespaces
cleanup_all_stuck_namespaces() {
    local skip_backup="${1:-false}"
    
    log "INFO" "Starting cleanup of all stuck namespaces"
    
    local stuck_namespaces
    stuck_namespaces=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1}' || true)
    
    if [[ -z "$stuck_namespaces" ]]; then
        log "INFO" "No stuck namespaces found"
        return 0
    fi
    
    echo -e "${YELLOW}Found stuck namespaces: $(echo "$stuck_namespaces" | tr '\n' ' ')${NC}"
    read -p "Are you sure you want to force delete ALL these namespaces? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    local success_count=0
    local failure_count=0
    
    while IFS= read -r namespace; do
        if [[ -n "$namespace" ]]; then
            log "INFO" "Processing namespace: $namespace"
            if force_delete_namespace "$namespace" "$skip_backup"; then
                ((success_count++))
            else
                ((failure_count++))
            fi
        fi
    done <<< "$stuck_namespaces"
    
    log "INFO" "Cleanup completed. Success: $success_count, Failures: $failure_count"
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
    
    local skip_backup="false"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-backup)
                skip_backup="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is required but not installed"
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to Kubernetes cluster"
    fi
    
    log "INFO" "Starting force delete namespace operation: $command"
    
    # Execute command
    case "$command" in
        "delete")
            if [[ $# -ne 1 ]]; then
                error_exit "Usage: $0 delete <namespace-name>"
            fi
            force_delete_namespace "$1" "$skip_backup"
            ;;
        "list")
            list_stuck_namespaces
            ;;
        "cleanup-all")
            cleanup_all_stuck_namespaces "$skip_backup"
            ;;
        *)
            error_exit "Unknown command: $command. Use -h for help."
            ;;
    esac
    
    log "INFO" "Operation completed successfully"
}

# Run main function
main "$@"