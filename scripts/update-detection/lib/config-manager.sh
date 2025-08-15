#!/bin/bash

# Configuration Manager Library
# Provides functions for loading and managing update detection configuration

# Default configuration file path
DEFAULT_CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/../config/update-detection.yaml"

# Global variables for configuration (using simple variables for macOS bash 3 compatibility)
CONFIG_GLOBAL_SCHEDULE=""
CONFIG_GLOBAL_DEFAULT_OUTPUT_FORMAT=""
CONFIG_GLOBAL_NOTIFICATIONS_ENABLED=""
CONFIG_GLOBAL_HISTORY_RETENTION_DAYS=""

# Component configuration variables
CONFIG_K3S_CHANNEL=""
CONFIG_K3S_CHECK_INTERVAL=""
CONFIG_K3S_MINIMUM_VERSION=""
CONFIG_K3S_SKIP_PRERELEASES=""
CONFIG_K3S_GITHUB_REPO=""
CONFIG_K3S_API_TIMEOUT=""

CONFIG_FLUX_TRACK_CONTROLLERS=""
CONFIG_FLUX_CHECK_INTERVAL=""
CONFIG_FLUX_SKIP_PRERELEASES=""
CONFIG_FLUX_MAIN_REPO=""
CONFIG_FLUX_API_TIMEOUT=""

CONFIG_LONGHORN_CHECK_INTERVAL=""
CONFIG_LONGHORN_MINIMUM_VERSION=""
CONFIG_LONGHORN_SKIP_PRERELEASES=""
CONFIG_LONGHORN_GITHUB_REPO=""
CONFIG_LONGHORN_HELM_REPO_URL=""
CONFIG_LONGHORN_CHECK_STORAGE_HEALTH=""

CONFIG_HELM_CHECK_INTERVAL=""
CONFIG_HELM_SKIP_PRERELEASES=""
CONFIG_HELM_TIMEOUT=""
CONFIG_HELM_MAX_RELEASES=""
CONFIG_HELM_CHECK_DEPENDENCIES=""

# Notification configuration
CONFIG_NOTIFICATIONS_CRITICAL_ENABLED=""
CONFIG_NOTIFICATIONS_REGULAR_ENABLED=""
CONFIG_NOTIFICATIONS_COMPLETION_ENABLED=""

# Logging configuration
CONFIG_LOGGING_LEVEL=""
CONFIG_LOGGING_FORMAT=""
CONFIG_LOGGING_TIMESTAMPS=""
CONFIG_LOGGING_ROTATION_ENABLED=""
CONFIG_LOGGING_MAX_SIZE_MB=""
CONFIG_LOGGING_MAX_FILES=""

# Reporting configuration
CONFIG_REPORTING_INCLUDE_HISTORY=""
CONFIG_REPORTING_STORAGE_PATH=""
CONFIG_REPORTING_RETENTION_DAYS=""

# Security configuration
CONFIG_SECURITY_VERIFY_SSL=""
CONFIG_SECURITY_HTTP_TIMEOUT=""
CONFIG_SECURITY_USER_AGENT=""

# Advanced configuration
CONFIG_ADVANCED_PARALLEL_PROCESSING=""
CONFIG_ADVANCED_MAX_CONCURRENT_REQUESTS=""
CONFIG_ADVANCED_RETRY_MAX_ATTEMPTS=""

# Load configuration from YAML file
load_config() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Configuration file not found: $config_file" >&2
        return 1
    fi
    
    # Check if yq is available for YAML parsing
    if ! command -v yq >/dev/null 2>&1; then
        echo "WARN: yq not available, using default configuration" >&2
        load_default_config
        return 0
    fi
    
    # Try to load configuration, fall back to defaults if yq fails
    CONFIG_GLOBAL_SCHEDULE=$(yq eval '.global.schedule // "0 6 * * *"' "$config_file" 2>/dev/null || echo "0 6 * * *")
    CONFIG_GLOBAL_DEFAULT_OUTPUT_FORMAT=$(yq eval '.global.default_output_format // "json"' "$config_file" 2>/dev/null || echo "json")
    CONFIG_GLOBAL_NOTIFICATIONS_ENABLED=$(yq eval '.global.notifications_enabled // true' "$config_file" 2>/dev/null || echo "true")
    CONFIG_GLOBAL_HISTORY_RETENTION_DAYS=$(yq eval '.global.history_retention_days // 90' "$config_file" 2>/dev/null || echo "90")
    
    # If any config failed to load, fall back to defaults
    if [[ -z "$CONFIG_GLOBAL_SCHEDULE" ]] || [[ "$CONFIG_GLOBAL_SCHEDULE" == "null" ]]; then
        echo "WARN: yq failed to parse YAML, using default configuration" >&2
        load_default_config
        return 0
    fi
    
    # Load component settings
    load_component_config "$config_file" "k3s"
    load_component_config "$config_file" "flux"
    load_component_config "$config_file" "longhorn"
    load_component_config "$config_file" "helm"
    
    # Load notification settings
    CONFIG_NOTIFICATIONS_CRITICAL_ENABLED=$(yq eval '.notifications.critical_updates.enabled // true' "$config_file" 2>/dev/null || echo "true")
    CONFIG_NOTIFICATIONS_REGULAR_ENABLED=$(yq eval '.notifications.regular_updates.enabled // false' "$config_file" 2>/dev/null || echo "false")
    CONFIG_NOTIFICATIONS_COMPLETION_ENABLED=$(yq eval '.notifications.completion_notifications.enabled // true' "$config_file" 2>/dev/null || echo "true")
    
    # Load logging settings
    CONFIG_LOGGING_LEVEL=$(yq eval '.logging.level // "INFO"' "$config_file" 2>/dev/null || echo "INFO")
    CONFIG_LOGGING_FORMAT=$(yq eval '.logging.format // "text"' "$config_file" 2>/dev/null || echo "text")
    CONFIG_LOGGING_TIMESTAMPS=$(yq eval '.logging.timestamps // true' "$config_file" 2>/dev/null || echo "true")
    CONFIG_LOGGING_ROTATION_ENABLED=$(yq eval '.logging.rotation.enabled // true' "$config_file" 2>/dev/null || echo "true")
    CONFIG_LOGGING_MAX_SIZE_MB=$(yq eval '.logging.rotation.max_size_mb // 10' "$config_file" 2>/dev/null || echo "10")
    CONFIG_LOGGING_MAX_FILES=$(yq eval '.logging.rotation.max_files // 5' "$config_file" 2>/dev/null || echo "5")
    
    # Load reporting settings
    CONFIG_REPORTING_INCLUDE_HISTORY=$(yq eval '.reporting.include_history // false' "$config_file" 2>/dev/null || echo "false")
    CONFIG_REPORTING_STORAGE_PATH=$(yq eval '.reporting.storage_path // "reports"' "$config_file" 2>/dev/null || echo "reports")
    CONFIG_REPORTING_RETENTION_DAYS=$(yq eval '.reporting.retention_days // 90' "$config_file" 2>/dev/null || echo "90")
    
    # Load security settings
    CONFIG_SECURITY_VERIFY_SSL=$(yq eval '.security.verify_ssl // true' "$config_file" 2>/dev/null || echo "true")
    CONFIG_SECURITY_HTTP_TIMEOUT=$(yq eval '.security.http_timeout // 30' "$config_file" 2>/dev/null || echo "30")
    CONFIG_SECURITY_USER_AGENT=$(yq eval '.security.user_agent // "k3s-flux-update-detector/1.0"' "$config_file" 2>/dev/null || echo "k3s-flux-update-detector/1.0")
    
    # Load advanced settings
    CONFIG_ADVANCED_PARALLEL_PROCESSING=$(yq eval '.advanced.parallel_processing // true' "$config_file" 2>/dev/null || echo "true")
    CONFIG_ADVANCED_MAX_CONCURRENT_REQUESTS=$(yq eval '.advanced.max_concurrent_requests // 5' "$config_file" 2>/dev/null || echo "5")
    CONFIG_ADVANCED_RETRY_MAX_ATTEMPTS=$(yq eval '.advanced.retry.max_attempts // 3' "$config_file" 2>/dev/null || echo "3")
}

