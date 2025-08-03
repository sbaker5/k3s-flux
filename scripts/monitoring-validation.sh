#!/bin/bash
# Monitoring System Validation Module
#
# This module validates the monitoring system health and readiness
# for k3s2 node integration.
#
# Requirements: 7.1 from k3s1-node-onboarding spec

# Validate Prometheus system health
validate_prometheus_health() {
    log "Validating Prometheus system health..."
    local issues=0
    
    # Check monitoring namespace
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        success "Monitoring namespace exists"
        add_to_report "✅ monitoring namespace: exists"
    else
        error "Monitoring namespace not found"
        add_to_report "❌ monitoring namespace: not found"
        issues=$((issues + 1))
        return $issues
    fi
    
    # Check Prometheus pods
    local prometheus_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
    local running_prometheus=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $prometheus_pods -gt 0 && $running_prometheus -eq $prometheus_pods ]]; then
        success "Prometheus is healthy ($running_prometheus/$prometheus_pods pods running)"
        add_to_report "✅ Prometheus pods: $running_prometheus/$prometheus_pods running"
    else
        error "Prometheus is not healthy ($running_prometheus/$prometheus_pods pods running)"
        add_to_report "❌ Prometheus pods: $running_prometheus/$prometheus_pods running"
        issues=$((issues + 1))
    fi
    
    # Check Prometheus service
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    if [[ -n "$prometheus_service" ]]; then
        success "Prometheus service exists: $prometheus_service"
        add_to_report "✅ Prometheus service: $prometheus_service"
        
        # Test Prometheus API accessibility
        local port_forward_pid=""
        kubectl port-forward -n monitoring "service/$prometheus_service" 9090:9090 >/dev/null 2>&1 &
        port_forward_pid=$!
        sleep 3
        
        if curl -s http://localhost:9090/api/v1/query?query=up >/dev/null 2>&1; then
            success "Prometheus API is accessible"
            add_to_report "✅ Prometheus API: accessible"
            
            # Check current targets
            local up_targets=$(curl -s http://localhost:9090/api/v1/query?query=up | jq -r '.data.result | length' 2>/dev/null || echo "0")
            log "Prometheus active targets: $up_targets"
            add_to_report "**Prometheus active targets**: $up_targets"
            
            # Check for node metrics (should include k3s1)
            local node_targets=$(curl -s "http://localhost:9090/api/v1/query?query=up{job=\"node-exporter\"}" | jq -r '.data.result | length' 2>/dev/null || echo "0")
            if [[ "$node_targets" -gt 0 ]]; then
                success "Node exporter metrics available ($node_targets nodes)"
                add_to_report "✅ Node exporter targets: $node_targets"
            else
                warn "No node exporter metrics found"
                add_to_report "⚠️ Node exporter targets: none found"
            fi
            
        else
            error "Prometheus API is not accessible"
            add_to_report "❌ Prometheus API: not accessible"
            issues=$((issues + 1))
        fi
        
        # Clean up port forward
        if [[ -n "$port_forward_pid" ]]; then
            kill $port_forward_pid 2>/dev/null || true
        fi
    else
        error "Prometheus service not found"
        add_to_report "❌ Prometheus service: not found"
        issues=$((issues + 1))
    fi
    
    # Check Prometheus configuration
    local prometheus_config=$(kubectl get secret -n monitoring -l app.kubernetes.io/name=prometheus -o name | head -1 2>/dev/null)
    if [[ -n "$prometheus_config" ]]; then
        success "Prometheus configuration secret found"
        add_to_report "✅ Prometheus config: secret found"
    else
        warn "Prometheus configuration secret not found"
        add_to_report "⚠️ Prometheus config: secret not found"
    fi
    
    return $issues
}

