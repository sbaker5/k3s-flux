#!/bin/bash

# Flux Update Detection Script
# Checks individual Flux controller GitHub releases and compares with current cluster versions
# Note: Flux v2 is a meta-project - individual controllers have their own versions

set -euo pipefail

# Configuration - Individual controller repositories (controller:repo format)
CONTROLLER_REPOS=(
    "source-controller:fluxcd/source-controller"
    "kustomize-controller:fluxcd/kustomize-controller"
    "helm-controller:fluxcd/helm-controller"
    "notification-controller:fluxcd/notification-controller"
)

FLUX_MAIN_REPO="fluxcd/flux2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Ensure directories exist
mkdir -p "${CONFIG_DIR}" "${LOGS_DIR}"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOGS_DIR}/flux-detection.log"
}

# Get repository for a controller
get_controller_repo() {
    local controller="$1"
    for entry in "${CONTROLLER_REPOS[@]}"; do
        local ctrl="${entry%%:*}"
        local repo="${entry##*:}"
        if [[ "$ctrl" == "$controller" ]]; then
            echo "$repo"
            return 0
        fi
    done
    echo ""
    return 1
}

# Get current Flux controller versions from cluster
get_current_flux_versions() {
    local versions_json="{"
    local first=true
    
    for entry in "${CONTROLLER_REPOS[@]}"; do
        local controller="${entry%%:*}"
        local version=""
        
        # Try to get version from deployment image
        if command -v kubectl >/dev/null 2>&1; then
            version=$(kubectl get deployment "$controller" -n flux-system -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "")
        fi
        
        # If not found, use a default version for testing
        if [[ -z "$version" ]]; then
            version="v1.6.0"  # More realistic default for controller versions
        fi
        
        # Add to JSON structure
        if [[ "$first" == "true" ]]; then
            first=false
        else
            versions_json+=","
        fi
        versions_json+="\"$controller\":\"$version\""
    done
    
    versions_json+="}"
    echo "$versions_json"
}

# Get latest version for a specific controller
get_controller_latest_version() {
    local controller="$1"
    local repo
    repo=$(get_controller_repo "$controller")
    
    if [[ -z "$repo" ]]; then
        echo "unknown"
        return 1
    fi
    
    local latest_version
    latest_version=$(curl -s --connect-timeout 10 --max-time 30 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/$repo/releases/latest" | jq -r '.tag_name' 2>/dev/null || echo "")
    
    if [[ -z "$latest_version" ]] || [[ "$latest_version" == "null" ]]; then
        echo "unknown"
        return 1
    fi
    
    echo "$latest_version"
}

# Get Flux v2 meta-release information
get_flux_meta_release() {
    local latest_release_json
    latest_release_json=$(curl -s --connect-timeout 10 --max-time 30 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/$FLUX_MAIN_REPO/releases/latest" || echo "{}")
    
    if ! echo "$latest_release_json" | jq empty 2>/dev/null; then
        echo "{}"
        return 1
    fi
    
    echo "$latest_release_json"
}

# Parse release information and identify security updates
parse_flux_release_info() {
    local current_versions_json="$1"
    
    # Get Flux v2 meta-release information
    local flux_meta_release
    flux_meta_release=$(get_flux_meta_release)
    
    local flux_version
    local release_date
    local release_body
    
    flux_version=$(echo "$flux_meta_release" | jq -r '.tag_name // "unknown"')
    release_date=$(echo "$flux_meta_release" | jq -r '.published_at // ""')
    release_body=$(echo "$flux_meta_release" | jq -r '.body // ""')
    
    # Check each controller for updates
    local controller_updates="{}"
    local any_updates="false"
    local total_updates=0
    
    for entry in "${CONTROLLER_REPOS[@]}"; do
        local controller="${entry%%:*}"
        local repo="${entry##*:}"
        
        local current_version
        current_version=$(echo "$current_versions_json" | jq -r ".\"$controller\"")
        
        local latest_version
        latest_version=$(get_controller_latest_version "$controller")
        
        local update_available="false"
        if [[ "$current_version" != "$latest_version" ]] && [[ "$latest_version" != "unknown" ]]; then
            update_available="true"
            any_updates="true"
            total_updates=$((total_updates + 1))
        fi
        
        # Add controller update info
        local controller_info
        controller_info=$(cat <<EOF
{
  "current_version": "$current_version",
  "latest_version": "$latest_version",
  "update_available": $update_available,
  "repository": "$repo"
}
EOF
)
        controller_updates=$(echo "$controller_updates" | jq --argjson info "$controller_info" ".\"$controller\" = \$info")
    done
    
    # Check for security indicators in release notes
    local security_update="false"
    if echo "$release_body" | grep -qi -E "(security|cve|vulnerability|patch)"; then
        security_update="true"
    fi
    
    # Check for breaking changes
    local breaking_changes="false"
    if echo "$release_body" | grep -qi -E "(breaking|incompatible|deprecated|removed)"; then
        breaking_changes="true"
    fi
    
    # Check for CRD changes
    local crd_changes="false"
    if echo "$release_body" | grep -qi -E "(crd|custom resource|api version)"; then
        crd_changes="true"
    fi
    
    # Generate structured output
    cat <<EOF
{
  "component": "flux",
  "flux_version": "$flux_version",
  "update_available": $any_updates,
  "total_controller_updates": $total_updates,
  "security_update": $security_update,
  "breaking_changes": $breaking_changes,
  "crd_changes": $crd_changes,
  "controllers": $controller_updates,
  "current_versions": $current_versions_json,
  "release_date": "$release_date",
  "changelog_url": "https://github.com/fluxcd/flux2/releases/tag/$flux_version",
  "scan_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Check for CRD version compatibility
check_crd_compatibility() {
    local latest_version="$1"
    
    log "INFO" "Checking CRD compatibility for version $latest_version"
    
    # Get current CRD versions from cluster
    local crd_info=""
    if command -v kubectl >/dev/null 2>&1; then
        # Check for key Flux CRDs
        local flux_crds=("gitrepositories.source.toolkit.fluxcd.io" "kustomizations.kustomize.toolkit.fluxcd.io" "helmreleases.helm.toolkit.fluxcd.io")
        
        for crd in "${flux_crds[@]}"; do
            local crd_version
            crd_version=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null || echo "not-found")
            crd_info+="$crd:$crd_version "
        done
        
        log "INFO" "Current CRD versions: $crd_info"
    else
        log "WARN" "kubectl not available, cannot check CRD versions"
    fi
    
    echo "$crd_info"
}

# Main execution
main() {
    log "INFO" "Starting Flux update detection"
    
    # Get current versions
    local current_versions_json
    current_versions_json=$(get_current_flux_versions) || {
        log "ERROR" "Failed to get current Flux versions"
        exit 1
    }
    log "INFO" "Current Flux controller versions retrieved"
    
    # Parse and output results
    parse_flux_release_info "$current_versions_json" || {
        log "ERROR" "Failed to parse release information"
        exit 1
    }
    
    log "INFO" "Flux update detection completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi