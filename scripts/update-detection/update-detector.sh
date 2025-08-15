#!/bin/bash

# Main Update Detection Orchestrator
# Provides the base framework for coordinating all update detection activities

set -euo pipefail

# Script directory and library paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source required libraries
source "${LIB_DIR}/config-manager.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/version-utils.sh"

# Global variables
COMPONENT="update-detector"
CONFIG_FILE=""
OUTPUT_FORMAT=""
OUTPUT_FILE=""
SPECIFIC_COMPONENT=""
DRY_RUN="false"
VERBOSE="false"

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Main update detection orchestrator for the k3s GitOps cluster.

OPTIONS:
    -c, --config FILE       Configuration file (default: config/update-detection.yaml)
    -f, --format FORMAT     Output format: json, yaml, text (default: from config)
    -o, --output FILE       Output file (default: stdout)
    --component COMPONENT   Only check specific component: k3s, flux, longhorn, helm
    --dry-run              Show what would be done without executing
    -v, --verbose          Enable verbose logging
    -h, --help             Show this help message

EXAMPLES:
    $0                                    # Run full update detection
    $0 --component k3s                   # Only check k3s updates
    $0 -f yaml -o report.yaml            # Generate YAML report to file
    $0 --dry-run                         # Show what would be executed
    $0 -v --component flux               # Verbose output for Flux only

COMPONENTS:
    k3s         - Kubernetes distribution updates
    flux        - Flux CD controller updates
    longhorn    - Longhorn storage system updates
    helm        - Helm chart updates for all releases

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --component)
                SPECIFIC_COMPONENT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "$COMPONENT" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate component if specified
    if [[ -n "$SPECIFIC_COMPONENT" ]]; then
        case "$SPECIFIC_COMPONENT" in
            k3s|flux|longhorn|helm) ;;
            *)
                log_error "$COMPONENT" "Invalid component: $SPECIFIC_COMPONENT"
                exit 1
                ;;
        esac
    fi
    
    # Validate output format if specified
    if [[ -n "$OUTPUT_FORMAT" ]]; then
        case "$OUTPUT_FORMAT" in
            json|yaml|text) ;;
            *)
                log_error "$COMPONENT" "Invalid output format: $OUTPUT_FORMAT"
                exit 1
                ;;
        esac
    fi
}

# Initialize the update detection system
initialize_system() {
    log_info "$COMPONENT" "Initializing update detection system"
    
    # Initialize configuration
    if [[ -n "$CONFIG_FILE" ]]; then
        init_config "$CONFIG_FILE" || {
            log_error "$COMPONENT" "Failed to load configuration from: $CONFIG_FILE"
            exit 1
        }
    else
        init_config || {
            log_error "$COMPONENT" "Failed to load default configuration"
            exit 1
        }
    fi
    
    # Initialize logging
    init_logging "$COMPONENT" || {
        log_error "$COMPONENT" "Failed to initialize logging system"
        exit 1
    }
    
    # Set verbose logging if requested
    if [[ "$VERBOSE" == "true" ]]; then
        CONFIG_LOGGING_LEVEL="DEBUG"
        LOG_LEVEL_NUM=0
    fi
    
    # Set output format from config if not specified
    if [[ -z "$OUTPUT_FORMAT" ]]; then
        OUTPUT_FORMAT=$(get_config "global" "default_output_format" "json")
    fi
    
    log_info "$COMPONENT" "System initialization completed"
    log_debug "$COMPONENT" "Configuration loaded, logging initialized, output format: $OUTPUT_FORMAT"
}

# Check system prerequisites
check_prerequisites() {
    log_info "$COMPONENT" "Checking system prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    local required_tools=("curl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    # Check for optional tools
    local optional_tools=("kubectl" "helm" "yq")
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_warn "$COMPONENT" "Optional tool not found: $tool (some features may be limited)"
        fi
    done
    
    # Report missing required tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "$COMPONENT" "Missing required tools: ${missing_tools[*]}"
        log_error "$COMPONENT" "Please install missing tools and try again"
        exit 1
    fi
    
    log_info "$COMPONENT" "Prerequisites check completed successfully"
}

# Execute component detection
execute_component_detection() {
    local component_name="$1"
    local start_time
    start_time=$(date +%s)
    
    log_info "$COMPONENT" "Starting $component_name update detection"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "$COMPONENT" "DRY RUN: Would execute ${SCRIPT_DIR}/detect-${component_name}-updates.sh"
        echo "{\"component\":\"$component_name\",\"dry_run\":true,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
        return 0
    fi
    
    # Execute the component detection script
    local script_path="${SCRIPT_DIR}/detect-${component_name}-updates.sh"
    
    if [[ ! -x "$script_path" ]]; then
        log_error "$COMPONENT" "Detection script not found or not executable: $script_path"
        echo "{\"component\":\"$component_name\",\"error\":\"script_not_found\"}"
        return 1
    fi
    
    local output
    local exit_code=0
    
    # Execute with timeout and capture output
    if output=$("$script_path" 2>&1); then
        log_info "$COMPONENT" "$component_name detection completed successfully"
    else
        exit_code=$?
        log_error "$COMPONENT" "$component_name detection failed with exit code: $exit_code"
        echo "{\"component\":\"$component_name\",\"error\":\"execution_failed\",\"exit_code\":$exit_code}"
        return $exit_code
    fi
    
    # Extract JSON from output (filter out log lines)
    local json_output
    json_output=$(echo "$output" | sed -n '/^{/,/^}$/p' | tr -d '\n' | sed 's/}{/}\n{/g' | tail -n1)
    
    # Validate JSON output
    if echo "$json_output" | jq empty 2>/dev/null; then
        echo "$json_output"
    else
        log_warn "$COMPONENT" "Invalid JSON output from $component_name detection script"
        echo "{\"component\":\"$component_name\",\"error\":\"invalid_output\"}"
        return 1
    fi
    
    # Log performance metrics
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_performance "$COMPONENT" "${component_name}_detection" "$duration"
}

# Orchestrate all component detections
orchestrate_detections() {
    log_info "$COMPONENT" "Starting update detection orchestration"
    
    local components=()
    
    # Determine which components to check
    if [[ -n "$SPECIFIC_COMPONENT" ]]; then
        components=("$SPECIFIC_COMPONENT")
        log_info "$COMPONENT" "Checking specific component: $SPECIFIC_COMPONENT"
    else
        components=("k3s" "flux" "longhorn" "helm")
        log_info "$COMPONENT" "Checking all components: ${components[*]}"
    fi
    
    local results="{}"
    local total_components=${#components[@]}
    local successful_components=0
    local failed_components=0
    
    # Process each component
    for component_name in "${components[@]}"; do
        log_info "$COMPONENT" "Processing component: $component_name"
        
        local component_result
        if component_result=$(execute_component_detection "$component_name"); then
            successful_components=$((successful_components + 1))
            log_info "$COMPONENT" "Successfully processed: $component_name"
        else
            failed_components=$((failed_components + 1))
            log_error "$COMPONENT" "Failed to process: $component_name"
        fi
        
        # Add result to collection
        results=$(echo "$results" | jq --arg comp "$component_name" --argjson data "$component_result" '.[$comp] = $data')
    done
    
    # Generate summary
    local summary
    summary=$(jq -n \
        --arg total "$total_components" \
        --arg successful "$successful_components" \
        --arg failed "$failed_components" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            total_components: ($total | tonumber),
            successful_components: ($successful | tonumber),
            failed_components: ($failed | tonumber),
            success_rate: (($successful | tonumber) / ($total | tonumber) * 100 | round),
            execution_timestamp: $timestamp
        }')
    
    # Combine results with summary
    local final_result
    final_result=$(echo "$results" | jq --argjson summary "$summary" '. + {execution_summary: $summary}')
    
    log_info "$COMPONENT" "Detection orchestration completed: $successful_components/$total_components successful"
    echo "$final_result"
}

# Generate final report
generate_final_report() {
    local detection_results="$1"
    
    log_info "$COMPONENT" "Generating final update report"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "$COMPONENT" "DRY RUN: Would generate report in $OUTPUT_FORMAT format"
        if [[ -n "$OUTPUT_FILE" ]]; then
            log_info "$COMPONENT" "DRY RUN: Would save report to: $OUTPUT_FILE"
        fi
        return 0
    fi
    
    # Use the existing report generator
    local report_args=()
    report_args+=("--format" "$OUTPUT_FORMAT")
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        report_args+=("--output" "$OUTPUT_FILE")
    fi
    
    if [[ -n "$SPECIFIC_COMPONENT" ]]; then
        report_args+=("--component" "$SPECIFIC_COMPONENT")
    fi
    
    # Execute report generator
    local report_script="${SCRIPT_DIR}/generate-update-report.sh"
    if [[ -x "$report_script" ]]; then
        log_info "$COMPONENT" "Executing report generator with args: ${report_args[*]}"
        "$report_script" "${report_args[@]}" || {
            log_error "$COMPONENT" "Report generation failed"
            return 1
        }
    else
        log_error "$COMPONENT" "Report generator script not found: $report_script"
        return 1
    fi
    
    log_info "$COMPONENT" "Final report generation completed"
}

# Cleanup and maintenance
perform_cleanup() {
    log_info "$COMPONENT" "Performing system cleanup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "$COMPONENT" "DRY RUN: Would perform cleanup operations"
        return 0
    fi
    
    # Clean up old logs
    cleanup_old_logs "${SCRIPT_DIR}/logs"
    
    # Clean up old version tracking data
    local retention_days
    retention_days=$(get_config "global" "history_retention_days" "90")
    cleanup_version_tracking "$retention_days" "$COMPONENT"
    
    # Clean up old reports
    local reports_dir="${SCRIPT_DIR}/reports"
    if [[ -d "$reports_dir" ]]; then
        find "$reports_dir" -name "*.json" -o -name "*.yaml" -o -name "*.txt" | \
        while read -r file; do
            local file_age_days
            if command -v stat >/dev/null 2>&1; then
                # macOS/BSD stat
                file_age_days=$(( ($(date +%s) - $(stat -f%m "$file" 2>/dev/null || echo "0")) / 86400 ))
            else
                # GNU stat (Linux)
                file_age_days=$(( ($(date +%s) - $(stat -c%Y "$file" 2>/dev/null || echo "0")) / 86400 ))
            fi
            
            if [[ $file_age_days -gt $retention_days ]]; then
                rm -f "$file" 2>/dev/null || true
                log_debug "$COMPONENT" "Removed old report file: $(basename "$file")"
            fi
        done
    fi
    
    log_info "$COMPONENT" "System cleanup completed"
}

# Cleanup function for emergency exits
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_warn "$COMPONENT" "Script exiting with error code $exit_code, performing cleanup"
        # Kill any background processes
        pkill -f "kubectl port-forward" 2>/dev/null || true
        # Clean up temporary files if any were created
        rm -f /tmp/update-detection-* 2>/dev/null || true
    fi
}

# Main execution function
main() {
    local start_time
    start_time=$(date +%s)
    
    # Set up cleanup trap
    trap cleanup_on_exit EXIT
    
    # Parse command line arguments
    parse_args "$@"
    
    # Initialize system
    initialize_system
    
    log_info "$COMPONENT" "Starting GitOps cluster update detection"
    
    # Check prerequisites
    check_prerequisites
    
    # Print configuration summary if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        print_config_summary
    fi
    
    # Orchestrate detections
    local detection_results
    if detection_results=$(orchestrate_detections); then
        log_info "$COMPONENT" "Update detection orchestration completed successfully"
    else
        log_error "$COMPONENT" "Update detection orchestration failed"
        exit 1
    fi
    
    # Generate final report
    generate_final_report "$detection_results"
    
    # Perform cleanup
    perform_cleanup
    
    # Log final performance metrics
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_performance "$COMPONENT" "full_update_detection" "$duration"
    
    log_info "$COMPONENT" "Update detection completed successfully in ${duration}s"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi