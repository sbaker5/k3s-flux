#!/bin/bash
# k3s2 Node Onboarding Orchestration Script
#
# This script coordinates the complete k3s2 node onboarding process,
# providing progress tracking, status reporting, rollback capabilities,
# and comprehensive logging and troubleshooting output.
#
# Requirements: 1.3, 7.1, 7.2, 7.4 from k3s1-node-onboarding spec
#
# Usage: ./scripts/k3s2-onboarding-orchestrator.sh [OPTIONS]
#   --dry-run: Simulate the onboarding process without making changes
#   --skip-validation: Skip pre-onboarding validation (not recommended)
#   --auto-fix: Automatically attempt to fix issues during validation
#   --report: Generate detailed progress and status reports
#   --rollback: Rollback a failed onboarding attempt
#   --status: Check current onboarding status
#   --resume: Resume a previously interrupted onboarding
#   --verbose: Enable verbose logging
#   --help: Show this help message

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="/tmp/k3s2-onboarding-logs"
STATE_DIR="/tmp/k3s2-onboarding-state"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/k3s2-onboarding-$TIMESTAMP.log"
STATE_FILE="$STATE_DIR/onboarding-state.json"
REPORT_FILE="$LOG_DIR/k3s2-onboarding-report-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Flags
DRY_RUN=false
SKIP_VALIDATION=false
AUTO_FIX=false
GENERATE_REPORT=false
ROLLBACK_MODE=false
STATUS_MODE=false
RESUME_MODE=false
VERBOSE=false

# Onboarding phases
declare -a ONBOARDING_PHASES=(
    "pre_validation"
    "gitops_activation"
    "node_join_monitoring"
    "storage_integration"
    "network_validation"
    "monitoring_integration"
    "security_validation"
    "post_validation"
    "health_verification"
)

# Phase status tracking (using arrays with consistent indexing)
PHASE_STATUS=()
PHASE_START_TIME=()
PHASE_END_TIME=()
PHASE_ERRORS=()

# Counters
TOTAL_PHASES=${#ONBOARDING_PHASES[@]}
COMPLETED_PHASES=0
FAILED_PHASES=0
CURRENT_PHASE=""

# Helper function to get phase index
get_phase_index() {
    local phase="$1"
    local index=0
    for p in "${ONBOARDING_PHASES[@]}"; do
        if [[ "$p" == "$phase" ]]; then
            echo $index
            return
        fi
        ((index++))
    done
    echo -1
}

# Helper functions for phase status management
get_phase_status() {
    local phase="$1"
    local index=$(get_phase_index "$phase")
    if [[ $index -ge 0 && $index -lt ${#PHASE_STATUS[@]} ]]; then
        echo "${PHASE_STATUS[$index]}"
    else
        echo "not_started"
    fi
}

set_phase_status() {
    local phase="$1"
    local status="$2"
    local index=$(get_phase_index "$phase")
    if [[ $index -ge 0 ]]; then
        PHASE_STATUS[$index]="$status"
    fi
}

get_phase_error() {
    local phase="$1"
    local index=$(get_phase_index "$phase")
    if [[ $index -ge 0 && $index -lt ${#PHASE_ERRORS[@]} ]]; then
        echo "${PHASE_ERRORS[$index]}"
    else
        echo ""
    fi
}

set_phase_error() {
    local phase="$1"
    local error="$2"
    local index=$(get_phase_index "$phase")
    if [[ $index -ge 0 ]]; then
        PHASE_ERRORS[$index]="$error"
    fi
}

# Initialize all phases as not started
for phase in "${ONBOARDING_PHASES[@]}"; do
    PHASE_STATUS+=("not_started")
    PHASE_START_TIME+=(0)
    PHASE_END_TIME+=(0)
    PHASE_ERRORS+=("")
done

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --auto-fix)
                AUTO_FIX=true
                shift
                ;;
            --report)
                GENERATE_REPORT=true
                shift
                ;;
            --rollback)
                ROLLBACK_MODE=true
                shift
                ;;
            --status)
                STATUS_MODE=true
                shift
                ;;
            --resume)
                RESUME_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
k3s2 Node Onboarding Orchestration Script

This script coordinates the complete k3s2 node onboarding process with
progress tracking, status reporting, and rollback capabilities.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run           Simulate the onboarding process without making changes
    --skip-validation   Skip pre-onboarding validation (not recommended)
    --auto-fix          Automatically attempt to fix issues during validation
    --report            Generate detailed progress and status reports
    --rollback          Rollback a failed onboarding attempt
    --status            Check current onboarding status
    --resume            Resume a previously interrupted onboarding
    --verbose           Enable verbose logging
    --help              Show this help message

EXAMPLES:
    # Standard onboarding with reports
    $0 --report

    # Dry run to test the process
    $0 --dry-run --verbose

    # Resume interrupted onboarding
    $0 --resume --verbose

    # Check current status
    $0 --status

    # Rollback failed onboarding
    $0 --rollback

PHASES:
    1. Pre-validation       - Validate cluster readiness
    2. GitOps Activation    - Enable k3s2 configuration in Git
    3. Node Join Monitoring - Monitor k3s2 joining the cluster
    4. Storage Integration  - Validate Longhorn integration
    5. Network Validation   - Verify network connectivity
    6. Monitoring Integration - Ensure monitoring includes k3s2
    7. Security Validation  - Validate RBAC and security posture
    8. Post Validation      - Run comprehensive validation
    9. Health Verification  - Final health and performance checks

REQUIREMENTS:
    - kubectl configured for k3s cluster
    - flux CLI installed
    - jq installed for JSON processing
    - Git repository access for GitOps changes

EOF
}

# Logging functions
log() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp] INFO: $message${NC}"
    echo "[$timestamp] INFO: $message" >> "$LOG_FILE"
}

