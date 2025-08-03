# Validation Script Development - Lessons Learned

This document captures key lessons learned during the development of the k3s2 pre-onboarding validation scripts, which can help future script development and troubleshooting.

> **📋 Important**: This document has been complemented by a comprehensive steering rule at `.kiro/steering/08-script-development-best-practices.md` that provides critical best practices and patterns for all script development. The steering rule is automatically applied when working with shell scripts and contains essential guidance for avoiding common pitfalls.

## Key Issues Encountered and Solutions

### 1. Bash `set -euo pipefail` and Error Handling

**Problem**: Scripts with `set -euo pipefail` would exit immediately when any command returned a non-zero exit code, preventing comprehensive validation testing.

**Symptoms**:
- Script stops after first failed test
- No summary or final results
- Incomplete validation coverage

**Solutions**:
```bash
# Instead of letting tests fail and exit:
run_test "Test Name" "test_function"

# Use explicit error handling:
run_test "Test Name" "test_function" || true

# Or capture exit codes:
local test_result=0
$test_function || test_result=$?
```

**Best Practice**: For validation scripts that need to run all tests regardless of individual failures, use explicit error handling rather than relying on `set -e` behavior.

### 2. Arithmetic Operations in Strict Mode

**Problem**: Bash arithmetic operations like `((COUNTER++))` can return exit code 1 when the result is 0, causing scripts to exit with `set -e`.

**Symptoms**:
- Script exits unexpectedly after counter operations
- No obvious error message
- Happens intermittently based on counter values

**Solutions**:
```bash
# Instead of:
((TESTS_PASSED++))

# Use:
TESTS_PASSED=$((TESTS_PASSED + 1))

# Or disable errexit temporarily:
set +e
((TESTS_PASSED++))
set -e
```

**Best Practice**: Use explicit arithmetic syntax `$((var + 1))` instead of `((var++))` in strict mode scripts.

### 3. k3s Architecture Differences

**Problem**: Standard Kubernetes validation checks fail on k3s because k3s uses embedded components instead of separate pods.

**Symptoms**:
- Control plane pod checks return 0/0 pods
- etcd pods not found
- kube-proxy and flannel pods missing

**Solutions**:
```bash
# Check for k3s embedded components:
if [[ $control_plane_pods -eq 0 ]]; then
    success "k3s embedded control plane (no separate pods expected)"
else
    # Standard Kubernetes validation
fi

# Use k3s-aware version detection:
local k8s_version=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "unknown")
if [[ "$k8s_version" == "unknown" ]]; then
    k8s_version=$(kubectl version --short 2>/dev/null | grep "Server Version" | cut -d: -f2 | tr -d ' ' || echo "unknown")
fi
```

**Best Practice**: Always account for different Kubernetes distributions (k3s, k0s, etc.) when writing validation scripts.

### 4. Module Sourcing and Path Issues

**Problem**: Sourcing validation modules failed when script directory paths weren't properly resolved.

**Symptoms**:
- "File not found" errors when sourcing modules
- Scripts work from some directories but not others

**Solutions**:
```bash
# Get script directory reliably:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules with full paths:
source "$SCRIPT_DIR/module-name.sh"

# Add error checking:
if [[ -f "$module_path" ]]; then
    source "$module_path"
else
    error "Module not found: $module_path"
    exit 1
fi
```

**Best Practice**: Always use absolute paths for sourcing modules and validate file existence before sourcing.

### 5. Long-Running Commands and Timeouts

**Problem**: Some validation tests (like DNS resolution, connectivity tests) could hang indefinitely.

**Symptoms**:
- Script appears to hang
- No output for extended periods
- Difficult to interrupt

**Solutions**:
```bash
# Use timeouts for network operations:
if curl --connect-timeout 5 "http://example.com" >/dev/null 2>&1; then
    success "Connectivity test passed"
fi

# Use kubectl timeouts:
kubectl exec pod-name --timeout=10s -- command

# Create temporary pods with resource limits:
kubectl apply -f - <<EOF
spec:
  containers:
  - name: test
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
EOF
```

**Best Practice**: Always use timeouts for network operations and external dependencies in validation scripts.

### 6. Temporary Resource Cleanup

**Problem**: Validation scripts created temporary pods and resources that weren't always cleaned up properly.

**Symptoms**:
- Test pods left running after script completion
- Port forwards not terminated
- Resource accumulation over multiple test runs

**Solutions**:
```bash
# Always cleanup temporary resources:
cleanup_resources() {
    kubectl delete pod test-pod --ignore-not-found >/dev/null 2>&1
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

# Use trap for cleanup:
trap cleanup_resources EXIT

# Clean up in each test function:
kubectl delete pod dns-test-pod --ignore-not-found >/dev/null 2>&1
```

**Best Practice**: Always implement cleanup functions and use traps to ensure resources are cleaned up even if scripts exit unexpectedly.

### 7. Output Formatting and Debugging

**Problem**: Complex scripts with multiple modules made debugging difficult without proper logging and output formatting.

**Solutions**:
```bash
# Consistent logging functions:
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

# Debug mode support:
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

# Progress indicators:
log "Running test $((current_test))/$total_tests: $test_name"
```

**Best Practice**: Implement consistent logging, support debug modes, and provide progress indicators for long-running validation scripts.

## Development Workflow Recommendations

### 1. Incremental Development
- Start with a simple script structure
- Add one validation module at a time
- Test each module independently before integration

### 2. Error Handling Strategy
- Use `set -euo pipefail` for catching errors early
- Add explicit error handling for validation functions
- Implement comprehensive cleanup procedures

### 3. Testing Approach
- Test scripts on actual cluster environments
- Verify behavior with both passing and failing conditions
- Test edge cases (missing resources, network issues, etc.)

### 4. Documentation
- Document expected behavior for each validation check
- Include troubleshooting steps for common failures
- Maintain examples of successful and failed outputs

## Script Architecture Patterns

### Modular Design
```bash
# Main script structure:
main() {
    check_dependencies
    source_validation_modules
    run_validation_tests
    generate_summary
}

# Module structure:
validate_component() {
    local issues=0
    # Validation logic
    return $issues
}
```

### Error Resilience
```bash
# Continue testing even with failures:
run_all_tests() {
    run_test "Test 1" "test_function_1" || true
    run_test "Test 2" "test_function_2" || true
    # Generate final summary
}
```

### Resource Management
```bash
# Proper cleanup pattern:
test_with_cleanup() {
    local cleanup_needed=false
    
    # Setup
    kubectl apply -f test-resource.yaml
    cleanup_needed=true
    
    # Test logic
    
    # Cleanup
    if [[ "$cleanup_needed" == "true" ]]; then
        kubectl delete -f test-resource.yaml --ignore-not-found
    fi
}
```

## Future Improvements

1. **Parallel Testing**: Some validation checks could run in parallel to reduce total execution time
2. **Caching**: Cache results of expensive operations (like cluster info) for reuse
3. **Configuration**: Make validation criteria configurable via config files
4. **Integration**: Integrate with CI/CD pipelines for automated validation
5. **Metrics**: Export validation results as metrics for monitoring systems

## Related Documentation

- [Script Development Best Practices](../../.kiro/steering/08-script-development-best-practices.md) - **Critical**: Comprehensive best practices and patterns
- [Scripts README](../../scripts/README.md) - Script development checklist and usage examples
- [Validation Test Cases](../../tests/validation/) - Example validation patterns and test scenarios