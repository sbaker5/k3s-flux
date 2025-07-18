#!/bin/bash

# Immutable Field Change Detection Tool
# Detects changes to immutable Kubernetes fields that would cause reconciliation failures

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to get immutable fields for a resource type
get_immutable_fields() {
    local kind=$1
    case $kind in
        Deployment)
            echo "spec.selector"
            ;;
        Service)
            echo "spec.clusterIP spec.type spec.ports[].nodePort"
            ;;
        StatefulSet)
            echo "spec.selector spec.serviceName spec.volumeClaimTemplates[].metadata.name"
            ;;
        Job)
            echo "spec.selector spec.template"
            ;;
        PersistentVolume)
            echo "spec.capacity spec.accessModes spec.persistentVolumeReclaimPolicy"
            ;;
        PersistentVolumeClaim)
            echo "spec.accessModes spec.resources.requests.storage spec.storageClassName"
            ;;
        Ingress)
            echo "spec.ingressClassName"
            ;;
        NetworkPolicy)
            echo "spec.podSelector"
            ;;
        ServiceAccount)
            echo "automountServiceAccountToken"
            ;;
        Secret)
            echo "type"
            ;;
        ConfigMap)
            echo "immutable"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Detect changes to immutable Kubernetes fields between Git revisions"
    echo ""
    echo "Options:"
    echo "  -b, --base-ref REF     Base Git reference (default: HEAD~1)"
    echo "  -h, --head-ref REF     Head Git reference (default: HEAD)"
    echo "  -v, --verbose          Enable verbose output"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     # Compare HEAD with HEAD~1"
    echo "  $0 -b main -h feature  # Compare main with feature branch"
    echo "  $0 -b HEAD~3          # Compare HEAD~3 with HEAD"
}

# Function to log messages
log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $*" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
        DEBUG)
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo -e "[DEBUG] $*"
            fi
            ;;
    esac
}

# Function to extract field value from YAML
extract_field_value() {
    local file=$1
    local field=$2
    local kind=$3
    local name=$4
    
    # Use yq if available for precise field extraction
    if command -v yq >/dev/null 2>&1; then
        yq eval "select(.kind == \"$kind\" and .metadata.name == \"$name\") | .$field" "$file" 2>/dev/null || echo "null"
    else
        # Simple fallback - just extract the field line and return a hash of the content
        # This is sufficient for detecting changes without needing exact value parsing
        local field_content
        case "$field" in
            "spec.selector")
                field_content=$(awk '/^spec:$/,/^[^ ]/ { if (/^  selector:/) { found=1; next } if (found && /^    /) print; if (found && /^  [^ ]/) exit }' "$file")
                ;;
            "spec.clusterIP"|"spec.type")
                field_content=$(awk -v field="${field#spec.}" '/^spec:$/,/^[^ ]/ { if ($1 == field":") print $2 }' "$file")
                ;;
            "spec.accessModes"|"spec.resources.requests.storage"|"spec.storageClassName")
                field_content=$(awk '/^spec:$/,/^[^ ]/ { print }' "$file")
                ;;
            *)
                field_content=$(grep -A 5 -B 5 "$field" "$file" 2>/dev/null || echo "")
                ;;
        esac
        
        # Return a hash of the content to detect changes
        if [[ -n "$field_content" ]]; then
            echo "$field_content" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "$field_content"
        else
            echo "null"
        fi
    fi
}

# Function to build kustomization and extract resources
build_kustomization() {
    local kustomization_dir=$1
    local output_file=$2
    
    log DEBUG "Building kustomization in $kustomization_dir"
    
    if [[ -f "$kustomization_dir/kustomization.yaml" ]]; then
        kubectl kustomize "$kustomization_dir" > "$output_file" 2>/dev/null || {
            log WARN "Failed to build kustomization in $kustomization_dir"
            return 1
        }
    else
        log DEBUG "No kustomization.yaml found in $kustomization_dir"
        return 1
    fi
}

# Function to extract resources from built YAML
extract_resources() {
    local yaml_file=$1
    local output_dir=$2
    
    # Split YAML into individual resource files
    awk '
    BEGIN { file_count=0 }
    /^---/ { 
        if (file_count > 0) close(output_file)
        file_count++
        output_file = "'$output_dir'/resource_" file_count ".yaml"
        next
    }
    { 
        if (file_count == 0) {
            file_count++
            output_file = "'$output_dir'/resource_" file_count ".yaml"
        }
        print > output_file 
    }
    END { if (file_count > 0) close(output_file) }
    ' "$yaml_file"
}

# Function to get resource metadata
get_resource_metadata() {
    local resource_file=$1
    
    local kind=$(grep "^kind:" "$resource_file" | awk '{print $2}' | tr -d '\r')
    local name=$(grep -A 10 "^metadata:" "$resource_file" | grep "^  name:" | awk '{print $2}' | tr -d '\r')
    local namespace=$(grep -A 10 "^metadata:" "$resource_file" | grep "^  namespace:" | awk '{print $2}' | tr -d '\r')
    
    echo "$kind|$name|$namespace"
}

# Function to check immutable fields for a resource
check_resource_immutable_fields() {
    local base_file=$1
    local head_file=$2
    local resource_key=$3
    
    local kind=$(echo "$resource_key" | cut -d'|' -f1)
    local name=$(echo "$resource_key" | cut -d'|' -f2)
    local namespace=$(echo "$resource_key" | cut -d'|' -f3)
    
    local fields=$(get_immutable_fields "$kind")
    if [[ -z "$fields" ]]; then
        log DEBUG "No immutable fields defined for $kind"
        return 0
    fi
    
    local violations=0
    
    log DEBUG "Checking immutable fields for $kind/$name: $fields"
    
    for field in $fields; do
        local base_value=$(extract_field_value "$base_file" "$field" "$kind" "$name")
        local head_value=$(extract_field_value "$head_file" "$field" "$kind" "$name")
        
        if [[ "$base_value" != "$head_value" && "$base_value" != "null" && "$head_value" != "null" ]]; then
            log ERROR "Immutable field change detected in $kind/$name"
            log ERROR "  Field: $field"
            log ERROR "  Before: $base_value"
            log ERROR "  After:  $head_value"
            if [[ -n "$namespace" ]]; then
                log ERROR "  Namespace: $namespace"
            fi
            echo ""
            violations=$((violations + 1))
        fi
    done
    
    return $violations
}

# Function to process kustomizations
process_kustomizations() {
    local base_ref=$1
    local head_ref=$2
    
    local base_dir="$TEMP_DIR/base"
    local head_dir="$TEMP_DIR/head"
    local violations=0
    
    mkdir -p "$base_dir" "$head_dir"
    
    # Checkout base revision
    log INFO "Checking out base revision: $base_ref"
    git archive "$base_ref" | tar -x -C "$base_dir"
    
    # Checkout head revision  
    log INFO "Checking out head revision: $head_ref"
    git archive "$head_ref" | tar -x -C "$head_dir"
    
    # Find all kustomization directories
    local kustomization_list="$TEMP_DIR/kustomization_dirs"
    find "$head_dir" -name "kustomization.yaml" -type f | xargs dirname | sort -u > "$kustomization_list"
    
    local kustomization_count=$(wc -l < "$kustomization_list")
    log INFO "Found $kustomization_count kustomization directories"
    
    while IFS= read -r kustomization_dir; do
        [[ -n "$kustomization_dir" ]] || continue
        local rel_dir="${kustomization_dir#$head_dir/}"
        local base_kustomization_dir="$base_dir/$rel_dir"
        
        log DEBUG "Processing kustomization: $rel_dir"
        
        # Skip if base doesn't have this kustomization
        if [[ ! -f "$base_kustomization_dir/kustomization.yaml" ]]; then
            log DEBUG "Skipping new kustomization: $rel_dir"
            continue
        fi
        
        # Build kustomizations
        local base_yaml="$TEMP_DIR/base_${rel_dir//\//_}.yaml"
        local head_yaml="$TEMP_DIR/head_${rel_dir//\//_}.yaml"
        
        if ! build_kustomization "$base_kustomization_dir" "$base_yaml"; then
            continue
        fi
        
        if ! build_kustomization "$kustomization_dir" "$head_yaml"; then
            continue
        fi
        
        # Extract resources
        local base_resources_dir="$TEMP_DIR/base_resources_${rel_dir//\//_}"
        local head_resources_dir="$TEMP_DIR/head_resources_${rel_dir//\//_}"
        
        mkdir -p "$base_resources_dir" "$head_resources_dir"
        
        extract_resources "$base_yaml" "$base_resources_dir"
        extract_resources "$head_yaml" "$head_resources_dir"
        
        # Compare resources using temporary files for indexing
        local base_index="$TEMP_DIR/base_index_${rel_dir//\//_}"
        local head_index="$TEMP_DIR/head_index_${rel_dir//\//_}"
        
        # Index base resources
        > "$base_index"
        for resource_file in "$base_resources_dir"/resource_*.yaml; do
            [[ -f "$resource_file" ]] || continue
            local metadata=$(get_resource_metadata "$resource_file")
            echo "$metadata|$resource_file" >> "$base_index"
        done
        
        # Index head resources
        > "$head_index"
        for resource_file in "$head_resources_dir"/resource_*.yaml; do
            [[ -f "$resource_file" ]] || continue
            local metadata=$(get_resource_metadata "$resource_file")
            echo "$metadata|$resource_file" >> "$head_index"
        done
        
        # Check for immutable field changes
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            local resource_key=$(echo "$line" | rev | cut -d'|' -f2- | rev)
            local head_file=$(echo "$line" | rev | cut -d'|' -f1 | rev)
            local base_file=$(grep "^${resource_key}|" "$base_index" | rev | cut -d'|' -f1 | rev)
            if [[ -n "$base_file" && -f "$base_file" ]]; then
                if ! check_resource_immutable_fields "$base_file" "$head_file" "$resource_key"; then
                    violations=$((violations + $?))
                fi
            fi
        done < "$head_index"
    done < "$kustomization_list"
    
    return $violations
}

# Main function
main() {
    local base_ref="HEAD~1"
    local head_ref="HEAD"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--base-ref)
                base_ref="$2"
                shift 2
                ;;
            -h|--head-ref)
                head_ref="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Change to repository root
    cd "$REPO_ROOT"
    
    # Verify we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log ERROR "Not in a Git repository"
        exit 1
    fi
    
    # Verify git references exist
    if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
        log ERROR "Base reference '$base_ref' does not exist"
        exit 1
    fi
    
    if ! git rev-parse --verify "$head_ref" >/dev/null 2>&1; then
        log ERROR "Head reference '$head_ref' does not exist"
        exit 1
    fi
    
    log INFO "Checking immutable field changes between $base_ref and $head_ref"
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log ERROR "kubectl is required but not installed"
        exit 1
    fi
    
    # Process kustomizations and check for violations
    local violations=0
    if ! process_kustomizations "$base_ref" "$head_ref"; then
        violations=$?
    fi
    
    if [[ $violations -eq 0 ]]; then
        log SUCCESS "No immutable field changes detected"
        exit 0
    else
        log ERROR "Found $violations immutable field violation(s)"
        echo ""
        log ERROR "These changes would cause Kubernetes reconciliation failures."
        log ERROR "Consider using resource replacement strategies or blue-green deployments."
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi