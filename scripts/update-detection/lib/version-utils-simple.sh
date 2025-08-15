#!/bin/bash

# Simplified Version Comparison Utilities
# Provides basic version comparison functions without logging dependencies

# Version comparison function using semantic versioning
compare_versions() {
    local version1="$1"
    local version2="$2"
    
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
    
    # Check for common pre-release indicators
    if echo "$version" | grep -qiE "(alpha|beta|rc|pre|dev|snapshot|nightly)"; then
        echo "true"
        return 0
    fi
    
    echo "false"
}

# Extract version from various formats
extract_version() {
    local input="$1"
    
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
    
    echo "$version"
}

# Get version type (major, minor, patch)
get_version_type() {
    local current_version="$1"
    local new_version="$2"
    
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
        echo "major"
        return 0
    fi
    
    # Compare minor version
    local current_minor=${current_parts[1]:-0}
    local new_minor=${new_parts[1]:-0}
    
    if [[ $new_minor -gt $current_minor ]]; then
        echo "minor"
        return 0
    fi
    
    # Compare patch version
    local current_patch=${current_parts[2]:-0}
    local new_patch=${new_parts[2]:-0}
    
    if [[ $new_patch -gt $current_patch ]]; then
        echo "patch"
        return 0
    fi
    
    echo "equal"
}

# Validate version format
validate_version_format() {
    local version="$1"
    
    # Check if version matches semantic versioning pattern
    if echo "$version" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+'; then
        echo "valid"
        return 0
    fi
    
    echo "invalid"
    return 1
}

# Export functions for use in other scripts
export -f compare_versions
export -f is_prerelease
export -f extract_version
export -f get_version_type
export -f validate_version_format