# Load component-specific configuration
load_component_config() {
    local config_file="$1"
    local component="$2"
    
    case "$component" in
        k3s)
            CONFIG_K3S_CHANNEL=$(yq eval '.components.k3s.channel // "stable"' "$config_file" 2>/dev/null || echo "stable")
            CONFIG_K3S_CHECK_INTERVAL=$(yq eval '.components.k3s.check_interval // 24' "$config_file" 2>/dev/null || echo "24")
            CONFIG_K3S_MINIMUM_VERSION=$(yq eval '.components.k3s.minimum_version // "v1.28.0"' "$config_file" 2>/dev/null || echo "v1.28.0")
            CONFIG_K3S_SKIP_PRERELEASES=$(yq eval '.components.k3s.skip_prereleases // true' "$config_file" 2>/dev/null || echo "true")
            CONFIG_K3S_GITHUB_REPO=$(yq eval '.components.k3s.github_repo // "k3s-io/k3s"' "$config_file" 2>/dev/null || echo "k3s-io/k3s")
            CONFIG_K3S_API_TIMEOUT=$(yq eval '.components.k3s.api_timeout // 30' "$config_file" 2>/dev/null || echo "30")
            ;;
        flux)
            CONFIG_FLUX_TRACK_CONTROLLERS=$(yq eval '.components.flux.track_controllers // true' "$config_file" 2>/dev/null || echo "true")
            CONFIG_FLUX_CHECK_INTERVAL=$(yq eval '.components.flux.check_interval // 24' "$config_file" 2>/dev/null || echo "24")
            CONFIG_FLUX_SKIP_PRERELEASES=$(yq eval '.components.flux.skip_prereleases // true' "$config_file" 2>/dev/null || echo "true")
            CONFIG_FLUX_MAIN_REPO=$(yq eval '.components.flux.main_repo // "fluxcd/flux2"' "$config_file" 2>/dev/null || echo "fluxcd/flux2")
            CONFIG_FLUX_API_TIMEOUT=$(yq eval '.components.flux.api_timeout // 30' "$config_file" 2>/dev/null || echo "30")
            ;;
        longhorn)
            CONFIG_LONGHORN_CHECK_INTERVAL=$(yq eval '.components.longhorn.check_interval // 24' "$config_file" 2>/dev/null || echo "24")
            CONFIG_LONGHORN_MINIMUM_VERSION=$(yq eval '.components.longhorn.minimum_version // "v1.9.0"' "$config_file" 2>/dev/null || echo "v1.9.0")
            CONFIG_LONGHORN_SKIP_PRERELEASES=$(yq eval '.components.longhorn.skip_prereleases // true' "$config_file" 2>/dev/null || echo "true")
            CONFIG_LONGHORN_GITHUB_REPO=$(yq eval '.components.longhorn.github_repo // "longhorn/longhorn"' "$config_file" 2>/dev/null || echo "longhorn/longhorn")
            CONFIG_LONGHORN_HELM_REPO_URL=$(yq eval '.components.longhorn.helm_repo_url // "https://charts.longhorn.io"' "$config_file" 2>/dev/null || echo "https://charts.longhorn.io")
            CONFIG_LONGHORN_CHECK_STORAGE_HEALTH=$(yq eval '.components.longhorn.check_storage_health // true' "$config_file" 2>/dev/null || echo "true")
            ;;
        helm)
            CONFIG_HELM_CHECK_INTERVAL=$(yq eval '.components.helm.check_interval // 24' "$config_file" 2>/dev/null || echo "24")
            CONFIG_HELM_SKIP_PRERELEASES=$(yq eval '.components.helm.skip_prereleases // true' "$config_file" 2>/dev/null || echo "true")
            CONFIG_HELM_TIMEOUT=$(yq eval '.components.helm.helm_timeout // 60' "$config_file" 2>/dev/null || echo "60")
            CONFIG_HELM_MAX_RELEASES=$(yq eval '.components.helm.max_releases // 100' "$config_file" 2>/dev/null || echo "100")
            CONFIG_HELM_CHECK_DEPENDENCIES=$(yq eval '.components.helm.check_dependencies // true' "$config_file" 2>/dev/null || echo "true")
            ;;
    esac
}

