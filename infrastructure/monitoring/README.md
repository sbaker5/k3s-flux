# Hybrid Monitoring Architecture

This directory implements a **hybrid monitoring architecture** designed for bulletproof GitOps operations with optional persistent storage.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hybrid Monitoring Stack                      │
├─────────────────────────────────────────────────────────────────┤
│  Core Tier (Always Available)          │  Long-term Tier       │
│  ├─ Prometheus Core (2h retention)     │  ├─ Prometheus LT     │
│  │  └─ emptyDir storage               │  │  └─ Longhorn 30d   │
│  ├─ Grafana Core (ephemeral)          │  ├─ Grafana LT        │
│  │  └─ Essential dashboards           │  │  └─ Full dashboards │
│  └─ Node/KSM exporters                │  └─ Alertmanager      │
│                                        │                       │
│  Status: BULLETPROOF                   │  Status: OPTIONAL     │
│  Dependencies: None                    │  Dependencies: Longhorn│
└─────────────────────────────────────────────────────────────────┘
```

## Design Principles

### 1. **Bulletproof Core**
- **No persistent storage dependencies** - Core monitoring uses `emptyDir`
- **Fast startup** - Minimal resource requirements and quick deployment
- **Always available** - Remains operational during storage failures
- **Essential visibility** - Provides immediate cluster health insights

### 2. **Optional Long-term Storage**
- **Historical data** - 30-day retention for trend analysis
- **Comprehensive dashboards** - Full feature set with persistence
- **Alerting** - Persistent alert rules and notification history
- **Graceful degradation** - System remains functional if this tier fails

### 3. **Data Flow**
- Core Prometheus → Remote Write → Long-term Prometheus
- Immediate visibility + Historical analysis
- No data loss during storage issues

## Directory Structure

```
infrastructure/monitoring/
├── README.md                    # This file
├── kustomization.yaml          # Main hybrid configuration
├── helm-repository.yaml        # Shared Helm repositories
├── prometheus-operator.yaml    # Shared Prometheus Operator
├── core/                       # Bulletproof monitoring tier
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── prometheus-core.yaml    # Ephemeral Prometheus (2h retention)
│   ├── grafana-core.yaml       # Ephemeral Grafana
│   └── servicemonitor.yaml     # Core service monitoring
├── longterm/                   # Optional persistent tier
│   ├── kustomization.yaml
│   ├── prometheus-longterm.yaml # Persistent Prometheus (30d retention)
│   └── grafana-longterm.yaml   # Persistent Grafana with full features
└── base/                       # Legacy configuration (deprecated)
```

## Deployment Strategy

### Phase 1: Core Monitoring (Always Deploy)
```yaml
# In kustomization.yaml
resources:
  - core/  # Always enabled
```

**Benefits:**
- ✅ Immediate cluster visibility
- ✅ No storage dependencies
- ✅ Fast recovery from failures
- ✅ Essential Flux/Longhorn monitoring

### Phase 2: Long-term Monitoring (Optional)
```yaml
# In kustomization.yaml  
resources:
  - core/
  - longterm/  # Enable when Longhorn is stable
```

**Benefits:**
- ✅ Historical trend analysis
- ✅ Persistent alerting
- ✅ Comprehensive dashboards
- ✅ Data continuity via remote_write

## Access Points

### Core Monitoring
- **Grafana Core**: `http://monitoring-core-grafana-core.monitoring.svc`
- **Prometheus Core**: `http://monitoring-core-prometheus-core-prometheus:9090`
- **Retention**: 2 hours
- **Storage**: Ephemeral (emptyDir)

### Long-term Monitoring (when enabled)
- **Grafana Long-term**: `http://cluster-ip:30300` (NodePort)
- **Prometheus Long-term**: `http://monitoring-longterm-prometheus-longterm-prometheus:9090`
- **Retention**: 30 days
- **Storage**: Persistent (Longhorn)

## Monitoring Targets

### Core Metrics (Always Available)
- **Kubernetes cluster state** (kube-state-metrics)
- **Node metrics** (node-exporter)
- **Flux controllers** (source, kustomize, helm, notification)
- **Longhorn storage** (manager endpoints)
- **Basic infrastructure health**

### Extended Metrics (Long-term Only)
- **Historical trends and capacity planning**
- **Alert rule evaluation history**
- **Custom application metrics**
- **Performance baselines**

## Operational Procedures

### Initial Deployment
```bash
# 1. Clean up any stuck resources
./scripts/cleanup-stuck-monitoring.sh

# 2. Deploy core monitoring
flux reconcile kustomization monitoring -n flux-system

# 3. Verify core monitoring is healthy
kubectl get pods -n monitoring -l monitoring.k3s-flux.io/tier=core

# 4. (Optional) Enable long-term monitoring
# Edit infrastructure/monitoring/kustomization.yaml
# Uncomment: - longterm/
```

### Troubleshooting

#### Core Monitoring Issues
```bash
# Check core monitoring pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=monitoring-core

# Check core Prometheus
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-core-prometheus 9090:9090

# Check core Grafana
kubectl port-forward -n monitoring svc/monitoring-core-grafana-core 3000:80
```

#### Long-term Monitoring Issues
```bash
# Check long-term monitoring pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=monitoring-longterm

# Check PVC status
kubectl get pvc -n monitoring

# Check Longhorn volumes
kubectl get volumes -n longhorn-system
```

### Recovery Procedures

#### Storage Failure Recovery
1. **Core monitoring continues operating** (no action needed)
2. Long-term monitoring will restart when storage recovers
3. Data continuity maintained via remote_write from core

#### Complete Monitoring Failure
1. Run cleanup script: `./scripts/cleanup-stuck-monitoring.sh`
2. Redeploy core monitoring: `flux reconcile kustomization monitoring`
3. Core monitoring provides immediate visibility
4. Re-enable long-term tier when ready

## Future Considerations

### KubeVirt Integration
When adding KubeVirt workloads:

1. **VM Storage**: Use dedicated storage class (not Longhorn)
2. **VM Monitoring**: Extend core monitoring for VM metrics
3. **Backup Strategy**: Separate VM backup from monitoring data
4. **Resource Isolation**: Ensure VM workloads don't impact monitoring

### Scaling Considerations
- **Core monitoring**: Scale horizontally with multiple replicas
- **Long-term monitoring**: Scale storage and retention policies
- **Network policies**: Implement proper segmentation
- **Resource quotas**: Prevent monitoring from consuming all resources

## Configuration Examples

### Enable Long-term Monitoring
```yaml
# infrastructure/monitoring/kustomization.yaml
resources:
  - helm-repository.yaml
  - prometheus-operator.yaml
  - core/
  - longterm/  # Uncomment this line
```

### Adjust Retention Policies
```yaml
# core/prometheus-core.yaml
prometheusSpec:
  retention: 4h  # Increase core retention

# longterm/prometheus-longterm.yaml  
prometheusSpec:
  retention: 90d  # Increase long-term retention
```

### Custom Storage Classes
```yaml
# For future KubeVirt workloads
storageSpec:
  volumeClaimTemplate:
    spec:
      storageClassName: local-nvme  # Fast local storage
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

This hybrid architecture ensures monitoring remains available during storage issues while providing optional historical data when needed.