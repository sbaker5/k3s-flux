#!/bin/bash
# Emergency CLI Tool
# Unified interface for all emergency cleanup operations
# Requirements: 7.2, 7.3

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
LOG_FILE="${SCRIPT_DIR}/emergency-cli.log"

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

# Check if required tools exist
check_tools() {
    local missing_tools=()
    
    if [[ ! -f "$SCRIPT_DIR/emergency-cleanup.sh" ]]; then
        missing_tools+=("emergency-cleanup.sh")
    fi
    
    if [[ ! -f "$SCRIPT_DIR/force-delete-namespace.sh" ]]; then
        missing_tools+=("force-delete-namespace.sh")
    fi
    
    if [[ ! -f "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" ]]; then
        missing_tools+=("cleanup-stuck-monitoring.sh")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error_exit "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Make scripts executable
    chmod +x "$SCRIPT_DIR/emergency-cleanup.sh"
    chmod +x "$SCRIPT_DIR/force-delete-namespace.sh"
    chmod +x "$SCRIPT_DIR/cleanup-stuck-monitoring.sh"
}

# Display system status
show_status() {
    echo -e "${BLUE}=== Kubernetes Cluster Emergency Status ===${NC}"
    echo
    
    # Cluster info
    echo -e "${CYAN}Cluster Information:${NC}"
    kubectl cluster-info --request-timeout=10s 2>/dev/null || echo -e "${RED}  ❌ Cannot connect to cluster${NC}"
    echo
    
    # Node status
    echo -e "${CYAN}Node Status:${NC}"
    kubectl get nodes -o wide --no-headers 2>/dev/null | while IFS= read -r line; do
        local status=$(echo "$line" | awk '{print $2}')
        local name=$(echo "$line" | awk '{print $1}')
        if [[ "$status" == "Ready" ]]; then
            echo -e "  ${GREEN}✓${NC} $name: $status"
        else
            echo -e "  ${RED}❌${NC} $name: $status"
        fi
    done || echo -e "${RED}  ❌ Cannot get node status${NC}"
    echo
    
    # Stuck namespaces
    echo -e "${CYAN}Stuck Namespaces:${NC}"
    local stuck_namespaces
    stuck_namespaces=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | awk '{print $1}' || true)
    
    if [[ -z "$stuck_namespaces" ]]; then
        echo -e "  ${GREEN}✓${NC} No stuck namespaces found"
    else
        while IFS= read -r namespace; do
            if [[ -n "$namespace" ]]; then
                echo -e "  ${RED}❌${NC} $namespace (terminating)"
            fi
        done <<< "$stuck_namespaces"
    fi
    echo
    
    # Stuck pods
    echo -e "${CYAN}Stuck Pods:${NC}"
    local stuck_pods_count
    stuck_pods_count=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -E "(Terminating|Unknown|Failed)" | wc -l | tr -d ' \n' || echo "0")
    
    if [[ "$stuck_pods_count" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} No stuck pods found"
    else
        echo -e "  ${RED}❌${NC} $stuck_pods_count stuck pods found"
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -E "(Terminating|Unknown|Failed)" | head -5 | while IFS= read -r line; do
            echo -e "    $line"
        done || true
        if [[ "$stuck_pods_count" -gt 5 ]]; then
            echo -e "    ... and $((stuck_pods_count - 5)) more"
        fi
    fi
    echo
    
    # Stuck PVCs
    echo -e "${CYAN}Stuck PVCs:${NC}"
    local stuck_pvcs_count
    stuck_pvcs_count=$(kubectl get pvc --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | wc -l | tr -d ' \n' || echo "0")
    
    if [[ "$stuck_pvcs_count" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} No stuck PVCs found"
    else
        echo -e "  ${RED}❌${NC} $stuck_pvcs_count stuck PVCs found"
    fi
    echo
    
    # Flux status
    echo -e "${CYAN}Flux Status:${NC}"
    if kubectl get namespace flux-system &>/dev/null; then
        local flux_pods_ready
        flux_pods_ready=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | awk '{print $2}' | grep -c "1/1" || echo "0")
        local flux_pods_total
        flux_pods_total=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [[ "$flux_pods_ready" -eq "$flux_pods_total" && "$flux_pods_total" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} Flux controllers running ($flux_pods_ready/$flux_pods_total)"
        else
            echo -e "  ${RED}❌${NC} Flux controllers not ready ($flux_pods_ready/$flux_pods_total)"
        fi
        
        # Check for stuck Flux resources
        local stuck_kustomizations
        stuck_kustomizations=$(kubectl get kustomizations -n flux-system -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "null" | wc -l || echo "0")
        
        if [[ "$stuck_kustomizations" -gt 0 ]]; then
            echo -e "  ${RED}❌${NC} $stuck_kustomizations stuck Kustomizations"
        fi
    else
        echo -e "  ${RED}❌${NC} Flux system namespace not found"
    fi
    echo
    
    # Monitoring status
    echo -e "${CYAN}Monitoring Status:${NC}"
    if kubectl get namespace monitoring &>/dev/null; then
        local monitoring_pods_ready
        monitoring_pods_ready=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | awk '{print $2}' | grep -c "/" | grep -c "1/1\|2/2\|3/3" || echo "0")
        local monitoring_pods_total
        monitoring_pods_total=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [[ "$monitoring_pods_ready" -eq "$monitoring_pods_total" && "$monitoring_pods_total" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} Monitoring pods running ($monitoring_pods_ready/$monitoring_pods_total)"
        else
            echo -e "  ${RED}❌${NC} Monitoring pods not ready ($monitoring_pods_ready/$monitoring_pods_total)"
        fi
        
        # Check for stuck monitoring namespace
        local monitoring_deletion_timestamp
        monitoring_deletion_timestamp=$(kubectl get namespace monitoring -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "null")
        if [[ "$monitoring_deletion_timestamp" != "null" ]]; then
            echo -e "  ${RED}❌${NC} Monitoring namespace stuck in Terminating state"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Monitoring namespace not found"
    fi
    echo
}

# Interactive menu
show_menu() {
    echo -e "${BLUE}=== Emergency Operations Menu ===${NC}"
    echo
    echo "1. Show cluster status"
    echo "2. Clean up stuck namespace"
    echo "3. Clean up stuck pods"
    echo "4. Clean up stuck PVCs"
    echo "5. Clean up stuck Flux resources"
    echo "6. Remove finalizers from resource"
    echo "7. Force delete resource"
    echo "8. List all stuck namespaces"
    echo "9. Clean up all stuck namespaces"
    echo "10. Run comprehensive cleanup"
    echo "11. Assess monitoring system health"
    echo "12. Clean up stuck monitoring resources"
    echo "13. Comprehensive monitoring cleanup"
    echo "0. Exit"
    echo
}

# Comprehensive cleanup
comprehensive_cleanup() {
    echo -e "${YELLOW}Starting comprehensive emergency cleanup...${NC}"
    echo -e "${RED}WARNING: This will attempt to clean up all stuck resources!${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Operation cancelled"
        return 0
    fi
    
    log "INFO" "Starting comprehensive cleanup"
    
    # Clean up stuck pods
    echo -e "${CYAN}Cleaning up stuck pods...${NC}"
    "$SCRIPT_DIR/emergency-cleanup.sh" pods || true
    
    # Clean up stuck PVCs
    echo -e "${CYAN}Cleaning up stuck PVCs...${NC}"
    "$SCRIPT_DIR/emergency-cleanup.sh" pvcs || true
    
    # Clean up stuck Flux resources
    echo -e "${CYAN}Cleaning up stuck Flux resources...${NC}"
    "$SCRIPT_DIR/emergency-cleanup.sh" flux || true
    
    # Clean up stuck namespaces
    echo -e "${CYAN}Cleaning up stuck namespaces...${NC}"
    "$SCRIPT_DIR/force-delete-namespace.sh" cleanup-all || true
    
    echo -e "${GREEN}Comprehensive cleanup completed${NC}"
    log "INFO" "Comprehensive cleanup completed"
}

# Interactive mode
interactive_mode() {
    while true; do
        echo
        show_menu
        read -p "Select an option (0-13): " -r choice
        echo
        
        case "$choice" in
            1)
                show_status
                ;;
            2)
                read -p "Enter namespace name: " -r namespace
                if [[ -n "$namespace" ]]; then
                    "$SCRIPT_DIR/emergency-cleanup.sh" namespace "$namespace"
                else
                    echo -e "${RED}Invalid namespace name${NC}"
                fi
                ;;
            3)
                read -p "Enter namespace (optional): " -r namespace
                read -p "Enter selector (optional): " -r selector
                "$SCRIPT_DIR/emergency-cleanup.sh" pods "$namespace" "$selector"
                ;;
            4)
                read -p "Enter namespace (optional): " -r namespace
                "$SCRIPT_DIR/emergency-cleanup.sh" pvcs "$namespace"
                ;;
            5)
                read -p "Enter namespace (default: flux-system): " -r namespace
                "$SCRIPT_DIR/emergency-cleanup.sh" flux "${namespace:-flux-system}"
                ;;
            6)
                read -p "Enter resource type: " -r resource_type
                read -p "Enter resource name: " -r resource_name
                read -p "Enter namespace (optional): " -r namespace
                if [[ -n "$resource_type" && -n "$resource_name" ]]; then
                    "$SCRIPT_DIR/emergency-cleanup.sh" finalizers "$resource_type" "$resource_name" "$namespace"
                else
                    echo -e "${RED}Resource type and name are required${NC}"
                fi
                ;;
            7)
                read -p "Enter resource type: " -r resource_type
                read -p "Enter resource name: " -r resource_name
                read -p "Enter namespace (optional): " -r namespace
                if [[ -n "$resource_type" && -n "$resource_name" ]]; then
                    "$SCRIPT_DIR/emergency-cleanup.sh" force-delete "$resource_type" "$resource_name" "$namespace"
                else
                    echo -e "${RED}Resource type and name are required${NC}"
                fi
                ;;
            8)
                "$SCRIPT_DIR/force-delete-namespace.sh" list
                ;;
            9)
                "$SCRIPT_DIR/force-delete-namespace.sh" cleanup-all
                ;;
            10)
                comprehensive_cleanup
                ;;
            11)
                "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" assess
                ;;
            12)
                echo -e "${CYAN}Monitoring cleanup options:${NC}"
                echo "  a) Assess monitoring health"
                echo "  b) Clean up monitoring namespace"
                echo "  c) Clean up monitoring CRDs"
                echo "  d) Comprehensive monitoring cleanup"
                read -p "Select monitoring cleanup option (a-d): " -r monitoring_choice
                case "$monitoring_choice" in
                    a) "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" assess ;;
                    b) "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" namespace ;;
                    c) "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" crds ;;
                    d) "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" comprehensive ;;
                    *) echo -e "${RED}Invalid monitoring option${NC}" ;;
                esac
                ;;
            13)
                "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" comprehensive
                ;;
            0)
                echo "Exiting..."
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 0-13.${NC}"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..." -r
    done
}

