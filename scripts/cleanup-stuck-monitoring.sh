#!/bin/bash
# Monitoring System Cleanup Tool
# Automated cleanup script for monitoring namespace and resources
# Requirements: 1.1, 1.2, 1.3, 1.4

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
LOG_FILE="${SCRIPT_DIR}/monitoring-cleanup.log"
BACKUP_DIR="${SCRIPT_DIR}/monitoring-backups/$(date +%Y%m%d-%H%M%S)"
MONITORING_NAMESPACE="monitoring"

# Monitoring-specific CRDs that might cause issues
MONITORING_CRDS=(
    "prometheuses.monitoring.coreos.com"
    "prometheusrules.monitoring.coreos.com"
    "servicemonitors.monitoring.coreos.com"
    "podmonitors.monitoring.coreos.com"
    "alertmanagers.monitoring.coreos.com"
    "thanosrulers.monitoring.coreos.com"
)

# Monitoring components that might get stuck
MONITORING_COMPONENTS=(
    "prometheus"
    "grafana"
    "alertmanager"
    "kube-state-metrics"
    "node-exporter"
    "prometheus-operator"
)

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
    log "INFO" "Checking prerequisites for monitoring cleanup..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is required but not installed"
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to Kubernetes cluster"
    fi
    
    # Check permissions
    if ! kubectl auth can-i delete namespace --all-namespaces &> /dev/null; then
        error_exit "Insufficient permissions for monitoring cleanup operations"
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

# Assess monitoring system health
assess_monitoring_health() {
    echo -e "${BLUE}=== Monitoring System Health Assessment ===${NC}"
    log "INFO" "Starting monitoring system health assessment"
    
    # Check if monitoring namespace exists
    if kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        echo -e "${CYAN}Monitoring namespace status:${NC}"
        local ns_status
        ns_status=$(kubectl get namespace "$MONITORING_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local deletion_timestamp
        deletion_timestamp=$(kubectl get namespace "$MONITORING_NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
        
        if [[ "$deletion_timestamp" != "null" ]]; then
            echo -e "  ${RED}❌${NC} Namespace is stuck in Terminating state"
            log "WARNING" "Monitoring namespace is stuck in Terminating state"
        elif [[ "$ns_status" == "Active" ]]; then
            echo -e "  ${GREEN}✓${NC} Namespace is Active"
        else
            echo -e "  ${YELLOW}⚠${NC} Namespace status: $ns_status"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Monitoring namespace does not exist"
        log "INFO" "Monitoring namespace does not exist"
    fi
    echo
    
    # Check monitoring pods
    echo -e "${CYAN}Monitoring pods status:${NC}"
    if kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        local pods_output
        pods_output=$(kubectl get pods -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null || echo "")
        
        if [[ -z "$pods_output" ]]; then
            echo -e "  ${YELLOW}⚠${NC} No pods found in monitoring namespace"
        else
            local total_pods=0
            local ready_pods=0
            local stuck_pods=0
            
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
                            echo -e "    ${GREEN}✓${NC} $pod_name: $status ($ready_status)"
                        else
                            echo -e "    ${YELLOW}⚠${NC} $pod_name: $status ($ready_status)"
                        fi
                    elif [[ "$status" =~ ^(Terminating|Unknown|Failed|CrashLoopBackOff|ImagePullBackOff)$ ]]; then
                        stuck_pods=$((stuck_pods + 1))
                        echo -e "    ${RED}❌${NC} $pod_name: $status ($ready_status)"
                    else
                        echo -e "    ${YELLOW}⚠${NC} $pod_name: $status ($ready_status)"
                    fi
                fi
            done <<< "$pods_output"
            
            echo -e "  Summary: ${ready_pods}/${total_pods} pods ready, ${stuck_pods} stuck"
            if [[ $stuck_pods -gt 0 ]]; then
                log "WARNING" "Found $stuck_pods stuck monitoring pods"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Cannot check pods - namespace does not exist"
    fi
    echo    
 
   # Check monitoring PVCs
    echo -e "${CYAN}Monitoring PVCs status:${NC}"
    if kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        local pvcs_output
        pvcs_output=$(kubectl get pvc -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null || echo "")
        
        if [[ -z "$pvcs_output" ]]; then
            echo -e "  ${GREEN}✓${NC} No PVCs found (ephemeral storage configuration)"
        else
            local stuck_pvcs=0
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    local pvc_name=$(echo "$line" | awk '{print $1}')
                    local status=$(echo "$line" | awk '{print $2}')
                    local deletion_timestamp
                    deletion_timestamp=$(kubectl get pvc "$pvc_name" -n "$MONITORING_NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
                    
                    if [[ "$deletion_timestamp" != "null" ]]; then
                        stuck_pvcs=$((stuck_pvcs + 1))
                        echo -e "    ${RED}❌${NC} $pvc_name: Terminating"
                    elif [[ "$status" == "Bound" ]]; then
                        echo -e "    ${GREEN}✓${NC} $pvc_name: $status"
                    else
                        echo -e "    ${YELLOW}⚠${NC} $pvc_name: $status"
                    fi
                fi
            done <<< "$pvcs_output"
            
            if [[ $stuck_pvcs -gt 0 ]]; then
                log "WARNING" "Found $stuck_pvcs stuck monitoring PVCs"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Cannot check PVCs - namespace does not exist"
    fi
    echo
    
    # Check monitoring CRDs
    echo -e "${CYAN}Monitoring CRDs status:${NC}"
    local problematic_crds=0
    for crd in "${MONITORING_CRDS[@]}"; do
        if kubectl get crd "$crd" &>/dev/null; then
            local deletion_timestamp
            deletion_timestamp=$(kubectl get crd "$crd" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
            
            if [[ "$deletion_timestamp" != "null" ]]; then
                problematic_crds=$((problematic_crds + 1))
                echo -e "    ${RED}❌${NC} $crd: Terminating"
            else
                echo -e "    ${GREEN}✓${NC} $crd: Available"
            fi
        else
            echo -e "    ${YELLOW}⚠${NC} $crd: Not found"
        fi
    done
    
    if [[ $problematic_crds -gt 0 ]]; then
        log "WARNING" "Found $problematic_crds problematic monitoring CRDs"
    fi
    echo
    
    # Check Flux monitoring resources
    echo -e "${CYAN}Flux monitoring resources status:${NC}"
    if kubectl get namespace flux-system &>/dev/null; then
        # Check ServiceMonitor
        if kubectl get servicemonitor -n "$MONITORING_NAMESPACE" flux-controllers-with-services &>/dev/null; then
            echo -e "    ${GREEN}✓${NC} Flux ServiceMonitor exists"
        else
            echo -e "    ${YELLOW}⚠${NC} Flux ServiceMonitor not found"
        fi
        
        # Check PodMonitor
        if kubectl get podmonitor -n "$MONITORING_NAMESPACE" flux-controllers-pods &>/dev/null; then
            echo -e "    ${GREEN}✓${NC} Flux PodMonitor exists"
        else
            echo -e "    ${YELLOW}⚠${NC} Flux PodMonitor not found"
        fi
    else
        echo -e "    ${YELLOW}⚠${NC} Flux system not available"
    fi
    echo
    
    log "INFO" "Monitoring system health assessment completed"
}

# Detect stuck monitoring resources
detect_stuck_resources() {
    log "INFO" "Detecting stuck monitoring resources"
    
    local stuck_resources=()
    
    # Check for stuck namespace
    if kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        local deletion_timestamp
        deletion_timestamp=$(kubectl get namespace "$MONITORING_NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
        if [[ "$deletion_timestamp" != "null" ]]; then
            stuck_resources+=("namespace:$MONITORING_NAMESPACE")
        fi
    fi
    
    # Check for stuck pods
    local stuck_pods
    stuck_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -E "(Terminating|Unknown|Failed)" | awk '{print $1}' || true)
    
    if [[ -n "$stuck_pods" ]]; then
        while IFS= read -r pod; do
            if [[ -n "$pod" ]]; then
                stuck_resources+=("pod:$pod")
            fi
        done <<< "$stuck_pods"
    fi
    
    # Check for stuck PVCs
    local stuck_pvcs
    stuck_pvcs=$(kubectl get pvc -n "$MONITORING_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1}' || true)
    
    if [[ -n "$stuck_pvcs" ]]; then
        while IFS= read -r pvc; do
            if [[ -n "$pvc" ]]; then
                stuck_resources+=("pvc:$pvc")
            fi
        done <<< "$stuck_pvcs"
    fi
    
    # Check for stuck CRDs
    for crd in "${MONITORING_CRDS[@]}"; do
        if kubectl get crd "$crd" &>/dev/null; then
            local deletion_timestamp
            deletion_timestamp=$(kubectl get crd "$crd" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
            if [[ "$deletion_timestamp" != "null" ]]; then
                stuck_resources+=("crd:$crd")
            fi
        fi
    done
    
    if [[ ${#stuck_resources[@]} -gt 0 ]]; then
        echo -e "${RED}Found ${#stuck_resources[@]} stuck monitoring resources:${NC}"
        for resource in "${stuck_resources[@]}"; do
            echo "  - $resource"
        done
        log "WARNING" "Found ${#stuck_resources[@]} stuck monitoring resources"
        return 1
    else
        echo -e "${GREEN}No stuck monitoring resources detected${NC}"
        log "INFO" "No stuck monitoring resources detected"
        return 0
    fi
}

# Clean up stuck monitoring namespace
cleanup_monitoring_namespace() {
    log "INFO" "Starting monitoring namespace cleanup"
    warn_and_confirm "This will force cleanup the monitoring namespace and all its resources"
    
    if ! kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
        log "INFO" "Monitoring namespace does not exist, nothing to clean up"
        return 0
    fi
    
    # Backup namespace definition
    backup_resource "namespace" "$MONITORING_NAMESPACE"
    
    # Stop any running port-forwards to monitoring services
    echo -e "${CYAN}Stopping monitoring port-forwards...${NC}"
    pkill -f "kubectl.*port-forward.*monitoring" || true
    pkill -f "kubectl.*port-forward.*prometheus" || true
    pkill -f "kubectl.*port-forward.*grafana" || true
    
    # Scale down monitoring deployments gracefully first
    echo -e "${CYAN}Scaling down monitoring deployments...${NC}"
    for component in "${MONITORING_COMPONENTS[@]}"; do
        local deployments
        deployments=$(kubectl get deployments -n "$MONITORING_NAMESPACE" -o name 2>/dev/null | grep -i "$component" || true)
        if [[ -n "$deployments" ]]; then
            while IFS= read -r deployment; do
                if [[ -n "$deployment" ]]; then
                    log "INFO" "Scaling down $deployment"
                    kubectl scale "$deployment" --replicas=0 -n "$MONITORING_NAMESPACE" --timeout=30s || true
                fi
            done <<< "$deployments"
        fi
    done
    
    # Wait a moment for graceful shutdown
    sleep 10
    
    # Remove finalizers from stuck PVCs first
    echo -e "${CYAN}Cleaning up stuck PVCs...${NC}"
    local stuck_pvcs
    stuck_pvcs=$(kubectl get pvc -n "$MONITORING_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1}' || true)
    
    if [[ -n "$stuck_pvcs" ]]; then
        while IFS= read -r pvc; do
            if [[ -n "$pvc" ]]; then
                log "INFO" "Removing finalizers from PVC: $pvc"
                backup_resource "pvc" "$pvc" "$MONITORING_NAMESPACE"
                kubectl patch pvc "$pvc" -n "$MONITORING_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge || true
            fi
        done <<< "$stuck_pvcs"
    fi
    
    # Force delete stuck pods
    echo -e "${CYAN}Cleaning up stuck pods...${NC}"
    local stuck_pods
    stuck_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | grep -E "(Terminating|Unknown|Failed)" || true)
    
    if [[ -n "$stuck_pods" ]]; then
        while IFS= read -r pod; do
            if [[ -n "$pod" ]]; then
                local pod_name="${pod#pod/}"
                log "INFO" "Force deleting stuck pod: $pod_name"
                backup_resource "pod" "$pod_name" "$MONITORING_NAMESPACE"
                kubectl delete "$pod" -n "$MONITORING_NAMESPACE" --force --grace-period=0 || true
            fi
        done <<< "$stuck_pods"
    fi  
  
    # Remove finalizers from all remaining resources
    echo -e "${CYAN}Removing finalizers from remaining resources...${NC}"
    local all_resources
    all_resources=$(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | xargs -I {} kubectl get {} -n "$MONITORING_NAMESPACE" --ignore-not-found -o name 2>/dev/null || true)
    
    if [[ -n "$all_resources" ]]; then
        while IFS= read -r resource; do
            if [[ -n "$resource" ]]; then
                log "INFO" "Removing finalizers from $resource"
                kubectl patch "$resource" -n "$MONITORING_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge || true
            fi
        done <<< "$all_resources"
    fi
    
    # Force delete the namespace
    echo -e "${CYAN}Force deleting monitoring namespace...${NC}"
    kubectl delete namespace "$MONITORING_NAMESPACE" --timeout=60s 2>/dev/null || {
        log "WARNING" "Graceful namespace deletion failed, removing finalizers"
        kubectl patch namespace "$MONITORING_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge || true
        
        # Wait and verify deletion
        sleep 10
        if kubectl get namespace "$MONITORING_NAMESPACE" &>/dev/null; then
            error_exit "Monitoring namespace still exists after cleanup attempts"
        fi
    }
    
    log "INFO" "Successfully cleaned up monitoring namespace"
    echo -e "${GREEN}Monitoring namespace cleanup completed${NC}"
}

# Clean up stuck monitoring CRDs
cleanup_monitoring_crds() {
    log "INFO" "Starting monitoring CRDs cleanup"
    warn_and_confirm "This will force cleanup stuck monitoring CRDs (may affect other monitoring installations)"
    
    local cleaned_crds=0
    
    for crd in "${MONITORING_CRDS[@]}"; do
        if kubectl get crd "$crd" &>/dev/null; then
            local deletion_timestamp
            deletion_timestamp=$(kubectl get crd "$crd" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
            
            if [[ "$deletion_timestamp" != "null" ]]; then
                log "INFO" "Cleaning up stuck CRD: $crd"
                backup_resource "crd" "$crd"
                
                # Remove finalizers
                kubectl patch crd "$crd" -p '{"metadata":{"finalizers":null}}' --type=merge || {
                    log "WARNING" "Failed to remove finalizers from CRD: $crd"
                    continue
                }
                
                # Force delete if still exists
                sleep 5
                if kubectl get crd "$crd" &>/dev/null; then
                    kubectl delete crd "$crd" --force --grace-period=0 || {
                        log "ERROR" "Failed to force delete CRD: $crd"
                        continue
                    }
                fi
                
                cleaned_crds=$((cleaned_crds + 1))
                log "INFO" "Successfully cleaned up CRD: $crd"
            fi
        fi
    done
    
    if [[ $cleaned_crds -gt 0 ]]; then
        echo -e "${GREEN}Cleaned up $cleaned_crds monitoring CRDs${NC}"
        log "INFO" "Cleaned up $cleaned_crds monitoring CRDs"
    else
        echo -e "${GREEN}No stuck monitoring CRDs found${NC}"
        log "INFO" "No stuck monitoring CRDs found"
    fi
}

# Comprehensive monitoring cleanup
comprehensive_monitoring_cleanup() {
    log "INFO" "Starting comprehensive monitoring cleanup"
    warn_and_confirm "This will perform a complete monitoring system cleanup (namespace, CRDs, resources)"
    
    echo -e "${BLUE}=== Comprehensive Monitoring Cleanup ===${NC}"
    
    # Step 1: Clean up monitoring namespace
    echo -e "${CYAN}Step 1: Cleaning up monitoring namespace...${NC}"
    cleanup_monitoring_namespace
    echo
    
    # Step 2: Clean up stuck CRDs
    echo -e "${CYAN}Step 2: Cleaning up stuck monitoring CRDs...${NC}"
    cleanup_monitoring_crds
    echo
    
    # Step 3: Verify cleanup
    echo -e "${CYAN}Step 3: Verifying cleanup...${NC}"
    sleep 5
    
    if detect_stuck_resources; then
        echo -e "${GREEN}✓ Comprehensive monitoring cleanup completed successfully${NC}"
        log "INFO" "Comprehensive monitoring cleanup completed successfully"
    else
        echo -e "${YELLOW}⚠ Some resources may still be stuck, manual intervention may be required${NC}"
        log "WARNING" "Some resources may still be stuck after comprehensive cleanup"
    fi
    
    echo -e "${BLUE}Cleanup completed. Backups saved to: $BACKUP_DIR${NC}"
}

# Display usage information
usage() {
    cat << EOF
Monitoring System Cleanup Tool

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    assess                        Assess monitoring system health and detect issues
    detect                        Detect stuck monitoring resources
    namespace                     Clean up stuck monitoring namespace and all resources
    crds                          Clean up stuck monitoring CRDs
    comprehensive                 Perform complete monitoring system cleanup
    
Options:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose logging

Examples:
    $0 assess                     # Assess monitoring system health
    $0 detect                     # Detect stuck resources
    $0 namespace                  # Clean up monitoring namespace
    $0 comprehensive              # Complete cleanup

Backup Location: $BACKUP_DIR
Log File: $LOG_FILE

WARNING: These operations can cause monitoring data loss.
Always ensure you have proper backups before running cleanup commands.
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
    
    # Handle verbose mode
    if [[ "$command" == "-v" || "$command" == "--verbose" ]]; then
        set -x
        if [[ $# -gt 0 ]]; then
            command="$1"
            shift
        else
            usage
            exit 1
        fi
    fi
    
    # Initialize
    check_prerequisites
    create_backup_dir
    
    log "INFO" "Starting monitoring cleanup operation: $command"
    
    # Execute command
    case "$command" in
        "assess")
            assess_monitoring_health
            ;;
        "detect")
            detect_stuck_resources
            ;;
        "namespace")
            cleanup_monitoring_namespace
            ;;
        "crds")
            cleanup_monitoring_crds
            ;;
        "comprehensive")
            comprehensive_monitoring_cleanup
            ;;
        *)
            error_exit "Unknown command: $command. Use -h for help."
            ;;
    esac
    
    log "INFO" "Monitoring cleanup operation completed successfully"
}

# Run main function
main "$@"