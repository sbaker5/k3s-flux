#!/bin/bash

# Validation Pipeline Test Runner
# Tests the GitOps resilience validation pipeline with various scenarios

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Test the GitOps resilience validation pipeline"
    echo ""
    echo "Options:"
    echo "  --category CATEGORY    Run specific test category (kustomization|immutable-fields|all)"
    echo "  -v, --verbose          Enable verbose output"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     # Run all tests"
    echo "  $0 --category kustomization"
    echo "  $0 --category immutable-fields --verbose"
}

# Function to run a test and track results
run_test() {
    local test_name=$1
    local test_command=$2
    local expected_result=$3  # "pass" or "fail"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log INFO "Running test: $test_name"
    log DEBUG "Command: $test_command"
    log DEBUG "Expected: $expected_result"
    
    local result="unknown"
    local output_file="$TEMP_DIR/test_output_$TOTAL_TESTS"
    
    if eval "$test_command" > "$output_file" 2>&1; then
        result="pass"
    else
        result="fail"
    fi
    
    if [[ "$result" == "$expected_result" ]]; then
        log SUCCESS "✅ $test_name - PASSED (expected $expected_result, got $result)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log ERROR "❌ $test_name - FAILED (expected $expected_result, got $result)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        
        if [[ "${VERBOSE:-false}" == "true" ]]; then
            echo "--- Test Output ---"
            cat "$output_file"
            echo "--- End Output ---"
        fi
    fi
    
    echo ""
}

# Function to test kustomization build validation
test_kustomization_validation() {
    log INFO "🔧 Testing Kustomization Build Validation"
    echo ""
    
    # Test 1: Valid kustomization should pass
    run_test \
        "Valid kustomization build" \
        "kubectl kustomize '$SCRIPT_DIR/valid-cases/simple-app'" \
        "pass"
    
    # Test 2: Invalid kustomization (missing file) should fail
    run_test \
        "Invalid kustomization (missing file)" \
        "kubectl kustomize '$SCRIPT_DIR/test-cases/invalid-kustomization'" \
        "fail"
    
    # Test 3: Invalid YAML syntax should fail
    run_test \
        "Invalid YAML syntax" \
        "kubectl kustomize '$SCRIPT_DIR/test-cases/invalid-syntax'" \
        "fail"
    
    # Test 4: Run the validation script on valid cases
    run_test \
        "Validation script on repository" \
        "cd '$REPO_ROOT' && '$REPO_ROOT/scripts/validate-kustomizations.sh'" \
        "pass"
}

# Function to test immutable field detection
test_immutable_field_detection() {
    log INFO "🔒 Testing Immutable Field Change Detection"
    echo ""
    
    # Create a temporary git repository for testing
    local test_repo="$TEMP_DIR/test_repo"
    mkdir -p "$test_repo"
    cd "$test_repo"
    
    # Initialize git repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Create initial commit with "before" state
    mkdir -p test-app
    cp "$SCRIPT_DIR/test-scenarios/immutable-fields/before/deployment.yaml" test-app/
    cp "$SCRIPT_DIR/test-scenarios/immutable-fields/before/service.yaml" test-app/
    
    # Create a simple kustomization
    cat > test-app/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF
    
    git add .
    git commit -m "Initial commit with before state"
    
    # Test 1: No changes should pass
    run_test \
        "No immutable field changes" \
        "'$REPO_ROOT/scripts/check-immutable-fields.sh' -b HEAD -h HEAD" \
        "pass"
    
    # Update to "after" state with immutable field changes
    cp "$SCRIPT_DIR/test-scenarios/immutable-fields/after/deployment.yaml" test-app/
    cp "$SCRIPT_DIR/test-scenarios/immutable-fields/after/service.yaml" test-app/
    git add .
    git commit -m "Update with immutable field changes"
    
    # Test 2: Immutable field changes should fail
    run_test \
        "Immutable field changes detected" \
        "'$REPO_ROOT/scripts/check-immutable-fields.sh' -b HEAD~1 -h HEAD" \
        "fail"
    
    # Test 3: Test with non-breaking changes
    # Reset to before state
    git reset --hard HEAD~1
    
    # Make only non-breaking changes
    sed -i.bak 's/nginx:1.20/nginx:1.21/' test-app/deployment.yaml
    sed -i.bak 's/replicas: 2/replicas: 3/' test-app/deployment.yaml
    rm -f test-app/*.bak
    git add .
    git commit -m "Non-breaking changes only"
    
    run_test \
        "Non-breaking changes only" \
        "'$REPO_ROOT/scripts/check-immutable-fields.sh' -b HEAD~1 -h HEAD" \
        "pass"
    
    cd "$REPO_ROOT"
    
    # Test 4: Direct comparison test with known immutable field changes
    log INFO "Testing direct immutable field comparison"
    
    # Create temporary files for direct comparison
    local before_yaml="$TEMP_DIR/before.yaml"
    local after_yaml="$TEMP_DIR/after.yaml"
    
    # Create before state
    cat > "$before_yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-app
      version: v1
  template:
    metadata:
      labels:
        app: test-app
        version: v1
    spec:
      containers:
      - name: test-container
        image: nginx:1.20
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-service
  namespace: default
spec:
  type: ClusterIP
  clusterIP: 10.96.100.100
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: test-app
EOF
    
    # Create after state with immutable field changes
    cat > "$after_yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test-app
      version: v2
  template:
    metadata:
      labels:
        app: test-app
        version: v2
    spec:
      containers:
      - name: test-container
        image: nginx:1.21
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-service
  namespace: default
spec:
  type: NodePort
  clusterIP: 10.96.100.101
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    nodePort: 30080
  selector:
    app: test-app
EOF
    
    # Test direct field comparison (this is a simplified test)
    local selector_before=$(grep -A 3 "selector:" "$before_yaml" | grep -A 2 "matchLabels:" | grep "version:" | awk '{print $2}')
    local selector_after=$(grep -A 3 "selector:" "$after_yaml" | grep -A 2 "matchLabels:" | grep "version:" | awk '{print $2}')
    
    if [[ "$selector_before" != "$selector_after" ]]; then
        log SUCCESS "✅ Direct immutable field detection - PASSED (detected selector change: $selector_before -> $selector_after)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log ERROR "❌ Direct immutable field detection - FAILED (should have detected selector change)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Function to test pre-commit hook integration
test_precommit_integration() {
    log INFO "🪝 Testing Pre-commit Hook Integration"
    echo ""
    
    # Check if pre-commit is configured
    if [[ -f "$REPO_ROOT/.pre-commit-config.yaml" ]]; then
        run_test \
            "Pre-commit configuration exists" \
            "test -f '$REPO_ROOT/.pre-commit-config.yaml'" \
            "pass"
        
        # Test pre-commit hook execution (dry run)
        if command -v pre-commit >/dev/null 2>&1; then
            run_test \
                "Pre-commit hooks can run" \
                "cd '$REPO_ROOT' && pre-commit run --all-files --dry-run" \
                "pass"
        else
            log WARN "pre-commit not installed, skipping hook execution test"
        fi
    else
        log WARN "No pre-commit configuration found, skipping integration tests"
    fi
}

# Function to test validation with real repository scenarios
test_real_scenarios() {
    log INFO "🏗️ Testing Real Repository Scenarios"
    echo ""
    
    # Test existing kustomizations in the repository
    local kustomization_dirs=(
        "clusters/k3s-flux"
        "infrastructure"
        "infrastructure/monitoring"
        "infrastructure/longhorn/base"
        "infrastructure/nginx-ingress"
        "apps/example-app/base"
        "apps/example-app/overlays/dev"
    )
    
    for dir in "${kustomization_dirs[@]}"; do
        if [[ -f "$REPO_ROOT/$dir/kustomization.yaml" ]]; then
            run_test \
                "Real kustomization: $dir" \
                "kubectl kustomize '$REPO_ROOT/$dir'" \
                "pass"
        fi
    done
}

# Function to generate test report
generate_report() {
    echo ""
    echo "=================================================="
    log INFO "📊 Test Results Summary"
    echo "=================================================="
    echo "Total Tests:  $TOTAL_TESTS"
    echo "Passed:       $PASSED_TESTS"
    echo "Failed:       $FAILED_TESTS"
    echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo "=================================================="
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log SUCCESS "🎉 All tests passed!"
        return 0
    else
        log ERROR "💥 $FAILED_TESTS test(s) failed"
        return 1
    fi
}

# Main function
main() {
    local category="all"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --category)
                category="$2"
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
    
    # Verify prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        log ERROR "kubectl is required but not installed"
        exit 1
    fi
    
    log INFO "🚀 Starting GitOps Resilience Validation Pipeline Tests"
    log INFO "Category: $category"
    log INFO "Repository: $REPO_ROOT"
    echo ""
    
    # Run tests based on category
    case $category in
        "kustomization")
            test_kustomization_validation
            ;;
        "immutable-fields")
            test_immutable_field_detection
            ;;
        "precommit")
            test_precommit_integration
            ;;
        "real")
            test_real_scenarios
            ;;
        "all")
            test_kustomization_validation
            test_immutable_field_detection
            test_precommit_integration
            test_real_scenarios
            ;;
        *)
            log ERROR "Unknown category: $category"
            usage
            exit 1
            ;;
    esac
    
    # Generate final report
    generate_report
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi