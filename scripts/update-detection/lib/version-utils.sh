#!/bin/bash

# Version Comparison and Tracking Utilities
# Provides functions for comparing versions and tracking component states

# Version comparison function using semantic versioning
compare_versions() {
    local version1="$1"
    local version2="$2"
    local component="${3:-version-utils}"
    
    # Normalize versions by removing 'v' prefix and any suffixes
    local v1_clean v2_clean
    v1_clean=$(echo "$version1" | sed 's/^v//' | sed 's/[+-].*//')
    v2_clean=$(echo "$version2" | sed 's/^v//' | sed 's/[+-].*//')
    
    # Split versions into arrays
    IFS='.' read -ra v1_parts <<< "$v1_clean"
    IFS='.' read -ra v2_parts <<< "$v2_clean"
    
    # Pad arrays to same length
    local max_length=${#v1_parts[@]}
    if [[ ${#v2_parts[@]} -gt $max_length ]]; then
        max_length=${#v2_parts[@]}
    fi
    
    # Compare each part
    for ((i=0; i<max_length; i++)); do
        local part1=${v1_parts[i]:-0}
        local part2=${v2_parts[i]:-0}
        
        # Remove non-numeric characters for comparison
        part1=$(echo "$part1" | sed 's/[^0-9].*//')
        part2=$(echo "$part2" | sed 's/[^0-9].*//')
        
        # Default to 0 if empty
        part1=${part1:-0}
        part2=${part2:-0}
        
        if [[ $part1 -lt $part2 ]]; then
            echo "older"
            return 0
        elif [[ $part1 -gt $part2 ]]; then
            echo "newer"
            return 0
        fi
    done
    
    echo "equal"
}

# Check if a version is a pre-release
is_prerelease() {
    local version="$1"
    local component="${2:-version-utils}"
    
    log_function_entry "$component" "is_prerelease" "$version"
    
    # Check for common pre-release indicators
    if echo "$version" | grep -qiE "(alpha|beta|rc|pre|dev|snapshot|nightly)"; then
        log_function_exit "$component" "is_prerelease" 0
        echo "true"
        return 0
    fi
    
    log_function_exit "$component" "is_prerelease" 0
    echo "false"
}

# Extract version from various formats
extract_version() {
    local input="$1"
    local component="${2:-version-utils}"
    
    log_function_entry "$component" "extract_version" "$input"
    
    # Try different patterns to extract version
    local version=""
    
    # Pattern 1: v1.2.3 format
    if [[ -z "$version" ]]; then
        version=$(echo "$input" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' | head -n1)
    fi
    
    # Pattern 2: Just numbers with dots
    if [[ -z "$version" ]]; then
        version=$(echo "$input" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    fi
    
    # Pattern 3: Container image tag format
    if [[ -z "$version" ]]; then
        version=$(echo "$input" | sed -n 's/.*:\(v\?[0-9][^[:space:]]*\).*/\1/p' | head -n1)
    fi
    
    log_function_exit "$component" "extract_version" 0
    echo "$version"
}

# Get version type (major, minor, patch)
get_version_type() {
    local current_version="$1"
    local new_version="$2"
    local component="${3:-version-utils}"
    
    log_function_entry "$component" "get_version_type" "$current_version" "$new_version"
    
    # Clean versions
    local current_clean new_clean
    current_clean=$(echo "$current_version" | sed 's/^v//' | sed 's/[+-].*//')
    new_clean=$(echo "$new_version" | sed 's/^v//' | sed 's/[+-].*//')
    
    # Split into parts
    IFS='.' read -ra current_parts <<< "$current_clean"
    IFS='.' read -ra new_parts <<< "$new_clean"
    
    # Compare major version
    local current_major=${current_parts[0]:-0}
    local new_major=${new_parts[0]:-0}
    
    if [[ $new_major -gt $current_major ]]; then
        log_function_exit "$component" "get_version_type" 0
        echo "major"
        return 0
    fi
    
    # Compare minor version
    local current_minor=${current_parts[1]:-0}
    local new_minor=${new_parts[1]:-0}
    
    if [[ $new_minor -gt $current_minor ]]; then
        log_function_exit "$component" "get_version_type" 0
        echo "minor"
        return 0
    fi
    
    # Compare patch version
    local current_patch=${current_parts[2]:-0}
    local new_patch=${new_parts[2]:-0}
    
    if [[ $new_patch -gt $current_patch ]]; then
        log_function_exit "$component" "get_version_type" 0
        echo "patch"
        return 0
    fi
    
    log_function_exit "$component" "get_version_type" 0
    echo "equal"
}

# Track component version state
track_component_version() {
    local component_name="$1"
    local current_version="$2"
    local latest_version="$3"
    local additional_data="${4:-{}}"
    local component="${5:-version-utils}"
    
    log_function_entry "$component" "track_component_version" "$component_name" "$current_version" "$latest_version"
    
    local tracking_file="${SCRIPT_DIR}/../logs/version-tracking.json"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create tracking entry
    local tracking_entry
    tracking_entry=$(jq -n \
        --arg component "$component_name" \
        --arg current "$current_version" \
        --arg latest "$latest_version" \
        --arg timestamp "$timestamp" \
        --argjson additional "$additional_data" \
        '{
            component: $component,
            current_version: $current,
            latest_version: $latest,
            timestamp: $timestamp,
            comparison: (if $current == $latest then "equal" else "update_available" end),
            additional_data: $additional
        }')
    
    # Load existing tracking data
    local tracking_data="[]"
    if [[ -f "$tracking_file" ]]; then
        tracking_data=$(cat "$tracking_file" 2>/dev/null || echo "[]")
    fi
    
    # Add new entry
    tracking_data=$(echo "$tracking_data" | jq --argjson entry "$tracking_entry" '. + [$entry]')
    
    # Keep only last 100 entries per component
    tracking_data=$(echo "$tracking_data" | jq --arg comp "$component_name" '
        group_by(.component) | 
        map(if .[0].component == $comp then .[-100:] else . end) | 
        flatten')
    
    # Save tracking data
    echo "$tracking_data" > "$tracking_file"
    
    log_info "$component" "Version tracking updated for $component_name: $current_version -> $latest_version"
    log_function_exit "$component" "track_component_version" 0
}

# Get version history for a component
get_version_history() {
    local component_name="$1"
    local limit="${2:-10}"
    local component="${3:-version-utils}"
    
    log_function_entry "$component" "get_version_history" "$component_name" "$limit"
    
    local tracking_file="${SCRIPT_DIR}/../logs/version-tracking.json"
    
    if [[ ! -f "$tracking_file" ]]; then
        echo "[]"
        log_function_exit "$component" "get_version_history" 0
        return 0
    fi
    
    # Get history for specific component
    local history
    history=$(jq --arg comp "$component_name" --argjson limit "$limit" '
        map(select(.component == $comp)) | 
        sort_by(.timestamp) | 
        reverse | 
        .[:$limit]' "$tracking_file" 2>/dev/null || echo "[]")
    
    log_function_exit "$component" "get_version_history" 0
    echo "$history"
}

# Generate version comparison report
generate_version_report() {
    local components_data="$1"
    local component="${2:-version-utils}"
    
    log_function_entry "$component" "generate_version_report" "components_data"
    
    local report_data="{}"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Process each component
    echo "$components_data" | jq -r 'keys[]' | while read -r comp_name; do
        local comp_data
        comp_data=$(echo "$components_data" | jq --arg comp "$comp_name" '.[$comp]')
        
        local current_version latest_version
        current_version=$(echo "$comp_data" | jq -r '.current_version // .current_app_version // "unknown"')
        latest_version=$(echo "$comp_data" | jq -r '.latest_version // .latest_app_version // "unknown"')
        
        if [[ "$current_version" != "unknown" ]] && [[ "$latest_version" != "unknown" ]]; then
            # Compare versions
            local comparison
            comparison=$(compare_versions "$current_version" "$latest_version" "$component")
            
            # Get version type
            local version_type
            version_type=$(get_version_type "$current_version" "$latest_version" "$component")
            
            # Check if pre-release
            local is_latest_prerelease
            is_latest_prerelease=$(is_prerelease "$latest_version" "$component")
            
            # Create component report
            local comp_report
            comp_report=$(jq -n \
                --arg current "$current_version" \
                --arg latest "$latest_version" \
                --arg comparison "$comparison" \
                --arg version_type "$version_type" \
                --arg is_prerelease "$is_latest_prerelease" \
                '{
                    current_version: $current,
                    latest_version: $latest,
                    comparison: $comparison,
                    version_type: $version_type,
                    latest_is_prerelease: ($is_prerelease == "true"),
                    update_recommended: ($comparison == "older" and $is_prerelease == "false")
                }')
            
            # Add to report
            report_data=$(echo "$report_data" | jq --arg comp "$comp_name" --argjson data "$comp_report" '.[$comp] = $data')
            
            # Track version
            track_component_version "$comp_name" "$current_version" "$latest_version" "$comp_data" "$component"
        fi
    done
    
    # Add metadata
    report_data=$(echo "$report_data" | jq --arg timestamp "$timestamp" '. + {generated_at: $timestamp}')
    
    log_function_exit "$component" "generate_version_report" 0
    echo "$report_data"
}

# Validate version format
validate_version_format() {
    local version="$1"
    local component="${2:-version-utils}"
    
    log_function_entry "$component" "validate_version_format" "$version"
    
    # Check if version matches semantic versioning pattern
    if echo "$version" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+'; then
        log_function_exit "$component" "validate_version_format" 0
        echo "valid"
        return 0
    fi
    
    log_function_exit "$component" "validate_version_format" 1
    echo "invalid"
    return 1
}

# Clean up old version tracking data
cleanup_version_tracking() {
    local retention_days="${1:-90}"
    local component="${2:-version-utils}"
    
    log_function_entry "$component" "cleanup_version_tracking" "$retention_days"
    
    local tracking_file="${SCRIPT_DIR}/../logs/version-tracking.json"
    
    if [[ ! -f "$tracking_file" ]]; then
        log_function_exit "$component" "cleanup_version_tracking" 0
        return 0
    fi
    
    # Calculate cutoff date
    local cutoff_date
    if command -v gdate >/dev/null 2>&1; then
        # macOS with GNU date
        cutoff_date=$(gdate -d "$retention_days days ago" -u +%Y-%m-%dT%H:%M:%SZ)
    elif date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        cutoff_date=$(date -d "$retention_days days ago" -u +%Y-%m-%dT%H:%M:%SZ)
    else
        # BSD date (macOS default)
        cutoff_date=$(date -u -v-"${retention_days}d" +%Y-%m-%dT%H:%M:%SZ)
    fi
    
    # Filter out old entries
    local filtered_data
    filtered_data=$(jq --arg cutoff "$cutoff_date" '
        map(select(.timestamp >= $cutoff))' "$tracking_file" 2>/dev/null || echo "[]")
    
    # Save filtered data
    echo "$filtered_data" > "$tracking_file"
    
    log_info "$component" "Version tracking cleanup completed, removed entries older than $retention_days days"
    log_function_exit "$component" "cleanup_version_tracking" 0
}

# Export functions for use in other scripts
export -f compare_versions
export -f is_prerelease
export -f extract_version
export -f get_version_type
export -f track_component_version
export -f get_version_history
export -f generate_version_report
export -f validate_version_format
export -f cleanup_version_tracking