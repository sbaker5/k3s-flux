#!/bin/bash
# Storage Redundancy Validation Tool
#
# This script specifically validates storage redundancy across k3s1 and k3s2 nodes
# ensuring Longhorn volumes are properly distributed for high availability.
#
# Requirements: 2.4 from k3s1-node-onboarding spec
#
# Usage: ./scripts/storage-redundancy-validator.sh [--create-test-volume] [--report]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/storage-redundancy-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/storage-redundancy-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
CREATE_TEST_VOLUME=false
GENERATE_REPORT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --create-test-volume)
            CREATE_TEST_VOLUME=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--create-test-volume] [--report]"
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

# Initialize report
init_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        mkdir -p "$REPORT_DIR"
        cat > "$REPORT_FILE" << EOF
# Storage Redundancy Validation Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Test Volume Creation**: $CREATE_TEST_VOLUME

## Executive Summary

This report validates storage redundancy across k3s1 and k3s2 nodes using Longhorn.

## Validation Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}

# Validate Longhorn node configuration
validate_longhorn_nodes() {
    log "Validating Longhorn node configuration..."
    add_to_report "### Longhorn Node Configuration"
    add_to_report ""
    
    local issues=0
    
    # Check both nodes exist in Longhorn
    local longhorn_nodes=$(kubectl get longhornnode -n longhorn-system --no-headers 2>/dev/null | wc -l)
    if [[ $longhorn_nodes -eq 2 ]]; then
        success "Both nodes are registered in Longhorn ($longhorn_nodes nodes)"
        add_to_report "✅ Longhorn nodes: $longhorn_nodes (both k3s1 and k3s2)"
    else
        error "Expected 2 Longhorn nodes, found $longhorn_nodes"
        add_to_report "❌ Longhorn nodes: $longhorn_nodes (expected 2)"
        issues=$((issues + 1))
    fi
    
    # Check k3s1 node details
    if kubectl get longhornnode k3s1 -n longhorn-system >/dev/null 2>&1; then
        local k3s1_ready=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        local k3s1_schedulable=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Schedulable")].status}' 2>/dev/null)
        
        if [[ "$k3s1_ready" == "True" && "$k3s1_schedulable" == "True" ]]; then
            success "k3s1 Longhorn node is ready and schedulable"
            add_to_report "✅ k3s1: Ready and schedulable"
        else
            error "k3s1 Longhorn node issues - Ready: $k3s1_ready, Schedulable: $k3s1_schedulable"
            add_to_report "❌ k3s1: Ready: $k3s1_ready, Schedulable: $k3s1_schedulable"
            issues=$((issues + 1))
        fi
        
        # Check k3s1 disk configuration
        local k3s1_disks=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.spec.disks}' 2>/dev/null)
        if [[ -n "$k3s1_disks" && "$k3s1_disks" != "{}" ]]; then
            local k3s1_disk_paths=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.spec.disks.*.path}' 2>/dev/null)
            success "k3s1 has disk configuration: $k3s1_disk_paths"
            add_to_report "✅ k3s1 disks: $k3s1_disk_paths"
        else
            error "k3s1 has no disk configuration"
            add_to_report "❌ k3s1 disks: none configured"
            issues=$((issues + 1))
        fi
    else
        error "k3s1 Longhorn node not found"
        add_to_report "❌ k3s1 Longhorn node: not found"
        issues=$((issues + 1))
    fi
    
    # Check k3s2 node details
    if kubectl get longhornnode k3s2 -n longhorn-system >/dev/null 2>&1; then
        local k3s2_ready=$(kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        local k3s2_schedulable=$(kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Schedulable")].status}' 2>/dev/null)
        
        if [[ "$k3s2_ready" == "True" && "$k3s2_schedulable" == "True" ]]; then
            success "k3s2 Longhorn node is ready and schedulable"
            add_to_report "✅ k3s2: Ready and schedulable"
        else
            error "k3s2 Longhorn node issues - Ready: $k3s2_ready, Schedulable: $k3s2_schedulable"
            add_to_report "❌ k3s2: Ready: $k3s2_ready, Schedulable: $k3s2_schedulable"
            issues=$((issues + 1))
        fi
        
        # Check k3s2 disk configuration
        local k3s2_disks=$(kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.spec.disks}' 2>/dev/null)
        if [[ -n "$k3s2_disks" && "$k3s2_disks" != "{}" ]]; then
            local k3s2_disk_paths=$(kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.spec.disks.*.path}' 2>/dev/null)
            success "k3s2 has disk configuration: $k3s2_disk_paths"
            add_to_report "✅ k3s2 disks: $k3s2_disk_paths"
        else
            error "k3s2 has no disk configuration"
            add_to_report "❌ k3s2 disks: none configured"
            issues=$((issues + 1))
        fi
    else
        error "k3s2 Longhorn node not found"
        add_to_report "❌ k3s2 Longhorn node: not found"
        issues=$((issues + 1))
    fi
    
    add_to_report ""
    return $issues
}

# Validate existing volume redundancy
validate_existing_volumes() {
    log "Validating existing volume redundancy..."
    add_to_report "### Existing Volume Redundancy"
    add_to_report ""
    
    local issues=0
    local volumes=$(kubectl get volumes -n longhorn-system --no-headers 2>/dev/null | wc -l)
    
    if [[ $volumes -eq 0 ]]; then
        log "No existing volumes found - redundancy validation will be performed with test volume"
        add_to_report "**Existing Volumes**: None found"
        add_to_report ""
        return 0
    fi
    
    log "Found $volumes existing volume(s) - analyzing redundancy..."
    add_to_report "**Existing Volumes**: $volumes found"
    add_to_report ""
    
    # Analyze each volume
    while IFS= read -r volume; do
        log "Analyzing volume: $volume"
        add_to_report "#### Volume: $volume"
        add_to_report ""
        
        # Get volume details
        local replica_count=$(kubectl get volume "$volume" -n longhorn-system -o jsonpath='{.spec.numberOfReplicas}' 2>/dev/null)
        local volume_size=$(kubectl get volume "$volume" -n longhorn-system -o jsonpath='{.spec.size}' 2>/dev/null)
        local volume_state=$(kubectl get volume "$volume" -n longhorn-system -o jsonpath='{.status.state}' 2>/dev/null)
        
        log "  Replica count: $replica_count"
        log "  Size: $volume_size"
        log "  State: $volume_state"
        add_to_report "- **Replica Count**: $replica_count"
        add_to_report "- **Size**: $volume_size"
        add_to_report "- **State**: $volume_state"
        
        # Check if volume has redundancy
        if [[ "$replica_count" -ge 2 ]]; then
            success "  Volume $volume has redundancy ($replica_count replicas)"
            add_to_report "- **Redundancy**: ✅ Yes ($replica_count replicas)"
            
            # Check replica distribution across nodes
            local replicas_json=$(kubectl get volume "$volume" -n longhorn-system -o jsonpath='{.status.replicas}' 2>/dev/null)
            if [[ -n "$replicas_json" ]]; then
                local replica_nodes=$(echo "$replicas_json" | jq -r 'keys[]' 2>/dev/null | sort | uniq)
                local node_count=$(echo "$replica_nodes" | wc -l)
                
                log "  Replica nodes: $replica_nodes"
                add_to_report "- **Replica Nodes**: $replica_nodes"
                
                if [[ $node_count -ge 2 ]]; then
                    success "  Volume $volume replicas are distributed across $node_count nodes"
                    add_to_report "- **Distribution**: ✅ Distributed across $node_count nodes"
                else
                    warn "  Volume $volume replicas are on same node"
                    add_to_report "- **Distribution**: ⚠️ Replicas on same node"
                fi
            else
                warn "  Could not get replica distribution for volume $volume"
                add_to_report "- **Distribution**: ⚠️ Could not determine"
            fi
        else
            warn "  Volume $volume has no redundancy ($replica_count replica)"
            add_to_report "- **Redundancy**: ⚠️ No ($replica_count replica)"
        fi
        
        add_to_report ""
    done < <(kubectl get volumes -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')
    
    return $issues
}

# Create and test volume redundancy
create_test_volume() {
    if [[ "$CREATE_TEST_VOLUME" != "true" ]]; then
        log "Skipping test volume creation (use --create-test-volume to enable)"
        return 0
    fi
    
    log "Creating test volume to validate redundancy..."
    add_to_report "### Test Volume Redundancy Validation"
    add_to_report ""
    
    local test_pvc="redundancy-test-pvc"
    local test_pod="redundancy-test-pod"
    
    # Clean up any existing test resources
    kubectl delete pod "$test_pod" --ignore-not-found=true >/dev/null 2>&1
    kubectl delete pvc "$test_pvc" --ignore-not-found=true >/dev/null 2>&1
    sleep 5
    
    # Create test PVC with 2 replicas
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc
  annotations:
    volume.beta.kubernetes.io/storage-class: longhorn
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: longhorn
EOF
    
    # Wait for PVC to be bound
    log "Waiting for test PVC to be bound..."
    if kubectl wait --for=condition=Bound pvc/"$test_pvc" --timeout=120s >/dev/null 2>&1; then
        success "Test PVC is bound"
        add_to_report "✅ Test PVC created and bound"
    else
        error "Test PVC failed to bind"
        add_to_report "❌ Test PVC failed to bind"
        return 1
    fi
    
    # Get the volume name
    local volume_name=$(kubectl get pvc "$test_pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
    if [[ -n "$volume_name" ]]; then
        log "Test volume name: $volume_name"
        add_to_report "**Test Volume**: $volume_name"
        
        # Wait for volume to be ready
        sleep 10
        
        # Check volume replica configuration
        local replica_count=$(kubectl get volume "$volume_name" -n longhorn-system -o jsonpath='{.spec.numberOfReplicas}' 2>/dev/null)
        log "Test volume replica count: $replica_count"
        add_to_report "**Replica Count**: $replica_count"
        
        if [[ "$replica_count" -ge 2 ]]; then
            success "Test volume has redundancy ($replica_count replicas)"
            add_to_report "✅ Test volume has redundancy"
            
            # Check replica distribution
            local replicas_json=$(kubectl get volume "$volume_name" -n longhorn-system -o jsonpath='{.status.replicas}' 2>/dev/null)
            if [[ -n "$replicas_json" ]]; then
                local replica_nodes=$(echo "$replicas_json" | jq -r 'keys[]' 2>/dev/null | sort | uniq)
                local node_count=$(echo "$replica_nodes" | wc -l)
                
                log "Test volume replica nodes: $replica_nodes"
                add_to_report "**Replica Nodes**: $replica_nodes"
                
                if [[ $node_count -ge 2 ]]; then
                    success "Test volume replicas are distributed across $node_count nodes"
                    add_to_report "✅ Replicas distributed across $node_count nodes"
                else
                    warn "Test volume replicas are on same node"
                    add_to_report "⚠️ Replicas on same node"
                fi
                
                # Test data persistence by creating a pod
                create_test_pod_with_volume "$test_pvc" "$test_pod"
            else
                warn "Could not get replica distribution for test volume"
                add_to_report "⚠️ Could not determine replica distribution"
            fi
        else
            warn "Test volume has no redundancy ($replica_count replica)"
            add_to_report "⚠️ Test volume has no redundancy"
        fi
    else
        error "Could not get test volume name"
        add_to_report "❌ Could not get test volume name"
        return 1
    fi
    
    # Clean up test resources
    log "Cleaning up test resources..."
    kubectl delete pod "$test_pod" --ignore-not-found=true >/dev/null 2>&1 &
    kubectl delete pvc "$test_pvc" --ignore-not-found=true >/dev/null 2>&1 &
    
    add_to_report ""
    return 0
}

# Create test pod with volume
create_test_pod_with_volume() {
    local pvc_name="$1"
    local pod_name="$2"
    
    log "Creating test pod to validate volume functionality..."
    
    # Create test pod
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
spec:
  containers:
  - name: test-container
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
    if kubectl wait --for=condition=Ready pod/"$pod_name" --timeout=60s >/dev/null 2>&1; then
        success "Test pod is ready"
        add_to_report "✅ Test pod created and ready"
        
        # Test writing data
        if kubectl exec "$pod_name" -- sh -c "echo 'redundancy test data' > /data/test.txt && cat /data/test.txt" >/dev/null 2>&1; then
            success "Data write/read test successful"
            add_to_report "✅ Data write/read test successful"
        else
            error "Data write/read test failed"
            add_to_report "❌ Data write/read test failed"
        fi
    else
        error "Test pod failed to become ready"
        add_to_report "❌ Test pod failed to become ready"
    fi
}

# Validate storage class configuration
validate_storage_class() {
    log "Validating storage class configuration for redundancy..."
    add_to_report "### Storage Class Configuration"
    add_to_report ""
    
    local issues=0
    
    # Check Longhorn storage class exists
    if kubectl get storageclass longhorn >/dev/null 2>&1; then
        success "Longhorn storage class exists"
        add_to_report "✅ Longhorn storage class exists"
        
        # Check replica count parameter
        local replica_count=$(kubectl get storageclass longhorn -o jsonpath='{.parameters.numberOfReplicas}' 2>/dev/null || echo "default")
        log "Storage class replica count: $replica_count"
        add_to_report "**Storage Class Replica Count**: $replica_count"
        
        if [[ "$replica_count" == "2" ]]; then
            success "Storage class configured for 2 replicas (optimal for 2-node setup)"
            add_to_report "✅ Configured for 2 replicas (optimal)"
        elif [[ "$replica_count" == "default" || "$replica_count" == "" ]]; then
            log "Storage class using default replica count (will use Longhorn setting)"
            add_to_report "ℹ️ Using Longhorn default replica count"
            
            # Check Longhorn default setting
            local default_replica_count=$(kubectl get setting default-replica-count -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "unknown")
            log "Longhorn default replica count: $default_replica_count"
            add_to_report "**Longhorn Default Replica Count**: $default_replica_count"
            
            if [[ "$default_replica_count" == "2" ]]; then
                success "Longhorn default replica count is 2 (good for redundancy)"
                add_to_report "✅ Longhorn default is 2 (good for redundancy)"
            elif [[ "$default_replica_count" == "1" ]]; then
                warn "Longhorn default replica count is 1 - consider increasing to 2"
                add_to_report "⚠️ Longhorn default is 1 - consider increasing to 2"
            else
                log "Longhorn default replica count: $default_replica_count"
                add_to_report "ℹ️ Longhorn default: $default_replica_count"
            fi
        else
            log "Storage class replica count: $replica_count"
            add_to_report "ℹ️ Storage class replica count: $replica_count"
        fi
        
        # Check if it's the default storage class
        local is_default=$(kubectl get storageclass longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
        if [[ "$is_default" == "true" ]]; then
            success "Longhorn is the default storage class"
            add_to_report "✅ Longhorn is the default storage class"
        else
            log "Longhorn is not the default storage class"
            add_to_report "ℹ️ Longhorn is not the default storage class"
        fi
    else
        error "Longhorn storage class not found"
        add_to_report "❌ Longhorn storage class not found"
        issues=$((issues + 1))
    fi
    
    add_to_report ""
    return $issues
}

# Generate summary report
generate_summary() {
    log "Generating storage redundancy validation summary..."
    add_to_report "## Validation Summary"
    add_to_report ""
    
    log "======================================================"
    log "Storage Redundancy Validation Summary"
    log "======================================================"
    
    # Overall assessment
    local overall_status="UNKNOWN"
    local recommendations=()
    
    # Check if both nodes are ready
    local k3s1_ready=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    local k3s2_ready=$(kubectl get longhornnode k3s2 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [[ "$k3s1_ready" == "True" && "$k3s2_ready" == "True" ]]; then
        # Check default replica count
        local default_replica_count=$(kubectl get setting default-replica-count -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "1")
        
        if [[ "$default_replica_count" == "2" ]]; then
            overall_status="EXCELLENT"
            success "🎉 EXCELLENT: Storage redundancy is properly configured!"
            add_to_report "**Overall Status**: 🎉 EXCELLENT"
            log "✅ Both nodes are ready for storage"
            log "✅ Default replica count is set to 2"
            log "✅ New volumes will automatically have redundancy"
            recommendations+=("✅ Storage redundancy is fully configured")
            recommendations+=("📊 Monitor storage usage and performance")
        else
            overall_status="GOOD"
            success "✅ GOOD: Storage redundancy is available but not optimally configured"
            add_to_report "**Overall Status**: ✅ GOOD"
            log "✅ Both nodes are ready for storage"
            log "⚠️ Default replica count is $default_replica_count (consider setting to 2)"
            recommendations+=("🔧 Consider setting default replica count to 2 for automatic redundancy")
            recommendations+=("📊 Monitor existing volumes and increase replicas if needed")
        fi
    else
        overall_status="ATTENTION_NEEDED"
        warn "⚠️ ATTENTION NEEDED: Storage redundancy has issues"
        add_to_report "**Overall Status**: ⚠️ ATTENTION NEEDED"
        log "❌ Not all nodes are ready for storage"
        log "k3s1 ready: $k3s1_ready, k3s2 ready: $k3s2_ready"
        recommendations+=("🔧 Fix node readiness issues before relying on storage redundancy")
        recommendations+=("📋 Check Longhorn node configuration and disk setup")
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
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by storage-redundancy-validator.sh*"
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
    log "Storage Redundancy Validation Tool v1.0"
    log "========================================"
    
    # Check dependencies
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        error "jq not found - please install jq (brew install jq)"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    init_report
    
    # Run validation steps
    local total_issues=0
    
    validate_longhorn_nodes
    total_issues=$((total_issues + $?))
    
    validate_storage_class
    total_issues=$((total_issues + $?))
    
    validate_existing_volumes
    total_issues=$((total_issues + $?))
    
    create_test_volume
    total_issues=$((total_issues + $?))
    
    # Generate summary
    generate_summary
    exit_code=$?
    
    exit $exit_code
}

# Run main function
main "$@"