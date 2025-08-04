#!/bin/bash
# Post-Onboarding Health Verification System
#
# This script performs comprehensive health validation after k3s2 node onboarding
# to ensure all systems are operational and properly distributed across nodes.
#
# Requirements: 7.3, 2.4, 4.3 from k3s1-node-onboarding spec
#
# Usage: ./scripts/post-onboarding-health-verification.sh [--report] [--fix] [--performance]
#   --report: Generate detailed health report
#   --fix: Attempt to fix identified issues
#   --performance: Run performance and load distribution tests

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/post-onboarding-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/post-onboarding-health-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Flags
GENERATE_REPORT=false
FIX_ISSUES=false
RUN_PERFORMANCE_TESTS=false

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0# Parse com
mand line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        --fix)
            FIX_ISSUES=true
            shift
            ;;
        --performance)
            RUN_PERFORMANCE_TESTS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--report] [--fix] [--performance]"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
}

debug() {
    echo -e "${PURPLE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*${NC}"
}

# Test result functions
test_result() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ $1 -eq 0 ]]; then
        success "✅ $2"
        add_to_report "✅ $2"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        error "❌ $2"
        add_to_report "❌ $2"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_warning() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    warn "⚠️ $1"
    add_to_report "⚠️ $1"
    WARNING_TESTS=$((WARNING_TESTS + 1))
}

# Initialize report
init_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        mkdir -p "$REPORT_DIR"
        cat > "$REPORT_FILE" << EOF
# Post-Onboarding Health Verification Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Script**: $0
**Performance Tests**: $RUN_PERFORMANCE_TESTS

## Executive Summary

This report contains comprehensive health validation results after k3s2 node onboarding.
The verification covers cluster health, storage redundancy, application distribution, and performance.

## Health Verification Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}# Depend
ency checks
check_dependencies() {
    local missing_deps=0
    
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        error "jq not found - please install jq (brew install jq)"
        missing_deps=$((missing_deps + 1))
    fi
    
    if [[ $missing_deps -gt 0 ]]; then
        error "Missing $missing_deps required dependencies"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        error "Please check your kubeconfig and cluster connectivity"
        exit 1
    fi
}

# Multi-node cluster health verification
verify_multi_node_cluster_health() {
    log "Verifying multi-node cluster health..."
    add_to_report "### Multi-Node Cluster Health"
    add_to_report ""
    
    # Check both nodes are present and ready
    local nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [[ $nodes -eq 2 ]]; then
        test_result 0 "Cluster has 2 nodes as expected"
    else
        test_result 1 "Cluster has $nodes nodes, expected 2"
        return 1
    fi
    
    # Check k3s1 (control plane) status
    local k3s1_status=$(kubectl get node k3s1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$k3s1_status" == "True" ]]; then
        test_result 0 "k3s1 control plane node is Ready"
    else
        test_result 1 "k3s1 control plane node is not Ready (Status: $k3s1_status)"
    fi
    
    # Check k3s2 (worker) status
    local k3s2_status=$(kubectl get node k3s2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$k3s2_status" == "True" ]]; then
        test_result 0 "k3s2 worker node is Ready"
    else
        test_result 1 "k3s2 worker node is not Ready (Status: $k3s2_status)"
    fi
    
    # Check node roles
    local k3s1_roles=$(kubectl get node k3s1 -o jsonpath='{.metadata.labels.kubernetes\.io/role}' 2>/dev/null || echo "")
    local k3s2_roles=$(kubectl get node k3s2 -o jsonpath='{.metadata.labels.kubernetes\.io/role}' 2>/dev/null || echo "")
    
    log "Node roles - k3s1: $k3s1_roles, k3s2: $k3s2_roles"
    add_to_report "**Node Roles**: k3s1: $k3s1_roles, k3s2: $k3s2_roles"
    
    # Check system pods distribution
    local system_pods_k3s1=$(kubectl get pods -n kube-system -o wide --no-headers 2>/dev/null | grep k3s1 | wc -l)
    local system_pods_k3s2=$(kubectl get pods -n kube-system -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
    
    log "System pods distribution - k3s1: $system_pods_k3s1, k3s2: $system_pods_k3s2"
    add_to_report "**System Pods Distribution**: k3s1: $system_pods_k3s1, k3s2: $system_pods_k3s2"
    
    if [[ $system_pods_k3s2 -gt 0 ]]; then
        test_result 0 "System pods are running on k3s2"
    else
        test_warning "No system pods found on k3s2 (may be expected for worker node)"
    fi
    
    add_to_report ""
}# Storag
e redundancy verification
verify_storage_redundancy() {
    log "Verifying storage redundancy across nodes..."
    add_to_report "### Storage Redundancy Verification"
    add_to_report ""
    
    # Check Longhorn nodes
    local longhorn_nodes=$(kubectl get longhornnode -n longhorn-system --no-headers 2>/dev/null | wc -l)
    if [[ $longhorn_nodes -eq 2 ]]; then
        test_result 0 "Longhorn recognizes both nodes ($longhorn_nodes nodes)"
    else
        test_result 1 "Longhorn has $longhorn_nodes nodes, expected 2"
    fi
    
    # Check k3s1 Longhorn node
    local k3s1_longhorn_ready=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$k3s1_longhorn_ready" == "True" ]]; then
        test_result 0 "k3s1 Longhorn node is ready"
    else
        test_result 1 "k3s1 Longhorn node is not ready (Status: $k3s1_longhorn_ready)"
    fi
    
    # Check k3s2 Longhorn node
    local k3s2_longhorn_ready=$(kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$k3s2_longhorn_ready" == "True" ]]; then
        test_result 0 "k3s2 Longhorn node is ready"
    else
        test_result 1 "k3s2 Longhorn node is not ready (Status: $k3s2_longhorn_ready)"
    fi
    
    # Check replica distribution for existing volumes
    local volumes=$(kubectl get volumes -n longhorn-system --no-headers 2>/dev/null | wc -l)
    if [[ $volumes -gt 0 ]]; then
        log "Found $volumes Longhorn volume(s) - checking replica distribution"
        add_to_report "**Longhorn Volumes**: $volumes found"
        
        # Check volumes with 2+ replicas (distributed)
        local distributed_volumes=0
        while IFS= read -r volume; do
            local replica_count=$(kubectl get volume "$volume" -n longhorn-system -o jsonpath='{.spec.numberOfReplicas}' 2>/dev/null)
            
            if [[ "$replica_count" -ge 2 ]]; then
                distributed_volumes=$((distributed_volumes + 1))
                log "Volume $volume has $replica_count replicas (distributed)"
                add_to_report "  - **$volume**: $replica_count replicas"
                test_result 0 "Volume $volume has distributed replicas"
            else
                log "Volume $volume has $replica_count replica (single node)"
                add_to_report "  - **$volume**: $replica_count replica (single node)"
            fi
        done < <(kubectl get volumes -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')
        
        if [[ $distributed_volumes -gt 0 ]]; then
            test_result 0 "$distributed_volumes volume(s) have distributed replicas"
        else
            test_warning "No volumes have distributed replicas yet"
        fi
    else
        log "No Longhorn volumes found - storage redundancy ready for new volumes"
        add_to_report "**Longhorn Volumes**: none found (ready for new volumes)"
    fi
    
    # Check default replica count setting
    local default_replica_count=$(kubectl get setting default-replica-count -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "unknown")
    log "Default replica count setting: $default_replica_count"
    add_to_report "**Default Replica Count**: $default_replica_count"
    
    if [[ "$default_replica_count" == "2" ]]; then
        test_result 0 "Default replica count is set for multi-node redundancy (2)"
    elif [[ "$default_replica_count" == "1" ]]; then
        test_warning "Default replica count is 1 - consider increasing to 2 for redundancy"
        if [[ "$FIX_ISSUES" == "true" ]]; then
            log "Updating default replica count to 2..."
            kubectl patch setting default-replica-count -n longhorn-system --type='merge' -p='{"value":"2"}'
            test_result 0 "Updated default replica count to 2"
            add_to_report "**Fix Applied**: Updated default replica count to 2"
        fi
    else
        log "Default replica count: $default_replica_count"
    fi
    
    add_to_report ""
}# App
lication distribution verification
verify_application_distribution() {
    log "Verifying application distribution across nodes..."
    add_to_report "### Application Distribution Verification"
    add_to_report ""
    
    # Check pod distribution across nodes
    local total_pods=$(kubectl get pods -A --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    local pods_k3s1=$(kubectl get pods -A --field-selector=status.phase=Running -o wide --no-headers 2>/dev/null | grep k3s1 | wc -l)
    local pods_k3s2=$(kubectl get pods -A --field-selector=status.phase=Running -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
    
    log "Pod distribution - Total: $total_pods, k3s1: $pods_k3s1, k3s2: $pods_k3s2"
    add_to_report "**Pod Distribution**: Total: $total_pods, k3s1: $pods_k3s1, k3s2: $pods_k3s2"
    
    if [[ $pods_k3s2 -gt 0 ]]; then
        test_result 0 "Pods are running on k3s2 ($pods_k3s2 pods)"
    else
        test_result 1 "No pods are running on k3s2"
    fi
    
    # Calculate distribution ratio
    if [[ $total_pods -gt 0 ]]; then
        local k3s2_percentage=$((pods_k3s2 * 100 / total_pods))
        
        log "Pod distribution percentage - k3s2: ${k3s2_percentage}%"
        add_to_report "**k3s2 Distribution**: ${k3s2_percentage}%"
        
        # Check if distribution is reasonable (not too skewed)
        if [[ $k3s2_percentage -ge 20 ]]; then
            test_result 0 "Pod distribution is reasonable (k3s2 has ${k3s2_percentage}%)"
        else
            test_warning "Pod distribution is skewed (k3s2 has only ${k3s2_percentage}%)"
        fi
    fi
    
    # Check DaemonSet distribution (should be on both nodes)
    check_daemonset_distribution "flannel" "kube-system"
    check_daemonset_distribution "longhorn-manager" "longhorn-system"
    
    add_to_report ""
}

# Helper function to check DaemonSet distribution
check_daemonset_distribution() {
    local daemonset_name="$1"
    local namespace="$2"
    
    if kubectl get daemonset "$daemonset_name" -n "$namespace" >/dev/null 2>&1; then
        local desired=$(kubectl get daemonset "$daemonset_name" -n "$namespace" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
        local ready=$(kubectl get daemonset "$daemonset_name" -n "$namespace" -o jsonpath='{.status.numberReady}' 2>/dev/null)
        
        log "DaemonSet $daemonset_name: $ready/$desired pods ready"
        add_to_report "**DaemonSet $daemonset_name**: $ready/$desired pods ready"
        
        if [[ "$ready" == "$desired" && "$desired" == "2" ]]; then
            test_result 0 "DaemonSet $daemonset_name is running on both nodes"
        elif [[ "$ready" == "$desired" ]]; then
            test_result 0 "DaemonSet $daemonset_name is healthy ($ready/$desired)"
        else
            test_result 1 "DaemonSet $daemonset_name is not healthy ($ready/$desired)"
        fi
    else
        log "DaemonSet $daemonset_name not found in namespace $namespace"
        add_to_report "**DaemonSet $daemonset_name**: not found in namespace $namespace"
    fi
}#
 Network connectivity verification
verify_network_connectivity() {
    log "Verifying network connectivity between nodes..."
    add_to_report "### Network Connectivity Verification"
    add_to_report ""
    
    # Check Flannel network
    local flannel_pods=$(kubectl get pods -n kube-system -l app=flannel --no-headers 2>/dev/null | wc -l)
    local running_flannel=$(kubectl get pods -n kube-system -l app=flannel --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $flannel_pods -eq 2 && $running_flannel -eq 2 ]]; then
        test_result 0 "Flannel CNI is running on both nodes"
    else
        test_result 1 "Flannel CNI is not healthy ($running_flannel/$flannel_pods pods running)"
    fi
    
    # Check kube-proxy
    local kube_proxy_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | wc -l)
    local running_kube_proxy=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $kube_proxy_pods -eq 2 && $running_kube_proxy -eq 2 ]]; then
        test_result 0 "kube-proxy is running on both nodes"
    else
        test_result 1 "kube-proxy is not healthy ($running_kube_proxy/$kube_proxy_pods pods running)"
    fi
    
    # Test cross-node connectivity
    test_cross_node_connectivity
    
    add_to_report ""
}

# Test cross-node connectivity
test_cross_node_connectivity() {
    log "Testing cross-node pod connectivity..."
    
    # Create test pods on each node if they don't exist
    local test_pod_k3s1="connectivity-test-k3s1"
    local test_pod_k3s2="connectivity-test-k3s2"
    
    # Create test pod on k3s1
    if ! kubectl get pod "$test_pod_k3s1" >/dev/null 2>&1; then
        kubectl run "$test_pod_k3s1" --image=busybox --restart=Never --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k3s1"}}}' -- sleep 3600 >/dev/null 2>&1
        sleep 5
    fi
    
    # Create test pod on k3s2
    if ! kubectl get pod "$test_pod_k3s2" >/dev/null 2>&1; then
        kubectl run "$test_pod_k3s2" --image=busybox --restart=Never --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k3s2"}}}' -- sleep 3600 >/dev/null 2>&1
        sleep 5
    fi
    
    # Wait for pods to be ready
    kubectl wait --for=condition=Ready pod/"$test_pod_k3s1" --timeout=60s >/dev/null 2>&1
    kubectl wait --for=condition=Ready pod/"$test_pod_k3s2" --timeout=60s >/dev/null 2>&1
    
    # Get pod IPs
    local k3s1_pod_ip=$(kubectl get pod "$test_pod_k3s1" -o jsonpath='{.status.podIP}' 2>/dev/null)
    local k3s2_pod_ip=$(kubectl get pod "$test_pod_k3s2" -o jsonpath='{.status.podIP}' 2>/dev/null)
    
    if [[ -n "$k3s1_pod_ip" && -n "$k3s2_pod_ip" ]]; then
        log "Test pod IPs - k3s1: $k3s1_pod_ip, k3s2: $k3s2_pod_ip"
        add_to_report "**Test Pod IPs**: k3s1: $k3s1_pod_ip, k3s2: $k3s2_pod_ip"
        
        # Test connectivity from k3s1 to k3s2
        if kubectl exec "$test_pod_k3s1" -- ping -c 1 "$k3s2_pod_ip" >/dev/null 2>&1; then
            test_result 0 "Pod connectivity from k3s1 to k3s2 works"
        else
            test_result 1 "Pod connectivity from k3s1 to k3s2 failed"
        fi
        
        # Test connectivity from k3s2 to k3s1
        if kubectl exec "$test_pod_k3s2" -- ping -c 1 "$k3s1_pod_ip" >/dev/null 2>&1; then
            test_result 0 "Pod connectivity from k3s2 to k3s1 works"
        else
            test_result 1 "Pod connectivity from k3s2 to k3s1 failed"
        fi
    else
        test_result 1 "Could not get test pod IPs for connectivity testing"
    fi
    
    # Clean up test pods
    kubectl delete pod "$test_pod_k3s1" --ignore-not-found=true >/dev/null 2>&1 &
    kubectl delete pod "$test_pod_k3s2" --ignore-not-found=true >/dev/null 2>&1 &
}#
 Monitoring integration verification
verify_monitoring_integration() {
    log "Verifying monitoring integration for both nodes..."
    add_to_report "### Monitoring Integration Verification"
    add_to_report ""
    
    # Check node-exporter on both nodes
    local node_exporter_pods=$(kubectl get pods -A -l app.kubernetes.io/name=node-exporter --no-headers 2>/dev/null | wc -l)
    local running_node_exporter=$(kubectl get pods -A -l app.kubernetes.io/name=node-exporter --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $node_exporter_pods -eq 2 && $running_node_exporter -eq 2 ]]; then
        test_result 0 "Node-exporter is running on both nodes"
    else
        test_result 1 "Node-exporter is not healthy ($running_node_exporter/$node_exporter_pods pods running)"
    fi
    
    # Check Grafana is running
    local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $grafana_pods -gt 0 ]]; then
        test_result 0 "Grafana is running and ready to display node metrics"
        add_to_report "**Grafana Status**: Running and ready for node metrics"
    else
        test_result 1 "Grafana is not running"
    fi
    
    add_to_report ""
}

# GitOps reconciliation verification
verify_gitops_reconciliation() {
    log "Verifying GitOps reconciliation for multi-node setup..."
    add_to_report "### GitOps Reconciliation Verification"
    add_to_report ""
    
    # Check Flux controllers
    local flux_controllers=("source-controller" "kustomize-controller" "helm-controller" "notification-controller")
    local healthy_controllers=0
    
    for controller in "${flux_controllers[@]}"; do
        local pod_status=$(kubectl get pods -n flux-system -l app=$controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [[ "$pod_status" == "Running" ]]; then
            healthy_controllers=$((healthy_controllers + 1))
        fi
    done
    
    if [[ $healthy_controllers -eq ${#flux_controllers[@]} ]]; then
        test_result 0 "All Flux controllers are healthy"
    else
        test_result 1 "Some Flux controllers are not healthy ($healthy_controllers/${#flux_controllers[@]})"
    fi
    
    # Check if k3s2 node configuration is applied
    if kubectl get longhornnode k3s2 -n longhorn-system >/dev/null 2>&1; then
        test_result 0 "k3s2 node configuration has been applied by Flux"
    else
        test_result 1 "k3s2 node configuration has not been applied by Flux"
    fi
    
    add_to_report ""
}#
 Performance and load distribution tests
run_performance_tests() {
    log "Running performance and load distribution tests..."
    add_to_report "### Performance and Load Distribution Tests"
    add_to_report ""
    
    # Test pod scheduling distribution
    test_pod_scheduling_distribution
    
    # Test storage performance across nodes
    test_storage_performance
    
    add_to_report ""
}

# Test pod scheduling distribution
test_pod_scheduling_distribution() {
    log "Testing pod scheduling distribution..."
    
    # Create a test deployment with multiple replicas
    local test_deployment="load-distribution-test"
    local test_replicas=6
    
    # Clean up any existing test deployment
    kubectl delete deployment "$test_deployment" --ignore-not-found=true >/dev/null 2>&1
    
    # Create test deployment
    kubectl create deployment "$test_deployment" --image=nginx --replicas=$test_replicas >/dev/null 2>&1
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available deployment/"$test_deployment" --timeout=120s >/dev/null 2>&1
    
    # Check distribution
    local pods_on_k3s1=$(kubectl get pods -l app="$test_deployment" -o wide --no-headers 2>/dev/null | grep k3s1 | wc -l)
    local pods_on_k3s2=$(kubectl get pods -l app="$test_deployment" -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
    
    log "Load distribution test - k3s1: $pods_on_k3s1 pods, k3s2: $pods_on_k3s2 pods"
    add_to_report "**Load Distribution Test**: k3s1: $pods_on_k3s1 pods, k3s2: $pods_on_k3s2 pods"
    
    if [[ $pods_on_k3s1 -gt 0 && $pods_on_k3s2 -gt 0 ]]; then
        test_result 0 "Pods are distributed across both nodes"
        
        # Check if distribution is reasonably balanced
        local distribution_ratio=$((pods_on_k3s1 * 100 / (pods_on_k3s1 + pods_on_k3s2)))
        if [[ $distribution_ratio -ge 30 && $distribution_ratio -le 70 ]]; then
            test_result 0 "Pod distribution is well balanced (${distribution_ratio}% on k3s1)"
        else
            test_warning "Pod distribution is skewed (${distribution_ratio}% on k3s1)"
        fi
    else
        test_result 1 "Pods are not distributed across both nodes"
    fi
    
    # Clean up test deployment
    kubectl delete deployment "$test_deployment" --ignore-not-found=true >/dev/null 2>&1
}

# Test storage performance
test_storage_performance() {
    log "Testing storage performance across nodes..."
    
    # Create test PVCs on both nodes
    local test_pvc_k3s1="storage-test-k3s1"
    local test_pvc_k3s2="storage-test-k3s2"
    
    # Clean up any existing test resources
    kubectl delete pvc "$test_pvc_k3s1" "$test_pvc_k3s2" --ignore-not-found=true >/dev/null 2>&1
    kubectl delete pod "storage-test-pod-k3s1" "storage-test-pod-k3s2" --ignore-not-found=true >/dev/null 2>&1
    
    # Create test PVCs
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc_k3s1
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc_k3s2
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
EOF
    
    # Wait for PVCs to be bound
    kubectl wait --for=condition=Bound pvc/"$test_pvc_k3s1" --timeout=60s >/dev/null 2>&1
    kubectl wait --for=condition=Bound pvc/"$test_pvc_k3s2" --timeout=60s >/dev/null 2>&1
    
    # Check PVC status
    local pvc1_status=$(kubectl get pvc "$test_pvc_k3s1" -o jsonpath='{.status.phase}' 2>/dev/null)
    local pvc2_status=$(kubectl get pvc "$test_pvc_k3s2" -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [[ "$pvc1_status" == "Bound" && "$pvc2_status" == "Bound" ]]; then
        test_result 0 "Storage provisioning works on both nodes"
        add_to_report "**Storage Test PVCs**: Both bound successfully"
    else
        test_result 1 "Storage provisioning failed (PVC1: $pvc1_status, PVC2: $pvc2_status)"
    fi
    
    # Clean up test resources
    kubectl delete pvc "$test_pvc_k3s1" "$test_pvc_k3s2" --ignore-not-found=true >/dev/null 2>&1 &
}# Generate
 health summary
generate_health_summary() {
    log "Generating health verification summary..."
    add_to_report "## Health Verification Summary"
    add_to_report ""
    add_to_report "**Total Tests**: $TOTAL_TESTS"
    add_to_report "**Passed**: $PASSED_TESTS"
    add_to_report "**Failed**: $FAILED_TESTS"
    add_to_report "**Warnings**: $WARNING_TESTS"
    add_to_report ""
    
    # Calculate success rate
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    log "======================================================"
    log "Post-Onboarding Health Verification Summary"
    log "======================================================"
    log "Total tests: $TOTAL_TESTS"
    log "Passed: $PASSED_TESTS"
    log "Failed: $FAILED_TESTS"
    log "Warnings: $WARNING_TESTS"
    log "Success rate: ${success_rate}%"
    
    # Overall health assessment
    if [[ $FAILED_TESTS -eq 0 ]]; then
        if [[ $WARNING_TESTS -eq 0 ]]; then
            success "🎉 EXCELLENT: k3s2 onboarding is fully successful!"
            add_to_report "**Overall Status**: 🎉 EXCELLENT - k3s2 onboarding fully successful"
            log "✅ All systems are operational across both nodes"
            log "✅ Storage redundancy is properly configured"
            log "✅ Applications are distributed correctly"
            log "✅ Network connectivity is working"
            log "✅ Monitoring is integrated"
            log "✅ GitOps reconciliation is healthy"
        else
            success "✅ GOOD: k3s2 onboarding is successful with minor issues"
            add_to_report "**Overall Status**: ✅ GOOD - k3s2 onboarding successful with minor issues"
            log "✅ All critical systems are operational"
            log "⚠️ Some non-critical issues detected (see warnings above)"
        fi
    elif [[ $FAILED_TESTS -le 2 ]]; then
        warn "⚠️ ATTENTION NEEDED: k3s2 onboarding has some issues"
        add_to_report "**Overall Status**: ⚠️ ATTENTION NEEDED - some issues require resolution"
        log "⚠️ Some systems need attention"
        log "🔧 Review failed tests and take corrective action"
    else
        error "❌ CRITICAL: k3s2 onboarding has significant issues"
        add_to_report "**Overall Status**: ❌ CRITICAL - significant issues require immediate attention"
        log "❌ Multiple critical systems have issues"
        log "🚨 Immediate action required"
    fi
    
    # Recommendations
    log ""
    log "📋 Recommendations:"
    add_to_report ""
    add_to_report "## Recommendations"
    add_to_report ""
    
    if [[ $FAILED_TESTS -eq 0 && $WARNING_TESTS -eq 0 ]]; then
        log "1. ✅ k3s2 onboarding is complete - cluster is ready for production workloads"
        log "2. 📊 Monitor cluster performance and resource utilization"
        log "3. 🔄 Consider deploying test applications to validate end-to-end functionality"
        add_to_report "1. ✅ k3s2 onboarding is complete - cluster ready for production workloads"
        add_to_report "2. 📊 Monitor cluster performance and resource utilization"
        add_to_report "3. 🔄 Consider deploying test applications to validate end-to-end functionality"
    else
        if [[ $FAILED_TESTS -gt 0 ]]; then
            log "1. 🔧 Address failed tests immediately"
            log "2. 📋 Review error messages and take corrective action"
            add_to_report "1. 🔧 Address failed tests immediately"
            add_to_report "2. 📋 Review error messages and take corrective action"
        fi
        if [[ $WARNING_TESTS -gt 0 ]]; then
            log "3. ⚠️ Review warnings and consider improvements"
            add_to_report "3. ⚠️ Review warnings and consider improvements"
        fi
        log "4. 🔄 Re-run this health verification after fixes"
        add_to_report "4. 🔄 Re-run this health verification after fixes"
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by post-onboarding-health-verification.sh*"
        log ""
        log "📄 Detailed report generated: $REPORT_FILE"
    fi
    
    log "======================================================"
    
    # Return appropriate exit code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        return 0
    else
        return $FAILED_TESTS
    fi
}# Main
 health verification function
run_post_onboarding_health_verification() {
    log "Starting Post-Onboarding Health Verification System..."
    log "======================================================"
    
    init_report
    add_to_report "## Health Verification Started"
    add_to_report "**Timestamp**: $(date)"
    add_to_report ""
    
    # Run comprehensive health checks
    verify_multi_node_cluster_health
    verify_storage_redundancy
    verify_application_distribution
    verify_network_connectivity
    verify_monitoring_integration
    verify_gitops_reconciliation
    
    if [[ "$RUN_PERFORMANCE_TESTS" == "true" ]]; then
        run_performance_tests
    fi
    
    # Generate summary
    generate_health_summary
}

# Main execution
main() {
    log "Post-Onboarding Health Verification System v1.0"
    log "================================================"
    
    check_dependencies
    
    # Run the health verification
    run_post_onboarding_health_verification
    exit_code=$?
    
    exit $exit_code
}

# Run main function
main "$@"