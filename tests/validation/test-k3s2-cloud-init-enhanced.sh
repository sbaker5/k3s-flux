#!/bin/bash

# Test script for enhanced k3s2 cloud-init configuration
# This script validates the enhanced cloud-init features

set -e

LOG_FILE="/tmp/k3s2-cloud-init-test.log"
TEST_STATUS="PASS"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

# Test result function
test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ $test_name: PASS${NC} - $message" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}✗ $test_name: FAIL${NC} - $message" | tee -a "$LOG_FILE"
        TEST_STATUS="FAIL"
    fi
}

# Initialize test log
echo "Starting k3s2 cloud-init enhanced configuration tests" > "$LOG_FILE"
log "Test started at $(date)"

echo "Testing Enhanced k3s2 Cloud-Init Configuration"
echo "=============================================="

# Test 1: Validate cloud-init file syntax
log "Test 1: Validating cloud-init YAML syntax"
if yamllint -d relaxed infrastructure/cloud-init/user-data.k3s2 >/dev/null 2>&1; then
    test_result "YAML Syntax" "PASS" "Cloud-init file has valid YAML syntax"
else
    test_result "YAML Syntax" "FAIL" "Cloud-init file has invalid YAML syntax"
fi

# Test 2: Check for required packages
log "Test 2: Checking required packages are specified"
required_packages=("open-iscsi" "jq" "curl" "wget" "netcat-openbsd" "systemd-journal-remote")
missing_packages=()

for package in "${required_packages[@]}"; do
    if ! grep -q "$package" infrastructure/cloud-init/user-data.k3s2; then
        missing_packages+=("$package")
    fi
done

if [ ${#missing_packages[@]} -eq 0 ]; then
    test_result "Required Packages" "PASS" "All required packages are specified"
else
    test_result "Required Packages" "FAIL" "Missing packages: ${missing_packages[*]}"
fi

# Test 3: Validate health check script structure
log "Test 3: Validating health check script structure"
if grep -q "update_status" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "check_overall_status" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Health Check Script" "PASS" "Health check functions are present"
else
    test_result "Health Check Script" "FAIL" "Health check functions are missing"
fi

# Test 4: Validate retry mechanism
log "Test 4: Validating retry mechanism implementation"
if grep -q "MAX_RETRIES" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "RETRY_DELAY" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "install_k3s_with_retry" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Retry Mechanism" "PASS" "Retry mechanism is implemented"
else
    test_result "Retry Mechanism" "FAIL" "Retry mechanism is missing or incomplete"
fi

# Test 5: Validate logging implementation
log "Test 5: Validating logging implementation"
if grep -q "/opt/k3s-onboarding/onboarding.log" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "timestamp=" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Logging Implementation" "PASS" "Comprehensive logging is implemented"
else
    test_result "Logging Implementation" "FAIL" "Logging implementation is incomplete"
fi

# Test 6: Validate status tracking
log "Test 6: Validating status tracking implementation"
if grep -q "status.json" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "packages_installed" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "cluster_joined" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Status Tracking" "PASS" "Status tracking is implemented"
else
    test_result "Status Tracking" "FAIL" "Status tracking is incomplete"
fi

# Test 7: Validate health check endpoint
log "Test 7: Validating health check endpoint service"
if grep -q "k3s-onboarding-health.service" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "8080" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Health Check Endpoint" "PASS" "Health check endpoint service is configured"
else
    test_result "Health Check Endpoint" "FAIL" "Health check endpoint service is missing"
fi

# Test 8: Validate cluster connectivity validation
log "Test 8: Validating cluster connectivity validation"
if grep -q "validate_cluster_connectivity" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "nc -z 192.168.86.71 6443" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Connectivity Validation" "PASS" "Cluster connectivity validation is implemented"
else
    test_result "Connectivity Validation" "FAIL" "Cluster connectivity validation is missing"
fi

# Test 9: Validate node labeling with retry
log "Test 9: Validating node labeling with retry mechanism"
if grep -q "apply_node_labels_with_retry" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "node.longhorn.io/create-default-disk=config" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "storage=longhorn" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Node Labeling" "PASS" "Node labeling with retry is implemented"
else
    test_result "Node Labeling" "FAIL" "Node labeling with retry is incomplete"
fi

# Test 10: Validate error handling
log "Test 10: Validating error handling implementation"
if grep -q "errors.*\[\]" infrastructure/cloud-init/user-data.k3s2 && \
   grep -q "ERROR:" infrastructure/cloud-init/user-data.k3s2; then
    test_result "Error Handling" "PASS" "Error handling is implemented"
else
    test_result "Error Handling" "FAIL" "Error handling is incomplete"
fi

# Summary
echo ""
echo "Test Summary"
echo "============"
log "Test completed at $(date)"

if [ "$TEST_STATUS" = "PASS" ]; then
    echo -e "${GREEN}All tests passed! Enhanced cloud-init configuration is ready.${NC}"
    log "All tests passed successfully"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the issues above.${NC}"
    log "Some tests failed - review required"
    exit 1
fi