# Display usage information
usage() {
    cat << EOF
Emergency CLI Tool - Unified Emergency Operations Interface

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    status                        Show cluster emergency status
    interactive                   Start interactive menu mode
    cleanup-all                   Run comprehensive cleanup of all stuck resources
    
    # Direct tool access:
    namespace <name>              Clean up stuck namespace
    pods [namespace] [selector]   Clean up stuck pods
    pvcs [namespace]              Clean up stuck PVCs
    flux [namespace]              Clean up stuck Flux resources
    finalizers <type> <name> [ns] Remove finalizers from resource
    force-delete <type> <name> [ns] Force delete resource
    list-namespaces               List stuck namespaces
    cleanup-namespaces            Clean up all stuck namespaces
    
    # Monitoring-specific commands:
    monitoring-assess             Assess monitoring system health
    monitoring-detect             Detect stuck monitoring resources
    monitoring-namespace          Clean up monitoring namespace
    monitoring-crds               Clean up stuck monitoring CRDs
    monitoring-comprehensive      Comprehensive monitoring cleanup

Options:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose logging

Examples:
    $0 status                     # Show cluster status
    $0 interactive                # Start interactive mode
    $0 cleanup-all                # Run comprehensive cleanup
    $0 namespace stuck-ns         # Clean specific namespace
    $0 pods default app=nginx     # Clean pods with selector

Log File: $LOG_FILE

This tool provides a unified interface to all emergency cleanup operations.
Use interactive mode for guided operations or direct commands for automation.
EOF
}