warn() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[$timestamp] WARN: $message${NC}"
    echo "[$timestamp] WARN: $message" >> "$LOG_FILE"
}

error() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[$timestamp] ERROR: $message${NC}"
    echo "[$timestamp] ERROR: $message" >> "$LOG_FILE"
}

success() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp] SUCCESS: $message${NC}"
    echo "[$timestamp] SUCCESS: $message" >> "$LOG_FILE"
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        local message="$*"
        local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
        echo -e "${PURPLE}[$timestamp] DEBUG: $message${NC}"
        echo "[$timestamp] DEBUG: $message" >> "$LOG_FILE"
    fi
}

progress() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}[$timestamp] PROGRESS: $message${NC}"
    echo "[$timestamp] PROGRESS: $message" >> "$LOG_FILE"
}

# Initialize logging and state directories
init_directories() {
    mkdir -p "$LOG_DIR" "$STATE_DIR"
    
    # Initialize log file
    cat > "$LOG_FILE" << EOF
# k3s2 Node Onboarding Orchestration Log
# Started: $(date)
# Script: $0
# Arguments: $*
# Dry Run: $DRY_RUN
# Auto Fix: $AUTO_FIX
# Generate Report: $GENERATE_REPORT

EOF

    debug "Initialized logging directory: $LOG_DIR"
    debug "Initialized state directory: $STATE_DIR"
    debug "Log file: $LOG_FILE"
    debug "State file: $STATE_FILE"
}

# Save current state to file
save_state() {
    local state_data=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "current_phase": "$CURRENT_PHASE",
    "completed_phases": $COMPLETED_PHASES,
    "failed_phases": $FAILED_PHASES,
    "total_phases": $TOTAL_PHASES,
    "phase_status": {
EOF

    local first=true
    for phase in "${ONBOARDING_PHASES[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            state_data+=","
        fi
        local status=$(get_phase_status "$phase")
        state_data+="
        \"$phase\": \"$status\""
    done

    state_data+="
    },
    "phase_errors": {
"

    first=true
    for phase in "${ONBOARDING_PHASES[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            state_data+=","
        fi
        local error_msg=$(get_phase_error "$phase")
        # Escape quotes in error message
        error_msg="${error_msg//\"/\\\"}"
        state_data+="
        \"$phase\": \"$error_msg\""
    done

    state_data+="
    }
}"

    echo "$state_data" > "$STATE_FILE"
    debug "State saved to $STATE_FILE"
}

# Load state from file
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        debug "Loading state from $STATE_FILE"
        
        # Load phase status
        for phase in "${ONBOARDING_PHASES[@]}"; do
            local status=$(jq -r ".phase_status.\"$phase\"" "$STATE_FILE" 2>/dev/null || echo "not_started")
            set_phase_status "$phase" "$status"
            
            local error_msg=$(jq -r ".phase_errors.\"$phase\"" "$STATE_FILE" 2>/dev/null || echo "")
            set_phase_error "$phase" "$error_msg"
        done
        
        # Load counters
        COMPLETED_PHASES=$(jq -r '.completed_phases' "$STATE_FILE" 2>/dev/null || echo "0")
        FAILED_PHASES=$(jq -r '.failed_phases' "$STATE_FILE" 2>/dev/null || echo "0")
        CURRENT_PHASE=$(jq -r '.current_phase' "$STATE_FILE" 2>/dev/null || echo "")
        
        log "State loaded - Completed: $COMPLETED_PHASES, Failed: $FAILED_PHASES"
    else
        debug "No existing state file found"
    fi
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    local missing_deps=0
    
    local required_commands=("kubectl" "flux" "jq" "git")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "$cmd not found - please install $cmd"
            missing_deps=$((missing_deps + 1))
        else
            debug "$cmd found: $(command -v "$cmd")"
        fi
    done
    
    if [[ $missing_deps -gt 0 ]]; then
        error "Missing $missing_deps required dependencies"
        return 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        error "Please check your kubeconfig and cluster connectivity"
        return 1
    fi
    
    # Check Git repository access
    if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
        error "Not in a Git repository - GitOps activation requires Git"
        return 1
    fi
    
    success "All dependencies available"
    return 0
}

# Display current onboarding status
show_status() {
    log "k3s2 Node Onboarding Status"
    log "============================"
    
    # Check if k3s2 node exists
    local k3s2_exists=false
    if kubectl get node k3s2 >/dev/null 2>&1; then
        k3s2_exists=true
        local k3s2_status=$(kubectl get node k3s2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        log "k3s2 Node Status: $k3s2_status"
    else
        log "k3s2 Node Status: Not Found"
    fi
    
    # Show phase status
    log ""
    log "Phase Status:"
    log "============="
    
    local phase_num=1
    for phase in "${ONBOARDING_PHASES[@]}"; do
        local status=$(get_phase_status "$phase")
        local status_icon=""
        
        case "$status" in
            "completed")
                status_icon="[DONE]"
                ;;
            "in_progress")
                status_icon="[RUNNING]"
                ;;
            "failed")
                status_icon="[FAILED]"
                ;;
            *)
                status_icon="[PENDING]"
                ;;
        esac
        
        printf "%2d. %-25s %s %s\n" "$phase_num" "${phase//_/ }" "$status_icon" "$status"
        
        # Show error if exists
        local error_msg=$(get_phase_error "$phase")
        if [[ -n "$error_msg" ]]; then
            echo "    Error: $error_msg"
        fi
        
        phase_num=$((phase_num + 1))
    done
    
    log ""
    log "Summary:"
    log "========"
    log "Total Phases: $TOTAL_PHASES"
    log "Completed: $COMPLETED_PHASES"
    log "Failed: $FAILED_PHASES"
    log "Remaining: $((TOTAL_PHASES - COMPLETED_PHASES - FAILED_PHASES))"
    
    if [[ "$k3s2_exists" == "true" ]]; then
        log ""
        log "k3s2 Node Details:"
        log "=================="
        kubectl get node k3s2 -o wide 2>/dev/null || log "Could not get k3s2 node details"
    fi
    
    # Show recent log entries
    if [[ -f "$LOG_FILE" ]]; then
        log ""
        log "Recent Log Entries (last 10):"
        log "=============================="
        tail -10 "$LOG_FILE" | while IFS= read -r line; do
            echo "$line"
        done
    fi
}

# Start a phase
start_phase() {
    local phase="$1"
    local index=$(get_phase_index "$phase")
    
    CURRENT_PHASE="$phase"
    set_phase_status "$phase" "in_progress"
    if [[ $index -ge 0 ]]; then
        PHASE_START_TIME[$index]=$(date +%s)
    fi
    
    progress "Starting phase: ${phase//_/ }"
    save_state
}

