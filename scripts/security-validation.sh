#!/bin/bash
# Security Validation Script
# 
# This script performs comprehensive security validation of the k3s GitOps cluster
# including network security, container security, secret management, and RBAC.
#
# Usage: ./scripts/security-validation.sh [--fix] [--report]
#   --fix: Attempt to fix identified security issues
#   --report: Generate detailed security report

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="/tmp/security-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/security-report-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FIX_ISSUES=false
GENERATE_REPORT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_ISSUES=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--fix] [--report]"
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
# Security Validation Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Validation Script**: $0

## Executive Summary

This report contains the results of automated security validation for the k3s GitOps cluster.

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

# Security validation functions

validate_network_security() {
    log "Validating network security configuration..."
    local issues=0
    
    add_to_report "### Network Security Validation"
    add_to_report ""
    
    # Check Tailscale deployment
    if kubectl get deployment tailscale-subnet-router -n tailscale >/dev/null 2>&1; then
        success "Tailscale subnet router deployment found"
        add_to_report "✅ Tailscale subnet router deployed"
        
        # Check if Tailscale pod is running
        if kubectl get pods -n tailscale -l app=tailscale-subnet-router | grep -q Running; then
            success "Tailscale subnet router is running"
            add_to_report "✅ Tailscale subnet router is running"
        else
            error "Tailscale subnet router is not running"
            add_to_report "❌ Tailscale subnet router is not running"
            issues=$((issues + 1))
        fi
        
        # Check for privileged containers
        if kubectl get deployment tailscale-subnet-router -n tailscale -o yaml | grep -q "privileged: true"; then
            warn "Privileged containers detected in Tailscale deployment"
            add_to_report "⚠️ Privileged containers detected (init container may be acceptable)"
            
            if [[ "$FIX_ISSUES" == "true" ]]; then
                log "Privileged containers are acceptable for Tailscale init container (sysctl requirements)"
            fi
        else
            success "No unexpected privileged containers in main Tailscale container"
            add_to_report "✅ Main Tailscale container not privileged"
        fi
        
        # Check image versions
        if kubectl get deployment tailscale-subnet-router -n tailscale -o yaml | grep -q "image:.*:latest"; then
            error "Using :latest image tags in Tailscale deployment"
            add_to_report "❌ Using :latest image tags (security risk)"
            issues=$((issues + 1))
            
            if [[ "$FIX_ISSUES" == "true" ]]; then
                warn "To fix: Update Tailscale deployment to use pinned image versions"
                add_to_report "**Fix**: Pin image versions in deployment"
            fi
        else
            success "Tailscale using pinned image versions"
            add_to_report "✅ Tailscale using pinned image versions"
        fi
        
    else
        error "Tailscale subnet router deployment not found"
        add_to_report "❌ Tailscale subnet router not deployed"
        issues=$((issues + 1))
    fi
    
    # Check for exposed services
    local exposed_services=$(kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.spec.type == "LoadBalancer" or .spec.type == "NodePort") | "\(.metadata.namespace)/\(.metadata.name)"')
    
    if [[ -n "$exposed_services" ]]; then
        warn "Found exposed services (LoadBalancer/NodePort):"
        echo "$exposed_services" | while read -r service; do
            warn "  - $service"
            add_to_report "⚠️ Exposed service: $service"
        done
    else
        success "No unexpected exposed services found"
        add_to_report "✅ No unexpected exposed services"
    fi
    
    add_to_report ""
    return $issues
}

validate_container_security() {
    log "Validating container security configuration..."
    local issues=0
    
    add_to_report "### Container Security Validation"
    add_to_report ""
    
    # Check for privileged containers across all namespaces
    local privileged_pods=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[]?.securityContext?.privileged == true or .spec.initContainers[]?.securityContext?.privileged == true) | "\(.metadata.namespace)/\(.metadata.name)"')
    
    if [[ -n "$privileged_pods" ]]; then
        warn "Found privileged containers:"
        echo "$privileged_pods" | while read -r pod; do
            warn "  - $pod"
            add_to_report "⚠️ Privileged container: $pod"
        done
        
        # Check if these are acceptable (like Tailscale init container)
        local acceptable_privileged=$(echo "$privileged_pods" | grep -c "tailscale" || true)
        if [[ $acceptable_privileged -gt 0 ]]; then
            log "Note: Tailscale init containers require privileged access for sysctl operations"
            add_to_report "**Note**: Tailscale init containers require privileged access for network configuration"
        fi
    else
        success "No privileged containers found"
        add_to_report "✅ No privileged containers found"
    fi
    
    # Check for containers without resource limits
    local unlimited_containers=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[] | .resources.limits == null) | "\(.metadata.namespace)/\(.metadata.name)"')
    
    if [[ -n "$unlimited_containers" ]]; then
        warn "Found containers without resource limits:"
        echo "$unlimited_containers" | while read -r pod; do
            warn "  - $pod"
            add_to_report "⚠️ Container without resource limits: $pod"
        done
        issues=$((issues + 1))
    else
        success "All containers have resource limits"
        add_to_report "✅ All containers have resource limits"
    fi
    
    # Check for containers running as root
    local root_containers=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[]?.securityContext?.runAsUser == 0 or (.spec.containers[]?.securityContext?.runAsUser == null and .spec.securityContext?.runAsUser == null)) | "\(.metadata.namespace)/\(.metadata.name)"')
    
    if [[ -n "$root_containers" ]]; then
        warn "Found containers potentially running as root:"
        echo "$root_containers" | while read -r pod; do
            warn "  - $pod"
            add_to_report "⚠️ Container potentially running as root: $pod"
        done
    else
        success "No containers explicitly running as root"
        add_to_report "✅ No containers explicitly running as root"
    fi
    
    add_to_report ""
    return $issues
}

validate_secret_management() {
    log "Validating secret management configuration..."
    local issues=0
    
    add_to_report "### Secret Management Validation"
    add_to_report ""
    
    # Check for SOPS configuration
    if kubectl get secret sops-age -n flux-system >/dev/null 2>&1; then
        success "SOPS age key secret found in flux-system"
        add_to_report "✅ SOPS age key configured"
    else
        error "SOPS age key secret not found - SOPS encryption not configured"
        add_to_report "❌ SOPS encryption not configured"
        issues=$((issues + 1))
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            warn "To fix: Run SOPS setup script to configure encryption"
            add_to_report "**Fix**: Configure SOPS encryption following docs/security/sops-setup.md"
        fi
    fi
    
    # Check for plaintext secrets in Git
    if find . -name "*.yaml" -o -name "*.yml" | xargs grep -l "kind: Secret" | grep -v ".sops." | head -5; then
        error "Found potential plaintext secrets in Git repository"
        add_to_report "❌ Potential plaintext secrets found in repository"
        issues=$((issues + 1))
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            warn "To fix: Encrypt secrets with SOPS before committing"
            add_to_report "**Fix**: Encrypt all secrets with SOPS"
        fi
    else
        success "No plaintext secrets found in Git repository"
        add_to_report "✅ No plaintext secrets in repository"
    fi
    
    # Check secret ages
    local old_secrets=$(kubectl get secrets --all-namespaces -o json | jq -r '.items[] | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > (90 * 24 * 3600)) | "\(.metadata.namespace)/\(.metadata.name)"')
    
    if [[ -n "$old_secrets" ]]; then
        warn "Found secrets older than 90 days (consider rotation):"
        echo "$old_secrets" | while read -r secret; do
            warn "  - $secret"
            add_to_report "⚠️ Old secret (>90 days): $secret"
        done
    else
        success "All secrets are within rotation policy (≤90 days)"
        add_to_report "✅ All secrets within rotation policy"
    fi
    
    add_to_report ""
    return $issues
}

validate_rbac_configuration() {
    log "Validating RBAC configuration..."
    local issues=0
    
    add_to_report "### RBAC Configuration Validation"
    add_to_report ""
    
    # Check for overly permissive cluster roles
    local permissive_roles=$(kubectl get clusterroles -o json | jq -r '.items[] | select(.rules[]?.verbs[]? == "*" and .rules[]?.resources[]? == "*") | .metadata.name')
    
    if [[ -n "$permissive_roles" ]]; then
        warn "Found overly permissive cluster roles:"
        echo "$permissive_roles" | while read -r role; do
            # Skip system roles that are expected to be permissive
            if [[ "$role" =~ ^(cluster-admin|system:|admin).*$ ]]; then
                log "  - $role (system role - acceptable)"
                add_to_report "ℹ️ System cluster role: $role (acceptable)"
            else
                warn "  - $role (review permissions)"
                add_to_report "⚠️ Permissive cluster role: $role"
            fi
        done
    else
        success "No unexpected permissive cluster roles found"
        add_to_report "✅ No unexpected permissive cluster roles"
    fi
    
    # Check service account permissions
    local service_accounts=$(kubectl get serviceaccounts --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"')
    
    log "Checking service account permissions..."
    add_to_report "**Service Account Analysis**:"
    
    # Focus on non-system service accounts
    echo "$service_accounts" | grep -v "system:" | grep -v "default" | while read -r sa; do
        local namespace=$(echo "$sa" | cut -d'/' -f1)
        local name=$(echo "$sa" | cut -d'/' -f2)
        
        # Check if service account has any role bindings
        local bindings=$(kubectl get rolebindings,clusterrolebindings --all-namespaces -o json | jq -r --arg ns "$namespace" --arg name "$name" '.items[] | select(.subjects[]?.name == $name and .subjects[]?.namespace == $ns) | "\(.metadata.namespace // "cluster")/\(.metadata.name)"')
        
        if [[ -n "$bindings" ]]; then
            add_to_report "- $sa: $(echo "$bindings" | wc -l) binding(s)"
        fi
    done
    
    add_to_report ""
    return $issues
}

validate_monitoring_security() {
    log "Validating security monitoring configuration..."
    local issues=0
    
    add_to_report "### Security Monitoring Validation"
    add_to_report ""
    
    # Check if Prometheus is collecting security metrics
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus >/dev/null 2>&1; then
        success "Prometheus monitoring is deployed"
        add_to_report "✅ Prometheus monitoring deployed"
        
        # Check for security-related PrometheusRules
        local security_rules=$(kubectl get prometheusrules --all-namespaces -o json | jq -r '.items[] | select(.spec.groups[]?.name == "security" or .spec.groups[]?.rules[]?.alert | test("Security|Privileged|Unauthorized")) | "\(.metadata.namespace)/\(.metadata.name)"')
        
        if [[ -n "$security_rules" ]]; then
            success "Security monitoring rules found:"
            echo "$security_rules" | while read -r rule; do
                success "  - $rule"
                add_to_report "✅ Security rule: $rule"
            done
        else
            warn "No security-specific monitoring rules found"
            add_to_report "⚠️ No security monitoring rules configured"
            
            if [[ "$FIX_ISSUES" == "true" ]]; then
                warn "To fix: Add security monitoring rules to Prometheus"
                add_to_report "**Fix**: Add security PrometheusRules for monitoring"
            fi
        fi
    else
        warn "Prometheus monitoring not found"
        add_to_report "⚠️ Prometheus monitoring not deployed"
    fi
    
    # Check audit logging configuration
    if kubectl get pods -n kube-system -l component=kube-apiserver -o yaml | grep -q "audit-log"; then
        success "Kubernetes audit logging appears to be configured"
        add_to_report "✅ Kubernetes audit logging configured"
    else
        warn "Kubernetes audit logging not detected"
        add_to_report "⚠️ Kubernetes audit logging not detected"
    fi
    
    add_to_report ""
    return $issues
}

# Main validation function
run_security_validation() {
    log "Starting comprehensive security validation..."
    
    init_report
    add_to_report "## Validation Started"
    add_to_report "**Timestamp**: $(date)"
    add_to_report ""
    
    local total_issues=0
    
    # Run all validation checks
    validate_network_security
    total_issues=$((total_issues + $?))
    
    validate_container_security
    total_issues=$((total_issues + $?))
    
    validate_secret_management
    total_issues=$((total_issues + $?))
    
    validate_rbac_configuration
    total_issues=$((total_issues + $?))
    
    validate_monitoring_security
    total_issues=$((total_issues + $?))
    
    # Summary
    add_to_report "## Validation Summary"
    add_to_report ""
    add_to_report "**Total Issues Found**: $total_issues"
    add_to_report "**Validation Completed**: $(date)"
    
    if [[ $total_issues -eq 0 ]]; then
        success "Security validation completed successfully - no critical issues found"
        add_to_report "**Overall Status**: ✅ PASS"
    elif [[ $total_issues -le 5 ]]; then
        warn "Security validation completed with $total_issues minor issues"
        add_to_report "**Overall Status**: ⚠️ PASS WITH WARNINGS"
    else
        error "Security validation found $total_issues issues requiring attention"
        add_to_report "**Overall Status**: ❌ ATTENTION REQUIRED"
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        log "Security report generated: $REPORT_FILE"
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by security-validation.sh*"
    fi
    
    return $total_issues
}

# Run the validation
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl not found - please install kubectl"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    error "jq not found - please install jq"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info >/dev/null 2>&1; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Run the validation
run_security_validation
exit_code=$?

if [[ "$GENERATE_REPORT" == "true" ]]; then
    echo
    log "Security validation report available at: $REPORT_FILE"
    
    # If running in CI/CD, also output to stdout
    if [[ -n "${CI:-}" ]]; then
        echo "## Security Validation Report"
        cat "$REPORT_FILE"
    fi
fi

exit $exit_code