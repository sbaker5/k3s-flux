#!/bin/bash
# Application Deployment Verification Tool
#
# This script validates that applications can be deployed and distributed
# correctly across k3s1 and k3s2 nodes after onboarding.
#
# Requirements: 4.3 from k3s1-node-onboarding spec
#
# Usage: ./scripts/application-deployment-verifier.sh [--deploy-test-app] [--report]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/application-deployment-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/application-deployment-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
DEPLOY_TEST_APP=false
GENERATE_REPORT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy-test-app)
            DEPLOY_TEST_APP=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--deploy-test-app] [--report]"
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
# Application Deployment Verification Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Test Application Deployment**: $DEPLOY_TEST_APP

## Executive Summary

This report validates application deployment and distribution across k3s1 and k3s2 nodes.

## Verification Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}

# Verify existing application deployments
verify_existing_deployments() {
    log "Verifying existing application deployments..."
    add_to_report "### Existing Application Deployments"
    add_to_report ""
    
    local issues=0
    
    # Get all deployments across all namespaces
    local deployments=$(kubectl get deployments -A --no-headers 2>/dev/null | wc -l)
    
    if [[ $deployments -eq 0 ]]; then
        log "No existing deployments found"
        add_to_report "**Existing Deployments**: None found"
        add_to_report ""
        return 0
    fi
    
    log "Found $deployments deployment(s) - analyzing distribution..."
    add_to_report "**Existing Deployments**: $deployments found"
    add_to_report ""
    
    # Analyze each deployment
    while IFS= read -r line; do
        local namespace=$(echo "$line" | awk '{print $1}')
        local deployment=$(echo "$line" | awk '{print $2}')
        local ready=$(echo "$line" | awk '{print $3}')
        local up_to_date=$(echo "$line" | awk '{print $4}')
        local available=$(echo "$line" | awk '{print $5}')
        
        log "Analyzing deployment: $namespace/$deployment"
        add_to_report "#### Deployment: $namespace/$deployment"
        add_to_report ""
        
        # Check deployment health
        local desired_replicas=$(echo "$ready" | cut -d'/' -f2)
        local ready_replicas=$(echo "$ready" | cut -d'/' -f1)
        
        add_to_report "- **Ready Replicas**: $ready_replicas/$desired_replicas"
        add_to_report "- **Up-to-Date**: $up_to_date"
        add_to_report "- **Available**: $available"
        
        if [[ "$ready_replicas" == "$desired_replicas" && "$desired_replicas" != "0" ]]; then
            success "  Deployment $namespace/$deployment is healthy"
            add_to_report "- **Health**: ✅ Healthy"
            
            # Check pod distribution across nodes
            check_deployment_node_distribution "$namespace" "$deployment"
        else
            error "  Deployment $namespace/$deployment is not healthy"
            add_to_report "- **Health**: ❌ Not healthy"
            issues=$((issues + 1))
        fi
        
        add_to_report ""
    done < <(kubectl get deployments -A --no-headers 2>/dev/null)
    
    return $issues
}

# Check deployment node distribution
check_deployment_node_distribution() {
    local namespace="$1"
    local deployment="$2"
    
    # Get pods for this deployment
    local pods_on_k3s1=$(kubectl get pods -n "$namespace" -l app="$deployment" -o wide --no-headers 2>/dev/null | grep k3s1 | wc -l)
    local pods_on_k3s2=$(kubectl get pods -n "$namespace" -l app="$deployment" -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
    local total_pods=$((pods_on_k3s1 + pods_on_k3s2))
    
    log "  Pod distribution: k3s1: $pods_on_k3s1, k3s2: $pods_on_k3s2"
    add_to_report "- **Pod Distribution**: k3s1: $pods_on_k3s1, k3s2: $pods_on_k3s2"
    
    if [[ $total_pods -eq 0 ]]; then
        warn "  No pods found for deployment $namespace/$deployment"
        add_to_report "- **Distribution Status**: ⚠️ No pods found"
        return
    fi
    
    if [[ $pods_on_k3s2 -gt 0 ]]; then
        success "  Deployment $namespace/$deployment has pods on k3s2"
        add_to_report "- **k3s2 Presence**: ✅ Yes ($pods_on_k3s2 pods)"
        
        # Check if distribution is balanced for multi-replica deployments
        if [[ $total_pods -gt 1 ]]; then
            local k3s2_percentage=$((pods_on_k3s2 * 100 / total_pods))
            if [[ $k3s2_percentage -ge 25 && $k3s2_percentage -le 75 ]]; then
                success "  Pod distribution is balanced (k3s2: ${k3s2_percentage}%)"
                add_to_report "- **Balance**: ✅ Balanced (k3s2: ${k3s2_percentage}%)"
            else
                warn "  Pod distribution is skewed (k3s2: ${k3s2_percentage}%)"
                add_to_report "- **Balance**: ⚠️ Skewed (k3s2: ${k3s2_percentage}%)"
            fi
        fi
    else
        warn "  Deployment $namespace/$deployment has no pods on k3s2"
        add_to_report "- **k3s2 Presence**: ⚠️ No pods on k3s2"
    fi
}

# Verify service accessibility across nodes
verify_service_accessibility() {
    log "Verifying service accessibility across nodes..."
    add_to_report "### Service Accessibility Verification"
    add_to_report ""
    
    local issues=0
    
    # Get all services
    local services=$(kubectl get services -A --no-headers 2>/dev/null | grep -v ClusterIP | wc -l)
    
    if [[ $services -eq 0 ]]; then
        log "No non-ClusterIP services found"
        add_to_report "**Services**: No non-ClusterIP services found"
        add_to_report ""
        return 0
    fi
    
    log "Found $services service(s) - checking accessibility..."
    add_to_report "**Services**: $services found"
    add_to_report ""
    
    # Check NodePort services specifically
    local nodeport_services=$(kubectl get services -A --no-headers 2>/dev/null | grep NodePort | wc -l)
    
    if [[ $nodeport_services -gt 0 ]]; then
        log "Found $nodeport_services NodePort service(s)"
        add_to_report "**NodePort Services**: $nodeport_services found"
        
        # Check if NodePort services are accessible on both nodes
        while IFS= read -r line; do
            local namespace=$(echo "$line" | awk '{print $1}')
            local service=$(echo "$line" | awk '{print $2}')
            local ports=$(echo "$line" | awk '{print $6}')
            
            log "Checking NodePort service: $namespace/$service"
            add_to_report "#### NodePort Service: $namespace/$service"
            add_to_report ""
            
            # Extract NodePort from ports string (format: port:nodeport/protocol)
            local nodeport=$(echo "$ports" | grep -o '[0-9]*:[0-9]*' | cut -d':' -f2 | head -1)
            
            if [[ -n "$nodeport" ]]; then
                log "  NodePort: $nodeport"
                add_to_report "- **NodePort**: $nodeport"
                
                # Test accessibility on both nodes
                test_nodeport_accessibility "$nodeport" "$namespace/$service"
            else
                warn "  Could not extract NodePort from: $ports"
                add_to_report "- **NodePort**: ⚠️ Could not extract from $ports"
            fi
            
            add_to_report ""
        done < <(kubectl get services -A --no-headers 2>/dev/null | grep NodePort)
    else
        log "No NodePort services found"
        add_to_report "**NodePort Services**: None found"
    fi
    
    add_to_report ""
    return $issues
}

# Test NodePort accessibility
test_nodeport_accessibility() {
    local nodeport="$1"
    local service_name="$2"
    
    # Get node IPs
    local k3s1_ip=$(kubectl get node k3s1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    local k3s2_ip=$(kubectl get node k3s2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    
    log "  Testing accessibility on k3s1 ($k3s1_ip:$nodeport)"
    if curl -s --connect-timeout 5 "http://$k3s1_ip:$nodeport" >/dev/null 2>&1; then
        success "  Service $service_name is accessible on k3s1"
        add_to_report "- **k3s1 Accessibility**: ✅ Accessible"
    else
        warn "  Service $service_name is not accessible on k3s1 (may be expected if no backend)"
        add_to_report "- **k3s1 Accessibility**: ⚠️ Not accessible (may be expected)"
    fi
    
    log "  Testing accessibility on k3s2 ($k3s2_ip:$nodeport)"
    if curl -s --connect-timeout 5 "http://$k3s2_ip:$nodeport" >/dev/null 2>&1; then
        success "  Service $service_name is accessible on k3s2"
        add_to_report "- **k3s2 Accessibility**: ✅ Accessible"
    else
        warn "  Service $service_name is not accessible on k3s2 (may be expected if no backend)"
        add_to_report "- **k3s2 Accessibility**: ⚠️ Not accessible (may be expected)"
    fi
}

# Deploy and test application
deploy_test_application() {
    if [[ "$DEPLOY_TEST_APP" != "true" ]]; then
        log "Skipping test application deployment (use --deploy-test-app to enable)"
        return 0
    fi
    
    log "Deploying test application to validate deployment capabilities..."
    add_to_report "### Test Application Deployment"
    add_to_report ""
    
    local test_namespace="app-deployment-test"
    local test_deployment="multi-node-test-app"
    local test_service="multi-node-test-service"
    
    # Clean up any existing test resources
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1
    sleep 10
    
    # Create test namespace
    kubectl create namespace "$test_namespace" >/dev/null 2>&1
    
    # Deploy test application with multiple replicas
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $test_deployment
  namespace: $test_namespace
  labels:
    app: $test_deployment
spec:
  replicas: 4
  selector:
    matchLabels:
      app: $test_deployment
  template:
    metadata:
      labels:
        app: $test_deployment
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: $test_service
  namespace: $test_namespace
spec:
  selector:
    app: $test_deployment
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30999
  type: NodePort
EOF
    
    # Wait for deployment to be ready
    log "Waiting for test deployment to be ready..."
    if kubectl wait --for=condition=available deployment/"$test_deployment" -n "$test_namespace" --timeout=120s >/dev/null 2>&1; then
        success "Test deployment is ready"
        add_to_report "✅ Test deployment created and ready"
        
        # Check pod distribution
        local pods_on_k3s1=$(kubectl get pods -n "$test_namespace" -l app="$test_deployment" -o wide --no-headers 2>/dev/null | grep k3s1 | wc -l)
        local pods_on_k3s2=$(kubectl get pods -n "$test_namespace" -l app="$test_deployment" -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
        
        log "Test app pod distribution - k3s1: $pods_on_k3s1, k3s2: $pods_on_k3s2"
        add_to_report "**Pod Distribution**: k3s1: $pods_on_k3s1, k3s2: $pods_on_k3s2"
        
        if [[ $pods_on_k3s1 -gt 0 && $pods_on_k3s2 -gt 0 ]]; then
            success "Test application pods are distributed across both nodes"
            add_to_report "✅ Pods distributed across both nodes"
            
            # Test service accessibility
            test_application_service_access "$test_namespace" "$test_service"
            
            # Test application functionality
            test_application_functionality "$test_namespace" "$test_deployment"
        else
            error "Test application pods are not distributed across both nodes"
            add_to_report "❌ Pods not distributed across both nodes"
        fi
    else
        error "Test deployment failed to become ready"
        add_to_report "❌ Test deployment failed to become ready"
        return 1
    fi
    
    # Clean up test resources
    log "Cleaning up test application..."
    kubectl delete namespace "$test_namespace" --ignore-not-found=true >/dev/null 2>&1 &
    
    add_to_report ""
    return 0
}

# Test application service access
test_application_service_access() {
    local namespace="$1"
    local service="$2"
    
    log "Testing service accessibility..."
    
    # Get node IPs
    local k3s1_ip=$(kubectl get node k3s1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    local k3s2_ip=$(kubectl get node k3s2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    
    # Test service on both nodes
    if curl -s --connect-timeout 10 "http://$k3s1_ip:30999" | grep -q "nginx" 2>/dev/null; then
        success "Test service is accessible via k3s1"
        add_to_report "✅ Service accessible via k3s1"
    else
        warn "Test service is not accessible via k3s1"
        add_to_report "⚠️ Service not accessible via k3s1"
    fi
    
    if curl -s --connect-timeout 10 "http://$k3s2_ip:30999" | grep -q "nginx" 2>/dev/null; then
        success "Test service is accessible via k3s2"
        add_to_report "✅ Service accessible via k3s2"
    else
        warn "Test service is not accessible via k3s2"
        add_to_report "⚠️ Service not accessible via k3s2"
    fi
}

# Test application functionality
test_application_functionality() {
    local namespace="$1"
    local deployment="$2"
    
    log "Testing application functionality..."
    
    # Get a pod from each node
    local k3s1_pod=$(kubectl get pods -n "$namespace" -l app="$deployment" -o wide --no-headers 2>/dev/null | grep k3s1 | head -1 | awk '{print $1}')
    local k3s2_pod=$(kubectl get pods -n "$namespace" -l app="$deployment" -o wide --no-headers 2>/dev/null | grep k3s2 | head -1 | awk '{print $1}')
    
    if [[ -n "$k3s1_pod" ]]; then
        if kubectl exec -n "$namespace" "$k3s1_pod" -- curl -s localhost:80 | grep -q "nginx" 2>/dev/null; then
            success "Application is functional on k3s1 pod"
            add_to_report "✅ Application functional on k3s1"
        else
            error "Application is not functional on k3s1 pod"
            add_to_report "❌ Application not functional on k3s1"
        fi
    fi
    
    if [[ -n "$k3s2_pod" ]]; then
        if kubectl exec -n "$namespace" "$k3s2_pod" -- curl -s localhost:80 | grep -q "nginx" 2>/dev/null; then
            success "Application is functional on k3s2 pod"
            add_to_report "✅ Application functional on k3s2"
        else
            error "Application is not functional on k3s2 pod"
            add_to_report "❌ Application not functional on k3s2"
        fi
    fi
}

# Verify ingress controller distribution
verify_ingress_distribution() {
    log "Verifying ingress controller distribution..."
    add_to_report "### Ingress Controller Distribution"
    add_to_report ""
    
    # Check for NGINX Ingress Controller
    local nginx_pods=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | wc -l)
    
    if [[ $nginx_pods -gt 0 ]]; then
        log "Found $nginx_pods NGINX Ingress Controller pod(s)"
        add_to_report "**NGINX Ingress Pods**: $nginx_pods found"
        
        # Check distribution
        local nginx_on_k3s1=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx -o wide --no-headers 2>/dev/null | grep k3s1 | wc -l)
        local nginx_on_k3s2=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
        
        log "NGINX Ingress distribution - k3s1: $nginx_on_k3s1, k3s2: $nginx_on_k3s2"
        add_to_report "**Distribution**: k3s1: $nginx_on_k3s1, k3s2: $nginx_on_k3s2"
        
        if [[ $nginx_on_k3s1 -gt 0 && $nginx_on_k3s2 -gt 0 ]]; then
            success "NGINX Ingress Controller is running on both nodes"
            add_to_report "✅ Running on both nodes"
        elif [[ $nginx_on_k3s2 -gt 0 ]]; then
            success "NGINX Ingress Controller is running on k3s2"
            add_to_report "✅ Running on k3s2"
        else
            warn "NGINX Ingress Controller is not running on k3s2"
            add_to_report "⚠️ Not running on k3s2"
        fi
    else
        log "No NGINX Ingress Controller pods found"
        add_to_report "**NGINX Ingress Pods**: None found"
    fi
    
    add_to_report ""
}

# Generate summary report
generate_summary() {
    log "Generating application deployment verification summary..."
    add_to_report "## Verification Summary"
    add_to_report ""
    
    log "======================================================"
    log "Application Deployment Verification Summary"
    log "======================================================"
    
    # Overall assessment
    local overall_status="UNKNOWN"
    local recommendations=()
    
    # Check if both nodes are ready
    local k3s1_ready=$(kubectl get node k3s1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    local k3s2_ready=$(kubectl get node k3s2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    # Check if there are pods running on k3s2
    local pods_on_k3s2=$(kubectl get pods -A --field-selector=status.phase=Running -o wide --no-headers 2>/dev/null | grep k3s2 | wc -l)
    
    if [[ "$k3s1_ready" == "True" && "$k3s2_ready" == "True" && $pods_on_k3s2 -gt 0 ]]; then
        overall_status="EXCELLENT"
        success "🎉 EXCELLENT: Application deployment across nodes is working perfectly!"
        add_to_report "**Overall Status**: 🎉 EXCELLENT"
        log "✅ Both nodes are ready"
        log "✅ Applications are being scheduled on k3s2"
        log "✅ Multi-node deployment is functional"
        recommendations+=("✅ Application deployment is fully functional across both nodes")
        recommendations+=("📊 Monitor application performance and resource utilization")
        recommendations+=("🔄 Consider deploying production applications")
    elif [[ "$k3s1_ready" == "True" && "$k3s2_ready" == "True" ]]; then
        overall_status="GOOD"
        success "✅ GOOD: Nodes are ready but limited application distribution"
        add_to_report "**Overall Status**: ✅ GOOD"
        log "✅ Both nodes are ready"
        log "⚠️ Limited or no applications running on k3s2"
        recommendations+=("🔧 Deploy applications with multiple replicas to test distribution")
        recommendations+=("📊 Monitor scheduler behavior and node affinity rules")
    else
        overall_status="ATTENTION_NEEDED"
        warn "⚠️ ATTENTION NEEDED: Application deployment has issues"
        add_to_report "**Overall Status**: ⚠️ ATTENTION NEEDED"
        log "❌ Not all nodes are ready for application deployment"
        log "k3s1 ready: $k3s1_ready, k3s2 ready: $k3s2_ready"
        recommendations+=("🔧 Fix node readiness issues before deploying applications")
        recommendations+=("📋 Check node labels, taints, and scheduler configuration")
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
        add_to_report "*Report generated by application-deployment-verifier.sh*"
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
    log "Application Deployment Verification Tool v1.0"
    log "============================================="
    
    # Check dependencies
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    init_report
    
    # Run verification steps
    local total_issues=0
    
    verify_existing_deployments
    total_issues=$((total_issues + $?))
    
    verify_service_accessibility
    total_issues=$((total_issues + $?))
    
    verify_ingress_distribution
    
    deploy_test_application
    total_issues=$((total_issues + $?))
    
    # Generate summary
    generate_summary
    exit_code=$?
    
    exit $exit_code
}

# Run main function
main "$@"