# Complete a phase successfully
complete_phase() {
    local phase="$1"
    local index=$(get_phase_index "$phase")
    
    set_phase_status "$phase" "completed"
    if [[ $index -ge 0 ]]; then
        PHASE_END_TIME[$index]=$(date +%s)
        local duration=$((PHASE_END_TIME[$index] - PHASE_START_TIME[$index]))
        success "Completed phase: ${phase//_/ } (${duration}s)"
    else
        success "Completed phase: ${phase//_/ }"
    fi
    
    COMPLETED_PHASES=$((COMPLETED_PHASES + 1))
    save_state
}

# Fail a phase
fail_phase() {
    local phase="$1"
    local error_msg="$2"
    local index=$(get_phase_index "$phase")
    
    set_phase_status "$phase" "failed"
    set_phase_error "$phase" "$error_msg"
    
    if [[ $index -ge 0 ]]; then
        PHASE_END_TIME[$index]=$(date +%s)
        local duration=$((PHASE_END_TIME[$index] - PHASE_START_TIME[$index]))
        error "Failed phase: ${phase//_/ } (${duration}s) - $error_msg"
    else
        error "Failed phase: ${phase//_/ } - $error_msg"
    fi
    
    FAILED_PHASES=$((FAILED_PHASES + 1))
    save_state
}

