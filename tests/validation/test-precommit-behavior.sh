#!/bin/bash

# Test Pre-commit Hook Behavior
# Simulates pre-commit hook execution with various scenarios

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
    esac
}

# Test 1: Validate that kustomization validation script works
test_kustomization_validation() {
    log INFO "Testing kustomization validation script"
    
    if "$REPO_ROOT/scripts/validate-kustomizations.sh"; then
        log SUCCESS "Kustomization validation passed"
        return 0
    else
        log ERROR "Kustomization validation failed"
        return 1
    fi
}

# Test 2: Test with invalid kustomization
test_invalid_kustomization() {
    log INFO "Testing invalid kustomization detection"
    
    # Try to build an invalid kustomization
    if kubectl kustomize "$SCRIPT_DIR/test-cases/invalid-kustomization" >/dev/null 2>&1; then
        log ERROR "Invalid kustomization should have failed but passed"
        return 1
    else
        log SUCCESS "Invalid kustomization correctly detected"
        return 0
    fi
}

# Test 3: Test valid kustomization
test_valid_kustomization() {
    log INFO "Testing valid kustomization build"
    
    if kubectl kustomize "$SCRIPT_DIR/valid-cases/simple-app" >/dev/null 2>&1; then
        log SUCCESS "Valid kustomization built successfully"
        return 0
    else
        log ERROR "Valid kustomization failed to build"
        return 1
    fi
}

# Test 4: Simulate pre-commit hook execution
test_precommit_simulation() {
    log INFO "Simulating pre-commit hook execution"
    
    local temp_script=$(mktemp)
    cat > "$temp_script" << 'EOF'
#!/bin/bash
set -e

echo "🔍 Validating kustomization builds..."

# Define directories to validate (excluding problematic ones)
DIRS=(
    "clusters/k3s-flux"
    "infrastructure"
    "infrastructure/monitoring"
    "infrastructure/longhorn/base"
    "infrastructure/nginx-ingress"
    "apps/example-app/base"
    "apps/example-app/overlays/dev"
    "apps/longhorn-test/base"
    "apps/longhorn-test/overlays/dev"
)

for dir in "${DIRS[@]}"; do
    if [ -f "$dir/kustomization.yaml" ]; then
        echo "📦 Building $dir..."
        kubectl kustomize "$dir" > /dev/null || {
            echo "❌ Failed to build $dir"
            exit 1
        }
    fi
done

echo "✅ All kustomization builds successful!"
EOF
    
    chmod +x "$temp_script"
    
    if "$temp_script"; then
        log SUCCESS "Pre-commit simulation passed"
        rm -f "$temp_script"
        return 0
    else
        log ERROR "Pre-commit simulation failed"
        rm -f "$temp_script"
        return 1
    fi
}

# Main execution
main() {
    log INFO "🚀 Testing Pre-commit Hook Behavior"
    echo ""
    
    local tests_passed=0
    local tests_total=4
    
    # Run tests
    if test_kustomization_validation; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_invalid_kustomization; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_valid_kustomization; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_precommit_simulation; then
        tests_passed=$((tests_passed + 1))
    fi
    
    echo ""
    log INFO "📊 Results: $tests_passed/$tests_total tests passed"
    
    if [[ $tests_passed -eq $tests_total ]]; then
        log SUCCESS "🎉 All pre-commit behavior tests passed!"
        return 0
    else
        log ERROR "💥 Some tests failed"
        return 1
    fi
}

main "$@"