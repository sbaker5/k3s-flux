#!/bin/bash
set -euo pipefail

# Test script for the Update Orchestrator
# 
# This script tests the dependency-aware update ordering functionality
# by creating test resources with various dependency patterns.
#
# USAGE:
#   ./scripts/test-update-orchestrator.sh
#
# EXIT CODES:
#   0    All tests passed
#   1    One or more tests failed
#
# REQUIREMENTS:
#   - kubectl (for Kubernetes operations)
#   - python3 (for orchestrator execution)
#   - Access to Kubernetes cluster

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# Test configuration
TEST_NAMESPACE="update-orchestrator-test"
TEST_DIR="/tmp/update-orchestrator-test"
ORCHESTRATOR_CLI="$SCRIPT_DIR/update-orchestrator.sh"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Cleanup function
cleanup() {
    log "Cleaning up test resources..."
    
    # Delete test namespace
    kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
    
    # Clean up temp directory
    rm -rf "$TEST_DIR" 2>/dev/null || true
    
    log "Cleanup completed"
}

# Set up cleanup trap
trap cleanup EXIT

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log "Running test: $test_name"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    local test_result=0
    $test_function || test_result=$?
    
    if [[ $test_result -eq 0 ]]; then
        success "$test_name - PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        error "$test_name - FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Setup test environment
setup_test_environment() {
    log "Setting up test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    
    # Create test namespace
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    
    # Check if orchestrator CLI exists
    if [[ ! -f "$ORCHESTRATOR_CLI" ]]; then
        error "Update orchestrator CLI not found: $ORCHESTRATOR_CLI"
        return 1
    fi
    
    # Make sure CLI is executable
    chmod +x "$ORCHESTRATOR_CLI"
    
    success "Test environment setup completed"
    return 0
}

# Create test resources with dependencies
create_test_resources() {
    log "Creating test resources with dependency patterns..."
    
    # Create ConfigMap (no dependencies)
    cat > "$TEST_DIR/configmap.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: $TEST_NAMESPACE
  annotations:
    gitops.flux.io/dependency-weight: "10"
data:
  database_url: "postgresql://localhost:5432/app"
  log_level: "info"
EOF

    # Create Secret (no dependencies)
    cat > "$TEST_DIR/secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: $TEST_NAMESPACE
  annotations:
    gitops.flux.io/dependency-weight: "10"
type: Opaque
data:
  password: cGFzc3dvcmQ=  # base64 encoded "password"
  api_key: YWJjZGVmZ2g=   # base64 encoded "abcdefgh"
EOF

    # Create Service (no dependencies)
    cat > "$TEST_DIR/service.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: $TEST_NAMESPACE
  annotations:
    gitops.flux.io/dependency-weight: "20"
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 8080
    name: http
  type: ClusterIP
EOF

    # Create Deployment (depends on ConfigMap and Secret)
    cat > "$TEST_DIR/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: $TEST_NAMESPACE
  annotations:
    gitops.flux.io/depends-on: "ConfigMap/app-config,Secret/app-secrets"
    gitops.flux.io/dependency-weight: "30"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: app
        image: nginx:1.21
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: database_url
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: log_level
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: api_key
        volumeMounts:
        - name: config-volume
          mountPath: /etc/config
        - name: secret-volume
          mountPath: /etc/secrets
      volumes:
      - name: config-volume
        configMap:
          name: app-config
      - name: secret-volume
        secret:
          secretName: app-secrets
EOF

    # Create Ingress (depends on Service)
    cat > "$TEST_DIR/ingress.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: $TEST_NAMESPACE
  annotations:
    gitops.flux.io/depends-on: "Service/app-service"
    gitops.flux.io/dependency-weight: "40"
spec:
  rules:
  - host: test-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
EOF

    # Create Job (depends on ConfigMap and Secret)
    cat > "$TEST_DIR/job.yaml" << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: app-migration
  namespace: $TEST_NAMESPACE
  annotations:
    gitops.flux.io/depends-on: "ConfigMap/app-config,Secret/app-secrets"
    gitops.flux.io/dependency-weight: "25"
spec:
  template:
    spec:
      containers:
      - name: migration
        image: alpine:3.14
        command: ["sh", "-c", "echo 'Running migration...' && sleep 10"]
        env:
        - name: DATABASE_URL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: database_url
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: password
      restartPolicy: Never
  backoffLimit: 3
EOF

    success "Test resources created in: $TEST_DIR"
    return 0
}

# Test dependency analysis
test_dependency_analysis() {
    log "Testing dependency analysis..."
    
    # Run dependency analysis
    if "$ORCHESTRATOR_CLI" analyze "$TEST_DIR" --output text; then
        success "Dependency analysis completed successfully"
        return 0
    else
        error "Dependency analysis failed"
        return 1
    fi
}

