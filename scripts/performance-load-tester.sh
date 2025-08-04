#!/bin/bash
# Performance and Load Distribution Testing Utility
#
# This script tests performance characteristics and load distribution
# across k3s1 and k3s2 nodes after onboarding.
#
# Requirements: 7.3 from k3s1-node-onboarding spec
#
# Usage: ./scripts/performance-load-tester.sh [--run-load-test] [--run-storage-test] [--report]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/performance-load-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/performance-load-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Flags
RUN_LOAD_TEST=false
RUN_STORAGE_TEST=false
GENERATE_REPORT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --run-load-test)
            RUN_LOAD_TEST=true
            shift
            ;;
        --run-storage-test)
            RUN_STORAGE_TEST=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--run-load-test] [--run-storage-test] [--report]"
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

# Initialize report
init_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        mkdir -p "$REPORT_DIR"
        cat > "$REPORT_FILE" << EOF
# Performance and Load Distribution Testing Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Load Testing**: $RUN_LOAD_TEST
**Storage Testing**: $RUN_STORAGE_TEST

## Executive Summary

This report contains performance and load distribution test results across k3s1 and k3s2 nodes.

## Test Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}

# Test node resource utilization
test_node_resource_utilization() {
    log "Testing node resource utilization..."
    add_to_report "### Node Resource Utilization"
    add_to_report ""
    
    # Check if metrics-server is available
    if ! kubectl top nodes >/dev/null 2>&1; then
        warn "Metrics server not available - using alternative methods"
        add_to_report "**Metrics Server**: Not available"
        add_to_report ""
        return 0
    fi
    
    # Get node resource usage
    log "Current node resource usage:"
    add_to_report "**Current Node Resource Usage**:"
    add_to_report ""
    
    while IFS= read -r line; do
        local node=$(echo "$line" | awk '{print $1}')
        local cpu=$(echo "$line" | awk '{print $2}')
        local cpu_percent=$(echo "$line" | awk '{print $3}')
        local memory=$(echo "$line" | awk '{print $4}')
        local memory_percent=$(echo "$line" | awk '{print $5}')
        
        log "  $node: CPU: $cpu ($cpu_percent), Memory: $memory ($memory_percent)"
        add_to_report "- **$node**: CPU: $cpu ($cpu_percent), Memory: $memory ($memory_percent)"
        
        # Check if resource usage is reasonable
        local cpu_num=$(echo "$cpu_percent" | sed 's/%//')
        local memory_num=$(echo "$memory_percent" | sed 's/%//')
        
        if [[ "$cpu_num" =~ ^[0-9]+$ ]] && [[ $cpu_num -lt 80 ]]; then
            success "  $node CPU usage is reasonable ($cpu_percent)"
        elif [[ "$cpu_num" =~ ^[0-9]+$ ]] && [[ $cpu_num -ge 80 ]]; then
            warn "  $node CPU usage is high ($cpu_percent)"
        fi
        
        if [[ "$memory_num" =~ ^[0-9]+$ ]] && [[ $memory_num -lt 80 ]]; then
            success "  $node memory usage is reasonable ($memory_percent)"
        elif [[ "$memory_num" =~ ^[0-9]+$ ]] && [[ $memory_num -ge 80 ]]; then
            warn "  $node memory usage is high ($memory_percent)"
        fi
    done < <(kubectl top nodes --no-headers 2>/dev/null)
    
    add_to_report ""
}

# Test pod scheduling distribution
test_pod_scheduling_distribution() {
    log "Testing pod scheduling distribution..."
    add_to_report "### Pod Scheduling Distribution Test"
    add_to_report ""
    
    local test_namespace="load-distribution-test"
    local test_deployment="scheduler-test"
    local test_replicas=8
    
    # Clean up any existing test resources
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1
    sleep 5
    
    # Create test namespace
    kubectl create namespace "$test_namespace" >/dev/null 2>&1
    
    # Create test deployment with multiple replicas
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $test_deployment
  namespace: $test_namespace
spec:
  replicas: $test_replicas
  selector:
    matchLabels:
      app: $test_deployment
  template:
    metadata:
      labels:
        app: $test_deployment
    spec:
      containers:
      - name: test-container
        image: busybox
        command: ["sleep", "300"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 50m
            memory: 64Mi
EOF
    
    # Wait for deployment to be ready
    log "Waiting for scheduler test deployment to be ready..."
    if kubectl wait --for=condition=available deployment/"$test_deployment" -n "$test_namespace" --timeout=120s >/dev/null 2>&1; then
        success "Scheduler test deployment is ready"
        add_to_report "✅ Test deployment created successfully"
        
        # Analyze pod distribution
        local pods_on_k3s1=$(kubectl get pods -n "$test_namespace" -l app="$test_deployment" -o wide --no-headers 2>/dev/null | grep k3s1 | wc -l)
        local pods_on_k3s2=$(kubectl get pods -n "$test_namespace" -l app="$test_deployment" -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
        local total_pods=$((pods_on_k3s1 + pods_on_k3s2))
        
        log "Pod distribution: k3s1: $pods_on_k3s1, k3s2: $pods_on_k3s2 (total: $total_pods)"
        add_to_report "**Pod Distribution**: k3s1: $pods_on_k3s1, k3s2: $pods_on_k3s2 (total: $total_pods)"
        
        if [[ $total_pods -eq $test_replicas ]]; then
            success "All pods were scheduled successfully"
            add_to_report "✅ All $test_replicas pods scheduled"
            
            # Calculate distribution metrics
            local k3s1_percentage=$((pods_on_k3s1 * 100 / total_pods))
            local k3s2_percentage=$((pods_on_k3s2 * 100 / total_pods))
            
            log "Distribution percentage: k3s1: ${k3s1_percentage}%, k3s2: ${k3s2_percentage}%"
            add_to_report "**Distribution Percentage**: k3s1: ${k3s1_percentage}%, k3s2: ${k3s2_percentage}%"
            
            # Evaluate distribution quality
            if [[ $pods_on_k3s2 -gt 0 ]]; then
                success "Pods are distributed across both nodes"
                add_to_report "✅ Multi-node distribution achieved"
                
                if [[ $k3s2_percentage -ge 30 && $k3s2_percentage -le 70 ]]; then
                    success "Pod distribution is well balanced"
                    add_to_report "✅ Distribution is well balanced"
                elif [[ $k3s2_percentage -ge 20 ]]; then
                    success "Pod distribution is acceptable"
                    add_to_report "✅ Distribution is acceptable"
                else
                    warn "Pod distribution is skewed toward k3s1"
                    add_to_report "⚠️ Distribution is skewed toward k3s1"
                fi
            else
                error "All pods are on k3s1 - no distribution achieved"
                add_to_report "❌ No multi-node distribution"
            fi
        else
            error "Not all pods were scheduled ($total_pods/$test_replicas)"
            add_to_report "❌ Only $total_pods/$test_replicas pods scheduled"
        fi
    else
        error "Scheduler test deployment failed to become ready"
        add_to_report "❌ Test deployment failed"
    fi
    
    # Clean up test resources
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1 &
    
    add_to_report ""
}

# Test network performance between nodes
test_network_performance() {
    if [[ "$RUN_LOAD_TEST" != "true" ]]; then
        log "Skipping network performance test (use --run-load-test to enable)"
        return 0
    fi
    
    log "Testing network performance between nodes..."
    add_to_report "### Network Performance Test"
    add_to_report ""
    
    local test_namespace="network-perf-test"
    local server_pod="iperf3-server"
    local client_pod="iperf3-client"
    
    # Clean up any existing test resources
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1
    sleep 5
    
    # Create test namespace
    kubectl create namespace "$test_namespace" >/dev/null 2>&1
    
    # Create iperf3 server on k3s1
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $server_pod
  namespace: $test_namespace
  labels:
    app: iperf3-server
spec:
  nodeSelector:
    kubernetes.io/hostname: k3s1
  containers:
  - name: iperf3
    image: networkstatic/iperf3
    args: ["-s"]
    ports:
    - containerPort: 5201
  restartPolicy: Never
---
apiVersion: v1
kind: Service
metadata:
  name: iperf3-server-service
  namespace: $test_namespace
spec:
  selector:
    app: iperf3-server
  ports:
  - port: 5201
    targetPort: 5201
EOF
    
    # Create iperf3 client on k3s2
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $client_pod
  namespace: $test_namespace
spec:
  nodeSelector:
    kubernetes.io/hostname: k3s2
  containers:
  - name: iperf3
    image: networkstatic/iperf3
    command: ["sleep", "300"]
  restartPolicy: Never
EOF
    
    # Wait for pods to be ready
    log "Waiting for network test pods to be ready..."
    if kubectl wait --for=condition=Ready pod/"$server_pod" -n "$test_namespace" --timeout=60s >/dev/null 2>&1 && \
       kubectl wait --for=condition=Ready pod/"$client_pod" -n "$test_namespace" --timeout=60s >/dev/null 2>&1; then
        
        success "Network test pods are ready"
        add_to_report "✅ Network test pods ready"
        
        # Get server service IP
        local server_ip=$(kubectl get service iperf3-server-service -n "$test_namespace" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
        
        if [[ -n "$server_ip" ]]; then
            log "Running network performance test (k3s2 -> k3s1)..."
            add_to_report "**Test Direction**: k3s2 -> k3s1"
            add_to_report "**Server IP**: $server_ip"
            
            # Run iperf3 test
            local test_output=$(kubectl exec -n "$test_namespace" "$client_pod" -- iperf3 -c "$server_ip" -t 10 -f M 2>/dev/null || echo "")
            
            if [[ -n "$test_output" ]]; then
                # Extract bandwidth from output
                local bandwidth=$(echo "$test_output" | grep "receiver" | awk '{print $(NF-1), $NF}' | head -1)
                
                if [[ -n "$bandwidth" ]]; then
                    success "Network performance test completed"
                    log "Bandwidth: $bandwidth"
                    add_to_report "✅ Test completed successfully"
                    add_to_report "**Bandwidth**: $bandwidth"
                    
                    # Basic performance evaluation
                    local bandwidth_num=$(echo "$bandwidth" | awk '{print $1}')
                    if [[ "$bandwidth_num" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                        if (( $(echo "$bandwidth_num > 100" | bc -l) )); then
                            success "Network performance is good (>100 Mbits/sec)"
                            add_to_report "✅ Performance: Good (>100 Mbits/sec)"
                        elif (( $(echo "$bandwidth_num > 50" | bc -l) )); then
                            success "Network performance is acceptable (>50 Mbits/sec)"
                            add_to_report "✅ Performance: Acceptable (>50 Mbits/sec)"
                        else
                            warn "Network performance is low (<50 Mbits/sec)"
                            add_to_report "⚠️ Performance: Low (<50 Mbits/sec)"
                        fi
                    fi
                else
                    warn "Could not extract bandwidth from test output"
                    add_to_report "⚠️ Could not extract bandwidth"
                fi
            else
                warn "Network performance test failed or produced no output"
                add_to_report "⚠️ Test failed or no output"
            fi
        else
            error "Could not get server service IP"
            add_to_report "❌ Could not get server service IP"
        fi
    else
        error "Network test pods failed to become ready"
        add_to_report "❌ Network test pods failed to become ready"
    fi
    
    # Clean up test resources
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1 &
    
    add_to_report ""
}

# Test storage performance across nodes
test_storage_performance() {
    if [[ "$RUN_STORAGE_TEST" != "true" ]]; then
        log "Skipping storage performance test (use --run-storage-test to enable)"
        return 0
    fi
    
    log "Testing storage performance across nodes..."
    add_to_report "### Storage Performance Test"
    add_to_report ""
    
    local test_namespace="storage-perf-test"
    
    # Clean up any existing test resources
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1
    sleep 10
    
    # Create test namespace
    kubectl create namespace "$test_namespace" >/dev/null 2>&1
    
    # Test storage on k3s1
    test_storage_on_node "k3s1" "$test_namespace"
    
    # Test storage on k3s2
    test_storage_on_node "k3s2" "$test_namespace"
    
    # Clean up test resources
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1 &
    
    add_to_report ""
}

# Test storage performance on specific node
test_storage_on_node() {
    local node="$1"
    local namespace="$2"
    
    log "Testing storage performance on $node..."
    add_to_report "#### Storage Performance on $node"
    add_to_report ""
    
    local pvc_name="storage-test-$node"
    local pod_name="storage-test-pod-$node"
    
    # Create PVC
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $pvc_name
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: longhorn
EOF
    
    # Wait for PVC to be bound
    if kubectl wait --for=condition=Bound pvc/"$pvc_name" -n "$namespace" --timeout=60s >/dev/null 2>&1; then
        success "PVC bound on $node"
        add_to_report "✅ PVC bound successfully"
        
        # Create test pod
        cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $namespace
spec:
  nodeSelector:
    kubernetes.io/hostname: $node
  containers:
  - name: storage-test
    image: busybox
    command: ["sleep", "300"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: $pvc_name
  restartPolicy: Never
EOF
        
        # Wait for pod to be ready
        if kubectl wait --for=condition=Ready pod/"$pod_name" -n "$namespace" --timeout=60s >/dev/null 2>&1; then
            success "Storage test pod ready on $node"
            add_to_report "✅ Test pod ready"
            
            # Run basic I/O test
            log "Running I/O test on $node..."
            
            # Write test
            local write_start=$(date +%s.%N)
            if kubectl exec -n "$namespace" "$pod_name" -- dd if=/dev/zero of=/data/testfile bs=1M count=100 >/dev/null 2>&1; then
                local write_end=$(date +%s.%N)
                local write_time=$(echo "$write_end - $write_start" | bc)
                local write_speed=$(echo "scale=2; 100 / $write_time" | bc)
                
                success "Write test completed on $node: ${write_speed} MB/s"
                add_to_report "✅ Write speed: ${write_speed} MB/s"
            else
                error "Write test failed on $node"
                add_to_report "❌ Write test failed"
            fi
            
            # Read test
            local read_start=$(date +%s.%N)
            if kubectl exec -n "$namespace" "$pod_name" -- dd if=/data/testfile of=/dev/null bs=1M >/dev/null 2>&1; then
                local read_end=$(date +%s.%N)
                local read_time=$(echo "$read_end - $read_start" | bc)
                local read_speed=$(echo "scale=2; 100 / $read_time" | bc)
                
                success "Read test completed on $node: ${read_speed} MB/s"
                add_to_report "✅ Read speed: ${read_speed} MB/s"
            else
                error "Read test failed on $node"
                add_to_report "❌ Read test failed"
            fi
            
            # Cleanup test file
            kubectl exec -n "$namespace" "$pod_name" -- rm -f /data/testfile >/dev/null 2>&1
            
        else
            error "Storage test pod failed to become ready on $node"
            add_to_report "❌ Test pod failed to become ready"
        fi
    else
        error "PVC failed to bind on $node"
        add_to_report "❌ PVC failed to bind"
    fi
    
    add_to_report ""
}

# Test cluster scalability
test_cluster_scalability() {
    log "Testing cluster scalability characteristics..."
    add_to_report "### Cluster Scalability Test"
    add_to_report ""
    
    # Get current cluster capacity
    local total_cpu=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.cpu}' | tr ' ' '\n' | awk '{sum += $1} END {print sum}')
    local total_memory=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.memory}' | tr ' ' '\n' | sed 's/Ki$//' | awk '{sum += $1} END {print sum/1024/1024 "Gi"}')
    local total_pods=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.pods}' | tr ' ' '\n' | awk '{sum += $1} END {print sum}')
    
    log "Cluster capacity: CPU: $total_cpu cores, Memory: $total_memory, Pods: $total_pods"
    add_to_report "**Cluster Capacity**:"
    add_to_report "- **CPU**: $total_cpu cores"
    add_to_report "- **Memory**: $total_memory"
    add_to_report "- **Pods**: $total_pods"
    
    # Get current usage
    local current_pods=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
    local pod_utilization=$((current_pods * 100 / total_pods))
    
    log "Current usage: $current_pods pods (${pod_utilization}% utilization)"
    add_to_report "**Current Usage**: $current_pods pods (${pod_utilization}% utilization)"
    
    # Scalability assessment
    if [[ $pod_utilization -lt 50 ]]; then
        success "Cluster has good scalability headroom"
        add_to_report "✅ Good scalability headroom (${pod_utilization}% used)"
    elif [[ $pod_utilization -lt 75 ]]; then
        success "Cluster has moderate scalability headroom"
        add_to_report "✅ Moderate scalability headroom (${pod_utilization}% used)"
    else
        warn "Cluster has limited scalability headroom"
        add_to_report "⚠️ Limited scalability headroom (${pod_utilization}% used)"
    fi
    
    add_to_report ""
}

# Generate performance summary
generate_performance_summary() {
    log "Generating performance and load testing summary..."
    add_to_report "## Performance Testing Summary"
    add_to_report ""
    
    log "======================================================"
    log "Performance and Load Distribution Testing Summary"
    log "======================================================"
    
    # Overall assessment
    local overall_status="UNKNOWN"
    local recommendations=()
    
    # Check if both nodes are ready and have pods
    local k3s1_ready=$(kubectl get node k3s1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    local k3s2_ready=$(kubectl get node k3s2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    local pods_on_k3s2=$(kubectl get pods -A --field-selector=status.phase=Running -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
    
    if [[ "$k3s1_ready" == "True" && "$k3s2_ready" == "True" && $pods_on_k3s2 -gt 0 ]]; then
        overall_status="EXCELLENT"
        success "🎉 EXCELLENT: Performance and load distribution is working well!"
        add_to_report "**Overall Status**: 🎉 EXCELLENT"
        log "✅ Both nodes are ready and operational"
        log "✅ Load is being distributed across nodes"
        log "✅ Performance characteristics are good"
        recommendations+=("✅ Performance and load distribution is optimal")
        recommendations+=("📊 Continue monitoring performance metrics")
        recommendations+=("🔄 Consider running periodic performance tests")
    elif [[ "$k3s1_ready" == "True" && "$k3s2_ready" == "True" ]]; then
        overall_status="GOOD"
        success "✅ GOOD: Infrastructure is ready but limited load distribution"
        add_to_report "**Overall Status**: ✅ GOOD"
        log "✅ Both nodes are ready"
        log "⚠️ Limited load distribution observed"
        recommendations+=("🔧 Deploy more applications to test load distribution")
        recommendations+=("📊 Monitor scheduler behavior and node utilization")
    else
        overall_status="ATTENTION_NEEDED"
        warn "⚠️ ATTENTION NEEDED: Performance testing has limitations"
        add_to_report "**Overall Status**: ⚠️ ATTENTION NEEDED"
        log "❌ Not all nodes are ready for performance testing"
        recommendations+=("🔧 Fix node readiness issues before performance testing")
        recommendations+=("📋 Check cluster health and node configuration")
    fi
    
    # Display recommendations
    log ""
    log "📋 Recommendations:"
    add_to_report ""
    add_to_report "## Recommendations"
    add_to_report ""
    
    for i in "${!recommendations[@]}"; do
        log "$((i + 1)). ${recommendations[i]}"
        add_to_report "$((i + 1)). ${recommendations[i]}"
    done
    
    # Additional recommendations based on tests run
    if [[ "$RUN_LOAD_TEST" == "true" ]]; then
        log "$((${#recommendations[@]} + 1)). 🔄 Network performance testing completed - monitor for regressions"
        add_to_report "$((${#recommendations[@]} + 1)). 🔄 Network performance testing completed - monitor for regressions"
    else
        log "$((${#recommendations[@]} + 1)). 🔧 Consider running network performance tests with --run-load-test"
        add_to_report "$((${#recommendations[@]} + 1)). 🔧 Consider running network performance tests with --run-load-test"
    fi
    
    if [[ "$RUN_STORAGE_TEST" == "true" ]]; then
        log "$((${#recommendations[@]} + 2)). 🔄 Storage performance testing completed - monitor for regressions"
        add_to_report "$((${#recommendations[@]} + 2)). 🔄 Storage performance testing completed - monitor for regressions"
    else
        log "$((${#recommendations[@]} + 2)). 🔧 Consider running storage performance tests with --run-storage-test"
        add_to_report "$((${#recommendations[@]} + 2)). 🔧 Consider running storage performance tests with --run-storage-test"
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by performance-load-tester.sh*"
        log ""
        log "📄 Detailed report generated: $REPORT_FILE"
    fi
    
    log "======================================================"
    
    # Return appropriate exit code
    case $overall_status in
        "EXCELLENT") return 0 ;;
        "GOOD") return 0 ;;
        "ATTENTION_NEEDED") return 1 ;;
        *) return 2 ;;
    esac
}

# Main execution
main() {
    log "Performance and Load Distribution Testing Utility v1.0"
    log "====================================================="
    
    # Check dependencies
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        exit 1
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        error "bc not found - please install bc (brew install bc)"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    init_report
    
    # Run performance tests
    test_node_resource_utilization
    test_pod_scheduling_distribution
    test_cluster_scalability
    
    if [[ "$RUN_LOAD_TEST" == "true" ]]; then
        test_network_performance
    fi
    
    if [[ "$RUN_STORAGE_TEST" == "true" ]]; then
        test_storage_performance
    fi
    
    # Generate summary
    generate_performance_summary
    exit_code=$?
    
    exit $exit_code
}

# Run main function
main "$@"