# Validate Grafana system health
validate_grafana_health() {
    log "Validating Grafana system health..."
    local issues=0
    
    # Check Grafana pods
    local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | wc -l)
    local running_grafana=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $grafana_pods -gt 0 && $running_grafana -eq $grafana_pods ]]; then
        success "Grafana is healthy ($running_grafana/$grafana_pods pods running)"
        add_to_report "✅ Grafana pods: $running_grafana/$grafana_pods running"
    else
        error "Grafana is not healthy ($running_grafana/$grafana_pods pods running)"
        add_to_report "❌ Grafana pods: $running_grafana/$grafana_pods running"
        issues=$((issues + 1))
    fi
    
    # Check Grafana service
    local grafana_service=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$grafana_service" ]]; then
        success "Grafana service exists: $grafana_service"
        add_to_report "✅ Grafana service: $grafana_service"
        
        # Test Grafana accessibility
        local port_forward_pid=""
        kubectl port-forward -n monitoring "service/$grafana_service" 3000:80 >/dev/null 2>&1 &
        port_forward_pid=$!
        sleep 3
        
        if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
            success "Grafana API is accessible"
            add_to_report "✅ Grafana API: accessible"
        else
            error "Grafana API is not accessible"
            add_to_report "❌ Grafana API: not accessible"
            issues=$((issues + 1))
        fi
        
        # Clean up port forward
        if [[ -n "$port_forward_pid" ]]; then
            kill $port_forward_pid 2>/dev/null || true
        fi
    else
        error "Grafana service not found"
        add_to_report "❌ Grafana service: not found"
        issues=$((issues + 1))
    fi
    
    # Check Grafana configuration
    local grafana_config=$(kubectl get configmap -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | wc -l)
    if [[ $grafana_config -gt 0 ]]; then
        success "Grafana configuration found"
        add_to_report "✅ Grafana config: found"
    else
        warn "Grafana configuration not found"
        add_to_report "⚠️ Grafana config: not found"
    fi
    
    # Check Grafana data source configuration
    local grafana_secret=$(kubectl get secret -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | wc -l)
    if [[ $grafana_secret -gt 0 ]]; then
        success "Grafana secrets found"
        add_to_report "✅ Grafana secrets: found"
    else
        warn "Grafana secrets not found"
        add_to_report "⚠️ Grafana secrets: not found"
    fi
    
    return $issues
}

