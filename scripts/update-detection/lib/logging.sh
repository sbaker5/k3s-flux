#!/bin/bash

# Structured Logging Library
# Provides enhanced logging capabilities for the update detection system

# Source configuration manager
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/config-manager.sh"

# Global logging variables
LOGGING_INITIALIZED=false
LOG_LEVEL_NUM=0
LOG_FILE=""
LOG_FORMAT="text"

# Log level mappings (using function for bash 3 compatibility)
get_log_level_num() {
    case "$1" in
        DEBUG) echo "0" ;;
        INFO) echo "1" ;;
        WARN) echo "2" ;;
        ERROR) echo "3" ;;
        *) echo "1" ;;  # Default to INFO
    esac
}

# Initialize logging system
init_logging() {
    local component="${1:-update-detection}"
    local logs_dir="${2:-$(dirname "$LIB_DIR")/logs}"
    
    # Ensure logs directory exists
    mkdir -p "$logs_dir"
    
    # Set log file
    LOG_FILE="${logs_dir}/${component}.log"
    
    # Load configuration if not already loaded
    if [[ -z "${CONFIG_LOGGING_LEVEL:-}" ]]; then
        init_config >/dev/null 2>&1 || true
    fi
    
    # Set log level
    local log_level="${CONFIG_LOGGING_LEVEL:-INFO}"
    LOG_LEVEL_NUM=$(get_log_level_num "$log_level")
    
    # Set log format
    LOG_FORMAT="${CONFIG_LOGGING_FORMAT:-text}"
    
    # Perform log rotation if enabled
    if [[ "${CONFIG_LOGGING_ROTATION_ENABLED:-true}" == "true" ]]; then
        rotate_logs
    fi
    
    LOGGING_INITIALIZED=true
}

# Rotate log files
rotate_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi
    
    local max_size_mb="${CONFIG_LOGGING_MAX_SIZE_MB:-10}"
    local max_files="${CONFIG_LOGGING_MAX_FILES:-5}"
    
    # Check file size (in MB)
    local file_size_mb
    if command -v stat >/dev/null 2>&1; then
        # macOS/BSD stat
        file_size_mb=$(stat -f%z "$LOG_FILE" 2>/dev/null | awk '{print int($1/1024/1024)}' || echo "0")
    else
        # GNU stat (Linux)
        file_size_mb=$(stat -c%s "$LOG_FILE" 2>/dev/null | awk '{print int($1/1024/1024)}' || echo "0")
    fi
    
    # Rotate if file is too large
    if [[ "$file_size_mb" -gt "$max_size_mb" ]]; then
        # Rotate existing files
        for ((i=max_files-1; i>=1; i--)); do
            local current_file="${LOG_FILE}.${i}"
            local next_file="${LOG_FILE}.$((i+1))"
            
            if [[ -f "$current_file" ]]; then
                mv "$current_file" "$next_file" 2>/dev/null || true
            fi
        done
        
        # Move current log to .1
        mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
        
        # Remove oldest file if it exceeds max_files
        local oldest_file="${LOG_FILE}.$((max_files+1))"
        if [[ -f "$oldest_file" ]]; then
            rm -f "$oldest_file" 2>/dev/null || true
        fi
    fi
}

# Format log message
format_log_message() {
    local level="$1"
    local component="$2"
    local message="$3"
    local timestamp
    
    # Generate timestamp if enabled
    if [[ "${CONFIG_LOGGING_TIMESTAMPS:-true}" == "true" ]]; then
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    else
        timestamp=""
    fi
    
    case "$LOG_FORMAT" in
        json)
            # JSON format
            local json_msg
            json_msg=$(jq -n \
                --arg timestamp "$timestamp" \
                --arg level "$level" \
                --arg component "$component" \
                --arg message "$message" \
                '{timestamp: $timestamp, level: $level, component: $component, message: $message}')
            echo "$json_msg"
            ;;
        text|*)
            # Text format (default)
            if [[ -n "$timestamp" ]]; then
                echo "[$timestamp] [$level] [$component] $message"
            else
                echo "[$level] [$component] $message"
            fi
            ;;
    esac
}

