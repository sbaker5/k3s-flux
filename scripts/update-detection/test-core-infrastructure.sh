#!/bin/bash

# Test script for core update detection infrastructure
# Validates that all components are working correctly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COMPONENT="test-infrastructure"

# Source libraries
source "${SCRIPT_DIR}/lib/config-manager.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/version-utils-simple.sh"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Colors for logging (following best practices)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test logging function with colors
test_log() {
    local level="$1"
    shift
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "PASS")
            echo -e "${GREEN}[$timestamp] SUCCESS: $*${NC}"
            ;;
        "FAIL")
            echo -e "${RED}[$timestamp] ERROR: $*${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}[$timestamp] INFO: $*${NC}"
            ;;
        *)
            echo "[$timestamp] [$level] $*"
            ;;
    esac
}

# Run a test and track results (following best practices for test continuation)
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    test_log "INFO" "Running test: $test_name"
    
    # Use explicit error handling to continue testing after failures
    local test_result=0
    $test_function || test_result=$?
    
    if [[ $test_result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        test_log "PASS" "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        test_log "FAIL" "$test_name"
        return 1
    fi
}

# Test configuration management
test_config_management() {
    # Test loading default configuration
    if ! init_config; then
        echo "Failed to initialize configuration"
        return 1
    fi
    
    # Test getting configuration values
    local schedule
    schedule=$(get_config "global" "schedule")
    if [[ -z "$schedule" ]]; then
        echo "Failed to get schedule configuration"
        return 1
    fi
    
    # Test validation
    if ! validate_config >/dev/null 2>&1; then
        echo "Configuration validation failed"
        return 1
    fi
    
    echo "Configuration management working correctly"
    return 0
}

# Test logging system
test_logging_system() {
    # Initialize logging
    if ! init_logging "$TEST_COMPONENT"; then
        echo "Failed to initialize logging"
        return 1
    fi
    
    # Test different log levels
    log_debug "$TEST_COMPONENT" "Debug message test"
    log_info "$TEST_COMPONENT" "Info message test"
    log_warn "$TEST_COMPONENT" "Warning message test"
    
    # Test structured logging
    local test_data='{"test": "data", "number": 42}'
    if ! log_structured "INFO" "$TEST_COMPONENT" "$test_data"; then
        echo "Structured logging failed"
        return 1
    fi
    
    # Test performance logging
    log_performance "$TEST_COMPONENT" "test_operation" "1.5" "test info"
    
    echo "Logging system working correctly"
    return 0
}

# Test version utilities
test_version_utilities() {
    # Test version comparison
    local result
    result=$(compare_versions "v1.2.3" "v1.2.4" "$TEST_COMPONENT")
    if [[ "$result" != "older" ]]; then
        echo "Version comparison failed: expected 'older', got '$result'"
        return 1
    fi
    
    result=$(compare_versions "v1.3.0" "v1.2.4" "$TEST_COMPONENT")
    if [[ "$result" != "newer" ]]; then
        echo "Version comparison failed: expected 'newer', got '$result'"
        return 1
    fi
    
    result=$(compare_versions "v1.2.3" "v1.2.3" "$TEST_COMPONENT")
    if [[ "$result" != "equal" ]]; then
        echo "Version comparison failed: expected 'equal', got '$result'"
        return 1
    fi
    
    # Test pre-release detection
    result=$(is_prerelease "v1.2.3-beta1" "$TEST_COMPONENT")
    if [[ "$result" != "true" ]]; then
        echo "Pre-release detection failed: expected 'true', got '$result'"
        return 1
    fi
    
    result=$(is_prerelease "v1.2.3" "$TEST_COMPONENT")
    if [[ "$result" != "false" ]]; then
        echo "Pre-release detection failed: expected 'false', got '$result'"
        return 1
    fi
    
    # Test version extraction
    result=$(extract_version "image:v1.2.3-alpine" "$TEST_COMPONENT")
    if [[ "$result" != "v1.2.3-alpine" ]]; then
        echo "Version extraction failed: expected 'v1.2.3-alpine', got '$result'"
        return 1
    fi
    
    # Test version type detection
    result=$(get_version_type "v1.2.3" "v2.0.0" "$TEST_COMPONENT")
    if [[ "$result" != "major" ]]; then
        echo "Version type detection failed: expected 'major', got '$result'"
        return 1
    fi
    
    result=$(get_version_type "v1.2.3" "v1.3.0" "$TEST_COMPONENT")
    if [[ "$result" != "minor" ]]; then
        echo "Version type detection failed: expected 'minor', got '$result'"
        return 1
    fi
    
    result=$(get_version_type "v1.2.3" "v1.2.4" "$TEST_COMPONENT")
    if [[ "$result" != "patch" ]]; then
        echo "Version type detection failed: expected 'patch', got '$result'"
        return 1
    fi
    
    # Test version validation
    result=$(validate_version_format "v1.2.3" "$TEST_COMPONENT")
    if [[ "$result" != "valid" ]]; then
        echo "Version validation failed: expected 'valid', got '$result'"
        return 1
    fi
    
    echo "Version utilities working correctly"
    return 0
}

# Test main orchestrator (dry run)
test_main_orchestrator() {
    # Test dry run execution
    if ! "${SCRIPT_DIR}/update-detector.sh" --dry-run --component k3s >/dev/null 2>&1; then
        echo "Main orchestrator dry run failed"
        return 1
    fi
    
    # Test help output
    if ! "${SCRIPT_DIR}/update-detector.sh" --help >/dev/null 2>&1; then
        echo "Main orchestrator help failed"
        return 1
    fi
    
    echo "Main orchestrator working correctly"
    return 0
}

# Test individual component scripts exist and are executable
test_component_scripts() {
    local components=("k3s" "flux" "longhorn" "helm")
    
    for component in "${components[@]}"; do
        local script_path="${SCRIPT_DIR}/detect-${component}-updates.sh"
        
        if [[ ! -f "$script_path" ]]; then
            echo "Component script not found: $script_path"
            return 1
        fi
        
        if [[ ! -x "$script_path" ]]; then
            echo "Component script not executable: $script_path"
            return 1
        fi
    done
    
    # Test report generator
    local report_script="${SCRIPT_DIR}/generate-update-report.sh"
    if [[ ! -f "$report_script" ]] || [[ ! -x "$report_script" ]]; then
        echo "Report generator script not found or not executable: $report_script"
        return 1
    fi
    
    echo "All component scripts exist and are executable"
    return 0
}

# Test directory structure
test_directory_structure() {
    local required_dirs=(
        "${SCRIPT_DIR}/config"
        "${SCRIPT_DIR}/lib"
        "${SCRIPT_DIR}/logs"
        "${SCRIPT_DIR}/reports"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "Required directory not found: $dir"
            return 1
        fi
    done
    
    # Test configuration file exists
    if [[ ! -f "${SCRIPT_DIR}/config/update-detection.yaml" ]]; then
        echo "Configuration file not found"
        return 1
    fi
    
    echo "Directory structure is correct"
    return 0
}

# Cleanup function for test resources
cleanup_test_resources() {
    # Clean up any temporary test files
    rm -f /tmp/test-update-detection-* 2>/dev/null || true
    # Kill any test processes
    pkill -f "test-update-detection" 2>/dev/null || true
}

# Main test execution
main() {
    # Set up cleanup trap
    trap cleanup_test_resources EXIT
    
    test_log "INFO" "Starting core infrastructure tests"
    test_log "INFO" "Test directory: $SCRIPT_DIR"
    
    # Run all tests (continue on failure following best practices)
    run_test "Directory Structure" test_directory_structure || true
    run_test "Configuration Management" test_config_management || true
    run_test "Logging System" test_logging_system || true
    run_test "Version Utilities" test_version_utilities || true
    run_test "Component Scripts" test_component_scripts || true
    run_test "Main Orchestrator" test_main_orchestrator || true
    
    # Print test summary
    echo ""
    test_log "INFO" "Test Summary:"
    test_log "INFO" "  Total Tests: $TESTS_TOTAL"
    test_log "INFO" "  Passed: $TESTS_PASSED"
    test_log "INFO" "  Failed: $TESTS_FAILED"
    test_log "INFO" "  Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        test_log "PASS" "All core infrastructure tests passed!"
        exit 0
    else
        test_log "FAIL" "Some tests failed. Please check the output above."
        exit 1
    fi
}

# Execute main function
main "$@"