# Validate ServiceMonitor configuration
validate_servicemonitor_config() {
    log "Validating ServiceMonitor configuration..."
    local issues=0
    
    # Check ServiceMonitors
    local servicemonitors=$(kubectl get servicemonitors -n monitoring --no-headers 2>/dev/null | wc -l)
    if [[ $servicemonitors -gt 0 ]]; then
        success "Found $servicemonitors ServiceMonitor(s)"
        add_to_report "✅ ServiceMonitors: $servicemonitors found"
        
        # List key ServiceMonitors
        log "ServiceMonitors:"
        kubectl get servicemonitors -n monitoring --no-headers | while read -r sm _; do
            log "  - $sm"
            add_to_report "  - $sm"
        done
    else
        warn "No ServiceMonitors found"
        add_to_report "⚠️ ServiceMonitors: none found"
    fi
    
    # Check PodMonitors
    local podmonitors=$(kubectl get podmonitors -n monitoring --no-headers 2>/dev/null | wc -l)
    if [[ $podmonitors -gt 0 ]]; then
        success "Found $podmonitors PodMonitor(s)"
        add_to_report "✅ PodMonitors: $podmonitors found"
        
        # List PodMonitors
        log "PodMonitors:"
        kubectl get podmonitors -n monitoring --no-headers | while read -r pm _; do
            log "  - $pm"
            add_to_report "  - $pm"
        done
    else
        warn "No PodMonitors found"
        add_to_report "⚠️ PodMonitors: none found"
    fi
    
    # Check Flux-specific monitoring (important for k3s2 integration)
    if kubectl get podmonitors -n monitoring flux-controllers-pods >/dev/null 2>&1; then
        success "Flux controllers PodMonitor exists"
        add_to_report "✅ Flux controllers monitoring: configured"
        
        # Check if it covers all controllers
        local flux_selector=$(kubectl get podmonitors -n monitoring flux-controllers-pods -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
        log "Flux PodMonitor selector: $flux_selector"
        add_to_report "**Flux PodMonitor selector**: $flux_selector"
    else
        warn "Flux controllers PodMonitor not found"
        add_to_report "⚠️ Flux controllers monitoring: not configured"
    fi
    
    # Check if ServiceMonitor exists for services
    if kubectl get servicemonitors -n monitoring flux-controllers-with-services >/dev/null 2>&1; then
        success "Flux services ServiceMonitor exists"
        add_to_report "✅ Flux services monitoring: configured"
    else
        warn "Flux services ServiceMonitor not found"
        add_to_report "⚠️ Flux services monitoring: not configured"
    fi
    
    # Check node-exporter ServiceMonitor/PodMonitor
    local node_exporter_monitors=$(kubectl get servicemonitors,podmonitors -n monitoring -o name | grep node-exporter | wc -l)
    if [[ $node_exporter_monitors -gt 0 ]]; then
        success "Node exporter monitoring configured"
        add_to_report "✅ Node exporter monitoring: configured"
    else
        warn "Node exporter monitoring not found"
        add_to_report "⚠️ Node exporter monitoring: not configured"
    fi
    
    return $issues
}

# Validate node exporter readiness
validate_node_exporter_readiness() {
    log "Validating node exporter readiness..."
    local issues=0
    
    # Check node-exporter DaemonSet
    local node_exporter_ds=$(kubectl get daemonset -A -l app.kubernetes.io/name=node-exporter --no-headers 2>/dev/null | wc -l)
    if [[ $node_exporter_ds -gt 0 ]]; then
        success "Node exporter DaemonSet found"
        add_to_report "✅ Node exporter DaemonSet: found"
        
        # Get DaemonSet details
        local ds_namespace=$(kubectl get daemonset -A -l app.kubernetes.io/name=node-exporter --no-headers | head -1 | awk '{print $1}')
        local ds_name=$(kubectl get daemonset -A -l app.kubernetes.io/name=node-exporter --no-headers | head -1 | awk '{print $2}')
        
        if [[ -n "$ds_namespace" && -n "$ds_name" ]]; then
            local desired=$(kubectl get daemonset "$ds_name" -n "$ds_namespace" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
            local ready=$(kubectl get daemonset "$ds_name" -n "$ds_namespace" -o jsonpath='{.status.numberReady}' 2>/dev/null)
            
            if [[ "$ready" == "$desired" && "$desired" -gt 0 ]]; then
                success "Node exporter DaemonSet is healthy ($ready/$desired pods ready)"
                add_to_report "✅ Node exporter status: $ready/$desired pods ready"
                
                # Check if running on k3s1
                local k3s1_node_exporter=$(kubectl get pods -n "$ds_namespace" -l app.kubernetes.io/name=node-exporter --field-selector spec.nodeName=k3s1 --no-headers 2>/dev/null | wc -l)
                if [[ $k3s1_node_exporter -gt 0 ]]; then
                    success "Node exporter running on k3s1"
                    add_to_report "✅ Node exporter on k3s1: running"
                else
                    warn "Node exporter not running on k3s1"
                    add_to_report "⚠️ Node exporter on k3s1: not running"
                fi
            else
                error "Node exporter DaemonSet is not healthy ($ready/$desired pods ready)"
                add_to_report "❌ Node exporter status: $ready/$desired pods ready"
                issues=$((issues + 1))
            fi
        fi
    else
        warn "Node exporter DaemonSet not found"
        add_to_report "⚠️ Node exporter DaemonSet: not found"
        
        # Check for node exporter pods directly
        local node_exporter_pods=$(kubectl get pods -A -l app.kubernetes.io/name=node-exporter --no-headers 2>/dev/null | wc -l)
        if [[ $node_exporter_pods -gt 0 ]]; then
            log "Found $node_exporter_pods node exporter pod(s) without DaemonSet"
            add_to_report "ℹ️ Node exporter pods: $node_exporter_pods found (no DaemonSet)"
        fi
    fi
    
    # Check node exporter metrics port
    local node_exporter_port=$(kubectl get pods -A -l app.kubernetes.io/name=node-exporter -o jsonpath='{.items[0].spec.containers[0].ports[?(@.name=="http-metrics")].containerPort}' 2>/dev/null || echo "unknown")
    if [[ "$node_exporter_port" == "9100" ]]; then
        success "Node exporter using standard metrics port (9100)"
        add_to_report "✅ Node exporter port: 9100 (standard)"
    elif [[ "$node_exporter_port" != "unknown" ]]; then
        log "Node exporter using custom metrics port: $node_exporter_port"
        add_to_report "ℹ️ Node exporter port: $node_exporter_port (custom)"
    else
        warn "Could not determine node exporter metrics port"
        add_to_report "⚠️ Node exporter port: could not determine"
    fi
    
    # Check if node exporter will automatically discover k3s2
    local node_selector=$(kubectl get daemonset -A -l app.kubernetes.io/name=node-exporter -o jsonpath='{.items[0].spec.template.spec.nodeSelector}' 2>/dev/null)
    if [[ -n "$node_selector" && "$node_selector" != "{}" ]]; then
        log "Node exporter has node selector: $node_selector"
        add_to_report "**Node exporter selector**: $node_selector"
        
        # Check if k3s2 would match the selector (we can't test this directly since k3s2 doesn't exist yet)
        log "Verify k3s2 will have matching labels when it joins"
        add_to_report "ℹ️ **Action needed**: Verify k3s2 will have matching labels"
    else
        success "Node exporter has no node selector - will run on all nodes including k3s2"
        add_to_report "✅ Node exporter selector: none (will run on all nodes)"
    fi
    
    # Check monitoring storage (should be ephemeral for bulletproof architecture)
    local monitoring_pvcs=$(kubectl get pvc -n monitoring --no-headers 2>/dev/null | wc -l)
    if [[ $monitoring_pvcs -eq 0 ]]; then
        success "Monitoring using ephemeral storage (bulletproof architecture)"
        add_to_report "✅ Monitoring storage: ephemeral (bulletproof)"
    else
        log "Found $monitoring_pvcs PVC(s) in monitoring namespace"
        add_to_report "ℹ️ Monitoring storage: $monitoring_pvcs PVCs found"
        
        # Check PVC status
        local bound_pvcs=$(kubectl get pvc -n monitoring --field-selector=status.phase=Bound --no-headers 2>/dev/null | wc -l)
        if [[ $bound_pvcs -eq $monitoring_pvcs ]]; then
            success "All monitoring PVCs are bound ($bound_pvcs/$monitoring_pvcs)"
            add_to_report "✅ Monitoring PVC status: $bound_pvcs/$monitoring_pvcs bound"
        else
            warn "Some monitoring PVCs are not bound ($bound_pvcs/$monitoring_pvcs)"
            add_to_report "⚠️ Monitoring PVC status: $bound_pvcs/$monitoring_pvcs bound"
        fi
    fi
    
    # Check alert manager (optional but recommended)
    local alertmanager_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers 2>/dev/null | wc -l)
    if [[ $alertmanager_pods -gt 0 ]]; then
        local running_alertmanager=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [[ $running_alertmanager -eq $alertmanager_pods ]]; then
            success "AlertManager is healthy ($running_alertmanager/$alertmanager_pods pods running)"
            add_to_report "✅ AlertManager: $running_alertmanager/$alertmanager_pods pods running"
        else
            warn "AlertManager is not healthy ($running_alertmanager/$alertmanager_pods pods running)"
            add_to_report "⚠️ AlertManager: $running_alertmanager/$alertmanager_pods pods running"
        fi
    else
        log "AlertManager not found (optional component)"
        add_to_report "ℹ️ AlertManager: not found (optional)"
    fi
    
    return $issues
}