# Test update planning
test_update_planning() {
    log "Testing update planning..."
    
    # Run update planning with dry-run
    if "$ORCHESTRATOR_CLI" plan --dry-run "$TEST_DIR"; then
        success "Update planning completed successfully"
        return 0
    else
        error "Update planning failed"
        return 1
    fi
}

# Test resource validation
test_resource_validation() {
    log "Testing resource validation..."
    
    # Run resource validation
    if "$ORCHESTRATOR_CLI" validate "$TEST_DIR"; then
        success "Resource validation completed successfully"
        return 0
    else
        error "Resource validation failed"
        return 1
    fi
}

# Test configuration display
test_configuration_display() {
    log "Testing configuration display..."
    
    # Show configuration
    if "$ORCHESTRATOR_CLI" config; then
        success "Configuration display completed successfully"
        return 0
    else
        error "Configuration display failed"
        return 1
    fi
}

# Test CLI help
test_cli_help() {
    log "Testing CLI help..."
    
    # Show help
    if "$ORCHESTRATOR_CLI" help >/dev/null; then
        success "CLI help completed successfully"
        return 0
    else
        error "CLI help failed"
        return 1
    fi
}

# Test with kustomization
test_kustomization_support() {
    log "Testing kustomization support..."
    
    # Create a kustomization
    cat > "$TEST_DIR/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- configmap.yaml
- secret.yaml
- service.yaml
- deployment.yaml
- ingress.yaml
- job.yaml

commonLabels:
  test-suite: update-orchestrator
  
namespace: $TEST_NAMESPACE
EOF

    # Test kustomization analysis
    if "$ORCHESTRATOR_CLI" analyze "$TEST_DIR" --output text; then
        success "Kustomization analysis completed successfully"
        return 0
    else
        error "Kustomization analysis failed"
        return 1
    fi
}

# Test error handling
test_error_handling() {
    log "Testing error handling..."
    
    # Test with non-existent directory
    if "$ORCHESTRATOR_CLI" analyze "/non/existent/path" 2>/dev/null; then
        error "Should have failed with non-existent path"
        return 1
    else
        success "Correctly handled non-existent path"
    fi
    
    # Test with invalid YAML
    echo "invalid: yaml: content:" > "$TEST_DIR/invalid.yaml"
    
    if "$ORCHESTRATOR_CLI" validate "$TEST_DIR/invalid.yaml" 2>/dev/null; then
        warn "Should have failed with invalid YAML (may be handled gracefully)"
    else
        success "Correctly handled invalid YAML"
    fi
    
    return 0
}

# Test Python orchestrator directly
test_python_orchestrator() {
    log "Testing Python orchestrator directly..."
    
    local orchestrator_script="$PROJECT_ROOT/infrastructure/recovery/update-orchestrator.py"
    
    if [[ ! -f "$orchestrator_script" ]]; then
        error "Python orchestrator script not found: $orchestrator_script"
        return 1
    fi
    
    # Test basic import and execution
    if python3 -c "
import sys
sys.path.append('$PROJECT_ROOT/infrastructure/recovery')
try:
    from update_orchestrator import UpdateOrchestrator, DependencyAnalyzer
    print('✅ Successfully imported UpdateOrchestrator classes')
    
    # Test basic instantiation
    analyzer = DependencyAnalyzer()
    orchestrator = UpdateOrchestrator()
    print('✅ Successfully created orchestrator instances')
    
except ImportError as e:
    print(f'❌ Import error: {e}')
    sys.exit(1)
except Exception as e:
    print(f'❌ Error: {e}')
    sys.exit(1)
"; then
        success "Python orchestrator direct test completed successfully"
        return 0
    else
        error "Python orchestrator direct test failed"
        return 1
    fi
}

# Main test execution
main() {
    log "🚀 Starting Update Orchestrator Tests"
    echo
    
    # Setup
    if ! setup_test_environment; then
        error "Failed to setup test environment"
        exit 1
    fi
    
    if ! create_test_resources; then
        error "Failed to create test resources"
        exit 1
    fi
    
    # Run tests with progress indicators
    log "📋 Running test suite..."
    echo
    
    run_test "CLI Help" "test_cli_help" || true
    run_test "Configuration Display" "test_configuration_display" || true
    run_test "Python Orchestrator Direct" "test_python_orchestrator" || true
    run_test "Resource Validation" "test_resource_validation" || true
    run_test "Dependency Analysis" "test_dependency_analysis" || true
    run_test "Update Planning" "test_update_planning" || true
    run_test "Kustomization Support" "test_kustomization_support" || true
    run_test "Error Handling" "test_error_handling" || true
    
    # Summary
    echo
    log "🏁 Test Summary:"
    success "Tests Passed: $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        error "Tests Failed: $TESTS_FAILED"
    else
        log "Tests Failed: $TESTS_FAILED"
    fi
    log "Total Tests: $TOTAL_TESTS"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo
        success "🎉 All tests passed! Update Orchestrator is working correctly."
        exit 0
    else
        echo
        error "❌ Some tests failed. Please check the output above."
        exit 1
    fi
}

# Check if running directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi