#!/bin/bash
# Cluster Readiness Validation Module
#
# This module validates that the k3s1 cluster is ready to accept
# the k3s2 node for onboarding.
#
# Requirements: 7.1 from k3s1-node-onboarding spec

# Validate k3s1 control plane health
validate_control_plane_health() {
    log "Validating k3s1 control plane health..."
    local issues=0
    
    # Check k3s1 node status
    local k3s1_status=$(kubectl get node k3s1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$k3s1_status" == "True" ]]; then
        success "k3s1 control plane node is Ready"
        add_to_report "✅ k3s1 node status: Ready"
    else
        error "k3s1 control plane node is not Ready (Status: $k3s1_status)"
        add_to_report "❌ k3s1 node status: $k3s1_status"
        issues=$((issues + 1))
    fi
    
    # Check control plane components (k3s has embedded components)
    local control_plane_pods=$(kubectl get pods -n kube-system -l tier=control-plane --no-headers 2>/dev/null | wc -l)
    local running_control_plane=$(kubectl get pods -n kube-system -l tier=control-plane --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $control_plane_pods -gt 0 && $running_control_plane -eq $control_plane_pods ]]; then
        success "All control plane components are running ($running_control_plane/$control_plane_pods)"
        add_to_report "✅ Control plane pods: $running_control_plane/$control_plane_pods running"
    elif [[ $control_plane_pods -eq 0 ]]; then
        success "k3s embedded control plane (no separate pods expected)"
        add_to_report "✅ Control plane: k3s embedded (no separate pods)"
    else
        error "Control plane components not all running ($running_control_plane/$control_plane_pods)"
        add_to_report "❌ Control plane pods: $running_control_plane/$control_plane_pods running"
        issues=$((issues + 1))
    fi
    
    # Check API server responsiveness
    if kubectl get --raw /healthz >/dev/null 2>&1; then
        success "Kubernetes API server is responsive"
        add_to_report "✅ API server health check: OK"
    else
        error "Kubernetes API server health check failed"
        add_to_report "❌ API server health check: FAILED"
        issues=$((issues + 1))
    fi
    
    # Check etcd health (if accessible)
    local etcd_pods=$(kubectl get pods -n kube-system -l component=etcd --no-headers 2>/dev/null | wc -l)
    if [[ $etcd_pods -gt 0 ]]; then
        local running_etcd=$(kubectl get pods -n kube-system -l component=etcd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [[ $running_etcd -eq $etcd_pods ]]; then
            success "etcd is healthy ($running_etcd/$etcd_pods pods running)"
            add_to_report "✅ etcd health: $running_etcd/$etcd_pods pods running"
        else
            error "etcd is not healthy ($running_etcd/$etcd_pods pods running)"
            add_to_report "❌ etcd health: $running_etcd/$etcd_pods pods running"
            issues=$((issues + 1))
        fi
    else
        log "etcd pods not found (may be external or embedded)"
        add_to_report "ℹ️ etcd: Not found as pods (may be embedded)"
    fi
    
    # Check cluster version compatibility
    local k8s_version=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "unknown")
    if [[ "$k8s_version" == "unknown" ]]; then
        k8s_version=$(kubectl version --short 2>/dev/null | grep "Server Version" | cut -d: -f2 | tr -d ' ' || echo "unknown")
    fi
    log "Kubernetes version: $k8s_version"
    add_to_report "**Kubernetes Version**: $k8s_version"
    
    return $issues
}

# Validate Flux GitOps system health
validate_flux_system_health() {
    log "Validating Flux GitOps system health..."
    local issues=0
    
    # Check Flux namespace
    if kubectl get namespace flux-system >/dev/null 2>&1; then
        success "Flux system namespace exists"
        add_to_report "✅ flux-system namespace: exists"
    else
        error "Flux system namespace not found"
        add_to_report "❌ flux-system namespace: not found"
        issues=$((issues + 1))
        return $issues
    fi
    
    # Check Flux controllers
    local flux_controllers=("source-controller" "kustomize-controller" "helm-controller" "notification-controller")
    local healthy_controllers=0
    
    for controller in "${flux_controllers[@]}"; do
        local pod_status=$(kubectl get pods -n flux-system -l app=$controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [[ "$pod_status" == "Running" ]]; then
            success "$controller is running"
            add_to_report "✅ $controller: Running"
            ((healthy_controllers++))
        else
            error "$controller is not running (Status: $pod_status)"
            add_to_report "❌ $controller: $pod_status"
            issues=$((issues + 1))
        fi
    done
    
    # Check Flux system overall health
    if flux check --pre >/dev/null 2>&1; then
        success "Flux pre-flight checks passed"
        add_to_report "✅ Flux pre-flight checks: PASSED"
    else
        error "Flux pre-flight checks failed"
        add_to_report "❌ Flux pre-flight checks: FAILED"
        issues=$((issues + 1))
    fi
    
    # Check Git repository connectivity
    local git_repos=$(kubectl get gitrepositories -n flux-system --no-headers 2>/dev/null | wc -l)
    if [[ $git_repos -gt 0 ]]; then
        local ready_repos=$(kubectl get gitrepositories -n flux-system -o jsonpath='{.items[?(@.status.conditions[0].status=="True")].metadata.name}' 2>/dev/null | wc -w)
        if [[ $ready_repos -eq $git_repos ]]; then
            success "All Git repositories are accessible ($ready_repos/$git_repos)"
            add_to_report "✅ Git repositories: $ready_repos/$git_repos accessible"
        else
            error "Some Git repositories are not accessible ($ready_repos/$git_repos)"
            add_to_report "❌ Git repositories: $ready_repos/$git_repos accessible"
            issues=$((issues + 1))
        fi
    else
        warn "No Git repositories found"
        add_to_report "⚠️ Git repositories: none found"
    fi
    
    # Check Kustomizations status
    local kustomizations=$(kubectl get kustomizations -n flux-system --no-headers 2>/dev/null | wc -l)
    if [[ $kustomizations -gt 0 ]]; then
        local ready_kustomizations=$(kubectl get kustomizations -n flux-system -o jsonpath='{.items[?(@.status.conditions[0].status=="True")].metadata.name}' 2>/dev/null | wc -w)
        if [[ $ready_kustomizations -eq $kustomizations ]]; then
            success "All Kustomizations are reconciled ($ready_kustomizations/$kustomizations)"
            add_to_report "✅ Kustomizations: $ready_kustomizations/$kustomizations reconciled"
        else
            warn "Some Kustomizations are not reconciled ($ready_kustomizations/$kustomizations)"
            add_to_report "⚠️ Kustomizations: $ready_kustomizations/$kustomizations reconciled"
            
            # List problematic kustomizations
            local failed_kustomizations=$(kubectl get kustomizations -n flux-system -o jsonpath='{.items[?(@.status.conditions[0].status=="False")].metadata.name}' 2>/dev/null)
            if [[ -n "$failed_kustomizations" ]]; then
                log "Failed Kustomizations: $failed_kustomizations"
                add_to_report "**Failed Kustomizations**: $failed_kustomizations"
            fi
        fi
    else
        warn "No Kustomizations found"
        add_to_report "⚠️ Kustomizations: none found"
    fi
    
    return $issues
}

# Validate core infrastructure health
validate_core_infrastructure_health() {
    log "Validating core infrastructure health..."
    local issues=0
    
    # Check CoreDNS
    local coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
    local running_coredns=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $coredns_pods -gt 0 && $running_coredns -eq $coredns_pods ]]; then
        success "CoreDNS is healthy ($running_coredns/$coredns_pods pods running)"
        add_to_report "✅ CoreDNS: $running_coredns/$coredns_pods pods running"
    else
        error "CoreDNS is not healthy ($running_coredns/$coredns_pods pods running)"
        add_to_report "❌ CoreDNS: $running_coredns/$coredns_pods pods running"
        issues=$((issues + 1))
    fi
    
    # Check CNI (Flannel)
    local flannel_pods=$(kubectl get pods -n kube-system -l app=flannel --no-headers 2>/dev/null | wc -l)
    local running_flannel=$(kubectl get pods -n kube-system -l app=flannel --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $flannel_pods -gt 0 && $running_flannel -eq $flannel_pods ]]; then
        success "Flannel CNI is healthy ($running_flannel/$flannel_pods pods running)"
        add_to_report "✅ Flannel CNI: $running_flannel/$flannel_pods pods running"
    else
        error "Flannel CNI is not healthy ($running_flannel/$flannel_pods pods running)"
        add_to_report "❌ Flannel CNI: $running_flannel/$flannel_pods pods running"
        issues=$((issues + 1))
    fi
    
    # Check kube-proxy
    local kube_proxy_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | wc -l)
    local running_kube_proxy=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $kube_proxy_pods -gt 0 && $running_kube_proxy -eq $kube_proxy_pods ]]; then
        success "kube-proxy is healthy ($running_kube_proxy/$kube_proxy_pods pods running)"
        add_to_report "✅ kube-proxy: $running_kube_proxy/$kube_proxy_pods pods running"
    else
        error "kube-proxy is not healthy ($running_kube_proxy/$kube_proxy_pods pods running)"
        add_to_report "❌ kube-proxy: $running_kube_proxy/$kube_proxy_pods pods running"
        issues=$((issues + 1))
    fi
    
    # Check system resource usage on k3s1
    local k3s1_cpu_usage=$(kubectl top node k3s1 --no-headers 2>/dev/null | awk '{print $3}' | sed 's/%//' || echo "unknown")
    local k3s1_memory_usage=$(kubectl top node k3s1 --no-headers 2>/dev/null | awk '{print $5}' | sed 's/%//' || echo "unknown")
    
    if [[ "$k3s1_cpu_usage" != "unknown" ]]; then
        log "k3s1 resource usage - CPU: ${k3s1_cpu_usage}%, Memory: ${k3s1_memory_usage}%"
        add_to_report "**k3s1 Resource Usage**: CPU: ${k3s1_cpu_usage}%, Memory: ${k3s1_memory_usage}%"
        
        # Warn if resource usage is high
        if [[ "$k3s1_cpu_usage" =~ ^[0-9]+$ ]] && [[ $k3s1_cpu_usage -gt 80 ]]; then
            warn "k3s1 CPU usage is high (${k3s1_cpu_usage}%)"
            add_to_report "⚠️ High CPU usage on k3s1: ${k3s1_cpu_usage}%"
        fi
        
        if [[ "$k3s1_memory_usage" =~ ^[0-9]+$ ]] && [[ $k3s1_memory_usage -gt 80 ]]; then
            warn "k3s1 memory usage is high (${k3s1_memory_usage}%)"
            add_to_report "⚠️ High memory usage on k3s1: ${k3s1_memory_usage}%"
        fi
    else
        log "Could not retrieve k3s1 resource usage (metrics-server may not be available)"
        add_to_report "ℹ️ k3s1 resource usage: metrics not available"
    fi
    
    return $issues
}

# Validate resource capacity for k3s2 addition
validate_resource_capacity() {
    log "Validating resource capacity for k3s2 addition..."
    local issues=0
    
    # Check cluster resource limits
    local total_pods=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
    local max_pods_per_node=110  # Default k3s limit
    
    log "Current cluster pods: $total_pods"
    add_to_report "**Current Cluster Pods**: $total_pods"
    
    if [[ $total_pods -lt $((max_pods_per_node / 2)) ]]; then
        success "Pod capacity is sufficient for expansion"
        add_to_report "✅ Pod capacity: sufficient for expansion"
    elif [[ $total_pods -lt $((max_pods_per_node * 3 / 4)) ]]; then
        warn "Pod capacity is moderate - monitor after k3s2 addition"
        add_to_report "⚠️ Pod capacity: moderate - monitor after expansion"
    else
        warn "Pod capacity is high - k3s2 addition will help distribute load"
        add_to_report "⚠️ Pod capacity: high - expansion recommended"
    fi
    
    # Check service account tokens and RBAC
    if kubectl auth can-i create nodes --as=system:node:k3s2 >/dev/null 2>&1; then
        success "RBAC is configured for node addition"
        add_to_report "✅ RBAC: configured for node addition"
    else
        log "RBAC check for node addition (this may be expected)"
        add_to_report "ℹ️ RBAC: node addition permissions (check may be expected to fail)"
    fi
    
    # Check for resource quotas that might affect k3s2
    local resource_quotas=$(kubectl get resourcequotas -A --no-headers 2>/dev/null | wc -l)
    if [[ $resource_quotas -gt 0 ]]; then
        log "Found $resource_quotas resource quota(s) - verify they allow k3s2 workloads"
        add_to_report "ℹ️ Resource quotas: $resource_quotas found - verify compatibility"
        kubectl get resourcequotas -A --no-headers | head -5
    else
        success "No resource quotas found - no restrictions on k3s2 workloads"
        add_to_report "✅ Resource quotas: none found"
    fi
    
    # Check for network policies that might affect k3s2
    local network_policies=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l)
    if [[ $network_policies -gt 0 ]]; then
        log "Found $network_policies network policy(ies) - verify they allow k3s2 traffic"
        add_to_report "ℹ️ Network policies: $network_policies found - verify compatibility"
    else
        success "No network policies found - no network restrictions"
        add_to_report "✅ Network policies: none found"
    fi
    
    # Check cluster certificates expiration
    local cert_expiry=$(kubectl get csr --no-headers 2>/dev/null | grep Pending | wc -l)
    if [[ $cert_expiry -eq 0 ]]; then
        success "No pending certificate signing requests"
        add_to_report "✅ Certificate signing: no pending requests"
    else
        warn "$cert_expiry pending certificate signing requests found"
        add_to_report "⚠️ Certificate signing: $cert_expiry pending requests"
    fi
    
    return $issues
}