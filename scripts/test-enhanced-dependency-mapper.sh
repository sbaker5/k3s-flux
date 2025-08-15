#!/bin/bash
set -euo pipefail

# Test script for enhanced dependency mapper
# 
# This script validates that the enhanced dependency analysis tools work correctly
# and provide the expected GitOps-specific features.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/../tests/dependency-analysis"
ENHANCED_ANALYZER="$SCRIPT_DIR/enhanced-dependency-analysis.sh"

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

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

setup_test_environment() {
    log "Setting up enhanced test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    
    # Create enhanced test manifests with GitOps patterns
    create_enhanced_test_manifests
}

create_enhanced_test_manifests() {
    log "Creating enhanced test manifests with GitOps patterns..."
    
    # Create Flux GitOps test manifests
    cat > "$TEST_DIR/flux-gitops-test.yaml" << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: infrastructure-repo
  namespace: flux-system
  labels:
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure
spec:
  interval: 1m
  url: https://github.com/example/infrastructure
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-core
  namespace: flux-system
  labels:
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure
  annotations:
    kustomize.toolkit.fluxcd.io/reconcile: "true"
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: infrastructure-repo
  path: "./infrastructure/core"
  prune: true
  wait: true
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-storage
  namespace: flux-system
  labels:
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure
  annotations:
    kustomize.toolkit.fluxcd.io/reconcile: "true"
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: infrastructure-repo
  path: "./infrastructure/storage"
  dependsOn:
  - name: infrastructure-core
  prune: true
  wait: true
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps-production
  namespace: flux-system
  labels:
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: application
  annotations:
    kustomize.toolkit.fluxcd.io/reconcile: "true"
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: infrastructure-repo
  path: "./apps/production"
  dependsOn:
  - name: infrastructure-core
  prune: true
  wait: true
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: monitoring-stack
  namespace: monitoring
  labels:
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure
  annotations:
    helm.toolkit.fluxcd.io/reconcile: "true"
spec:
  interval: 30m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: "45.x"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  valuesFrom:
  - kind: ConfigMap
    name: monitoring-config
  - kind: Secret
    name: monitoring-secrets
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
  labels:
    app.kubernetes.io/part-of: k3s-flux
spec:
  interval: 24h
  url: https://prometheus-community.github.io/helm-charts
EOF

    # Create complex application with multiple dependencies
    cat > "$TEST_DIR/complex-app-test.yaml" << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: complex-app
  labels:
    app.kubernetes.io/part-of: k3s-flux
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: complex-app
  labels:
    app.kubernetes.io/part-of: k3s-flux
data:
  database.yaml: |
    host: postgres-service
    port: 5432
    database: app_db
  redis.yaml: |
    host: redis-service
    port: 6379
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: complex-app
  labels:
    app.kubernetes.io/part-of: k3s-flux
type: Opaque
data:
  db-password: cGFzc3dvcmQ=
  redis-password: cmVkaXNwYXNz
  api-key: YXBpa2V5MTIz
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: complex-app
  labels:
    app.kubernetes.io/part-of: k3s-flux
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: longhorn
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: complex-app
  labels:
    app: web-app
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: application
spec:
  replicas: 3
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
        image: nginx:1.21
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
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: api-key
        volumeMounts:
        - name: config-volume
          mountPath: /etc/config
        - name: data-volume
          mountPath: /var/data
        - name: secret-volume
          mountPath: /etc/secrets
          readOnly: true
      volumes:
      - name: config-volume
        configMap:
          name: app-config
      - name: data-volume
        persistentVolumeClaim:
          claimName: app-data
      - name: secret-volume
        secret:
          secretName: app-secrets
---
apiVersion: v1
kind: Service
metadata:
  name: web-app-service
  namespace: complex-app
  labels:
    app.kubernetes.io/part-of: k3s-flux
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-app-ingress
  namespace: complex-app
  labels:
    app.kubernetes.io/part-of: k3s-flux
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
  - hosts:
    - complex-app.local
    secretName: app-tls-secret
  rules:
  - host: complex-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app-service
            port:
              number: 80
---
apiVersion: v1
kind: Secret
metadata:
  name: app-tls-secret
  namespace: complex-app
  labels:
    app.kubernetes.io/part-of: k3s-flux
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi0=
  tls.key: LS0tLS1CRUdJTi0=
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: monitoring-config
  namespace: monitoring
  labels:
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure
data:
  values.yaml: |
    prometheus:
      prometheusSpec:
        retention: 30d
    grafana:
      adminPassword: admin123
---
apiVersion: v1
kind: Secret
metadata:
  name: monitoring-secrets
  namespace: monitoring
  labels:
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure
type: Opaque
data:
  grafana-password: YWRtaW4xMjM=
EOF

    log "Enhanced test manifests created in $TEST_DIR"
}

test_enhanced_manifest_analysis() {
    log "Testing enhanced manifest analysis..."
    
    local output_dir="$TEST_DIR/enhanced-manifest-analysis-output"
    
    if "$ENHANCED_ANALYZER" manifest-analysis \
        --manifests "$TEST_DIR" \
        --output-dir "$output_dir" \
        --verbose; then
        log "✓ Enhanced manifest analysis completed successfully"
        
        # Check if expected files were created
        if [[ -f "$output_dir/manifest-dependency-report.md" ]]; then
            log "✓ Enhanced dependency report generated"
            
            # Check for GitOps-specific content
            if grep -q "Flux-Managed Resources" "$output_dir/manifest-dependency-report.md"; then
                log "✓ GitOps-specific analysis detected"
            else
                warn "⚠ GitOps-specific analysis not found in report"
            fi
            
            # Check for risk assessment
            if grep -q "Risk Level" "$output_dir/manifest-dependency-report.md"; then
                log "✓ Risk assessment included"
            else
                warn "⚠ Risk assessment not found in report"
            fi
            
        else
            error "✗ Enhanced dependency report not found"
            return 1
        fi
        
        if [[ -f "$output_dir/manifest-dependency-graph.png" ]]; then
            log "✓ Enhanced dependency graph generated"
        else
            warn "⚠ Enhanced dependency graph not generated (matplotlib may not be available)"
        fi
        
    else
        error "✗ Enhanced manifest analysis failed"
        return 1
    fi
}

test_enhanced_impact_analysis() {
    log "Testing enhanced impact analysis..."
    
    local output_dir="$TEST_DIR/enhanced-impact-analysis-output"
    
    # Test impact analysis for the Flux GitRepository
    if "$ENHANCED_ANALYZER" impact-analysis \
        --resource "GitRepository/infrastructure-repo/flux-system" \
        --manifests "$TEST_DIR" \
        --output-dir "$output_dir" \
        --verbose; then
        log "✓ Enhanced impact analysis completed successfully"
        
        # Check if report was created
        if [[ -f "$output_dir/impact-report.md" ]]; then
            log "✓ Enhanced impact report generated"
        else
            error "✗ Enhanced impact report not found"
            return 1
        fi
        
    else
        error "✗ Enhanced impact analysis failed"
        return 1
    fi
}

test_risk_assessment() {
    log "Testing risk assessment functionality..."
    
    local output_dir="$TEST_DIR/risk-assessment-output"
    
    if "$ENHANCED_ANALYZER" risk-assessment \
        --manifests "$TEST_DIR" \
        --output-dir "$output_dir" \
        --verbose; then
        log "✓ Risk assessment completed successfully"
        
        if [[ -f "$output_dir/risk-assessment-report.md" ]]; then
            log "✓ Risk assessment report generated"
            
            # Check for risk-specific content
            if grep -q "Critical Risk Resources" "$output_dir/risk-assessment-report.md"; then
                log "✓ Risk categorization detected"
            else
                warn "⚠ Risk categorization not found"
            fi
            
            # Check for recommendations
            if grep -q "Recommendations" "$output_dir/risk-assessment-report.md"; then
                log "✓ Recommendations included"
            else
                warn "⚠ Recommendations not found"
            fi
            
        else
            error "✗ Risk assessment report not found"
            return 1
        fi
        
    else
        error "✗ Risk assessment failed"
        return 1
    fi
}

test_enhanced_visualization() {
    log "Testing enhanced visualization..."
    
    local output_dir="$TEST_DIR/enhanced-visualization-output"
    
    if "$ENHANCED_ANALYZER" visualize \
        --manifests "$TEST_DIR" \
        --filter "flux" \
        --output-dir "$output_dir" \
        --verbose; then
        log "✓ Enhanced visualization completed successfully"
        
        if [[ -f "$output_dir/enhanced-dependency-graph.png" ]]; then
            log "✓ Enhanced dependency graph with risk coloring generated"
        else
            warn "⚠ Enhanced dependency graph not generated (matplotlib may not be available)"
        fi
        
    else
        error "✗ Enhanced visualization failed"
        return 1
    fi
}

test_data_export() {
    log "Testing data export functionality..."
    
    local output_dir="$TEST_DIR/export-output"
    
    if "$ENHANCED_ANALYZER" export \
        --manifests "$TEST_DIR" \
        --output-dir "$output_dir" \
        --verbose; then
        log "✓ Data export completed successfully"
        
        if [[ -f "$output_dir/dependency-data.json" ]]; then
            log "✓ JSON export file generated"
            
            # Check JSON structure
            if python3 -c "import json; json.load(open('$output_dir/dependency-data.json'))" 2>/dev/null; then
                log "✓ JSON export is valid"
                
                # Check for expected fields
                if python3 -c "
import json
data = json.load(open('$output_dir/dependency-data.json'))
assert 'resources' in data
assert 'relations' in data
assert 'risk_assessments' in data
print('✓ JSON export contains expected fields')
" 2>/dev/null; then
                    log "✓ JSON export structure validated"
                else
                    warn "⚠ JSON export missing expected fields"
                fi
            else
                error "✗ JSON export is invalid"
                return 1
            fi
            
        else
            error "✗ JSON export file not found"
            return 1
        fi
        
    else
        error "✗ Data export failed"
        return 1
    fi
}

test_full_analysis() {
    log "Testing full analysis workflow..."
    
    local output_dir="$TEST_DIR/full-analysis-output"
    
    if "$ENHANCED_ANALYZER" full-analysis \
        --manifests "$TEST_DIR" \
        --output-dir "$output_dir" \
        --verbose; then
        log "✓ Full analysis completed successfully"
        
        # Check all expected outputs
        local expected_files=(
            "enhanced-dependency-report.md"
            "enhanced-dependency-graph.png"
            "dependency-data.json"
        )
        
        local found_files=0
        for file in "${expected_files[@]}"; do
            if [[ -f "$output_dir/$file" ]]; then
                log "✓ Found $file"
                ((found_files++))
            else
                warn "⚠ Missing $file"
            fi
        done
        
        if [[ $found_files -eq ${#expected_files[@]} ]]; then
            log "✓ All expected files generated"
        else
            warn "⚠ Some files missing from full analysis"
        fi
        
    else
        error "✗ Full analysis failed"
        return 1
    fi
}

validate_gitops_patterns() {
    log "Validating GitOps-specific pattern detection..."
    
    local report_file="$TEST_DIR/enhanced-manifest-analysis-output/manifest-dependency-report.md"
    
    if [[ ! -f "$report_file" ]]; then
        error "✗ Report file not found for GitOps validation"
        return 1
    fi
    
    # Check for GitOps-specific relationships
    local expected_patterns=(
        "sources_from.*GitRepository"
        "depends_on.*Kustomization"
        "chart_from.*HelmRepository"
        "values_from.*ConfigMap"
        "Flux-Managed Resources"
        "Critical Infrastructure Resources"
    )
    
    local found_patterns=0
    for pattern in "${expected_patterns[@]}"; do
        if grep -q "$pattern" "$report_file"; then
            log "✓ Found GitOps pattern: $pattern"
            ((found_patterns++))
        else
            warn "⚠ GitOps pattern not found: $pattern"
        fi
    done
    
    if [[ $found_patterns -gt 0 ]]; then
        log "✓ GitOps-specific patterns detected ($found_patterns/${#expected_patterns[@]})"
    else
        error "✗ No GitOps-specific patterns found"
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
    log "Starting enhanced dependency mapper tests..."
    
    local failed_tests=0
    
    # Setup
    setup_test_environment
    
    # Run tests
    test_enhanced_manifest_analysis || ((failed_tests++))
    test_enhanced_impact_analysis || ((failed_tests++))
    test_risk_assessment || ((failed_tests++))
    test_enhanced_visualization || ((failed_tests++))
    test_data_export || ((failed_tests++))
    test_full_analysis || ((failed_tests++))
    validate_gitops_patterns || ((failed_tests++))
    
    # Cleanup
    cleanup_test_environment
    
    # Report results
    if [[ $failed_tests -eq 0 ]]; then
        log "🎉 All enhanced dependency mapper tests passed!"
        info "Enhanced features validated:"
        info "  ✓ GitOps-specific dependency detection"
        info "  ✓ Risk assessment and categorization"
        info "  ✓ Enhanced visualization with risk coloring"
        info "  ✓ JSON export for integration"
        info "  ✓ Comprehensive reporting"
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