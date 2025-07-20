---
inclusion: always
---

# Flux Monitoring and Metrics Collection

## Overview
This document captures important knowledge about monitoring Flux controllers in our k3s cluster, including architectural decisions and implementation details discovered during development.

## Flux Controller Architecture

### Controllers and Services
Flux controllers have different service exposure patterns:

**Controllers WITH Services:**
- `source-controller` - Has service, exposes metrics on port 8080 (http-prom)
- `notification-controller` - Has service, exposes metrics on port 8080 (http-prom)

**Controllers WITHOUT Services:**
- `kustomize-controller` - No service, only pod metrics on port 8080 (http-prom)
- `helm-controller` - No service, only pod metrics on port 8080 (http-prom)

### Metrics Endpoints
All Flux controllers expose metrics on:
- **Port**: 8080 (named `http-prom`)
- **Path**: `/metrics`
- **Format**: Prometheus format

## Monitoring Implementation

### Hybrid Approach Required
Due to the mixed service/pod architecture, we use both ServiceMonitor and PodMonitor:

1. **ServiceMonitor** (`flux-controllers-with-services`):
   - Monitors controllers that have services
   - Uses service discovery
   - Targets: source-controller, notification-controller

2. **PodMonitor** (`flux-controllers-pods`):
   - Monitors all controllers directly via pods
   - Uses pod discovery
   - Targets: all four controllers (source, kustomize, helm, notification)

### Key Metrics Available

**Controller Runtime Metrics:**
- `controller_runtime_active_workers` - Active workers per controller
- `controller_runtime_reconcile_total` - Total reconciliations
- `controller_runtime_reconcile_time_seconds_*` - Reconciliation duration
- `controller_runtime_reconcile_errors_total` - Reconciliation errors

**Flux-Specific Metrics:**
- `gotk_reconcile_duration_seconds_*` - GitOps Toolkit reconciliation timing
- `gotk_reconcile_condition` - Reconciliation condition status
- `gotk_event_*` - Event handling metrics
- `gotk_receiver_*` - Webhook receiver metrics

**Workqueue Metrics:**
- `workqueue_*` - Controller work queue metrics

## Configuration Files

### Location
- **ServiceMonitor + PodMonitor**: `infrastructure/monitoring/core/flux-servicemonitor.yaml`
- **Kustomization**: `infrastructure/monitoring/core/kustomization.yaml`

### Labels and Selectors
- **Service Selector**: `app.kubernetes.io/part-of: flux` + `control-plane: controller`
- **Pod Selector**: `app` in `[source-controller, kustomize-controller, helm-controller, notification-controller]`

### Metric Filtering
We filter metrics to reduce cardinality:
```yaml
metricRelabelings:
  - sourceLabels: [__name__]
    regex: 'flux_.*|gotk_.*|controller_runtime_.*|workqueue_.*|rest_client_.*'
    action: keep
```

## Troubleshooting

### Common Issues
1. **Missing Metrics**: Check if both ServiceMonitor and PodMonitor are deployed
2. **Service Discovery Fails**: Some controllers don't have services - use PodMonitor
3. **Port Issues**: All controllers use port 8080 (http-prom), not the main service port

### Verification Commands
```bash
# Check controller pods and their ports
kubectl get pods -n flux-system -l app=source-controller -o jsonpath='{.items[0].spec.containers[0].ports}'

# Test metrics endpoint directly
kubectl exec -n flux-system deployment/source-controller -- wget -qO- http://localhost:8080/metrics | head -10

# Check ServiceMonitor/PodMonitor resources
kubectl get servicemonitor,podmonitor -n monitoring -l monitoring.k3s-flux.io/component=flux-metrics

# Query Prometheus for Flux metrics
curl -s "http://localhost:9090/api/v1/query?query=controller_runtime_active_workers"
```

### Port Forward for Testing
```bash
# Prometheus
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090 --address=0.0.0.0 &

# Individual controller metrics
kubectl port-forward -n flux-system deployment/source-controller 8080:8080 --address=0.0.0.0 &
```

## Architecture Decisions

### Why Both ServiceMonitor and PodMonitor?
- **ServiceMonitor**: Preferred for controllers with services (more stable)
- **PodMonitor**: Required for controllers without services (kustomize, helm)
- **Redundancy**: PodMonitor covers all controllers as backup

### Metric Retention
- **Core Monitoring**: 2h retention (ephemeral, bulletproof)
- **Long-term Monitoring**: Disabled by default (requires Longhorn)

### Labels Added
- `cluster: k3s-flux` - For multi-cluster identification
- `controller: <controller-name>` - Controller identification
- `namespace: flux-system` - Namespace context
- `pod: <pod-name>` - Pod identification
- `node: <node-name>` - Node context

## Integration with Grafana

### Dashboards Available
- **Flux Cluster**: Grafana dashboard ID 16714
- **Flux Control Plane**: Grafana dashboard ID 16713

### Data Source
- **Name**: Prometheus-Core
- **URL**: `http://monitoring-core-prometheus-kube-prom-prometheus:9090`

## Future Considerations

### When Longhorn is Stable
- Enable long-term monitoring with persistent storage
- Increase retention periods for historical analysis
- Add alerting rules for Flux reconciliation failures

### Multi-Cluster Setup
- The `cluster: k3s-flux` label is already in place
- ServiceMonitor/PodMonitor can be replicated per cluster
- Prometheus federation may be needed for centralized monitoring