# Load default configuration when YAML parsing is not available
load_default_config() {
    # Global defaults
    CONFIG_GLOBAL_SCHEDULE="0 6 * * *"
    CONFIG_GLOBAL_DEFAULT_OUTPUT_FORMAT="json"
    CONFIG_GLOBAL_NOTIFICATIONS_ENABLED="true"
    CONFIG_GLOBAL_HISTORY_RETENTION_DAYS="90"
    
    # Component defaults
    CONFIG_K3S_CHANNEL="stable"
    CONFIG_K3S_CHECK_INTERVAL="24"
    CONFIG_K3S_MINIMUM_VERSION="v1.28.0"
    CONFIG_K3S_SKIP_PRERELEASES="true"
    CONFIG_K3S_GITHUB_REPO="k3s-io/k3s"
    CONFIG_K3S_API_TIMEOUT="30"
    
    CONFIG_FLUX_TRACK_CONTROLLERS="true"
    CONFIG_FLUX_CHECK_INTERVAL="24"
    CONFIG_FLUX_SKIP_PRERELEASES="true"
    CONFIG_FLUX_MAIN_REPO="fluxcd/flux2"
    CONFIG_FLUX_API_TIMEOUT="30"
    
    CONFIG_LONGHORN_CHECK_INTERVAL="24"
    CONFIG_LONGHORN_MINIMUM_VERSION="v1.9.0"
    CONFIG_LONGHORN_SKIP_PRERELEASES="true"
    CONFIG_LONGHORN_GITHUB_REPO="longhorn/longhorn"
    CONFIG_LONGHORN_HELM_REPO_URL="https://charts.longhorn.io"
    CONFIG_LONGHORN_CHECK_STORAGE_HEALTH="true"
    
    CONFIG_HELM_CHECK_INTERVAL="24"
    CONFIG_HELM_SKIP_PRERELEASES="true"
    CONFIG_HELM_TIMEOUT="60"
    CONFIG_HELM_MAX_RELEASES="100"
    CONFIG_HELM_CHECK_DEPENDENCIES="true"
    
    # Notification defaults
    CONFIG_NOTIFICATIONS_CRITICAL_ENABLED="true"
    CONFIG_NOTIFICATIONS_REGULAR_ENABLED="false"
    CONFIG_NOTIFICATIONS_COMPLETION_ENABLED="true"
    
    # Logging defaults
    CONFIG_LOGGING_LEVEL="INFO"
    CONFIG_LOGGING_FORMAT="text"
    CONFIG_LOGGING_TIMESTAMPS="true"
    CONFIG_LOGGING_ROTATION_ENABLED="true"
    CONFIG_LOGGING_MAX_SIZE_MB="10"
    CONFIG_LOGGING_MAX_FILES="5"
    
    # Reporting defaults
    CONFIG_REPORTING_INCLUDE_HISTORY="false"
    CONFIG_REPORTING_STORAGE_PATH="reports"
    CONFIG_REPORTING_RETENTION_DAYS="90"
    
    # Security defaults
    CONFIG_SECURITY_VERIFY_SSL="true"
    CONFIG_SECURITY_HTTP_TIMEOUT="30"
    CONFIG_SECURITY_USER_AGENT="k3s-flux-update-detector/1.0"
    
    # Advanced defaults
    CONFIG_ADVANCED_PARALLEL_PROCESSING="true"
    CONFIG_ADVANCED_MAX_CONCURRENT_REQUESTS="5"
    CONFIG_ADVANCED_RETRY_MAX_ATTEMPTS="3"
}

