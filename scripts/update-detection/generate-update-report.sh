#!/bin/bash

# Unified Update Report Generator
# Aggregates update information from all component detection scripts and generates comprehensive reports

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LOGS_DIR="${SCRIPT_DIR}/logs"
REPORTS_DIR="${SCRIPT_DIR}/reports"

# Ensure directories exist
mkdir -p "${CONFIG_DIR}" "${LOGS_DIR}" "${REPORTS_DIR}"

# Default configuration
DEFAULT_OUTPUT_FORMAT="json"
DEFAULT_INCLUDE_HISTORY="false"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOGS_DIR}/update-report.log"
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Generate unified update report from all component detection scripts.

OPTIONS:
    -f, --format FORMAT     Output format: json, yaml, text (default: json)
    -o, --output FILE       Output file (default: stdout)
    -h, --history          Include update history
    --component COMPONENT   Only check specific component: k3s, flux, longhorn, helm
    --help                 Show this help message

EXAMPLES:
    $0                                    # Generate JSON report to stdout
    $0 -f yaml -o report.yaml            # Generate YAML report to file
    $0 --component k3s                   # Only check k3s updates
    $0 -f text --history                 # Generate text report with history

EOF
}

# Parse command line arguments
parse_args() {
    OUTPUT_FORMAT="$DEFAULT_OUTPUT_FORMAT"
    OUTPUT_FILE=""
    INCLUDE_HISTORY="$DEFAULT_INCLUDE_HISTORY"
    SPECIFIC_COMPONENT=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--history)
                INCLUDE_HISTORY="true"
                shift
                ;;
            --component)
                SPECIFIC_COMPONENT="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate output format
    case "$OUTPUT_FORMAT" in
        json|yaml|text) ;;
        *)
            log "ERROR" "Invalid output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
    
    # Validate component if specified
    if [[ -n "$SPECIFIC_COMPONENT" ]]; then
        case "$SPECIFIC_COMPONENT" in
            k3s|flux|longhorn|helm) ;;
            *)
                log "ERROR" "Invalid component: $SPECIFIC_COMPONENT"
                exit 1
                ;;
        esac
    fi
}

# Run component detection script and capture output
run_component_detection() {
    local component="$1"
    local script_path="${SCRIPT_DIR}/detect-${component}-updates.sh"
    
    if [[ ! -x "$script_path" ]]; then
        log "WARN" "Detection script not found or not executable: $script_path"
        echo "{\"component\":\"$component\",\"error\":\"script_not_found\"}"
        return 0
    fi
    
    log "INFO" "Running $component update detection"
    
    # Run the script and capture output, filtering out log lines
    local output
    local raw_output
    raw_output=$("$script_path" 2>/dev/null) || {
        log "WARN" "Failed to run $component detection script"
        echo "{\"component\":\"$component\",\"error\":\"execution_failed\"}"
        return 0
    }
    
    # Extract JSON by finding lines that start with { and end with }
    output=$(echo "$raw_output" | sed -n '/^{/,/^}$/p' | tr -d '\n' | sed 's/}{/}\n{/g' | tail -n 1)
    
    # Validate JSON output
    if echo "$output" | jq empty 2>/dev/null; then
        echo "$output"
    else
        log "WARN" "Invalid JSON output from $component detection script"
        echo "{\"component\":\"$component\",\"error\":\"invalid_output\"}"
    fi
}

# Aggregate all component updates
aggregate_updates() {
    local components=()
    
    # Determine which components to check
    if [[ -n "$SPECIFIC_COMPONENT" ]]; then
        components=("$SPECIFIC_COMPONENT")
    else
        components=("k3s" "flux" "longhorn" "helm")
    fi
    
    local aggregated_data="{\"components\":{},\"summary\":{}}"
    local total_updates=0
    local security_updates=0
    local breaking_changes=0
    local components_with_updates=0
    
    # Process each component
    for component in "${components[@]}"; do
        log "INFO" "Processing $component updates"
        
        local component_data
        component_data=$(run_component_detection "$component")
        
        # Add component data to aggregated result
        aggregated_data=$(echo "$aggregated_data" | jq --argjson data "$component_data" ".components[\"$component\"] = \$data")
        
        # Update summary statistics
        if echo "$component_data" | jq -e '.update_available == true' >/dev/null 2>&1; then
            components_with_updates=$((components_with_updates + 1))
            
            # Count updates based on component type
            if [[ "$component" == "helm" ]]; then
                local helm_updates
                helm_updates=$(echo "$component_data" | jq -r '.updates_available // 0')
                total_updates=$((total_updates + helm_updates))
            else
                total_updates=$((total_updates + 1))
            fi
        fi
        
        # Check for security updates
        if echo "$component_data" | jq -e '.security_update == true' >/dev/null 2>&1; then
            security_updates=$((security_updates + 1))
        fi
        
        # Check for breaking changes
        if echo "$component_data" | jq -e '.breaking_changes == true' >/dev/null 2>&1; then
            breaking_changes=$((breaking_changes + 1))
        fi
    done
    
    # Generate summary
    local summary
    summary=$(cat <<EOF
{
  "total_components_checked": ${#components[@]},
  "components_with_updates": $components_with_updates,
  "total_updates_available": $total_updates,
  "security_updates": $security_updates,
  "breaking_changes": $breaking_changes,
  "scan_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "recommended_action": "$(get_recommended_action $security_updates $breaking_changes $total_updates)"
}
EOF
)
    
    # Add summary to aggregated data
    aggregated_data=$(echo "$aggregated_data" | jq --argjson summary "$summary" '.summary = $summary')
    
    echo "$aggregated_data"
}

# Get recommended action based on update analysis
get_recommended_action() {
    local security_updates="$1"
    local breaking_changes="$2"
    local total_updates="$3"
    
    if [[ "$security_updates" -gt 0 ]]; then
        echo "immediate_security_update"
    elif [[ "$breaking_changes" -gt 0 ]]; then
        echo "schedule_maintenance_with_testing"
    elif [[ "$total_updates" -gt 0 ]]; then
        echo "schedule_maintenance"
    else
        echo "no_action_required"
    fi
}

# Load update history
load_update_history() {
    local history_file="${REPORTS_DIR}/update-history.json"
    
    if [[ -f "$history_file" ]]; then
        cat "$history_file"
    else
        echo "[]"
    fi
}

# Save current report to history
save_to_history() {
    local report_data="$1"
    local history_file="${REPORTS_DIR}/update-history.json"
    
    # Load existing history
    local history
    history=$(load_update_history)
    
    # Add current report to history
    local updated_history
    updated_history=$(echo "$history" | jq --argjson report "$report_data" '. + [$report]')
    
    # Keep only last 30 entries
    updated_history=$(echo "$updated_history" | jq '.[(-30):]')
    
    # Save updated history
    echo "$updated_history" > "$history_file"
    
    log "INFO" "Report saved to update history"
}

# Convert JSON to YAML format
json_to_yaml() {
    local json_data="$1"
    
    # Use yq if available, otherwise use a simple conversion
    if command -v yq >/dev/null 2>&1; then
        echo "$json_data" | yq eval -P
    else
        # Simple JSON to YAML conversion using jq
        echo "$json_data" | jq -r 'to_entries | map("\(.key): \(.value)") | .[]'
    fi
}

# Convert JSON to human-readable text format
json_to_text() {
    local json_data="$1"
    
    cat <<EOF
# GitOps Cluster Update Report
Generated: $(echo "$json_data" | jq -r '.summary.scan_timestamp')

## Summary
- Components Checked: $(echo "$json_data" | jq -r '.summary.total_components_checked')
- Components with Updates: $(echo "$json_data" | jq -r '.summary.components_with_updates')
- Total Updates Available: $(echo "$json_data" | jq -r '.summary.total_updates_available')
- Security Updates: $(echo "$json_data" | jq -r '.summary.security_updates')
- Breaking Changes: $(echo "$json_data" | jq -r '.summary.breaking_changes')
- Recommended Action: $(echo "$json_data" | jq -r '.summary.recommended_action')

## Component Details

EOF

    # Process each component
    echo "$json_data" | jq -r '.components | to_entries[] | "\(.key):\(.value)"' | while IFS=':' read -r component data; do
        echo "### $component"
        
        # Check if component has error
        if echo "$data" | jq -e '.error' >/dev/null 2>&1; then
            echo "  Status: ERROR - $(echo "$data" | jq -r '.error')"
            echo ""
            continue
        fi
        
        # Display component-specific information
        case "$component" in
            k3s|flux|longhorn)
                echo "  Current Version: $(echo "$data" | jq -r '.current_version // .current_app_version // "unknown"')"
                echo "  Latest Version: $(echo "$data" | jq -r '.latest_version // .latest_app_version // "unknown"')"
                echo "  Update Available: $(echo "$data" | jq -r '.update_available')"
                echo "  Security Update: $(echo "$data" | jq -r '.security_update')"
                echo "  Breaking Changes: $(echo "$data" | jq -r '.breaking_changes')"
                ;;
            helm)
                echo "  Total Releases: $(echo "$data" | jq -r '.total_releases')"
                echo "  Updates Available: $(echo "$data" | jq -r '.updates_available')"
                ;;
        esac
        
        echo ""
    done
}

# Format and output the report
format_output() {
    local report_data="$1"
    
    case "$OUTPUT_FORMAT" in
        json)
            echo "$report_data" | jq .
            ;;
        yaml)
            json_to_yaml "$report_data"
            ;;
        text)
            json_to_text "$report_data"
            ;;
    esac
}

# Main execution
main() {
    log "INFO" "Starting unified update report generation"
    
    # Parse command line arguments
    parse_args "$@"
    
    log "INFO" "Output format: $OUTPUT_FORMAT"
    if [[ -n "$OUTPUT_FILE" ]]; then
        log "INFO" "Output file: $OUTPUT_FILE"
    fi
    if [[ -n "$SPECIFIC_COMPONENT" ]]; then
        log "INFO" "Checking only: $SPECIFIC_COMPONENT"
    fi
    
    # Aggregate update information
    local report_data
    report_data=$(aggregate_updates) || {
        log "ERROR" "Failed to aggregate update information"
        exit 1
    }
    
    # Add history if requested
    if [[ "$INCLUDE_HISTORY" == "true" ]]; then
        local history
        history=$(load_update_history)
        report_data=$(echo "$report_data" | jq --argjson history "$history" '. + {"history": $history}')
        log "INFO" "Update history included in report"
    fi
    
    # Save to history
    save_to_history "$report_data"
    
    # Format and output the report
    local formatted_output
    formatted_output=$(format_output "$report_data")
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$formatted_output" > "$OUTPUT_FILE"
        log "INFO" "Report saved to: $OUTPUT_FILE"
    else
        echo "$formatted_output"
    fi
    
    log "INFO" "Update report generation completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi