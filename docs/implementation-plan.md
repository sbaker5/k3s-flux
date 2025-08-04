# K3s Homelab Implementation Plan

## Table of Contents
1. [Current Status](#current-status)
2. [GitOps Resilience Patterns](#gitops-resilience-patterns)
3. [Monitoring & Observability](#monitoring--observability)
4. [Security Enhancements](#security-enhancements)
5. [Backup & Recovery](#backup--recovery)
6. [Documentation](#documentation)
7. [Long-term Improvements](#long-term-improvements)

> **📋 For system architecture details, see [Architecture Overview](architecture-overview.md)**

## Current Status

### ✅ Completed Infrastructure
- **k3s Cluster**: Operational with single node (k3s1), ready for multi-node expansion
- **Flux CD**: GitOps system fully deployed and operational
- **Longhorn Storage**: Distributed storage system operational, multi-node ready
- **NGINX Ingress**: Ingress controller running on NodePorts 30080/30443
- **Monitoring System**: Bulletproof monitoring with ephemeral storage
- **Remote Access**: Tailscale-based secure remote access configured
- **Multi-Node Infrastructure**: k3s2 node configuration prepared and ready for activation

### 🎯 Current Focus Areas
- **Multi-Node Expansion**: k3s2 worker node onboarding **ready for deployment** (GitOps configuration complete, enhanced cloud-init ready, comprehensive validation suite completed, onboarding orchestration completed)
- **GitOps Resilience**: Automated error detection and recovery patterns (completed)
- **Monitoring Optimization**: Enhanced Flux metrics collection and alerting (completed)
- **Security Validation**: Multi-node security posture validation and SOPS integration testing
- **Operational Excellence**: Rollback procedures and emergency recovery tooling

## Network Troubleshooting

### 1. Verify kube-proxy
```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-proxy
```

### 2. Check Flannel CNI
```bash
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel -l app=flannel
```

### 3. Test Pod-to-Pod Connectivity
```bash
# Create test pods
kubectl run test-pod1 --image=busybox -- sleep 3600
kubectl run test-pod2 --image=busybox -- sleep 3600

# Test connectivity
kubectl exec -it test-pod1 -- ping test-pod2
```

## GitOps Resilience Patterns

### Current Implementation Status

**✅ Completed Components:**
- **Pre-commit validation infrastructure** - Kustomization build validation with comprehensive error detection
- **Immutable field conflict detection** - Advanced tool detecting breaking changes across 10+ resource types
- **Emergency recovery procedures** - Comprehensive troubleshooting guide with manual recovery procedures
- **Validation scripts** - Automated tools for preventing deployment failures
- **Reconciliation health monitoring** - Complete hybrid monitoring architecture with bulletproof core tier
- **GitOps health monitoring dashboard** - Grafana dashboard for Flux reconciliation visibility and performance tracking
- **Alert rules for stuck reconciliations** - Comprehensive PrometheusRule resources for proactive detection
- **Error pattern detection system** - Advanced controller with 20+ error patterns and comprehensive testing suite
- **Automated recovery system** - Complete error pattern detection and resource recreation automation

**✅ Recently Completed:**
- **Multi-node cluster expansion** - k3s2 worker node ready for deployment (GitOps configuration complete, enhanced cloud-init with comprehensive error handling and health monitoring ready, monitoring integration completed, comprehensive onboarding orchestration completed)
- **Storage discovery enhancement** - Improved disk discovery DaemonSet with better error handling and validation
- **Comprehensive validation suite** - Complete onboarding validation scripts with real-time monitoring and health checks
- **Post-onboarding health verification** - Comprehensive cluster health check and application deployment verification tools

**🚧 In Progress:**
- **Resource lifecycle management** - Blue-green deployment patterns for immutable resources
- **Security and RBAC validation** - Multi-node security posture validation and SOPS integration testing
- **Rollback and recovery procedures** - Node drain and removal scripts for emergency situations

**📋 Planned:**
- **Advanced deployment patterns** - Canary deployments and progressive delivery
- **Multi-cluster resilience** - Extending patterns to multi-cluster environments

### Available Tools

#### 1. Kustomization Build Validation
```bash
# Validate all kustomization builds
./scripts/validate-kustomizations.sh

# Checks 9+ directories for build errors
# Catches YAML syntax errors, missing resources, invalid configurations
```

#### 2. Immutable Field Change Detection
```bash
# Check for breaking changes between commits
./scripts/check-immutable-fields.sh

# Compare specific branches
./scripts/check-immutable-fields.sh -b main -h feature-branch

# Detects changes to immutable fields in:
# - Deployments (spec.selector)
# - Services (spec.clusterIP, spec.type)
# - StatefulSets (spec.selector, spec.serviceName)
# - PVCs (spec.accessModes, spec.resources.requests.storage)
# - And 6+ other resource types
```

#### 3. Emergency Recovery Procedures
- **Location**: `docs/troubleshooting/flux-recovery-guide.md`
- **Covers**: Namespace stuck states, authentication failures, controller recovery
- **Includes**: Step-by-step recovery procedures and verification checklists

#### 4. Monitoring Cleanup Procedures
```bash
# Clean up stuck monitoring resources and PVCs
./scripts/cleanup-stuck-monitoring.sh

# Features:
# - Removes stuck PVCs with finalizer cleanup
# - Cleans up failed HelmReleases
# - Removes orphaned Helm secrets
# - Suspends/resumes monitoring kustomization safely
```

### Next Implementation Steps

#### Phase 1: Monitoring Infrastructure (✅ Completed)
```bash
# Monitoring infrastructure is fully deployed
flux reconcile kustomization monitoring -n flux-system

# Access monitoring dashboards
kubectl port-forward -n monitoring svc/monitoring-core-grafana-core 3000:80

# View active alerts
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090
```

#### Phase 2: Automated Recovery System (✅ Completed)
```bash
# Error pattern detection system is fully deployed
kubectl apply -k infrastructure/recovery/

# Test the detection system
./tests/validation/test-tasks-3.1-3.2.sh

# Run comprehensive validation
./tests/validation/test-pattern-simulation.sh

# Monitor detection activity
kubectl logs -n flux-recovery deployment/error-pattern-detector -f
```

**Recovery Configuration** (implemented):
```yaml
# Recovery patterns are configured in infrastructure/recovery/recovery-patterns-config.yaml
# 20+ error patterns with recovery actions defined
# RBAC permissions for resource recreation configured
# Auto-recovery settings and retry logic implemented
```

#### Phase 3: Resource Lifecycle Management
- Blue-green deployment strategies for immutable resources
- Atomic resource replacement tooling
- Dependency-aware update ordering

## Multi-Node Cluster Expansion

### Current Status: Ready for k3s2 Onboarding

**✅ Prepared Infrastructure:**
- **Node Configuration**: k3s2 node configuration files ready and activated in `infrastructure/k3s2-node-config/`
- **Cloud-Init Setup**: Enhanced automated onboarding configuration at `infrastructure/cloud-init/user-data.k3s2` with comprehensive error handling, retry mechanisms, and health monitoring
- **Storage Integration**: Disk discovery DaemonSet ready for multi-node storage
- **GitOps Management**: Flux Kustomizations activated for k3s2 (storage kustomization includes k3s2-node-config)
- **Validation Tools**: ✅ **Completed** - Comprehensive pre-onboarding validation scripts including cluster readiness, network connectivity, storage health, and monitoring system validation
- **Monitoring Integration**: ✅ **Completed** - k3s2 monitoring integration with enhanced ServiceMonitors, PodMonitors, Grafana dashboards, and alerting rules
- **Health Monitoring**: Real-time onboarding status monitoring with HTTP health check endpoint on port 8080

**🎯 Onboarding Process:**
1. **Node Preparation**: Boot k3s2 with cloud-init or manual setup
2. **Cluster Join**: Automated k3s agent installation and cluster join
3. **GitOps Activation**: Uncomment k3s2-node-config in storage kustomization
4. **Storage Integration**: Automatic Longhorn disk discovery and configuration
5. **Validation**: Run comprehensive validation suite

**📋 Validation Commands:**
```bash
# Test cluster readiness for k3s2 onboarding
./tests/validation/test-k3s2-node-onboarding.sh

# After k3s2 joins, validate full integration
./tests/validation/test-k3s2-node-onboarding.sh

# Comprehensive multi-node validation
./tests/validation/post-outage-health-check.sh
```

**📚 Documentation:**
- [Multi-Node Cluster Expansion Guide](setup/multi-node-cluster-expansion.md) - Complete onboarding procedures
- [k3s2 Node Onboarding Spec](../.kiro/specs/k3s1-node-onboarding/) - Detailed requirements and implementation plan

### Integration with CI/CD

#### Pre-commit Hooks Setup
```bash
# Install pre-commit framework
pip install pre-commit

# Install hooks
pre-commit install

# Manual validation
pre-commit run --all-files
```

#### Git Hook Configuration
```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: validate-kustomizations
        name: Validate Kustomizations
        entry: ./scripts/validate-kustomizations.sh
        language: script
        pass_filenames: false
      - id: check-immutable-fields
        name: Check Immutable Fields
        entry: ./scripts/check-immutable-fields.sh
        language: script
        pass_filenames: false
```

## GitOps Implementation

### 1. Flux CD Health Check
```bash
flux check
flux get all -A
```

### 2. Resource Protection
```yaml
# Add to critical resources
metadata:
  annotations:
    fluxcd.io/ignore: "false"
    reconcile.fluxcd.io/ignore: "false"
```

### 3. Semantic Versioning
```yaml
# In HelmRelease
spec:
  chart:
    spec:
      version: "1.5.x"  # Use exact or patch version
```

## Security Enhancements

### 1. Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: longhorn-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 2. Enable Audit Logging
```yaml
# In k3s server config
apiServer:
  audit-policy-file: /etc/rancher/k3s/audit-policy.yaml
  audit-log-path: /var/lib/rancher/k3s/server/logs/audit.log
  audit-log-maxage: 30
  audit-log-maxbackup: 10
  audit-log-maxsize: 100
```

## Monitoring & Observability

### 1. Hybrid Monitoring Architecture (✅ Completed)

**Design**: Bulletproof core monitoring + optional long-term storage

```
Core Tier (Always Available)     │  Long-term Tier (Optional)
├─ Prometheus Core (2h retention) │  ├─ Prometheus LT (30d retention)
│  └─ emptyDir storage            │  │  └─ Longhorn storage
├─ Grafana Core (ephemeral)       │  ├─ Grafana LT (persistent)
│  └─ Essential dashboards        │  │  └─ Full feature dashboards
└─ Optimized Flux PodMonitor      │  └─ Alertmanager
```

**Deployment Steps**:
```bash
# 1. Clean up any stuck monitoring resources (comprehensive automation)
./scripts/cleanup-stuck-monitoring.sh

# 2. Deploy core monitoring (bulletproof)
flux reconcile kustomization monitoring -n flux-system

# 3. Verify core monitoring health (automated assessment)
./scripts/monitoring-health-assessment.sh

# 4. (Optional) Enable long-term monitoring when Longhorn is stable
# Edit infrastructure/monitoring/kustomization.yaml
# Uncomment: - longterm/
```

**Benefits**:
- ✅ **Bulletproof**: Core monitoring survives storage failures
- ✅ **Fast recovery**: Ephemeral storage enables quick restarts
- ✅ **Automated cleanup**: Comprehensive monitoring cleanup with interactive confirmation
- ✅ **Optimized metrics**: PodMonitor with advanced filtering for all Flux controllers
- ✅ **Remote access**: Validated Tailscale remote access procedures
- ✅ **Alert rules**: Comprehensive PrometheusRule resources for stuck reconciliation detection
- ✅ **KubeVirt ready**: Storage architecture prepared for VM workloads

### 2. Monitoring System Maintenance (✅ Completed)

**Automated Cleanup Tools**:
```bash
# Comprehensive monitoring cleanup with multiple modes
./scripts/cleanup-stuck-monitoring.sh                    # Interactive cleanup
./scripts/cleanup-stuck-monitoring.sh assess             # Assessment only
./scripts/cleanup-stuck-monitoring.sh detect             # Detect stuck resources
./scripts/cleanup-stuck-monitoring.sh namespace          # Clean namespace only
./scripts/cleanup-stuck-monitoring.sh comprehensive      # Full cleanup

# Health assessment with detailed reporting
./scripts/monitoring-health-assessment.sh
```

**Features**:
- ✅ **Interactive confirmation** before cleanup operations
- ✅ **Stuck resource detection** with automatic identification
- ✅ **HelmRelease suspension/resumption** for safe cleanup
- ✅ **Comprehensive logging** with timestamped operations
- ✅ **Health assessment** with color-coded status indicators

### 3. Alert Rules for GitOps Resilience (Completed)

**Status**: ✅ **Implemented** - Comprehensive PrometheusRule resources deployed

**Alert Coverage**:
- **Flux Reconciliation**: Stuck Kustomizations, HelmReleases, GitRepositories
- **Controller Health**: Down controllers, high error rates, performance issues
- **GitOps Resilience**: Stuck resource termination, deployment rollouts, conflicts
- **System Health**: Overall GitOps system degradation detection

**Key Files**:
- `infrastructure/monitoring/core/flux-alerts.yaml` - Core Flux alerts
- `infrastructure/monitoring/core/gitops-resilience-alerts.yaml` - Resilience patterns
- `docs/monitoring/flux-alerting-strategy.md` - Comprehensive documentation

**Verification**:
```bash
# Check alert rules are loaded
kubectl get prometheusrule -n monitoring

# View active alerts
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090
# Navigate to http://localhost:9090/alerts
```

### 4. Configure Longhorn Metrics
```yaml
# In Longhorn values.yaml
defaultSettings:
  metricsServer: "http://monitoring-core-prometheus-core-prometheus:9090"
```

## Backup & Recovery

### 1. Install Velero
```bash
# Install Velero CLI
brew install velero

# Install Velero in cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.2.1 \
  --bucket my-velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio:9000
```

## Documentation

### 1. Network Architecture
- Update network diagram
- Document service dependencies
- Document access patterns

### 2. Runbooks
- Service recovery procedures
- Backup/restore procedures
- Troubleshooting guides

## Long-term Improvements

### 1. Progressive Delivery
- Implement Flagger for canary deployments
- Set up automated rollback on failure

### 2. Multi-cluster Management
- Set up Fleet for multi-cluster management
- Implement cluster API for provisioning

### 3. Policy as Code
- Implement OPA/Gatekeeper
- Define and enforce policies

## Next Steps
1. [ ] Implement port-forwarding workaround
2. [ ] Verify NGINX Ingress accessibility
3. [ ] Check network connectivity between components
4. [ ] Implement GitOps best practices
5. [ ] Set up monitoring and alerting
6. [ ] Document network architecture
7. [ ] Implement security enhancements
8. [ ] Set up backup solution
9. [ ] Document operational procedures
