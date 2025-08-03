# Design Document

## Overview

This design addresses the systematic cleanup and optimization of the monitoring system while documenting and validating the existing Tailscale remote access infrastructure. The approach focuses on bulletproof monitoring architecture with ephemeral storage, comprehensive Flux metrics collection, and reliable remote access procedures.

## Architecture

### Monitoring System Architecture

The monitoring system follows a bulletproof design with ephemeral storage and dual metric collection strategies to ensure reliability even during storage failures.

**Core Components:**
- Prometheus Core: 2h retention, ephemeral storage, resource-limited
- Grafana Core: ephemeral storage, connects to Prometheus Core
- ServiceMonitor: Monitors Flux controllers with services
- PodMonitor: Monitors all Flux controllers directly via pods

**Remote Access:**
- Tailscale Subnet Router: Provides secure remote access
- kubectl contexts: k3s-remote for remote, default for local
- SSH access: k3s1-tailscale for direct node access
- Emergency CLI: ./scripts/emergency-cli.sh for troubleshooting

### Bulletproof Design Principles

1. **Core Monitoring Independence**: Monitoring operates without persistent storage dependencies
2. **Dual Collection Strategy**: Both ServiceMonitor and PodMonitor ensure complete coverage
3. **Short Retention**: 2-hour retention prevents resource exhaustion
4. **Resource Limits**: Controlled resource usage prevents cluster impact

## Components and Interfaces

### 1. Monitoring Cleanup System

#### Core Components
- **Prometheus Core**: monitoring-core-prometheus HelmRelease with ephemeral storage
- **Grafana Core**: monitoring-core-grafana HelmRelease with ephemeral storage
- **Flux ServiceMonitor**: Monitors controllers with services (source, notification)
- **Flux PodMonitor**: Monitors all controllers directly via pods

#### Cleanup Procedures
```bash
# Monitoring namespace cleanup
kubectl delete namespace monitoring --force --grace-period=0

# Stuck PVC cleanup
kubectl patch pvc <pvc-name> -n monitoring -p '{"metadata":{"finalizers":null}}'

# CRD cleanup if needed
kubectl delete crd prometheuses.monitoring.coreos.com --force --grace-period=0
```

### 2. Flux Metrics Collection

#### Hybrid Monitoring Strategy
The design uses both ServiceMonitor and PodMonitor to handle Flux's mixed architecture:

**ServiceMonitor Coverage**:
- source-controller: Has service, port 8080 (http-prom)
- notification-controller: Has service, port 8080 (http-prom)

**PodMonitor Coverage**:
- All four controllers: source-controller, kustomize-controller, helm-controller, notification-controller
- Direct pod access to port 8080 (http-prom)
- Backup for service-based controllers

#### Metric Filtering
```yaml
metricRelabelings:
  - sourceLabels: [__name__]
    regex: "flux_.*|gotk_.*|controller_runtime_.*|workqueue_.*|rest_client_.*"
    action: keep
```

### 3. Remote Access System

#### Existing Tailscale Infrastructure
- **Subnet Router**: tailscale-subnet-router deployment in tailscale namespace
- **Network Routes**: 10.42.0.0/16 (pods), 10.43.0.0/16 (services)
- **Hostname**: k3s-cluster in Tailscale network

#### Access Methods
1. **kubectl Remote Context**: k3s-remote context for full cluster access
2. **SSH Access**: k3s1-tailscale for direct node access
3. **Emergency CLI**: ./scripts/emergency-cli.sh for troubleshooting

#### Service Access Patterns
```bash
# Prometheus access
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090 --address=0.0.0.0

# Grafana access
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0
```

## Data Models

### Monitoring Configuration Model
```yaml
# Core monitoring configuration
monitoring:
  core:
    prometheus:
      retention: "2h"
      storage: "ephemeral"
      resources:
        requests: { cpu: "100m", memory: "512Mi" }
        limits: { cpu: "500m", memory: "1Gi" }
    grafana:
      storage: "ephemeral"
      datasource: "prometheus-core"
  
  flux_metrics:
    collection_method: "hybrid"  # ServiceMonitor + PodMonitor
    scrape_interval: "30s"
    metric_filters: ["flux_.*", "gotk_.*", "controller_runtime_.*"]
```

### Remote Access Configuration Model
```yaml
# Remote access configuration
remote_access:
  tailscale:
    hostname: "k3s-cluster"
    routes: ["10.42.0.0/16", "10.43.0.0/16"]
    namespace: "tailscale"
  
  kubectl_contexts:
    local: "default"
    remote: "k3s-remote"
  
  emergency_access:
    ssh_host: "k3s1-tailscale"
    cli_tool: "./scripts/emergency-cli.sh"
```

## Error Handling

### Monitoring System Errors

#### Stuck Namespace Recovery
```bash
# Force namespace deletion
kubectl patch namespace monitoring -p '{"metadata":{"finalizers":null}}'
kubectl delete namespace monitoring --force --grace-period=0

# Recreate clean namespace
kubectl create namespace monitoring
```

#### CRD Conflicts
```bash
# Remove stuck CRDs
kubectl delete crd prometheuses.monitoring.coreos.com --force --grace-period=0
kubectl delete crd servicemonitors.monitoring.coreos.com --force --grace-period=0

# Redeploy monitoring stack
flux reconcile kustomization infrastructure-monitoring -n flux-system
```

#### Metrics Collection Failures
1. **ServiceMonitor Issues**: Fall back to PodMonitor collection
2. **PodMonitor Issues**: Verify pod selectors and port configurations
3. **Scrape Failures**: Check Flux controller health and port accessibility

### Remote Access Errors

#### Tailscale Connection Issues
```bash
# Check Tailscale pod status
kubectl get pods -n tailscale
kubectl logs -n tailscale deployment/tailscale-subnet-router

# Restart Tailscale
kubectl rollout restart deployment/tailscale-subnet-router -n tailscale
```

#### kubectl Context Issues
```bash
# Verify contexts
kubectl config get-contexts

# Switch contexts
kubectl config use-context k3s-remote  # For remote access
kubectl config use-context default     # For local access
```

## Testing Strategy

### Monitoring System Validation

#### Health Check Procedures
```bash
# 1. Verify monitoring namespace
kubectl get namespace monitoring

# 2. Check Prometheus deployment
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# 3. Validate metrics collection
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090 --address=0.0.0.0 &
curl -s "http://localhost:9090/api/v1/query?query=up" | jq '.data.result | length'

# 4. Test Flux metrics
curl -s "http://localhost:9090/api/v1/query?query=controller_runtime_active_workers" | jq '.data.result'

# 5. Verify Grafana connectivity
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0 &
curl -s http://localhost:3000/api/health
```

### Remote Access Validation

#### Connection Testing
```bash
# Test Tailscale connectivity
tailscale status | grep k3s-cluster

# Test kubectl remote access
kubectl --context=k3s-remote get nodes

# Test SSH access
ssh k3s1-tailscale "kubectl get nodes"

# Test emergency CLI
ssh k3s1-tailscale "./scripts/emergency-cli.sh status"
```

## Implementation Phases

### Phase 1: Monitoring System Cleanup
1. **Assessment**: Identify stuck resources and configuration issues
2. **Cleanup**: Remove stuck namespaces, PVCs, and CRDs
3. **Redeployment**: Clean deployment of monitoring stack
4. **Validation**: Verify all components are healthy

### Phase 2: Flux Metrics Optimization
1. **ServiceMonitor Review**: Validate service-based metric collection
2. **PodMonitor Implementation**: Ensure comprehensive pod-based collection
3. **Metric Filtering**: Optimize metric collection for performance
4. **Dashboard Validation**: Verify Flux dashboards display correctly

### Phase 3: Remote Access Documentation
1. **Procedure Documentation**: Update remote access procedures
2. **Context Management**: Document kubectl context switching
3. **Emergency Procedures**: Validate emergency access methods
4. **Testing Scripts**: Create automated validation scripts

### Phase 4: System Integration Testing
1. **End-to-End Testing**: Validate complete monitoring and access workflow
2. **Failure Scenarios**: Test recovery procedures
3. **Performance Validation**: Ensure system meets performance requirements
4. **Documentation Updates**: Finalize all documentation