# Main function
main() {
    # Check prerequisites
    check_tools
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        interactive_mode
        exit 0
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
            interactive_mode
            exit 0
        fi
    fi
    
    log "INFO" "Starting emergency CLI operation: $command"
    
    # Execute command
    case "$command" in
        "status")
            show_status
            ;;
        "interactive")
            interactive_mode
            ;;
        "cleanup-all")
            comprehensive_cleanup
            ;;
        "namespace")
            if [[ $# -ne 1 ]]; then
                error_exit "Usage: $0 namespace <namespace-name>"
            fi
            "$SCRIPT_DIR/emergency-cleanup.sh" namespace "$1"
            ;;
        "pods")
            "$SCRIPT_DIR/emergency-cleanup.sh" pods "${1:-}" "${2:-}"
            ;;
        "pvcs")
            "$SCRIPT_DIR/emergency-cleanup.sh" pvcs "${1:-}"
            ;;
        "flux")
            "$SCRIPT_DIR/emergency-cleanup.sh" flux "${1:-flux-system}"
            ;;
        "finalizers")
            if [[ $# -lt 2 ]]; then
                error_exit "Usage: $0 finalizers <resource-type> <resource-name> [namespace]"
            fi
            "$SCRIPT_DIR/emergency-cleanup.sh" finalizers "$1" "$2" "${3:-}"
            ;;
        "force-delete")
            if [[ $# -lt 2 ]]; then
                error_exit "Usage: $0 force-delete <resource-type> <resource-name> [namespace]"
            fi
            "$SCRIPT_DIR/emergency-cleanup.sh" force-delete "$1" "$2" "${3:-}"
            ;;
        "list-namespaces")
            "$SCRIPT_DIR/force-delete-namespace.sh" list
            ;;
        "cleanup-namespaces")
            "$SCRIPT_DIR/force-delete-namespace.sh" cleanup-all
            ;;
        "monitoring-assess")
            "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" assess
            ;;
        "monitoring-detect")
            "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" detect
            ;;
        "monitoring-namespace")
            "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" namespace
            ;;
        "monitoring-crds")
            "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" crds
            ;;
        "monitoring-comprehensive")
            "$SCRIPT_DIR/cleanup-stuck-monitoring.sh" comprehensive
            ;;
        *)
            error_exit "Unknown command: $command. Use -h for help."
            ;;
    esac
    
    log "INFO" "Emergency CLI operation completed successfully"
}

# Run main function
main "$@"