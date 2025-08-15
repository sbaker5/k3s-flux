#!/bin/bash

# Helm Chart Update Detection Script
# Scans all HelmRelease resources for chart updates and checks repositories for new versions

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Ensure directories exist
mkdir -p "${CONFIG_DIR}" "${LOGS_DIR}"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOGS_DIR}/helm-detection.log"
}

# Get all HelmRelease resources from cluster
get_helm_releases() {
    local helm_releases_json="[]"
    
    if command -v kubectl >/dev/null 2>&1; then
        # Get all HelmRelease resources across all namespaces
        local releases
        releases=$(kubectl get helmreleases.helm.toolkit.fluxcd.io -A -o json 2>/dev/null || echo '{"items":[]}')
        
        if [[ -n "$releases" ]] && echo "$releases" | jq empty 2>/dev/null; then
            helm_releases_json="$releases"
        fi
    fi
    
    echo "$helm_releases_json"
}

# Check for updates for a specific HelmRelease
check_helm_release_updates() {
    local release_name="$1"
    local release_namespace="$2"
    local chart_name="$3"
    local current_version="$4"
    local repo_url="$5"
    
    local latest_version=""
    local update_available="false"
    local breaking_changes="false"
    local dependencies_changed="false"
    
    # Try to get latest version using helm search
    if command -v helm >/dev/null 2>&1 && [[ -n "$repo_url" ]]; then
        # Extract repo name from chart name (format: repo/chart)
        local repo_name
        repo_name=$(echo "$chart_name" | cut -d'/' -f1 2>/dev/null || echo "")
        
        if [[ -n "$repo_name" ]]; then
            # Add/update repository
            helm repo add "$repo_name" "$repo_url" >/dev/null 2>&1 || true
            helm repo update "$repo_name" >/dev/null 2>&1 || true
            
            # Search for latest version
            latest_version=$(helm search repo "$chart_name" --output json 2>/dev/null | jq -r '.[0].version' 2>/dev/null || echo "")
        fi
    fi
    
    # If helm search failed, use current version as latest (no update available)
    if [[ -z "$latest_version" ]]; then
        latest_version="$current_version"
    fi
    
    # Compare versions
    if [[ "$current_version" != "$latest_version" ]]; then
        update_available="true"
        
        # Try to get chart information to detect breaking changes
        if command -v helm >/dev/null 2>&1 && [[ -n "$chart_name" ]]; then
            # Get chart info (this is a simplified check)
            local chart_info
            chart_info=$(helm show chart "$chart_name" --version "$latest_version" 2>/dev/null || echo "")
            
            # Check for breaking changes indicators in chart description or notes
            if echo "$chart_info" | grep -qi -E "(breaking|incompatible|major|deprecated)"; then
                breaking_changes="true"
            fi
            
            # Check if dependencies changed by comparing chart metadata
            local current_chart_info
            current_chart_info=$(helm show chart "$chart_name" --version "$current_version" 2>/dev/null || echo "")
            
            if [[ -n "$chart_info" ]] && [[ -n "$current_chart_info" ]]; then
                local current_deps
                local latest_deps
                current_deps=$(echo "$current_chart_info" | grep -A 20 "dependencies:" 2>/dev/null || echo "")
                latest_deps=$(echo "$chart_info" | grep -A 20 "dependencies:" 2>/dev/null || echo "")
                
                if [[ "$current_deps" != "$latest_deps" ]]; then
                    dependencies_changed="true"
                fi
            fi
        fi
    fi
    
    # Generate JSON for this release
    cat <<EOF
{
  "name": "$release_name",
  "namespace": "$release_namespace",
  "chart": "$chart_name",
  "current_version": "$current_version",
  "latest_version": "$latest_version",
  "update_available": $update_available,
  "breaking_changes": $breaking_changes,
  "dependencies_changed": $dependencies_changed,
  "repository_url": "$repo_url"
}
EOF
}

# Parse all HelmRelease resources and check for updates
parse_helm_releases() {
    local helm_releases_json="$1"
    
    local releases_array="[]"
    local total_releases=0
    local updates_available=0
    
    # Process each HelmRelease
    local releases
    releases=$(echo "$helm_releases_json" | jq -r '.items[]' 2>/dev/null || echo "")
    
    if [[ -n "$releases" ]]; then
        while IFS= read -r release; do
            if [[ -z "$release" ]] || [[ "$release" == "null" ]]; then
                continue
            fi
            
            # Extract release information
            local name namespace chart_name current_version repo_url
            name=$(echo "$release" | jq -r '.metadata.name' 2>/dev/null || echo "unknown")
            namespace=$(echo "$release" | jq -r '.metadata.namespace' 2>/dev/null || echo "unknown")
            chart_name=$(echo "$release" | jq -r '.spec.chart.spec.chart' 2>/dev/null || echo "unknown")
            current_version=$(echo "$release" | jq -r '.spec.chart.spec.version // "latest"' 2>/dev/null || echo "latest")
            
            # Get repository URL from sourceRef
            local source_name source_namespace
            source_name=$(echo "$release" | jq -r '.spec.chart.spec.sourceRef.name' 2>/dev/null || echo "")
            source_namespace=$(echo "$release" | jq -r '.spec.chart.spec.sourceRef.namespace // "flux-system"' 2>/dev/null || echo "flux-system")
            
            repo_url=""
            if [[ -n "$source_name" ]] && command -v kubectl >/dev/null 2>&1; then
                repo_url=$(kubectl get helmrepository "$source_name" -n "$source_namespace" -o jsonpath='{.spec.url}' 2>/dev/null || echo "")
            fi
            
            # Check for updates
            local release_update_info
            release_update_info=$(check_helm_release_updates "$name" "$namespace" "$chart_name" "$current_version" "$repo_url")
            
            # Add to releases array
            releases_array=$(echo "$releases_array" | jq --argjson release "$release_update_info" '. + [$release]')
            
            total_releases=$((total_releases + 1))
            
            # Check if update is available
            local update_available
            update_available=$(echo "$release_update_info" | jq -r '.update_available')
            if [[ "$update_available" == "true" ]]; then
                updates_available=$((updates_available + 1))
            fi
            
        done <<< "$(echo "$helm_releases_json" | jq -c '.items[]' 2>/dev/null)"
    fi
    
    # Generate summary
    cat <<EOF
{
  "component": "helm-charts",
  "total_releases": $total_releases,
  "updates_available": $updates_available,
  "releases": $releases_array,
  "scan_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Main execution
main() {
    log "INFO" "Starting Helm chart update detection"
    
    # Get all HelmRelease resources
    local helm_releases_json
    helm_releases_json=$(get_helm_releases) || {
        log "ERROR" "Failed to get HelmRelease resources"
        exit 1
    }
    
    local release_count
    release_count=$(echo "$helm_releases_json" | jq '.items | length' 2>/dev/null || echo "0")
    log "INFO" "Found $release_count HelmRelease resources"
    
    # Parse and check for updates
    parse_helm_releases "$helm_releases_json" || {
        log "ERROR" "Failed to parse HelmRelease information"
        exit 1
    }
    
    log "INFO" "Helm chart update detection completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi