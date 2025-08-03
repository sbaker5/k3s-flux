#!/bin/bash
# Network Connectivity Verification Module
#
# This module verifies network connectivity and configuration
# to ensure k3s2 can properly integrate with the cluster networking.
#
# Requirements: 7.1 from k3s1-node-onboarding spec

# Verify cluster network configuration
verify_cluster_network_config() {
    log "Verifying cluster network configuration..."
    local issues=0
    
    # Check cluster CIDR configuration
    local cluster_cidr=$(kubectl cluster-info dump 2>/dev/null | grep -o 'cluster-cidr=[^"]*' | cut -d= -f2 | head -1 || echo "unknown")
    local service_cidr=$(kubectl cluster-info dump 2>/dev/null | grep -o 'service-cluster-ip-range=[^"]*' | cut -d= -f2 | head -1 || echo "unknown")
    
    log "Cluster CIDR: $cluster_cidr"
    log "Service CIDR: $service_cidr"
    add_to_report "**Cluster CIDR**: $cluster_cidr"
    add_to_report "**Service CIDR**: $service_cidr"
    
    # Verify expected CIDR ranges for k3s
    if [[ "$cluster_cidr" == "10.42.0.0/16" ]]; then
        success "Cluster CIDR matches expected k3s default"
        add_to_report "✅ Cluster CIDR: matches k3s default (10.42.0.0/16)"
    elif [[ "$cluster_cidr" != "unknown" ]]; then
        log "Cluster CIDR is custom: $cluster_cidr"
        add_to_report "ℹ️ Cluster CIDR: custom configuration ($cluster_cidr)"
    else
        warn "Could not determine cluster CIDR"
        add_to_report "⚠️ Cluster CIDR: could not determine"
    fi
    
    if [[ "$service_cidr" == "10.43.0.0/16" ]]; then
        success "Service CIDR matches expected k3s default"
        add_to_report "✅ Service CIDR: matches k3s default (10.43.0.0/16)"
    elif [[ "$service_cidr" != "unknown" ]]; then
        log "Service CIDR is custom: $service_cidr"
        add_to_report "ℹ️ Service CIDR: custom configuration ($service_cidr)"
    else
        warn "Could not determine service CIDR"
        add_to_report "⚠️ Service CIDR: could not determine"
    fi
    
    # Check Flannel configuration
    local flannel_config=$(kubectl get configmap kube-flannel-cfg -n kube-system -o jsonpath='{.data.cni-conf\.json}' 2>/dev/null || echo "")
    if [[ -n "$flannel_config" ]]; then
        success "Flannel CNI configuration found"
        add_to_report "✅ Flannel CNI: configuration found"
        
        # Check if VXLAN backend is configured
        if echo "$flannel_config" | grep -q '"Type": "vxlan"'; then
            success "Flannel VXLAN backend configured"
            add_to_report "✅ Flannel backend: VXLAN configured"
        else
            log "Flannel backend configuration:"
            echo "$flannel_config" | jq -r '.plugins[0].delegate.backend // "unknown"' 2>/dev/null || echo "Could not parse"
            add_to_report "ℹ️ Flannel backend: check configuration"
        fi
    else
        warn "Flannel configuration not found"
        add_to_report "⚠️ Flannel CNI: configuration not found"
    fi
    
    # Check network interface on k3s1
    local k3s1_ip=$(kubectl get node k3s1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    if [[ -n "$k3s1_ip" ]]; then
        success "k3s1 internal IP: $k3s1_ip"
        add_to_report "✅ k3s1 internal IP: $k3s1_ip"
        
        # Test connectivity to k3s1 API server
        if curl -k --connect-timeout 5 "https://$k3s1_ip:6443/version" >/dev/null 2>&1; then
            success "k3s1 API server accessible on $k3s1_ip:6443"
            add_to_report "✅ k3s1 API server: accessible on $k3s1_ip:6443"
        else
            error "k3s1 API server not accessible on $k3s1_ip:6443"
            add_to_report "❌ k3s1 API server: not accessible on $k3s1_ip:6443"
            issues=$((issues + 1))
        fi
    else
        error "Could not determine k3s1 internal IP"
        add_to_report "❌ k3s1 internal IP: could not determine"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Verify NodePort service accessibility
verify_nodeport_accessibility() {
    log "Verifying NodePort service accessibility..."
    local issues=0
    
    # Check for NodePort services
    local nodeport_services=$(kubectl get services -A --field-selector spec.type=NodePort --no-headers 2>/dev/null | wc -l)
    
    if [[ $nodeport_services -gt 0 ]]; then
        success "Found $nodeport_services NodePort service(s)"
        add_to_report "✅ NodePort services: $nodeport_services found"
        
        # Test specific NodePort services
        log "NodePort services:"
        kubectl get services -A --field-selector spec.type=NodePort --no-headers | while read -r namespace name type cluster_ip external_ip ports age; do
            log "  - $namespace/$name: $ports"
            add_to_report "  - **$namespace/$name**: $ports"
        done
        
        # Test NGINX Ingress NodePorts (30080, 30443)
        local k3s1_ip=$(kubectl get node k3s1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        if [[ -n "$k3s1_ip" ]]; then
            # Test HTTP NodePort (30080)
            if curl --connect-timeout 5 "http://$k3s1_ip:30080" >/dev/null 2>&1; then
                success "HTTP NodePort (30080) accessible on k3s1"
                add_to_report "✅ HTTP NodePort (30080): accessible on k3s1"
            else
                # This might be expected if no default backend is configured
                log "HTTP NodePort (30080) test - may be expected if no default backend"
                add_to_report "ℹ️ HTTP NodePort (30080): test response (may be expected)"
            fi
            
            # Test HTTPS NodePort (30443)
            if curl -k --connect-timeout 5 "https://$k3s1_ip:30443" >/dev/null 2>&1; then
                success "HTTPS NodePort (30443) accessible on k3s1"
                add_to_report "✅ HTTPS NodePort (30443): accessible on k3s1"
            else
                log "HTTPS NodePort (30443) test - may be expected if no default backend"
                add_to_report "ℹ️ HTTPS NodePort (30443): test response (may be expected)"
            fi
        else
            warn "Cannot test NodePort accessibility - k3s1 IP not found"
            add_to_report "⚠️ NodePort testing: k3s1 IP not available"
        fi
    else
        warn "No NodePort services found"
        add_to_report "⚠️ NodePort services: none found"
    fi
    
    return $issues
}

# Verify ingress controller health
verify_ingress_controller_health() {
    log "Verifying ingress controller health..."
    local issues=0
    
    # Check for NGINX Ingress Controller
    local nginx_pods=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | wc -l)
    local running_nginx=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $nginx_pods -gt 0 ]]; then
        if [[ $running_nginx -eq $nginx_pods ]]; then
            success "NGINX Ingress Controller is healthy ($running_nginx/$nginx_pods pods running)"
            add_to_report "✅ NGINX Ingress Controller: $running_nginx/$nginx_pods pods running"
        else
            error "NGINX Ingress Controller is not healthy ($running_nginx/$nginx_pods pods running)"
            add_to_report "❌ NGINX Ingress Controller: $running_nginx/$nginx_pods pods running"
            issues=$((issues + 1))
        fi
        
        # Check ingress controller configuration
        local ingress_namespace=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | head -1 | awk '{print $1}')
        if [[ -n "$ingress_namespace" ]]; then
            log "NGINX Ingress Controller namespace: $ingress_namespace"
            add_to_report "**NGINX Namespace**: $ingress_namespace"
            
            # Check for ingress controller service
            local ingress_service=$(kubectl get services -n "$ingress_namespace" -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | wc -l)
            if [[ $ingress_service -gt 0 ]]; then
                success "NGINX Ingress Controller service exists"
                add_to_report "✅ NGINX Ingress service: exists"
            else
                warn "NGINX Ingress Controller service not found"
                add_to_report "⚠️ NGINX Ingress service: not found"
            fi
        fi
    else
        warn "NGINX Ingress Controller not found"
        add_to_report "⚠️ NGINX Ingress Controller: not found"
        
        # Check for other ingress controllers
        local other_ingress=$(kubectl get pods -A -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep -i ingress | wc -l)
        if [[ $other_ingress -gt 0 ]]; then
            log "Found $other_ingress other ingress controller pod(s)"
            add_to_report "ℹ️ Other ingress controllers: $other_ingress found"
        fi
    fi
    
    # Check existing ingress resources
    local ingress_resources=$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l)
    if [[ $ingress_resources -gt 0 ]]; then
        success "Found $ingress_resources ingress resource(s)"
        add_to_report "✅ Ingress resources: $ingress_resources found"
        
        # List ingress resources
        log "Ingress resources:"
        kubectl get ingress -A --no-headers | head -5 | while read -r namespace name class hosts address ports age; do
            log "  - $namespace/$name: $hosts"
            add_to_report "  - **$namespace/$name**: $hosts"
        done
    else
        log "No ingress resources found"
        add_to_report "ℹ️ Ingress resources: none found"
    fi
    
    return $issues
}

# Verify DNS resolution
verify_dns_resolution() {
    log "Verifying DNS resolution..."
    local issues=0
    
    # Test DNS resolution with a temporary pod
    log "Creating temporary pod for DNS testing..."
    
    # Create test pod
    kubectl apply -f - <<EOF >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: dns-test-pod
  namespace: default
  labels:
    test: k3s2-pre-onboarding
spec:
  containers:
  - name: dns-test
    image: busybox:1.35
    command: ['sleep', '300']
  restartPolicy: Never
EOF
    
    # Wait for pod to be ready
    local wait_count=0
    while [[ $wait_count -lt 30 ]]; do
        if kubectl get pod dns-test-pod --no-headers 2>/dev/null | grep -q Running; then
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if kubectl get pod dns-test-pod --no-headers 2>/dev/null | grep -q Running; then
        success "DNS test pod is running"
        add_to_report "✅ DNS test pod: running"
        
        # Test internal DNS resolution
        if kubectl exec dns-test-pod -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
            success "Internal DNS resolution works (kubernetes.default.svc.cluster.local)"
            add_to_report "✅ Internal DNS: kubernetes.default.svc.cluster.local resolves"
        else
            error "Internal DNS resolution failed"
            add_to_report "❌ Internal DNS: kubernetes.default.svc.cluster.local failed"
            issues=$((issues + 1))
        fi
        
        # Test external DNS resolution
        if kubectl exec dns-test-pod -- nslookup google.com >/dev/null 2>&1; then
            success "External DNS resolution works (google.com)"
            add_to_report "✅ External DNS: google.com resolves"
        else
            warn "External DNS resolution failed (may be expected in restricted environments)"
            add_to_report "⚠️ External DNS: google.com failed (may be expected)"
        fi
        
        # Test CoreDNS service resolution
        if kubectl exec dns-test-pod -- nslookup kube-dns.kube-system.svc.cluster.local >/dev/null 2>&1; then
            success "CoreDNS service resolution works"
            add_to_report "✅ CoreDNS service: kube-dns.kube-system.svc.cluster.local resolves"
        else
            error "CoreDNS service resolution failed"
            add_to_report "❌ CoreDNS service: resolution failed"
            issues=$((issues + 1))
        fi
    else
        error "DNS test pod failed to start"
        add_to_report "❌ DNS test pod: failed to start"
        issues=$((issues + 1))
    fi
    
    # Cleanup test pod
    kubectl delete pod dns-test-pod --ignore-not-found >/dev/null 2>&1
    
    # Check CoreDNS configuration
    local coredns_config=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null)
    if [[ -n "$coredns_config" ]]; then
        success "CoreDNS configuration found"
        add_to_report "✅ CoreDNS configuration: found"
        
        # Check for cluster.local domain
        if echo "$coredns_config" | grep -q "cluster.local"; then
            success "CoreDNS configured for cluster.local domain"
            add_to_report "✅ CoreDNS domain: cluster.local configured"
        else
            warn "CoreDNS cluster.local domain configuration not found"
            add_to_report "⚠️ CoreDNS domain: cluster.local not found in config"
        fi
    else
        error "CoreDNS configuration not found"
        add_to_report "❌ CoreDNS configuration: not found"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Verify external connectivity
verify_external_connectivity() {
    log "Verifying external connectivity..."
    local issues=0
    
    # Create test pod for external connectivity
    log "Creating temporary pod for external connectivity testing..."
    
    kubectl apply -f - <<EOF >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: connectivity-test-pod
  namespace: default
  labels:
    test: k3s2-pre-onboarding
spec:
  containers:
  - name: connectivity-test
    image: busybox:1.35
    command: ['sleep', '300']
  restartPolicy: Never
EOF
    
    # Wait for pod to be ready
    local wait_count=0
    while [[ $wait_count -lt 30 ]]; do
        if kubectl get pod connectivity-test-pod --no-headers 2>/dev/null | grep -q Running; then
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if kubectl get pod connectivity-test-pod --no-headers 2>/dev/null | grep -q Running; then
        success "Connectivity test pod is running"
        add_to_report "✅ Connectivity test pod: running"
        
        # Test external HTTP connectivity
        if kubectl exec connectivity-test-pod -- wget -q --timeout=10 --tries=1 -O /dev/null http://google.com >/dev/null 2>&1; then
            success "External HTTP connectivity works"
            add_to_report "✅ External HTTP: google.com accessible"
        else
            warn "External HTTP connectivity failed (may be expected in restricted environments)"
            add_to_report "⚠️ External HTTP: google.com failed (may be expected)"
        fi
        
        # Test external HTTPS connectivity
        if kubectl exec connectivity-test-pod -- wget -q --timeout=10 --tries=1 -O /dev/null https://google.com >/dev/null 2>&1; then
            success "External HTTPS connectivity works"
            add_to_report "✅ External HTTPS: google.com accessible"
        else
            warn "External HTTPS connectivity failed (may be expected in restricted environments)"
            add_to_report "⚠️ External HTTPS: google.com failed (may be expected)"
        fi
        
        # Test connectivity to container registries
        if kubectl exec connectivity-test-pod -- wget -q --timeout=10 --tries=1 -O /dev/null https://registry-1.docker.io >/dev/null 2>&1; then
            success "Docker Hub registry connectivity works"
            add_to_report "✅ Docker Hub: registry-1.docker.io accessible"
        else
            warn "Docker Hub registry connectivity failed"
            add_to_report "⚠️ Docker Hub: registry-1.docker.io failed"
        fi
        
        # Test internal cluster connectivity
        local k3s1_ip=$(kubectl get node k3s1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        if [[ -n "$k3s1_ip" ]]; then
            if kubectl exec connectivity-test-pod -- ping -c 3 "$k3s1_ip" >/dev/null 2>&1; then
                success "Internal cluster connectivity to k3s1 works"
                add_to_report "✅ Internal connectivity: k3s1 ($k3s1_ip) reachable"
            else
                error "Internal cluster connectivity to k3s1 failed"
                add_to_report "❌ Internal connectivity: k3s1 ($k3s1_ip) unreachable"
                issues=$((issues + 1))
            fi
        fi
    else
        error "Connectivity test pod failed to start"
        add_to_report "❌ Connectivity test pod: failed to start"
        issues=$((issues + 1))
    fi
    
    # Cleanup test pod
    kubectl delete pod connectivity-test-pod --ignore-not-found >/dev/null 2>&1
    
    # Check for network policies that might affect k3s2
    local network_policies=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l)
    if [[ $network_policies -gt 0 ]]; then
        log "Found $network_policies network policy(ies) - ensure they allow k3s2 traffic"
        add_to_report "ℹ️ Network policies: $network_policies found - verify k3s2 compatibility"
        
        # List network policies
        kubectl get networkpolicies -A --no-headers | head -3 | while read -r namespace name pod_selector age; do
            log "  - $namespace/$name"
            add_to_report "  - **$namespace/$name**"
        done
    else
        success "No network policies found - no network restrictions"
        add_to_report "✅ Network policies: none found"
    fi
    
    return $issues
}