# Core logging function
write_log() {
    local level="$1"
    local component="$2"
    shift 2
    local message="$*"
    
    # Initialize logging if not done
    if [[ "$LOGGING_INITIALIZED" != "true" ]]; then
        init_logging "$component"
    fi
    
    # Check if message should be logged based on level
    local level_num
    level_num=$(get_log_level_num "$level")
    if [[ "$level_num" -lt "$LOG_LEVEL_NUM" ]]; then
        return 0
    fi
    
    # Format message
    local formatted_message
    formatted_message=$(format_log_message "$level" "$component" "$message")
    
    # Write to stdout/stderr and log file
    if [[ "$level" == "ERROR" ]]; then
        echo "$formatted_message" >&2
    else
        echo "$formatted_message"
    fi
    
    # Write to log file if specified
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted_message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Convenience logging functions
log_debug() {
    local component="${1:-update-detection}"
    shift
    write_log "DEBUG" "$component" "$@"
}

log_info() {
    local component="${1:-update-detection}"
    shift
    write_log "INFO" "$component" "$@"
}

log_warn() {
    local component="${1:-update-detection}"
    shift
    write_log "WARN" "$component" "$@"
}

log_error() {
    local component="${1:-update-detection}"
    shift
    write_log "ERROR" "$component" "$@"
}

# Log structured data (JSON)
log_structured() {
    local level="$1"
    local component="$2"
    local data="$3"
    
    # Validate JSON
    if ! echo "$data" | jq empty 2>/dev/null; then
        log_error "$component" "Invalid JSON data for structured logging"
        return 1
    fi
    
    # Log the structured data
    write_log "$level" "$component" "STRUCTURED_DATA: $data"
}

# Log function entry/exit for debugging
log_function_entry() {
    local component="$1"
    local function_name="$2"
    shift 2
    local args="$*"
    
    log_debug "$component" "ENTER: $function_name($args)"
}

log_function_exit() {
    local component="$1"
    local function_name="$2"
    local exit_code="${3:-0}"
    
    log_debug "$component" "EXIT: $function_name (code: $exit_code)"
}

# Log performance metrics
log_performance() {
    local component="$1"
    local operation="$2"
    local duration="$3"
    local additional_info="${4:-}"
    
    local perf_data
    perf_data=$(jq -n \
        --arg operation "$operation" \
        --arg duration "$duration" \
        --arg info "$additional_info" \
        '{operation: $operation, duration_seconds: $duration, additional_info: $info}')
    
    log_structured "INFO" "$component" "$perf_data"
}

# Log API call metrics
log_api_call() {
    local component="$1"
    local method="$2"
    local url="$3"
    local status_code="$4"
    local duration="$5"
    
    local api_data
    api_data=$(jq -n \
        --arg method "$method" \
        --arg url "$url" \
        --arg status "$status_code" \
        --arg duration "$duration" \
        '{method: $method, url: $url, status_code: $status, duration_seconds: $duration}')
    
    log_structured "INFO" "$component" "$api_data"
}

# Clean up old log files
cleanup_old_logs() {
    local logs_dir="${1:-$(dirname "$LIB_DIR")/logs}"
    local retention_days="30"  # Fixed value since this config key doesn't exist in our schema
    
    if [[ ! -d "$logs_dir" ]]; then
        return 0
    fi
    
    log_info "logging" "Cleaning up log files older than $retention_days days"
    
    # Find and remove old log files
    find "$logs_dir" -name "*.log*" -type f -mtime "+$retention_days" -delete 2>/dev/null || true
    
    log_info "logging" "Log cleanup completed"
}

# Get log statistics
get_log_stats() {
    local component="${1:-}"
    local logs_dir="${2:-$(dirname "$LIB_DIR")/logs}"
    
    if [[ ! -d "$logs_dir" ]]; then
        echo "{\"error\": \"logs directory not found\"}"
        return 1
    fi
    
    local total_files=0
    local total_size=0
    local log_files=()
    
    # Count log files and calculate total size
    while IFS= read -r -d '' file; do
        if [[ -n "$component" ]] && [[ ! "$file" =~ $component ]]; then
            continue
        fi
        
        log_files+=("$(basename "$file")")
        total_files=$((total_files + 1))
        
        # Get file size
        local file_size
        if command -v stat >/dev/null 2>&1; then
            file_size=$(stat -f%z "$file" 2>/dev/null || echo "0")
        else
            file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        fi
        total_size=$((total_size + file_size))
        
    done < <(find "$logs_dir" -name "*.log*" -type f -print0 2>/dev/null)
    
    # Convert size to human readable
    local size_mb=$((total_size / 1024 / 1024))
    
    # Generate JSON stats
    local files_json
    files_json=$(printf '%s\n' "${log_files[@]}" | jq -R . | jq -s .)
    
    jq -n \
        --arg total_files "$total_files" \
        --arg total_size_mb "$size_mb" \
        --argjson files "$files_json" \
        '{total_files: ($total_files | tonumber), total_size_mb: ($total_size_mb | tonumber), files: $files}'
}

# Export functions for use in other scripts
export -f init_logging
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_structured
export -f log_function_entry
export -f log_function_exit
export -f log_performance
export -f log_api_call
export -f cleanup_old_logs
export -f get_log_stats