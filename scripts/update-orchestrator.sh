#!/bin/bash
set -euo pipefail

# Update Orchestrator CLI Tool
# 
# This script provides a command-line interface for the dependency-aware update orchestrator.
# It allows planning, executing, and monitoring resource updates with proper dependency ordering.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}

info() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

# Configuration
ORCHESTRATOR_SCRIPT="$PROJECT_ROOT/infrastructure/recovery/update-orchestrator.py"
CONFIG_FILE="$PROJECT_ROOT/infrastructure/recovery/update-orchestrator-config.yaml"
TEMP_DIR="/tmp/update-orchestrator"

# Ensure temp directory exists
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR/resources-*.yaml" 2>/dev/null || true
}
trap cleanup EXIT

# Usage information
usage() {
    cat << EOF
Update Orchestrator CLI Tool

USAGE:
    $0 <command> [options]

COMMANDS:
    plan <resources>     Plan updates for resources with dependency analysis
    execute <plan>       Execute a previously created update plan
    status              Show status of running updates
    validate <resources> Validate resources without executing updates
    analyze <resources>  Analyze dependencies without planning updates
    rollback            Rollback the last update operation
    config              Show current configuration
    help                Show this help message

RESOURCE SPECIFICATION:
    Resources can be specified as:
    - File paths: path/to/resource.yaml
    - Directories: path/to/resources/ (all .yaml files)
    - Kustomization paths: path/to/kustomization/ (kubectl kustomize)
    - Stdin: - (read YAML from stdin)

OPTIONS:
    --dry-run           Plan and validate without executing
    --config <file>     Use custom configuration file
    --namespace <ns>    Limit to specific namespace
    --timeout <seconds> Override default timeout
    --parallel          Allow parallel batch execution
    --no-rollback       Disable automatic rollback on failure
    --verbose           Enable verbose logging
    --output <format>   Output format: text, json, yaml

EXAMPLES:
    # Plan updates for a directory of resources
    $0 plan infrastructure/monitoring/

    # Execute updates with dry-run first
    $0 plan --dry-run apps/example-app/
    $0 execute /tmp/update-orchestrator/plan-*.json

    # Validate resources without updating
    $0 validate infrastructure/core/

    # Analyze dependencies
    $0 analyze clusters/k3s-flux/

    # Monitor update status
    $0 status

    # Rollback last update
    $0 rollback

EXIT CODES:
    0    Success
    1    General error (missing dependencies, invalid arguments, etc.)
    2    Validation failure
    3    Execution failure
    4    Configuration error

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for required tools
    for tool in kubectl python3; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # Check for Python script
    if [[ ! -f "$ORCHESTRATOR_SCRIPT" ]]; then
        error "Update orchestrator script not found: $ORCHESTRATOR_SCRIPT"
        return 1
    fi
    
    # Check for Python dependencies
    if ! python3 -c "import yaml, asyncio" 2>/dev/null; then
        warn "Python dependencies may be missing. Install with: brew install python3"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing_deps[*]}"
        error "Install with: brew install ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# Load resources from various sources
load_resources() {
    local resource_specs=("$@")
    local temp_file="$TEMP_DIR/resources-$(date +%s).yaml"
    local resource_count=0
    
    log "Loading resources from ${#resource_specs[@]} sources..."
    
    for spec in "${resource_specs[@]}"; do
        if [[ "$spec" == "-" ]]; then
            # Read from stdin
            log "Reading resources from stdin..."
            cat >> "$temp_file"
            echo "---" >> "$temp_file"
            
        elif [[ -f "$spec" ]]; then
            # Single file
            log "Loading resource file: $spec"
            cat "$spec" >> "$temp_file"
            echo "---" >> "$temp_file"
            resource_count=$((resource_count + 1))
            
        elif [[ -d "$spec" ]]; then
            # Directory - check if it's a kustomization
            if [[ -f "$spec/kustomization.yaml" ]] || [[ -f "$spec/kustomization.yml" ]]; then
                log "Building kustomization: $spec"
                kubectl kustomize "$spec" >> "$temp_file"
                echo "---" >> "$temp_file"
                resource_count=$((resource_count + 1))
            else
                # Regular directory - load all YAML files
                log "Loading YAML files from directory: $spec"
                find "$spec" -name "*.yaml" -o -name "*.yml" | while read -r file; do
                    cat "$file" >> "$temp_file"
                    echo "---" >> "$temp_file"
                    resource_count=$((resource_count + 1))
                done
            fi
            
        else
            error "Resource source not found: $spec"
            return 1
        fi
    done
    
    if [[ ! -s "$temp_file" ]]; then
        error "No resources loaded"
        return 1
    fi
    
    success "Loaded resources to: $temp_file"
    echo "$temp_file"
}

# Plan updates
plan_updates() {
    local resource_file="$1"
    local dry_run="${2:-false}"
    local plan_file="$TEMP_DIR/plan-$(date +%s).json"
    
    log "Planning updates for resources in: $resource_file"
    
    # Build Python command
    local python_cmd=(
        python3 "$ORCHESTRATOR_SCRIPT"
        --mode plan
        --resources "$resource_file"
    )
    
    if [[ "$dry_run" == "true" ]]; then
        python_cmd+=(--dry-run)
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        python_cmd+=(--config "$CONFIG_FILE")
    fi
    
    # Add additional options
    if [[ "${NAMESPACE:-}" ]]; then
        python_cmd+=(--namespace "$NAMESPACE")
    fi
    
    if [[ "${TIMEOUT:-}" ]]; then
        python_cmd+=(--timeout "$TIMEOUT")
    fi
    
    if [[ "${PARALLEL:-false}" == "true" ]]; then
        python_cmd+=(--parallel)
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        python_cmd+=(--verbose)
    fi
    
    # Execute planning
    log "Executing: ${python_cmd[*]}"
    if "${python_cmd[@]}"; then
        success "Update plan created: $plan_file"
        
        # Show plan summary
        if [[ -f "$plan_file" ]]; then
            show_plan_summary "$plan_file"
        fi
        
        echo "$plan_file"
        return 0
    else
        error "Update planning failed"
        return 1
    fi
}

# Execute updates
execute_updates() {
    local plan_file="$1"
    
    if [[ ! -f "$plan_file" ]]; then
        error "Plan file not found: $plan_file"
        return 1
    fi
    
    log "Executing update plan: $plan_file"
    
    # Build Python command
    local python_cmd=(
        python3 "$ORCHESTRATOR_SCRIPT"
        --mode execute
        --plan "$plan_file"
    )
    
    if [[ -f "$CONFIG_FILE" ]]; then
        python_cmd+=(--config "$CONFIG_FILE")
    fi
    
    if [[ "${NO_ROLLBACK:-false}" == "true" ]]; then
        python_cmd+=(--no-rollback)
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        python_cmd+=(--verbose)
    fi
    
    # Execute updates
    log "Executing: ${python_cmd[*]}"
    if "${python_cmd[@]}"; then
        success "Updates executed successfully"
        return 0
    else
        error "Update execution failed"
        return 1
    fi
}

# Show plan summary
show_plan_summary() {
    local plan_file="$1"
    
    if [[ ! -f "$plan_file" ]]; then
        return 1
    fi
    
    info "Update Plan Summary:"
    echo
    
    # Extract summary using Python
    python3 -c "
import json
import sys

try:
    with open('$plan_file', 'r') as f:
        plan = json.load(f)
    
    print(f\"📋 Total Resources: {plan.get('total_operations', 0)}\")
    print(f\"📦 Total Batches: {plan.get('total_batches', 0)}\")
    print(f\"🔄 Dry Run: {plan.get('dry_run', False)}\")
    print()
    
    batches = plan.get('batches', [])
    for i, batch in enumerate(batches):
        print(f\"Batch {i + 1}: {len(batch.get('operations', []))} operations\")
        for op in batch.get('operations', [])[:3]:  # Show first 3
            resource = op.get('resource', {})
            strategy = op.get('strategy', 'unknown')
            print(f\"  - {resource.get('kind', 'Unknown')}/{resource.get('name', 'unknown')} ({strategy})\")
        if len(batch.get('operations', [])) > 3:
            print(f\"  ... and {len(batch.get('operations', [])) - 3} more\")
        print()

except Exception as e:
    print(f\"Error reading plan: {e}\", file=sys.stderr)
    sys.exit(1)
"
}

# Validate resources
validate_resources() {
    local resource_file="$1"
    
    log "Validating resources in: $resource_file"
    
    # Build Python command
    local python_cmd=(
        python3 "$ORCHESTRATOR_SCRIPT"
        --mode validate
        --resources "$resource_file"
    )
    
    if [[ -f "$CONFIG_FILE" ]]; then
        python_cmd+=(--config "$CONFIG_FILE")
    fi
    
    if [[ "${NAMESPACE:-}" ]]; then
        python_cmd+=(--namespace "$NAMESPACE")
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        python_cmd+=(--verbose)
    fi
    
    # Execute validation
    log "Executing: ${python_cmd[*]}"
    if "${python_cmd[@]}"; then
        success "Resource validation completed"
        return 0
    else
        error "Resource validation failed"
        return 1
    fi
}

# Analyze dependencies
analyze_dependencies() {
    local resource_file="$1"
    
    log "Analyzing dependencies in: $resource_file"
    
    # Build Python command
    local python_cmd=(
        python3 "$ORCHESTRATOR_SCRIPT"
        --mode analyze
        --resources "$resource_file"
    )
    
    if [[ -f "$CONFIG_FILE" ]]; then
        python_cmd+=(--config "$CONFIG_FILE")
    fi
    
    if [[ "${NAMESPACE:-}" ]]; then
        python_cmd+=(--namespace "$NAMESPACE")
    fi
    
    if [[ "${OUTPUT:-}" ]]; then
        python_cmd+=(--output "$OUTPUT")
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        python_cmd+=(--verbose)
    fi
    
    # Execute analysis
    log "Executing: ${python_cmd[*]}"
    if "${python_cmd[@]}"; then
        success "Dependency analysis completed"
        return 0
    else
        error "Dependency analysis failed"
        return 1
    fi
}

# Show status
show_status() {
    log "Checking update orchestrator status..."
    
    # Build Python command
    local python_cmd=(
        python3 "$ORCHESTRATOR_SCRIPT"
        --mode status
    )
    
    if [[ "${OUTPUT:-}" ]]; then
        python_cmd+=(--output "$OUTPUT")
    fi
    
    # Execute status check
    if "${python_cmd[@]}"; then
        return 0
    else
        error "Status check failed"
        return 1
    fi
}

# Rollback updates
rollback_updates() {
    log "Rolling back last update operation..."
    
    # Build Python command
    local python_cmd=(
        python3 "$ORCHESTRATOR_SCRIPT"
        --mode rollback
    )
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        python_cmd+=(--verbose)
    fi
    
    # Execute rollback
    log "Executing: ${python_cmd[*]}"
    if "${python_cmd[@]}"; then
        success "Rollback completed"
        return 0
    else
        error "Rollback failed"
        return 1
    fi
}

# Show configuration
show_config() {
    log "Current update orchestrator configuration:"
    echo
    
    if [[ -f "$CONFIG_FILE" ]]; then
        info "Configuration file: $CONFIG_FILE"
        echo
        # Extract and display key configuration values
        python3 -c "
import yaml
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config_data = yaml.safe_load(f)
    
    config = config_data.get('data', {}).get('config.yaml', '')
    if config:
        config_dict = yaml.safe_load(config)
        
        print('⚙️  Key Configuration:')
        print(f'   Batch Timeout: {config_dict.get(\"batch_timeout\", \"unknown\")}s')
        print(f'   Operation Timeout: {config_dict.get(\"operation_timeout\", \"unknown\")}s')
        print(f'   Max Retries: {config_dict.get(\"max_retries\", \"unknown\")}')
        print(f'   Parallel Batches: {config_dict.get(\"parallel_batches\", \"unknown\")}')
        print(f'   Validation Enabled: {config_dict.get(\"validation_enabled\", \"unknown\")}')
        print(f'   Rollback on Failure: {config_dict.get(\"rollback_on_failure\", \"unknown\")}')
        print()
        
        strategies = config_dict.get('strategies', {})
        if strategies:
            print('🔄 Update Strategies:')
            for resource_type, strategy in strategies.items():
                print(f'   {resource_type}: {strategy}')
    else:
        print('No configuration found in ConfigMap')

except Exception as e:
    print(f'Error reading configuration: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        warn "Configuration file not found: $CONFIG_FILE"
        info "Using default configuration"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="true"
                shift
                ;;
            --no-rollback)
                NO_ROLLBACK="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --output)
                OUTPUT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
}

# Main function
main() {
    # Parse global options first
    parse_args "$@"
    
    # Get remaining arguments
    local remaining_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --*)
                # Skip options we already parsed
                if [[ "$1" == "--config" ]] || [[ "$1" == "--namespace" ]] || [[ "$1" == "--timeout" ]] || [[ "$1" == "--output" ]]; then
                    shift 2
                else
                    shift
                fi
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Get command
    if [[ ${#remaining_args[@]} -eq 0 ]]; then
        error "No command specified"
        usage
        exit 1
    fi
    
    local command="${remaining_args[0]}"
    local command_args=("${remaining_args[@]:1}")
    
    # Execute command
    case "$command" in
        plan)
            if [[ ${#command_args[@]} -eq 0 ]]; then
                error "No resources specified for planning"
                exit 1
            fi
            
            resource_file=$(load_resources "${command_args[@]}")
            plan_file=$(plan_updates "$resource_file" "${DRY_RUN:-false}")
            
            if [[ "${DRY_RUN:-false}" == "false" ]]; then
                info "To execute this plan, run:"
                info "$0 execute $plan_file"
            fi
            ;;
            
        execute)
            if [[ ${#command_args[@]} -eq 0 ]]; then
                error "No plan file specified for execution"
                exit 1
            fi
            
            execute_updates "${command_args[0]}"
            ;;
            
        validate)
            if [[ ${#command_args[@]} -eq 0 ]]; then
                error "No resources specified for validation"
                exit 1
            fi
            
            resource_file=$(load_resources "${command_args[@]}")
            validate_resources "$resource_file"
            ;;
            
        analyze)
            if [[ ${#command_args[@]} -eq 0 ]]; then
                error "No resources specified for analysis"
                exit 1
            fi
            
            resource_file=$(load_resources "${command_args[@]}")
            analyze_dependencies "$resource_file"
            ;;
            
        status)
            show_status
            ;;
            
        rollback)
            rollback_updates
            ;;
            
        config)
            show_config
            ;;
            
        help)
            usage
            ;;
            
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"