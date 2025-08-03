#!/bin/bash
# Storage System Health Check Module
#
# This module validates the Longhorn storage system health
# and prerequisites for k3s2 node storage integration.
#
# Requirements: 7.1 from k3s1-node-onboarding spec

# Check Longhorn system health
check_longhorn_system_health() {
    log "Checking Longhorn system health..."
    local issues=0
    
    # Check Longhorn namespace
    if kubectl get namespace longhorn-system >/dev/null 2>&1; then
        success "Longhorn system namespace exists"
        add_to_report "✅ longhorn-system namespace: exists"
    else
        error "Longhorn system namespace not found"
        add_to_report "❌ longhorn-system namespace: not found"
        issues=$((issues + 1))
        return $issues
    fi
    
    # Check Longhorn manager pods
    local longhorn_managers=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | wc -l)
    local running_managers=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $longhorn_managers -gt 0 && $running_managers -eq $longhorn_managers ]]; then
        success "Longhorn manager is healthy ($running_managers/$longhorn_managers pods running)"
        add_to_report "✅ Longhorn manager: $running_managers/$longhorn_managers pods running"
    else
        error "Longhorn manager is not healthy ($running_managers/$longhorn_managers pods running)"
        add_to_report "❌ Longhorn manager: $running_managers/$longhorn_managers pods running"
        issues=$((issues + 1))
    fi
    
    # Check Longhorn driver deployer
    local driver_deployers=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer --no-headers 2>/dev/null | wc -l)
    local running_deployers=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $driver_deployers -gt 0 && $running_deployers -eq $driver_deployers ]]; then
        success "Longhorn driver deployer is healthy ($running_deployers/$driver_deployers pods running)"
        add_to_report "✅ Longhorn driver deployer: $running_deployers/$driver_deployers pods running"
    else
        error "Longhorn driver deployer is not healthy ($running_deployers/$driver_deployers pods running)"
        add_to_report "❌ Longhorn driver deployer: $running_deployers/$driver_deployers pods running"
        issues=$((issues + 1))
    fi
    
    # Check Longhorn UI
    local longhorn_ui=$(kubectl get pods -n longhorn-system -l app=longhorn-ui --no-headers 2>/dev/null | wc -l)
    local running_ui=$(kubectl get pods -n longhorn-system -l app=longhorn-ui --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $longhorn_ui -gt 0 && $running_ui -eq $longhorn_ui ]]; then
        success "Longhorn UI is healthy ($running_ui/$longhorn_ui pods running)"
        add_to_report "✅ Longhorn UI: $running_ui/$longhorn_ui pods running"
    else
        warn "Longhorn UI is not healthy ($running_ui/$longhorn_ui pods running)"
        add_to_report "⚠️ Longhorn UI: $running_ui/$longhorn_ui pods running"
    fi
    
    # Check Longhorn instance manager
    local instance_managers=$(kubectl get pods -n longhorn-system -l app=longhorn-instance-manager --no-headers 2>/dev/null | wc -l)
    local running_instance_managers=$(kubectl get pods -n longhorn-system -l app=longhorn-instance-manager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ $instance_managers -gt 0 && $running_instance_managers -eq $instance_managers ]]; then
        success "Longhorn instance managers are healthy ($running_instance_managers/$instance_managers pods running)"
        add_to_report "✅ Longhorn instance managers: $running_instance_managers/$instance_managers pods running"
    else
        error "Longhorn instance managers are not healthy ($running_instance_managers/$instance_managers pods running)"
        add_to_report "❌ Longhorn instance managers: $running_instance_managers/$instance_managers pods running"
        issues=$((issues + 1))
    fi
    
    # Check Longhorn nodes
    local longhorn_nodes=$(kubectl get longhornnode -n longhorn-system --no-headers 2>/dev/null | wc -l)
    if [[ $longhorn_nodes -gt 0 ]]; then
        success "Found $longhorn_nodes Longhorn node(s)"
        add_to_report "✅ Longhorn nodes: $longhorn_nodes found"
        
        # Check k3s1 node specifically
        if kubectl get longhornnode k3s1 -n longhorn-system >/dev/null 2>&1; then
            local k3s1_ready=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            if [[ "$k3s1_ready" == "True" ]]; then
                success "k3s1 Longhorn node is ready"
                add_to_report "✅ k3s1 Longhorn node: ready"
            else
                error "k3s1 Longhorn node is not ready (Status: $k3s1_ready)"
                add_to_report "❌ k3s1 Longhorn node: not ready ($k3s1_ready)"
                issues=$((issues + 1))
            fi
        else
            error "k3s1 Longhorn node not found"
            add_to_report "❌ k3s1 Longhorn node: not found"
            issues=$((issues + 1))
        fi
    else
        error "No Longhorn nodes found"
        add_to_report "❌ Longhorn nodes: none found"
        issues=$((issues + 1))
    fi
    
    # Check Longhorn settings
    local default_replica_count=$(kubectl get setting default-replica-count -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "unknown")
    log "Longhorn default replica count: $default_replica_count"
    add_to_report "**Longhorn default replica count**: $default_replica_count"
    
    if [[ "$default_replica_count" == "2" ]]; then
        success "Default replica count is set for multi-node redundancy"
        add_to_report "✅ Replica count: configured for multi-node (2)"
    elif [[ "$default_replica_count" == "1" ]]; then
        warn "Default replica count is 1 - will increase to 2 when k3s2 is added"
        add_to_report "⚠️ Replica count: currently 1 (will increase with k3s2)"
    else
        log "Default replica count: $default_replica_count"
        add_to_report "ℹ️ Replica count: $default_replica_count"
    fi
    
    return $issues
}