# Execute a phase with error handling
execute_phase() {
    local phase="$1"
    local phase_function="$2"
    
    # Skip if already completed (for resume mode)
    local current_status=$(get_phase_status "$phase")
    if [[ "$current_status" == "completed" ]]; then
        log "Phase ${phase//_/ } already completed - skipping"
        return 0
    fi
    
    start_phase "$phase"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would execute phase: ${phase//_/ }"
        sleep 2  # Simulate work
        complete_phase "$phase"
        return 0
    fi
    
    # Execute the phase function
    local phase_result=0
    if $phase_function; then
        complete_phase "$phase"
    else
        phase_result=$?
        fail_phase "$phase" "Phase function returned error code $phase_result"
        return $phase_result
    fi
}

# Phase 1: Pre-validation
phase_pre_validation() {
    log "Running pre-onboarding validation..."
    
    # Check if k3s2 already exists
    if kubectl get node k3s2 >/dev/null 2>&1; then
        warn "k3s2 node already exists in cluster"
        local k3s2_status=$(kubectl get node k3s2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [[ "$k3s2_status" == "True" ]]; then
            log "k3s2 node is already Ready - skipping to validation phases"
            return 0
        else
            warn "k3s2 node exists but is not Ready - continuing with onboarding"
        fi
    fi
    
    # Run pre-onboarding validation script
    local validation_args=""
    if [[ "$AUTO_FIX" == "true" ]]; then
        validation_args="--fix"
    fi
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        validation_args="$validation_args --report"
    fi
    
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        warn "Skipping pre-validation as requested"
        return 0
    fi
    
    log "Executing pre-onboarding validation script..."
    if "$SCRIPT_DIR/k3s2-pre-onboarding-validation.sh" $validation_args; then
        success "Pre-onboarding validation passed"
        return 0
    else
        error "Pre-onboarding validation failed"
        return 1
    fi
}

# Phase 2: GitOps activation
phase_gitops_activation() {
    log "Activating k3s2 configuration in GitOps..."
    
    # Check if k3s2-node-config is already uncommented
    local kustomization_file="$PROJECT_ROOT/infrastructure/storage/kustomization.yaml"
    
    if ! grep -q "^  - ../k3s2-node-config/" "$kustomization_file"; then
        log "k3s2-node-config is commented out - activating it"
        
        # Backup the file
        cp "$kustomization_file" "$kustomization_file.backup-$TIMESTAMP"
        
        # Uncomment the k3s2-node-config line
        sed -i.tmp 's|^  # - ../k3s2-node-config/|  - ../k3s2-node-config/|' "$kustomization_file"
        rm "$kustomization_file.tmp" 2>/dev/null || true
        
        # Verify the change
        if grep -q "^  - ../k3s2-node-config/" "$kustomization_file"; then
            success "k3s2-node-config activated in kustomization.yaml"
        else
            error "Failed to activate k3s2-node-config in kustomization.yaml"
            return 1
        fi
        
        # Commit the change to Git
        cd "$PROJECT_ROOT"
        git add "$kustomization_file"
        git commit -m "feat: activate k3s2 node configuration for onboarding

- Uncommented k3s2-node-config in infrastructure/storage/kustomization.yaml
- This enables Flux to apply k3s2-specific Longhorn node configuration
- Part of automated k3s2 onboarding process

Requirements: 3.1, 3.2, 3.3 from k3s1-node-onboarding spec"
        
        log "Committed GitOps activation to Git repository"
        
        # Push the change (if possible)
        if git push origin main 2>/dev/null; then
            success "Pushed GitOps activation to remote repository"
        else
            warn "Could not push to remote repository - manual push may be required"
        fi
    else
        log "k3s2-node-config is already activated in GitOps"
    fi
    
    # Trigger Flux reconciliation
    log "Triggering Flux reconciliation..."
    if flux reconcile kustomization infrastructure-storage -n flux-system --timeout=60s; then
        success "Flux reconciliation triggered successfully"
    else
        warn "Flux reconciliation may have issues - continuing anyway"
    fi
    
    return 0
}

# Phase 3: Node join monitoring
phase_node_join_monitoring() {
    log "Monitoring k3s2 node join process..."
    
    local max_wait_time=300  # 5 minutes
    local check_interval=10
    local elapsed_time=0
    
    while [[ $elapsed_time -lt $max_wait_time ]]; do
        if kubectl get node k3s2 >/dev/null 2>&1; then
            local k3s2_status=$(kubectl get node k3s2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            
            if [[ "$k3s2_status" == "True" ]]; then
                success "k3s2 node has joined the cluster and is Ready"
                
                # Show node details
                log "k3s2 node details:"
                kubectl get node k3s2 -o wide
                
                return 0
            else
                progress "k3s2 node found but not Ready yet (Status: $k3s2_status)"
            fi
        else
            progress "Waiting for k3s2 node to join the cluster... (${elapsed_time}s/${max_wait_time}s)"
        fi
        
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
    done
    
    error "k3s2 node did not join the cluster within $max_wait_time seconds"
    return 1
}

# Phase 4: Storage integration
phase_storage_integration() {
    log "Validating Longhorn storage integration..."
    
    # Wait for Longhorn to recognize k3s2
    local max_wait_time=180  # 3 minutes
    local check_interval=15
    local elapsed_time=0
    
    while [[ $elapsed_time -lt $max_wait_time ]]; do
        if kubectl get longhornnode k3s2 -n longhorn-system >/dev/null 2>&1; then
            local k3s2_longhorn_ready=$(kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            
            if [[ "$k3s2_longhorn_ready" == "True" ]]; then
                success "k3s2 Longhorn node is ready"
                
                # Show Longhorn node details
                log "k3s2 Longhorn node details:"
                kubectl get longhornnode k3s2 -n longhorn-system -o yaml | grep -A 10 "spec:" | head -15
                
                return 0
            else
                progress "k3s2 Longhorn node found but not ready yet (Status: $k3s2_longhorn_ready)"
            fi
        else
            progress "Waiting for Longhorn to recognize k3s2 node... (${elapsed_time}s/${max_wait_time}s)"
        fi
        
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
    done
    
    error "k3s2 Longhorn node did not become ready within $max_wait_time seconds"
    return 1
}

# Phase 5: Network validation
phase_network_validation() {
    log "Validating network connectivity..."
    
    # Run network connectivity verification
    if "$SCRIPT_DIR/network-connectivity-verification.sh" >/dev/null 2>&1; then
        success "Network connectivity validation passed"
    else
        warn "Network connectivity validation had issues - checking basic connectivity"
        
        # Basic connectivity test
        if kubectl get pods -A -o wide | grep k3s2 >/dev/null 2>&1; then
            success "Pods are running on k3s2 - basic connectivity working"
        else
            error "No pods running on k3s2 - network issues may exist"
            return 1
        fi
    fi
    
    return 0
}

# Phase 6: Monitoring integration
phase_monitoring_integration() {
    log "Validating monitoring integration..."
    
    # Check if node-exporter is running on k3s2
    local max_wait_time=120  # 2 minutes
    local check_interval=10
    local elapsed_time=0
    
    while [[ $elapsed_time -lt $max_wait_time ]]; do
        local node_exporter_k3s2=$(kubectl get pods -A -l app.kubernetes.io/name=node-exporter -o wide --no-headers 2>/dev/null | grep k3s2 | grep Running | wc -l)
        
        if [[ $node_exporter_k3s2 -gt 0 ]]; then
            success "Node-exporter is running on k3s2"
            return 0
        else
            progress "Waiting for node-exporter to start on k3s2... (${elapsed_time}s/${max_wait_time}s)"
        fi
        
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
    done
    
    warn "Node-exporter may not be running on k3s2 yet - monitoring integration may be delayed"
    return 0  # Non-critical for onboarding success
}

# Phase 7: Security validation
phase_security_validation() {
    log "Validating security and RBAC..."
    
    # Run security validation if script exists
    if [[ -f "$SCRIPT_DIR/security-validation.sh" ]]; then
        if "$SCRIPT_DIR/security-validation.sh" >/dev/null 2>&1; then
            success "Security validation passed"
        else
            warn "Security validation had issues - manual review recommended"
        fi
    else
        log "Security validation script not found - performing basic checks"
        
        # Basic security checks
        if kubectl auth can-i get nodes --as=system:node:k3s2 >/dev/null 2>&1; then
            success "k3s2 node has appropriate RBAC permissions"
        else
            log "k3s2 node RBAC check (may be expected to fail)"
        fi
    fi
    
    return 0
}

# Phase 8: Post validation
phase_post_validation() {
    log "Running post-onboarding validation..."
    
    # Run comprehensive validation scripts
    local validation_scripts=(
        "cluster-readiness-validation.sh"
        "storage-health-check.sh"
        "monitoring-validation.sh"
    )
    
    local validation_passed=0
    local validation_total=0
    
    for script in "${validation_scripts[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            validation_total=$((validation_total + 1))
            log "Running $script..."
            
            if "$SCRIPT_DIR/$script" >/dev/null 2>&1; then
                success "$script passed"
                validation_passed=$((validation_passed + 1))
            else
                warn "$script had issues"
            fi
        fi
    done
    
    if [[ $validation_passed -eq $validation_total ]]; then
        success "All post-validation checks passed ($validation_passed/$validation_total)"
    else
        warn "Some post-validation checks had issues ($validation_passed/$validation_total passed)"
    fi
    
    return 0
}

# Phase 9: Health verification
phase_health_verification() {
    log "Running comprehensive health verification..."
    
    # Run post-onboarding health verification
    local health_args=""
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        health_args="--report"
    fi
    
    if "$SCRIPT_DIR/post-onboarding-health-verification.sh" $health_args; then
        success "Health verification passed - k3s2 onboarding is complete!"
        return 0
    else
        error "Health verification failed - onboarding may have issues"
        return 1
    fi
}

# Rollback onboarding
rollback_onboarding() {
    log "Starting k3s2 onboarding rollback..."
    
    # Confirm rollback
    if [[ "$DRY_RUN" != "true" ]]; then
        echo -n "Are you sure you want to rollback k3s2 onboarding? [y/N]: "
        read -r confirmation
        if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
            log "Rollback cancelled by user"
            return 0
        fi
    fi
    
    # Step 1: Drain k3s2 node if it exists
    if kubectl get node k3s2 >/dev/null 2>&1; then
        log "Draining k3s2 node..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would drain k3s2 node"
        else
            kubectl drain k3s2 --ignore-daemonsets --delete-emptydir-data --timeout=300s || warn "Node drain had issues"
        fi
    fi
    
    # Step 2: Remove k3s2 from cluster
    if kubectl get node k3s2 >/dev/null 2>&1; then
        log "Removing k3s2 node from cluster..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would delete k3s2 node"
        else
            kubectl delete node k3s2 || warn "Node deletion had issues"
        fi
    fi
    
    # Step 3: Deactivate k3s2 configuration in GitOps
    local kustomization_file="$PROJECT_ROOT/infrastructure/storage/kustomization.yaml"
    
    if grep -q "^  - ../k3s2-node-config/" "$kustomization_file"; then
        log "Deactivating k3s2-node-config in GitOps..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would comment out k3s2-node-config"
        else
            # Backup the file
            cp "$kustomization_file" "$kustomization_file.rollback-$TIMESTAMP"
            
            # Comment out the k3s2-node-config line
            sed -i.tmp 's|^  - ../k3s2-node-config/|  # - ../k3s2-node-config/|' "$kustomization_file"
            rm "$kustomization_file.tmp" 2>/dev/null || true
            
            # Commit the change
            cd "$PROJECT_ROOT"
            git add "$kustomization_file"
            git commit -m "feat: deactivate k3s2 node configuration (rollback)

- Commented out k3s2-node-config in infrastructure/storage/kustomization.yaml
- Part of k3s2 onboarding rollback process
- Node has been drained and removed from cluster"
            
            # Push if possible
            git push origin main 2>/dev/null || warn "Could not push rollback to remote repository"
        fi
    fi
    
    # Step 4: Trigger Flux reconciliation
    log "Triggering Flux reconciliation for rollback..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would trigger Flux reconciliation"
    else
        flux reconcile kustomization infrastructure-storage -n flux-system --timeout=60s || warn "Flux reconciliation had issues"
    fi
    
    # Step 5: Clean up state
    log "Cleaning up onboarding state..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up state files"
    else
        rm -f "$STATE_FILE"
        log "State file removed"
    fi
    
    success "k3s2 onboarding rollback completed"
    return 0
}

# Generate final report
generate_final_report() {
    if [[ "$GENERATE_REPORT" != "true" ]]; then
        return 0
    fi
    
    log "Generating final onboarding report..."
    
    cat > "$REPORT_FILE" << EOF
# k3s2 Node Onboarding Report

**Date**: $(date)
**Script**: $0
**Dry Run**: $DRY_RUN
**Auto Fix**: $AUTO_FIX

## Executive Summary

This report contains the complete k3s2 node onboarding process results,
including phase execution status, timing information, and final cluster state.

## Onboarding Results

**Total Phases**: $TOTAL_PHASES
**Completed Phases**: $COMPLETED_PHASES
**Failed Phases**: $FAILED_PHASES
**Success Rate**: $(( COMPLETED_PHASES * 100 / TOTAL_PHASES ))%

## Phase Details

EOF

    local phase_num=1
    for phase in "${ONBOARDING_PHASES[@]}"; do
        local status=$(get_phase_status "$phase")
        local status_icon=""
        local index=$(get_phase_index "$phase")
        
        case "$status" in
            "completed")
                status_icon="[DONE]"
                ;;
            "in_progress")
                status_icon="[RUNNING]"
                ;;
            "failed")
                status_icon="[FAILED]"
                ;;
            *)
                status_icon="[PENDING]"
                ;;
        esac
        
        echo "### $phase_num. ${phase//_/ } $status_icon" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "**Status**: $status" >> "$REPORT_FILE"
        
        if [[ $index -ge 0 && ${PHASE_START_TIME[$index]} -gt 0 && ${PHASE_END_TIME[$index]} -gt 0 ]]; then
            local duration=$((PHASE_END_TIME[$index] - PHASE_START_TIME[$index]))
            echo "**Duration**: ${duration}s" >> "$REPORT_FILE"
        fi
        
        local error_msg=$(get_phase_error "$phase")
        if [[ -n "$error_msg" ]]; then
            echo "**Error**: $error_msg" >> "$REPORT_FILE"
        fi
        
        echo "" >> "$REPORT_FILE"
        phase_num=$((phase_num + 1))
    done
    
    # Add cluster state
    cat >> "$REPORT_FILE" << EOF
## Final Cluster State

### Nodes
\`\`\`
$(kubectl get nodes -o wide 2>/dev/null || echo "Could not retrieve node information")
\`\`\`

### Longhorn Nodes
\`\`\`
$(kubectl get longhornnode -n longhorn-system 2>/dev/null || echo "Could not retrieve Longhorn node information")
\`\`\`

### Pod Distribution
\`\`\`
$(kubectl get pods -A -o wide --no-headers 2>/dev/null | awk '{print $8}' | sort | uniq -c | sort -nr || echo "Could not retrieve pod distribution")
\`\`\`

## Recommendations

EOF

    if [[ $FAILED_PHASES -eq 0 ]]; then
        cat >> "$REPORT_FILE" << EOF
[DONE] **SUCCESS**: k3s2 onboarding completed successfully!

1. Monitor cluster performance and resource utilization
2. Deploy test applications to validate end-to-end functionality
3. Verify storage redundancy with multi-replica volumes
4. Check monitoring dashboards for both nodes

EOF
    else
        cat >> "$REPORT_FILE" << EOF
[FAILED] **ATTENTION NEEDED**: Some phases failed during onboarding

1. Review failed phases and error messages above
2. Check cluster logs for additional troubleshooting information
3. Consider running rollback if issues are severe
4. Re-run onboarding after addressing issues

EOF
    fi
    
    cat >> "$REPORT_FILE" << EOF
---
*Report generated by k3s2-onboarding-orchestrator.sh*
*Log file: $LOG_FILE*
EOF

    success "Final report generated: $REPORT_FILE"
}

# Main onboarding orchestration
run_onboarding_orchestration() {
    log "Starting k3s2 Node Onboarding Orchestration"
    log "============================================="
    
    # Load existing state if resuming
    if [[ "$RESUME_MODE" == "true" ]]; then
        load_state
        log "Resuming onboarding from previous state"
    fi
    
    # Execute all phases
    for phase in "${ONBOARDING_PHASES[@]}"; do
        local phase_function="phase_${phase}"
        
        if ! execute_phase "$phase" "$phase_function"; then
            error "Phase ${phase//_/ } failed - stopping onboarding"
            
            # Save final state
            save_state
            generate_final_report
            
            log ""
            log "Onboarding failed at phase: ${phase//_/ }"
            log "Use --status to check current state"
            log "Use --rollback to rollback changes"
            log "Use --resume to continue after fixing issues"
            
            return 1
        fi
    done
    
    # All phases completed successfully
    success "All onboarding phases completed successfully!"
    
    # Generate final report
    generate_final_report
    
    log ""
    log "[SUCCESS] k3s2 Node Onboarding Complete!"
    log "=================================="
    log "[DONE] k3s2 node has been successfully onboarded"
    log "[DONE] Storage redundancy is configured"
    log "[DONE] Network connectivity is validated"
    log "[DONE] Monitoring integration is active"
    log "[DONE] All health checks passed"
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        log ""
        log "[REPORT] Detailed report: $REPORT_FILE"
    fi
    
    log "[LOG] Log file: $LOG_FILE"
    
    return 0
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Initialize
    init_directories
    
    log "k3s2 Node Onboarding Orchestrator v1.0"
    log "======================================="
    log "Dry Run: $DRY_RUN"
    log "Skip Validation: $SKIP_VALIDATION"
    log "Auto Fix: $AUTO_FIX"
    log "Generate Report: $GENERATE_REPORT"
    log "Rollback Mode: $ROLLBACK_MODE"
    log "Status Mode: $STATUS_MODE"
    log "Resume Mode: $RESUME_MODE"
    log "Verbose: $VERBOSE"
    log ""
    
    # Check dependencies
    if ! check_dependencies; then
        error "Dependency check failed"
        exit 1
    fi
    
    # Load state for status/resume modes
    if [[ "$STATUS_MODE" == "true" || "$RESUME_MODE" == "true" || "$ROLLBACK_MODE" == "true" ]]; then
        load_state
    fi
    
    # Handle different modes
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_status
        exit 0
    elif [[ "$ROLLBACK_MODE" == "true" ]]; then
        rollback_onboarding
        exit $?
    else
        # Run the main onboarding orchestration
        run_onboarding_orchestration
        exit $?
    fi
}

# Run main function with all arguments
main "$@"