# Get configuration value
get_config() {
    local section="$1"
    local key="$2"
    local default_value="${3:-}"
    
    case "$section" in
        global)
            case "$key" in
                schedule) echo "${CONFIG_GLOBAL_SCHEDULE:-$default_value}" ;;
                default_output_format) echo "${CONFIG_GLOBAL_DEFAULT_OUTPUT_FORMAT:-$default_value}" ;;
                notifications_enabled) echo "${CONFIG_GLOBAL_NOTIFICATIONS_ENABLED:-$default_value}" ;;
                history_retention_days) echo "${CONFIG_GLOBAL_HISTORY_RETENTION_DAYS:-$default_value}" ;;
                *) echo "$default_value" ;;
            esac
            ;;
        components)
            case "$key" in
                k3s_channel) echo "${CONFIG_K3S_CHANNEL:-$default_value}" ;;
                k3s_check_interval) echo "${CONFIG_K3S_CHECK_INTERVAL:-$default_value}" ;;
                k3s_minimum_version) echo "${CONFIG_K3S_MINIMUM_VERSION:-$default_value}" ;;
                k3s_skip_prereleases) echo "${CONFIG_K3S_SKIP_PRERELEASES:-$default_value}" ;;
                k3s_github_repo) echo "${CONFIG_K3S_GITHUB_REPO:-$default_value}" ;;
                k3s_api_timeout) echo "${CONFIG_K3S_API_TIMEOUT:-$default_value}" ;;
                flux_track_controllers) echo "${CONFIG_FLUX_TRACK_CONTROLLERS:-$default_value}" ;;
                flux_check_interval) echo "${CONFIG_FLUX_CHECK_INTERVAL:-$default_value}" ;;
                flux_skip_prereleases) echo "${CONFIG_FLUX_SKIP_PRERELEASES:-$default_value}" ;;
                flux_main_repo) echo "${CONFIG_FLUX_MAIN_REPO:-$default_value}" ;;
                flux_api_timeout) echo "${CONFIG_FLUX_API_TIMEOUT:-$default_value}" ;;
                longhorn_check_interval) echo "${CONFIG_LONGHORN_CHECK_INTERVAL:-$default_value}" ;;
                longhorn_minimum_version) echo "${CONFIG_LONGHORN_MINIMUM_VERSION:-$default_value}" ;;
                longhorn_skip_prereleases) echo "${CONFIG_LONGHORN_SKIP_PRERELEASES:-$default_value}" ;;
                longhorn_github_repo) echo "${CONFIG_LONGHORN_GITHUB_REPO:-$default_value}" ;;
                longhorn_helm_repo_url) echo "${CONFIG_LONGHORN_HELM_REPO_URL:-$default_value}" ;;
                longhorn_check_storage_health) echo "${CONFIG_LONGHORN_CHECK_STORAGE_HEALTH:-$default_value}" ;;
                helm_check_interval) echo "${CONFIG_HELM_CHECK_INTERVAL:-$default_value}" ;;
                helm_skip_prereleases) echo "${CONFIG_HELM_SKIP_PRERELEASES:-$default_value}" ;;
                helm_timeout) echo "${CONFIG_HELM_TIMEOUT:-$default_value}" ;;
                helm_max_releases) echo "${CONFIG_HELM_MAX_RELEASES:-$default_value}" ;;
                helm_check_dependencies) echo "${CONFIG_HELM_CHECK_DEPENDENCIES:-$default_value}" ;;
                *) echo "$default_value" ;;
            esac
            ;;
        notifications)
            case "$key" in
                critical_enabled) echo "${CONFIG_NOTIFICATIONS_CRITICAL_ENABLED:-$default_value}" ;;
                regular_enabled) echo "${CONFIG_NOTIFICATIONS_REGULAR_ENABLED:-$default_value}" ;;
                completion_enabled) echo "${CONFIG_NOTIFICATIONS_COMPLETION_ENABLED:-$default_value}" ;;
                *) echo "$default_value" ;;
            esac
            ;;
        logging)
            case "$key" in
                level) echo "${CONFIG_LOGGING_LEVEL:-$default_value}" ;;
                format) echo "${CONFIG_LOGGING_FORMAT:-$default_value}" ;;
                timestamps) echo "${CONFIG_LOGGING_TIMESTAMPS:-$default_value}" ;;
                rotation_enabled) echo "${CONFIG_LOGGING_ROTATION_ENABLED:-$default_value}" ;;
                max_size_mb) echo "${CONFIG_LOGGING_MAX_SIZE_MB:-$default_value}" ;;
                max_files) echo "${CONFIG_LOGGING_MAX_FILES:-$default_value}" ;;
                *) echo "$default_value" ;;
            esac
            ;;
        reporting)
            case "$key" in
                include_history) echo "${CONFIG_REPORTING_INCLUDE_HISTORY:-$default_value}" ;;
                storage_path) echo "${CONFIG_REPORTING_STORAGE_PATH:-$default_value}" ;;
                retention_days) echo "${CONFIG_REPORTING_RETENTION_DAYS:-$default_value}" ;;
                *) echo "$default_value" ;;
            esac
            ;;
        security)
            case "$key" in
                verify_ssl) echo "${CONFIG_SECURITY_VERIFY_SSL:-$default_value}" ;;
                http_timeout) echo "${CONFIG_SECURITY_HTTP_TIMEOUT:-$default_value}" ;;
                user_agent) echo "${CONFIG_SECURITY_USER_AGENT:-$default_value}" ;;
                *) echo "$default_value" ;;
            esac
            ;;
        advanced)
            case "$key" in
                parallel_processing) echo "${CONFIG_ADVANCED_PARALLEL_PROCESSING:-$default_value}" ;;
                max_concurrent_requests) echo "${CONFIG_ADVANCED_MAX_CONCURRENT_REQUESTS:-$default_value}" ;;
                retry_max_attempts) echo "${CONFIG_ADVANCED_RETRY_MAX_ATTEMPTS:-$default_value}" ;;
                *) echo "$default_value" ;;
            esac
            ;;
        *)
            echo "$default_value"
            ;;
    esac
}

# Validate configuration
validate_config() {
    local errors=0
    
    # Validate schedule format (basic cron validation)
    local schedule
    schedule=$(get_config "global" "schedule")
    if [[ ! "$schedule" =~ ^[0-9*,-/]+[[:space:]]+[0-9*,-/]+[[:space:]]+[0-9*,-/]+[[:space:]]+[0-9*,-/]+[[:space:]]+[0-9*,-/]+$ ]]; then
        echo "ERROR: Invalid cron schedule format: $schedule" >&2
        errors=$((errors + 1))
    fi
    
    # Validate output format
    local output_format
    output_format=$(get_config "global" "default_output_format")
    if [[ ! "$output_format" =~ ^(json|yaml|text)$ ]]; then
        echo "ERROR: Invalid output format: $output_format" >&2
        errors=$((errors + 1))
    fi
    
    # Validate log level
    local log_level
    log_level=$(get_config "logging" "level")
    if [[ ! "$log_level" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]]; then
        echo "ERROR: Invalid log level: $log_level" >&2
        errors=$((errors + 1))
    fi
    
    # Validate numeric values
    local retention_days
    retention_days=$(get_config "global" "history_retention_days")
    if ! [[ "$retention_days" =~ ^[0-9]+$ ]] || [[ "$retention_days" -lt 1 ]]; then
        echo "ERROR: Invalid history retention days: $retention_days" >&2
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Print configuration summary
print_config_summary() {
    echo "Configuration Summary:"
    echo "  Schedule: $(get_config "global" "schedule")"
    echo "  Output Format: $(get_config "global" "default_output_format")"
    echo "  Notifications: $(get_config "global" "notifications_enabled")"
    echo "  Log Level: $(get_config "logging" "level")"
    echo "  History Retention: $(get_config "global" "history_retention_days") days"
    echo ""
    echo "Component Settings:"
    echo "  k3s Channel: $(get_config "components" "k3s_channel")"
    echo "  k3s Check Interval: $(get_config "components" "k3s_check_interval")h"
    echo "  Flux Track Controllers: $(get_config "components" "flux_track_controllers")"
    echo "  Longhorn Storage Health Check: $(get_config "components" "longhorn_check_storage_health")"
    echo "  Helm Max Releases: $(get_config "components" "helm_max_releases")"
}

# Initialize configuration (call this in scripts that use config)
init_config() {
    local config_file="${1:-}"
    
    if [[ -n "$config_file" ]]; then
        load_config "$config_file"
    else
        load_config
    fi
    
    if ! validate_config; then
        echo "ERROR: Configuration validation failed" >&2
        return 1
    fi
}

# Export functions for use in other scripts
export -f load_config
export -f get_config
export -f validate_config
export -f print_config_summary
export -f init_config