# Check storage prerequisites
check_storage_prerequisites() {
    log "Checking storage prerequisites..."
    local issues=0
    
    # Check if iSCSI is available on k3s1 (required for Longhorn)
    if kubectl get node k3s1 -o jsonpath='{.metadata.labels}' | grep -q "node.longhorn.io/create-default-disk"; then
        success "k3s1 has Longhorn disk creation label"
        add_to_report "✅ k3s1 Longhorn labels: disk creation enabled"
    else
        warn "k3s1 missing Longhorn disk creation label"
        add_to_report "⚠️ k3s1 Longhorn labels: disk creation label missing"
    fi
    
    # Check for storage class
    if kubectl get storageclass longhorn >/dev/null 2>&1; then
        success "Longhorn storage class exists"
        add_to_report "✅ Longhorn storage class: exists"
        
        # Check if it's the default storage class
        local is_default=$(kubectl get storageclass longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
        if [[ "$is_default" == "true" ]]; then
            success "Longhorn is the default storage class"
            add_to_report "✅ Longhorn storage class: default"
        else
            log "Longhorn is not the default storage class"
            add_to_report "ℹ️ Longhorn storage class: not default"
        fi
    else
        error "Longhorn storage class not found"
        add_to_report "❌ Longhorn storage class: not found"
        issues=$((issues + 1))
    fi
    
    # Check existing volumes
    local volumes=$(kubectl get volumes -n longhorn-system --no-headers 2>/dev/null | wc -l)
    if [[ $volumes -gt 0 ]]; then
        success "Found $volumes Longhorn volume(s)"
        add_to_report "✅ Longhorn volumes: $volumes found"
        
        # Check volume health
        local healthy_volumes=$(kubectl get volumes -n longhorn-system -o jsonpath='{.items[?(@.status.robustness=="Healthy")].metadata.name}' 2>/dev/null | wc -w)
        if [[ $healthy_volumes -eq $volumes ]]; then
            success "All volumes are healthy ($healthy_volumes/$volumes)"
            add_to_report "✅ Volume health: $healthy_volumes/$volumes healthy"
        else
            warn "Some volumes are not healthy ($healthy_volumes/$volumes)"
            add_to_report "⚠️ Volume health: $healthy_volumes/$volumes healthy"
        fi
    else
        log "No Longhorn volumes found (this is normal for a new cluster)"
        add_to_report "ℹ️ Longhorn volumes: none found (normal for new cluster)"
    fi
    
    # Check PVCs using Longhorn
    local longhorn_pvcs=$(kubectl get pvc -A --no-headers 2>/dev/null | grep longhorn | wc -l)
    if [[ $longhorn_pvcs -gt 0 ]]; then
        success "Found $longhorn_pvcs PVC(s) using Longhorn"
        add_to_report "✅ Longhorn PVCs: $longhorn_pvcs found"
        
        # Check PVC status
        local bound_pvcs=$(kubectl get pvc -A --no-headers 2>/dev/null | grep longhorn | grep Bound | wc -l)
        if [[ $bound_pvcs -eq $longhorn_pvcs ]]; then
            success "All Longhorn PVCs are bound ($bound_pvcs/$longhorn_pvcs)"
            add_to_report "✅ Longhorn PVC status: $bound_pvcs/$longhorn_pvcs bound"
        else
            warn "Some Longhorn PVCs are not bound ($bound_pvcs/$longhorn_pvcs)"
            add_to_report "⚠️ Longhorn PVC status: $bound_pvcs/$longhorn_pvcs bound"
        fi
    else
        log "No PVCs using Longhorn found"
        add_to_report "ℹ️ Longhorn PVCs: none found"
    fi
    
    # Check CSI driver
    if kubectl get csidriver longhorn.csi.driver.longhorn.io >/dev/null 2>&1; then
        success "Longhorn CSI driver is registered"
        add_to_report "✅ Longhorn CSI driver: registered"
    else
        error "Longhorn CSI driver not found"
        add_to_report "❌ Longhorn CSI driver: not found"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Check disk discovery system
check_disk_discovery_system() {
    log "Checking disk discovery system..."
    local issues=0
    
    # Check if disk discovery DaemonSet exists
    if kubectl get daemonset disk-discovery -n longhorn-system >/dev/null 2>&1; then
        success "Disk discovery DaemonSet exists"
        add_to_report "✅ Disk discovery DaemonSet: exists"
        
        # Check DaemonSet status
        local desired=$(kubectl get daemonset disk-discovery -n longhorn-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
        local ready=$(kubectl get daemonset disk-discovery -n longhorn-system -o jsonpath='{.status.numberReady}' 2>/dev/null)
        
        if [[ "$ready" == "$desired" && "$desired" -gt 0 ]]; then
            success "Disk discovery DaemonSet is healthy ($ready/$desired pods ready)"
            add_to_report "✅ Disk discovery status: $ready/$desired pods ready"
        else
            error "Disk discovery DaemonSet is not healthy ($ready/$desired pods ready)"
            add_to_report "❌ Disk discovery status: $ready/$desired pods ready"
            issues=$((issues + 1))
        fi
    else
        # Check if it exists in the storage namespace or as a different name
        local discovery_pods=$(kubectl get pods -A -l app=disk-discovery --no-headers 2>/dev/null | wc -l)
        if [[ $discovery_pods -gt 0 ]]; then
            success "Found $discovery_pods disk discovery pod(s)"
            add_to_report "✅ Disk discovery pods: $discovery_pods found"
        else
            warn "Disk discovery system not found - may need to be deployed"
            add_to_report "⚠️ Disk discovery system: not found"
            
            # Check if the configuration exists in the repository
            if [[ -f "infrastructure/storage/disk-discovery-daemonset.yaml" ]]; then
                log "Disk discovery configuration found in repository"
                add_to_report "ℹ️ Disk discovery config: found in repository"
            else
                warn "Disk discovery configuration not found in repository"
                add_to_report "⚠️ Disk discovery config: not found in repository"
            fi
        fi
    fi
    
    # Check k3s1 disk configuration
    if kubectl get longhornnode k3s1 -n longhorn-system >/dev/null 2>&1; then
        local k3s1_disks=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.spec.disks}' 2>/dev/null)
        if [[ -n "$k3s1_disks" && "$k3s1_disks" != "{}" ]]; then
            success "k3s1 has disk configuration"
            add_to_report "✅ k3s1 disk config: configured"
            
            # Get disk details
            local disk_paths=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.spec.disks.*.path}' 2>/dev/null)
            log "k3s1 disk paths: $disk_paths"
            add_to_report "**k3s1 disk paths**: $disk_paths"
        else
            warn "k3s1 has no disk configuration"
            add_to_report "⚠️ k3s1 disk config: none found"
        fi
    else
        error "k3s1 Longhorn node not found"
        add_to_report "❌ k3s1 Longhorn node: not found"
        issues=$((issues + 1))
    fi
    
    # Check k3s2 node configuration (should exist in Git but not in cluster yet)
    if [[ -f "infrastructure/k3s2-node-config/k3s2-node.yaml" ]]; then
        success "k3s2 node configuration exists in repository"
        add_to_report "✅ k3s2 node config: exists in repository"
        
        # Check if it contains disk configuration
        if grep -q "disks:" "infrastructure/k3s2-node-config/k3s2-node.yaml"; then
            success "k3s2 node configuration includes disk setup"
            add_to_report "✅ k3s2 disk config: included in node config"
        else
            warn "k3s2 node configuration missing disk setup"
            add_to_report "⚠️ k3s2 disk config: missing from node config"
        fi
    else
        error "k3s2 node configuration not found in repository"
        add_to_report "❌ k3s2 node config: not found in repository"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Check storage capacity planning
check_storage_capacity_planning() {
    log "Checking storage capacity planning..."
    local issues=0
    
    # Get current storage usage
    if kubectl get longhornnode k3s1 -n longhorn-system >/dev/null 2>&1; then
        local k3s1_storage_info=$(kubectl get longhornnode k3s1 -n longhorn-system -o jsonpath='{.status.diskStatus}' 2>/dev/null)
        
        if [[ -n "$k3s1_storage_info" ]]; then
            success "k3s1 storage information available"
            add_to_report "✅ k3s1 storage info: available"
            
            # Parse storage information (this is complex JSON, so we'll do basic checks)
            local disk_count=$(echo "$k3s1_storage_info" | jq 'length' 2>/dev/null || echo "0")
            log "k3s1 configured disks: $disk_count"
            add_to_report "**k3s1 configured disks**: $disk_count"
            
            if [[ "$disk_count" -gt 0 ]]; then
                success "k3s1 has storage disks configured"
                add_to_report "✅ k3s1 storage disks: $disk_count configured"
            else
                warn "k3s1 has no storage disks configured"
                add_to_report "⚠️ k3s1 storage disks: none configured"
            fi
        else
            warn "k3s1 storage information not available"
            add_to_report "⚠️ k3s1 storage info: not available"
        fi
    else
        error "Cannot check k3s1 storage - Longhorn node not found"
        add_to_report "❌ k3s1 storage check: Longhorn node not found"
        issues=$((issues + 1))
    fi
    
    # Check current volume usage
    local total_volumes=$(kubectl get volumes -n longhorn-system --no-headers 2>/dev/null | wc -l)
    if [[ $total_volumes -gt 0 ]]; then
        log "Current volume count: $total_volumes"
        add_to_report "**Current volumes**: $total_volumes"
        
        # Check replica distribution (will improve with k3s2)
        local single_replica_volumes=$(kubectl get volumes -n longhorn-system -o jsonpath='{.items[?(@.spec.numberOfReplicas==1)].metadata.name}' 2>/dev/null | wc -w)
        if [[ $single_replica_volumes -gt 0 ]]; then
            log "$single_replica_volumes volume(s) have single replica - will benefit from k3s2 addition"
            add_to_report "ℹ️ Single replica volumes: $single_replica_volumes (will benefit from k3s2)"
        fi
        
        local multi_replica_volumes=$(kubectl get volumes -n longhorn-system -o jsonpath='{.items[?(@.spec.numberOfReplicas>1)].metadata.name}' 2>/dev/null | wc -w)
        if [[ $multi_replica_volumes -gt 0 ]]; then
            success "$multi_replica_volumes volume(s) already have multiple replicas"
            add_to_report "✅ Multi-replica volumes: $multi_replica_volumes"
        fi
    else
        log "No volumes currently exist - k3s2 will be ready for new volumes"
        add_to_report "ℹ️ Current volumes: none (k3s2 ready for new volumes)"
    fi
    
    # Check storage class configuration for multi-node
    local replica_count=$(kubectl get storageclass longhorn -o jsonpath='{.parameters.numberOfReplicas}' 2>/dev/null || echo "default")
    log "Storage class replica count: $replica_count"
    add_to_report "**Storage class replica count**: $replica_count"
    
    if [[ "$replica_count" == "2" ]]; then
        success "Storage class configured for 2 replicas (optimal for 2-node setup)"
        add_to_report "✅ Storage class replicas: 2 (optimal for 2-node)"
    elif [[ "$replica_count" == "default" || "$replica_count" == "" ]]; then
        log "Storage class using default replica count (will use Longhorn setting)"
        add_to_report "ℹ️ Storage class replicas: using Longhorn default"
    else
        log "Storage class replica count: $replica_count"
        add_to_report "ℹ️ Storage class replicas: $replica_count"
    fi
    
    # Check backup configuration (optional but recommended)
    local backup_targets=$(kubectl get setting backup-target -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "")
    if [[ -n "$backup_targets" && "$backup_targets" != '""' ]]; then
        success "Backup target configured: $backup_targets"
        add_to_report "✅ Backup target: configured ($backup_targets)"
    else
        log "No backup target configured (optional but recommended)"
        add_to_report "ℹ️ Backup target: not configured (optional)"
    fi
    
    return $issues
}