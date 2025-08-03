---
inclusion: fileMatch
fileMatchPattern: 'scripts/*.sh'
---

# Script Development Best Practices

When developing or modifying shell scripts, especially validation scripts, follow these critical best practices learned from the k3s2 validation script development:

## Critical Bash Scripting Issues

### 1. Arithmetic Operations in Strict Mode
**NEVER use `((var++))` with `set -euo pipefail`** - it can cause scripts to exit when the result is 0.

```bash
# ❌ WRONG - can cause script to exit
((TESTS_PASSED++))

# ✅ CORRECT - safe arithmetic
TESTS_PASSED=$((TESTS_PASSED + 1))
```

### 2. Error Handling in Validation Scripts
When you need to continue testing even after failures:

```bash
# ❌ WRONG - script exits on first failure
run_test "Test Name" "test_function"

# ✅ CORRECT - continue testing after failures
run_test "Test Name" "test_function" || true

# ✅ ALSO CORRECT - explicit error handling
local test_result=0
$test_function || test_result=$?
```

### 3. k3s Architecture Awareness
k3s uses embedded components, not separate pods. Always check for both patterns:

```bash
# Check for standard K8s control plane pods
local control_plane_pods=$(kubectl get pods -n kube-system -l tier=control-plane --no-headers | wc -l)

if [[ $control_plane_pods -gt 0 ]]; then
    # Standard Kubernetes validation
else
    # k3s embedded control plane - this is normal
    success "k3s embedded control plane (no separate pods expected)"
fi
```

### 4. Resource Cleanup
Always clean up temporary resources:

```bash
# Create cleanup function
cleanup_resources() {
    kubectl delete pod test-pod --ignore-not-found >/dev/null 2>&1
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

# Use trap for automatic cleanup
trap cleanup_resources EXIT

# Clean up in each function
kubectl delete pod dns-test-pod --ignore-not-found >/dev/null 2>&1
```

### 5. Timeout Handling
Always use timeouts for network operations:

```bash
# ❌ WRONG - can hang indefinitely
curl http://example.com

# ✅ CORRECT - with timeout
curl --connect-timeout 5 http://example.com

# ✅ CORRECT - kubectl with timeout
kubectl exec pod-name --timeout=10s -- command
```

### 6. Module Sourcing
Use absolute paths and error checking:

```bash
# Get script directory reliably
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source with full path and error checking
if [[ -f "$SCRIPT_DIR/module.sh" ]]; then
    source "$SCRIPT_DIR/module.sh"
else
    error "Module not found: $SCRIPT_DIR/module.sh"
    exit 1
fi
```

## Required Script Structure

### Logging Functions
Always implement consistent logging:

```bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}
```

### Error Handling Pattern
Use this pattern for validation scripts:

```bash
set -euo pipefail

# Test execution wrapper that continues on failure
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log "Running test: $test_name"
    
    local test_result=0
    $test_function || test_result=$?
    
    if [[ $test_result -eq 0 ]]; then
        success "$test_name - PASSED"
        return 0
    else
        error "$test_name - FAILED"
        return 1
    fi
}

# Run tests with continuation
run_test "Test 1" "test_function_1" || true
run_test "Test 2" "test_function_2" || true
```

## Development Checklist

Before committing any script:

- [ ] Use `$((var + 1))` instead of `((var++))`
- [ ] Add `|| true` to test functions that should continue on failure
- [ ] Include timeout handling for network operations
- [ ] Implement resource cleanup functions
- [ ] Use absolute paths for sourcing modules
- [ ] Add consistent logging with timestamps
- [ ] Test with both passing and failing conditions
- [ ] Account for k3s architecture differences (embedded components)
- [ ] Provide progress indicators for long operations
- [ ] Include usage examples and exit code documentation

## Reference Documentation

For detailed information, see:
- `docs/troubleshooting/validation-script-development.md` - Comprehensive development guide
- `scripts/README.md` - Script development best practices
- `tests/validation/` - Example validation patterns

## Common k3s Differences

When writing validation scripts for k3s:

- **Control plane**: Embedded, no separate pods
- **etcd**: Embedded, no separate pods  
- **kube-proxy**: May not have separate pods
- **Flannel**: May not have separate DaemonSet pods
- **Version detection**: Use `kubectl version -o json` with fallback

Always check for both standard Kubernetes and k3s patterns in your validation logic.