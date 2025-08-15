#!/bin/bash
set -euo pipefail

# Test script for dependency analyzer
# 
# This script validates that the dependency analysis tools work correctly
# by testing them against known resource configurations.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/../tests/dependency-analysis"
ANALYZER_SCRIPT="$SCRIPT_DIR/analyze-dependencies.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[TEST] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

setup_test_environment() {
    log "Setting up test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    
    # Create test manifests
    create_test_manifests
}

create_test_manifests() {
    log "Creating test manifests..."
    
    # Create a simple app with dependencies
    cat > "$TEST_DIR/test-app.yaml" << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: test-app
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: test-app
data:
  config.yaml: |
    database:
      host: postgres
      port: 5432
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: test-app
type: Opaque
data:
  db-password: cGFzc3dvcmQ=  # password
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: test-app
  labels:
    app: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:1.20
        ports:
        - containerPort: 80
        env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: database.host
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: db-password
        volumeMounts:
        - name: config-volume
          mountPath: /etc/config
      volumes:
      - name: config-volume
        configMap:
          name: app-config
---
apiVersion: v1
kind: Service
metadata:
  name: web-app-service
  namespace: test-app
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-app-ingress
  namespace: test-app
spec:
  rules:
  - host: test-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app-service
            port:
              number: 80
  tls:
  - hosts:
    - test-app.local
    secretName: app-tls-secret
---
apiVersion: v1
kind: Secret
metadata:
  name: app-tls-secret
  namespace: test-app
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi0=  # dummy cert
  tls.key: LS0tLS1CRUdJTi0=  # dummy key
EOF

    # Create a Flux-specific test
    cat > "$TEST_DIR/flux-test.yaml" << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: test-repo
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/example/test-repo
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: test-app-kustomization
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: test-repo
  path: "./apps/test-app"
  dependsOn:
  - name: infrastructure-core
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-core
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: test-repo
  path: "./infrastructure/core"
EOF

    log "Test manifests created in $TEST_DIR"
}

test_manifest_analysis() {
    log "Testing manifest analysis..."
    
    local output_dir="$TEST_DIR/manifest-analysis-output"
    
    if "$ANALYZER_SCRIPT" manifest-analysis \
        --manifests "$TEST_DIR" \
        --output-dir "$output_dir"; then
        log "✓ Manifest analysis completed successfully"
        
        # Check if expected files were created
        if [[ -f "$output_dir/dependency-report.md" ]]; then
            log "✓ Dependency report generated"
        else
            error "✗ Dependency report not found"
            return 1
        fi
        
        if [[ -f "$output_dir/dependency-graph.png" ]]; then
            log "✓ Dependency graph generated"
        else
            warn "⚠ Dependency graph not generated (matplotlib may not be available)"
        fi
        
    else
        error "✗ Manifest analysis failed"
        return 1
    fi
}

test_impact_analysis() {
    log "Testing impact analysis..."
    
    local output_dir="$TEST_DIR/impact-analysis-output"
    
    # Test impact analysis for the web-app deployment
    if "$ANALYZER_SCRIPT" impact-analysis \
        --resource "Deployment/web-app/test-app" \
        --manifests "$TEST_DIR" \
        --output-dir "$output_dir"; then
        log "✓ Impact analysis completed successfully"
        
        # Check if report was created
        if [[ -f "$output_dir/impact-report.md" ]]; then
            log "✓ Impact report generated"
        else
            error "✗ Impact report not found"
            return 1
        fi
        
    else
        error "✗ Impact analysis failed"
        return 1
    fi
}

test_visualization() {
    log "Testing visualization..."
    
    local output_dir="$TEST_DIR/visualization-output"
    
    if "$ANALYZER_SCRIPT" visualize \
        --manifests "$TEST_DIR" \
        --filter "web-app" \
        --output-dir "$output_dir"; then
        log "✓ Visualization completed successfully"
        
        if [[ -f "$output_dir/dependency-graph.png" ]]; then
            log "✓ Filtered dependency graph generated"
        else
            warn "⚠ Dependency graph not generated (matplotlib may not be available)"
        fi
        
    else
        error "✗ Visualization failed"
        return 1
    fi
}

test_cluster_analysis() {
    log "Testing cluster analysis (if cluster is available)..."
    
    # Check if kubectl is available and cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        warn "⚠ Cluster not available, skipping cluster analysis test"
        return 0
    fi
    
    local output_dir="$TEST_DIR/cluster-analysis-output"
    
    # Test with flux-system namespace if it exists
    if kubectl get namespace flux-system &>/dev/null; then
        if "$ANALYZER_SCRIPT" cluster-analysis \
            --namespaces "flux-system" \
            --output-dir "$output_dir"; then
            log "✓ Cluster analysis completed successfully"
        else
            error "✗ Cluster analysis failed"
            return 1
        fi
    else
        warn "⚠ flux-system namespace not found, skipping cluster analysis test"
    fi
}

validate_expected_dependencies() {
    log "Validating expected dependencies were found..."
    
    local report_file="$TEST_DIR/manifest-analysis-output/dependency-report.md"
    
    if [[ ! -f "$report_file" ]]; then
        error "✗ Report file not found for validation"
        return 1
    fi
    
    # Check for expected relationships
    local expected_relations=(
        "Deployment.*web-app.*references.*ConfigMap"
        "Deployment.*web-app.*references.*Secret"
        "Service.*web-app-service.*selects.*Pod"
        "Ingress.*web-app-ingress.*references.*Service"
        "Kustomization.*test-app-kustomization.*depends_on.*Kustomization"
    )
    
    local found_relations=0
    for relation in "${expected_relations[@]}"; do
        if grep -q "$relation" "$report_file"; then
            log "✓ Found expected relation: $relation"
            ((found_relations++))
        else
            warn "⚠ Expected relation not found: $relation"
        fi
    done
    
    if [[ $found_relations -gt 0 ]]; then
        log "✓ Found $found_relations expected dependency relationships"
    else
        error "✗ No expected dependency relationships found"
        return 1
    fi
}

cleanup_test_environment() {
    log "Cleaning up test environment..."
    
    # Remove test outputs but keep manifests for manual inspection
    rm -rf "$TEST_DIR"/*-output
    
    log "Test cleanup completed (test manifests preserved in $TEST_DIR)"
}

run_all_tests() {
    log "Starting dependency analyzer tests..."
    
    local failed_tests=0
    
    # Setup
    setup_test_environment
    
    # Run tests
    test_manifest_analysis || ((failed_tests++))
    test_impact_analysis || ((failed_tests++))
    test_visualization || ((failed_tests++))
    validate_expected_dependencies || ((failed_tests++))
    test_cluster_analysis || ((failed_tests++))
    
    # Cleanup
    cleanup_test_environment
    
    # Report results
    if [[ $failed_tests -eq 0 ]]; then
        log "🎉 All tests passed!"
        return 0
    else
        error "❌ $failed_tests test(s) failed"
        return 1
    fi
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi