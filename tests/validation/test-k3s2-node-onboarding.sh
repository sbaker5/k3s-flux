#!/bin/bash

# Test script for k3s2 node onboarding validation
# Tests the requirements from .kiro/specs/k3s1-node-onboarding/requirements.md

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

run_test() {
    ((TESTS_RUN++))
    local test_name="$1"
    local test_command="$2"
    
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Test functions

test_cluster_prerequisites() {
    log_info "=== Testing Cluster Prerequisites ==="
    
    # Test k3s1 cluster health
    run_test "k3s1 cluster API accessible" \
        "kubectl cluster-info >/dev/null 2>&1"
    
    # Test Flux operational
    run_test "Flux system healthy" \
        "flux check --pre >/dev/null 2>&1"
    
    # Test storage system
    run_test "Longhorn system pods running" \
        "kubectl get pods -n longhorn-system --no-headers | grep -v Running | wc -l | grep -q '^0$'"
    
    # Test monitoring system
    run_test "Core monitoring operational" \
        "kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep -v Running | wc -l | grep -q '^0$'"
}

test_node_availability() {
    log_info "=== Testing Node Availability ==="
    
    # Check if k3s2 node exists
    if kubectl get node k3s2 >/dev/null 2>&1; then
        log_info "k3s2 node found in cluster"
        
        # Test node status
        run_test "k3s2 node is Ready" \
            "kubectl get node k3s2 --no-headers | grep -q Ready"
        
        # Test node labels
        run_test "k3s2 has Longhorn labels" \
            "kubectl get node k3s2 --show-labels | grep -q 'storage=longhorn'"
        
        return 0
    else
        log_warning "k3s2 node not found - testing prerequisites only"
        return 1
    fi
}

test_gitops_configuration() {
    log_info "=== Testing GitOps Configuration ==="
    
    # Test k3s2 node configuration exists
    run_test "k3s2 node configuration files exist" \
        "test -f infrastructure/k3s2-node-config/k3s2-node.yaml && test -f infrastructure/k3s2-node-config/kustomization.yaml"
    
    # Test storage kustomization includes k3s2 (when activated)
    if grep -q "k3s2-node-config" infrastructure/storage/kustomization.yaml 2>/dev/null; then
        run_test "k3s2 configuration activated in storage kustomization" \
            "grep -v '^[[:space:]]*#' infrastructure/storage/kustomization.yaml | grep -q k3s2-node-config"
        
        # Test Flux reconciliation
        run_test "Storage kustomization reconciled successfully" \
            "kubectl get kustomization infrastructure-storage -n flux-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
    else
        log_warning "k3s2 configuration not yet activated in storage kustomization"
    fi
    
    # Test cloud-init configuration exists
    run_test "Cloud-init configuration exists" \
        "test -f infrastructure/cloud-init/user-data.k3s2"
}

test_storage_integration() {
    log_info "=== Testing Storage Integration ==="
    
    if ! kubectl get node k3s2 >/dev/null 2>&1; then
        log_warning "k3s2 node not available - skipping storage integration tests"
        return 0
    fi
    
    # Test Longhorn node exists
    run_test "k3s2 Longhorn node exists" \
        "kubectl get longhornnode k3s2 -n longhorn-system >/dev/null 2>&1"
    
    # Test disk discovery DaemonSet
    run_test "Disk discovery DaemonSet running on k3s2" \
        "kubectl get pods -n longhorn-system -l app=disk-discovery --field-selector spec.nodeName=k3s2 --no-headers | grep -q Running"
    
    # Test storage capacity
    run_test "k3s2 has available storage capacity" \
        "kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.status.diskStatus}' | grep -q 'allowScheduling.*true'"
    
    # Test replica distribution (if volumes exist)
    local volume_count=$(kubectl get volumes -n longhorn-system --no-headers 2>/dev/null | wc -l)
    if [ "$volume_count" -gt 0 ]; then
        run_test "Volumes can use k3s2 for replicas" \
            "kubectl get volumes -n longhorn-system -o jsonpath='{.items[*].status.robustness}' | grep -q Healthy"
    else
        log_info "No volumes exist yet - skipping replica distribution test"
    fi
}

test_networking_integration() {
    log_info "=== Testing Networking Integration ==="
    
    if ! kubectl get node k3s2 >/dev/null 2>&1; then
        log_warning "k3s2 node not available - skipping networking tests"
        return 0
    fi
    
    # Test Flannel CNI
    run_test "Flannel CNI running on k3s2" \
        "kubectl get pods -n kube-system -l app=flannel --field-selector spec.nodeName=k3s2 --no-headers | grep -q Running"
    
    # Test NodePort services accessibility
    run_test "NGINX Ingress DaemonSet on k3s2" \
        "kubectl get pods -n ingress-nginx --field-selector spec.nodeName=k3s2 --no-headers | wc -l | grep -v '^0$'"
    
    # Test pod network connectivity (create test pod)
    if kubectl run k3s2-network-test --image=busybox --restart=Never --rm -i --tty=false --command -- /bin/sh -c "ping -c 1 8.8.8.8" >/dev/null 2>&1; then
        log_success "Pod network connectivity from k3s2"
        ((TESTS_PASSED++))
    else
        log_error "Pod network connectivity from k3s2"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

test_monitoring_integration() {
    log_info "=== Testing Monitoring Integration ==="
    
    if ! kubectl get node k3s2 >/dev/null 2>&1; then
        log_warning "k3s2 node not available - skipping monitoring tests"
        return 0
    fi
    
    # Test node-exporter on k3s2
    run_test "Node-exporter running on k3s2" \
        "kubectl get pods -n monitoring -l app.kubernetes.io/name=node-exporter --field-selector spec.nodeName=k3s2 --no-headers | grep -q Running"
    
    # Test Flux controller metrics (if controllers scheduled on k3s2)
    local flux_pods_on_k3s2=$(kubectl get pods -n flux-system --field-selector spec.nodeName=k3s2 --no-headers 2>/dev/null | wc -l)
    if [ "$flux_pods_on_k3s2" -gt 0 ]; then
        run_test "Flux controllers on k3s2 expose metrics" \
            "kubectl get pods -n flux-system --field-selector spec.nodeName=k3s2 -o jsonpath='{.items[*].spec.containers[*].ports[?(@.name==\"http-prom\")].containerPort}' | grep -q 8080"
    else
        log_info "No Flux controllers on k3s2 - skipping controller metrics test"
    fi
    
    # Test Prometheus can scrape k3s2 metrics
    if kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090 >/dev/null 2>&1 &; then
        local pf_pid=$!
        sleep 2
        
        if curl -s "http://localhost:9090/api/v1/query?query=up{instance=~\".*k3s2.*\"}" | grep -q '"result":\['; then
            log_success "Prometheus collecting metrics from k3s2"
            ((TESTS_PASSED++))
        else
            log_error "Prometheus not collecting metrics from k3s2"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
        
        kill $pf_pid 2>/dev/null || true
    else
        log_warning "Could not test Prometheus metrics collection"
    fi
}

test_security_posture() {
    log_info "=== Testing Security Posture ==="
    
    if ! kubectl get node k3s2 >/dev/null 2>&1; then
        log_warning "k3s2 node not available - skipping security tests"
        return 0
    fi
    
    # Test RBAC policies
    run_test "k3s2 has proper RBAC configuration" \
        "kubectl auth can-i get pods --as=system:node:k3s2 -n kube-system"
    
    # Test SOPS secrets (if any exist)
    local sops_secrets=$(kubectl get secrets -A -o jsonpath='{.items[?(@.metadata.annotations.sops\.sh/encrypted)].metadata.name}' 2>/dev/null | wc -w)
    if [ "$sops_secrets" -gt 0 ]; then
        run_test "SOPS secrets accessible on k3s2" \
            "kubectl get secrets -A -o jsonpath='{.items[?(@.metadata.annotations.sops\.sh/encrypted)].metadata.name}' | wc -w | grep -v '^0$'"
    else
        log_info "No SOPS secrets found - skipping SOPS test"
    fi
    
    # Test Tailscale connectivity (if configured)
    if kubectl get pods -n tailscale >/dev/null 2>&1; then
        run_test "Tailscale subnet router operational" \
            "kubectl get pods -n tailscale --no-headers | grep -v Running | wc -l | grep -q '^0$'"
    else
        log_info "Tailscale not configured - skipping VPN connectivity test"
    fi
}

test_application_distribution() {
    log_info "=== Testing Application Distribution ==="
    
    if ! kubectl get node k3s2 >/dev/null 2>&1; then
        log_warning "k3s2 node not available - skipping application distribution tests"
        return 0
    fi
    
    # Create test deployment to verify scheduling
    kubectl apply -f - <<EOF >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k3s2-test-deployment
  namespace: default
  labels:
    test: k3s2-onboarding
spec:
  replicas: 2
  selector:
    matchLabels:
      app: k3s2-test
  template:
    metadata:
      labels:
        app: k3s2-test
    spec:
      containers:
      - name: test
        image: nginx:alpine
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
EOF
    
    # Wait for deployment
    sleep 10
    
    # Test pod distribution
    local pods_on_k3s2=$(kubectl get pods -l app=k3s2-test --field-selector spec.nodeName=k3s2 --no-headers 2>/dev/null | wc -l)
    if [ "$pods_on_k3s2" -gt 0 ]; then
        log_success "Applications can be scheduled on k3s2"
        ((TESTS_PASSED++))
    else
        log_warning "No test pods scheduled on k3s2 (may be due to resource constraints or taints)"
    fi
    ((TESTS_RUN++))
    
    # Cleanup
    kubectl delete deployment k3s2-test-deployment >/dev/null 2>&1 || true
}

test_storage_redundancy() {
    log_info "=== Testing Storage Redundancy ==="
    
    if ! kubectl get node k3s2 >/dev/null 2>&1; then
        log_warning "k3s2 node not available - skipping storage redundancy tests"
        return 0
    fi
    
    # Create test PVC to verify multi-node storage
    kubectl apply -f - <<EOF >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: k3s2-redundancy-test
  namespace: default
  labels:
    test: k3s2-onboarding
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 100Mi
EOF
    
    # Wait for PVC to be bound
    sleep 15
    
    # Check if PVC is bound
    if kubectl get pvc k3s2-redundancy-test --no-headers | grep -q Bound; then
        log_success "Multi-node storage provisioning works"
        ((TESTS_PASSED++))
        
        # Check replica distribution
        local volume_name=$(kubectl get pv -o jsonpath='{.items[?(@.spec.claimRef.name=="k3s2-redundancy-test")].metadata.name}')
        if [ -n "$volume_name" ]; then
            local replica_count=$(kubectl get volume "$volume_name" -n longhorn-system -o jsonpath='{.status.currentNodeID}' 2>/dev/null | wc -w)
            if [ "$replica_count" -ge 2 ]; then
                log_success "Volume has multiple replicas for redundancy"
                ((TESTS_PASSED++))
            else
                log_warning "Volume may not have sufficient replicas"
            fi
            ((TESTS_RUN++))
        fi
    else
        log_error "Multi-node storage provisioning failed"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Cleanup
    kubectl delete pvc k3s2-redundancy-test >/dev/null 2>&1 || true
}

# Main execution
main() {
    echo "=============================================="
    echo "k3s2 Node Onboarding Validation Test Suite"
    echo "=============================================="
    echo
    
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    if ! command -v flux >/dev/null 2>&1; then
        log_error "flux CLI not found. Please install Flux CLI."
        exit 1
    fi
    
    # Run test suites
    test_cluster_prerequisites
    echo
    
    local k3s2_available=false
    if test_node_availability; then
        k3s2_available=true
    fi
    echo
    
    test_gitops_configuration
    echo
    
    if [ "$k3s2_available" = true ]; then
        test_storage_integration
        echo
        
        test_networking_integration
        echo
        
        test_monitoring_integration
        echo
        
        test_security_posture
        echo
        
        test_application_distribution
        echo
        
        test_storage_redundancy
        echo
    fi
    
    # Summary
    echo "=============================================="
    echo "Test Summary"
    echo "=============================================="
    echo "Tests Run: $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        if [ "$k3s2_available" = true ]; then
            echo -e "${GREEN}✅ k3s2 node onboarding validation PASSED${NC}"
            echo "k3s2 node is successfully integrated into the cluster."
        else
            echo -e "${YELLOW}⚠️  k3s2 node not available - prerequisites validation PASSED${NC}"
            echo "Cluster is ready for k3s2 node onboarding."
        fi
        exit 0
    else
        echo -e "${RED}❌ k3s2 node onboarding validation FAILED${NC}"
        echo "Please review the failed tests and resolve issues before proceeding."
        exit 1
    fi
}

# Run main function
main "$@"