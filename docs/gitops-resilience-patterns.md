# GitOps Resilience Patterns

This document describes the comprehensive resilience system implemented to prevent infrastructure lock-ups, automate recovery from stuck states, and ensure smooth infrastructure evolution in our k3s GitOps environment.

## Overview

The GitOps Resilience Patterns system addresses critical challenges in Kubernetes GitOps deployments:

- **Immutable Field Conflicts**: Preventing reconciliation failures from field changes that require resource recreation
- **Stuck Reconciliations**: Automated detection and recovery from hung Flux reconciliation states
- **Resource Dependencies**: Managing complex dependency chains during updates
- **Change Validation**: Pre-deployment validation to catch breaking changes early
- **Emergency Recovery**: Well-defined procedures for manual intervention when automation fails

## Current Implementation Status

### ✅ Completed Components

#### 1. Pre-commit Validation Infrastructure
**Location**: `scripts/validate-kustomizations.sh`

Validates that all kustomization.yaml files can build successfully before commits reach the cluster.

**Features**:
- Validates 9+ kustomization directories
- Catches YAML syntax errors, missing resources, invalid configurations
- Integrates with Git pre-commit hooks
- Zero-dependency validation (only requires kubectl)

**Usage**:
```bash
# Manual validation
./scripts/validate-kustomizations.sh

# Install as pre-commit hook
pre-commit install
```

#### 2. Immutable Field Conflict Detection
**Location**: `scripts/check-immutable-fields.sh`

Advanced tool that detects changes to immutable Kubernetes fields between Git revisions that would cause reconciliation failures.

**Supported Resource Types**:
- **Deployment**: `spec.selector`
- **Service**: `spec.clusterIP`, `spec.type`, `spec.ports[].nodePort`
- **StatefulSet**: `spec.selector`, `spec.serviceName`, `spec.volumeClaimTemplates[].metadata.name`
- **Job**: `spec.selector`, `spec.template`
- **PersistentVolume**: `spec.capacity`, `spec.accessModes`, `spec.persistentVolumeReclaimPolicy`
- **PersistentVolumeClaim**: `spec.accessModes`, `spec.resources.requests.storage`, `spec.storageClassName`
- **Ingress**: `spec.ingressClassName`
- **NetworkPolicy**: `spec.podSelector`
- **ServiceAccount**: `automountServiceAccountToken`
- **Secret**: `type`
- **ConfigMap**: `immutable`

**Usage**:
```bash
# Check changes between HEAD~1 and HEAD (default)
./scripts/check-immutable-fields.sh

# Check changes between specific branches
./scripts/check-immutable-fields.sh -b main -h feature-branch

# Enable verbose output
./scripts/check-immutable-fields.sh -v
```

#### 3. Emergency Recovery Procedures
**Location**: `docs/troubleshooting/flux-recovery-guide.md`

Comprehensive troubleshooting guide covering:
- Namespace stuck states and finalizer removal
- Authentication failures and token refresh
- Controller recovery and restart procedures
- Resource cleanup and force deletion
- Escalation procedures and verification checklists

### ✅ Completed Monitoring Infrastructure

#### 1. Reconciliation Health Monitoring
**Status**: ✅ **Complete hybrid monitoring architecture implemented**

**Implemented Features**:
- **Hybrid Storage Architecture**: ✅ Ephemeral core monitoring (emptyDir) + optional long-term storage (Longhorn)
- **Bulletproof Design**: ✅ Core monitoring remains operational during storage failures
- **Hybrid Flux Monitoring**: ✅ ServiceMonitor + PodMonitor for comprehensive Flux controller metrics collection
- **Alert Rules for Stuck Reconciliations**: ✅ Comprehensive PrometheusRule resources for proactive detection
- **KubeVirt Preparation**: ✅ Storage tier design ready for future VM workloads
- **Cleanup Automation**: ✅ Automated cleanup of stuck monitoring resources and PVCs

#### 2. GitOps Health Monitoring Dashboard
**Status**: ✅ **Grafana dashboard fully integrated**

**Architecture**:
```
Core Tier (Always Available)     │  Long-term Tier (Optional)
├─ Prometheus Core (2h retention) │  ├─ Prometheus LT (30d retention)
│  └─ emptyDir storage            │  │  └─ Longhorn storage
├─ Grafana Core (ephemeral)       │  ├─ Grafana LT (persistent)
│  └─ Essential dashboards        │  │  └─ Full feature dashboards
└─ Node/KSM exporters             │  └─ Alertmanager
```

**Usage**:
```bash
# Deploy hybrid monitoring
flux reconcile kustomization monitoring -n flux-system

# Access core monitoring
kubectl port-forward -n monitoring svc/monitoring-core-grafana-core 3000:80

# Clean up stuck resources if needed
./scripts/cleanup-stuck-monitoring.sh
```

**Dashboard Features**:
- **GitOps Health Dashboard**: ✅ Comprehensive Grafana dashboard for Flux reconciliation visibility
- **Performance Tracking**: ✅ Panels for reconciliation timing, error rates, and resource status
- **Hybrid Integration**: ✅ Works with both ephemeral core and persistent long-term monitoring
- **Alert Integration**: ✅ Dashboard panels linked to PrometheusRule alerts
- **Operational Visibility**: ✅ Real-time monitoring of GitOps system health

### 🚧 In Progress Components

#### 1. System State Backup and Restore Capabilities (Task 4.3)
**Status**: 🚧 **In Progress** - Automated backup of Flux configurations and cluster state

**Planned Features**:
- Automated backup of Flux configurations and cluster state
- Restore procedures for critical system components
- Longhorn volume backup integration
- Encrypted backup storage with SOPS integration

#### 2. Automated Recovery System Integration
**Status**: ✅ **Complete** - Individual components complete, overall system integration operational

**Current State**:
- ✅ **Detection Controller**: Fully implemented with 20+ error patterns
- ✅ **Event Monitoring**: Real-time Kubernetes event watching with correlation
- ✅ **Pattern Classification**: Advanced pattern matching with confidence scoring
- ✅ **Testing Infrastructure**: Comprehensive test suite with multiple validation scripts
- ✅ **Operational Documentation**: Complete testing guide and troubleshooting procedures
- ✅ **Recovery Integration**: Detection system fully connected to automated recovery actions
- ✅ **Recovery Automation**: Complete system integration with comprehensive testing suite
- ✅ **System Integration**: Overall system integration completed and operational

#### 3. Code Quality and Documentation Improvements
**Status**: 🔄 **Continuous improvement of existing validation infrastructure**

**Planned Improvements**:
- **Documentation Accuracy**: Fix inconsistent validation step descriptions between docs and implementation
- **Script Robustness**: Standardize error handling patterns and improve temporary file cleanup
- **Dependency Detection**: Enhance dependency checking with clear impact explanations and installation hints
- **Performance Optimization**: Add parallel processing options and configurable job limits
- **Error Message Quality**: Replace generic errors with specific, actionable guidance
- **Architecture Strengthening**: Implement consistent logging framework and configuration file support

**Implementation**:
```yaml
# Monitoring configuration
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: flux-reconciliation-health
spec:
  groups:
  - name: flux.reconciliation
    rules:
    - alert: FluxKustomizationStuck
      expr: |
        (time() - flux_kustomization_last_applied_revision_timestamp) > 300
        and flux_kustomization_ready == 0
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Flux kustomization {{ $labels.name }} stuck for > 5 minutes"
```

### 🚧 In Progress Components

#### 1. Error Pattern Detection System
**Status**: ✅ **Components Complete** - Advanced error pattern detection system with comprehensive monitoring

**Location**: `infrastructure/recovery/`

**Implemented Features**:
- ✅ **Error Pattern Detection Controller**: Comprehensive Python-based controller monitoring Flux events
- ✅ **Pattern Classification**: 20+ predefined error patterns with confidence scoring
- ✅ **Event Correlation**: Advanced event correlation with noise reduction and burst detection
- ✅ **Resource Health Tracking**: Comprehensive health monitoring with trend analysis
- ✅ **Recovery State Management**: Pattern match tracking with retry logic and escalation
- ✅ **Kubernetes Integration**: Full RBAC, ServiceAccount, and cluster-wide monitoring
- ✅ **Testing Infrastructure**: Comprehensive test suite for validation and troubleshooting
- ✅ **Recovery Automation**: Complete system integration with comprehensive testing suite

**Supported Error Patterns**:
- **Immutable Field Conflicts**: `field is immutable`, `spec.selector` conflicts
- **HelmRelease Issues**: Upgrade failures, install retries exhausted, timeouts
- **Kustomization Problems**: Build failures, resource not found, dependency timeouts
- **Resource Conflicts**: Version conflicts, admission webhook failures, finalizer issues
- **Infrastructure Issues**: Resource quotas, storage problems, network policies
- **Advanced Patterns**: Cascading failures, controller crash loops, authentication failures

**Deployment and Testing**:
```bash
# Deploy error pattern detection system
kubectl apply -k infrastructure/recovery/

# Check controller status
kubectl get pods -n flux-recovery -l app=error-pattern-detector

# View detected patterns
kubectl logs -n flux-recovery deployment/error-pattern-detector

# Test system functionality
./tests/validation/test-tasks-3.1-3.2.sh

# Run comprehensive validation with simulation
./tests/validation/test-pattern-simulation.sh
```

**Configuration**: 
- **Pattern Definitions**: `infrastructure/recovery/recovery-patterns-config.yaml`
- **Controller Logic**: `infrastructure/recovery/error-pattern-detector.yaml`
- **Recovery Actions**: 15+ predefined recovery procedures with configurable timeouts

#### 2. Resource Lifecycle Management
**Status**: 🚧 **In Progress** - Blue-green deployment patterns for immutable resources

**Planned Features**:
- Blue-green deployment strategies for resources with immutable fields
- Atomic resource replacement with zero downtime
- Dependency-aware update ordering
- Resource update strategy annotations

## Integration Patterns

### Pre-commit Hook Setup

1. **Install pre-commit framework**:
```bash
pip install pre-commit
```

2. **Create `.pre-commit-config.yaml`**:
```yaml
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

3. **Install hooks**:
```bash
pre-commit install
```

### CI/CD Integration

The validation scripts can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
name: Validate Infrastructure
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
      with:
        fetch-depth: 0  # Required for immutable field checking
    - name: Install kubectl
      uses: azure/setup-kubectl@v3
    - name: Validate Kustomizations
      run: ./scripts/validate-kustomizations.sh
    - name: Check Immutable Fields
      run: ./scripts/check-immutable-fields.sh
```

## Best Practices

### 1. Resource Update Strategies

**For resources with immutable fields**:
- Use blue-green deployment patterns
- Implement proper cleanup procedures
- Validate dependencies before updates

**Annotation-based strategy definition**:
```yaml
metadata:
  annotations:
    gitops.flux.io/update-strategy: "blue-green|rolling|recreate"
    gitops.flux.io/immutable-fields: "spec.selector,spec.clusterIP"
    gitops.flux.io/dependency-weight: "10"
    gitops.flux.io/recovery-policy: "auto|manual"
```

### 2. Change Validation Workflow

1. **Pre-commit validation** - Catch syntax and build errors locally
2. **Immutable field checking** - Detect breaking changes before push
3. **CI/CD validation** - Automated testing in pipeline
4. **Staged deployment** - Gradual rollout with validation gates
5. **Health monitoring** - Continuous reconciliation state tracking

### 3. Recovery Procedures

**Automated Recovery Triggers**:
- Reconciliation stuck for > 5 minutes
- Immutable field error patterns detected
- HelmRelease upgrade failures
- Resource dependency conflicts

**Manual Intervention Scenarios**:
- Automated recovery fails after max retries
- Critical system components affected
- Data integrity concerns
- Complex dependency conflicts

## Monitoring and Alerting

### Key Metrics to Monitor

1. **Reconciliation Timing**:
   - `flux_kustomization_last_applied_revision_timestamp`
   - `flux_kustomization_reconcile_duration_seconds`

2. **Error Rates**:
   - `flux_kustomization_reconcile_errors_total`
   - `flux_helmrelease_reconcile_errors_total`

3. **Resource Health**:
   - `flux_kustomization_ready`
   - `flux_helmrelease_ready`

### Alert Rules

**Status**: ✅ **Completed** - Comprehensive PrometheusRule resources implemented

**Location**: 
- `infrastructure/monitoring/core/flux-alerts.yaml` - Core Flux reconciliation alerts
- `infrastructure/monitoring/core/gitops-resilience-alerts.yaml` - GitOps resilience pattern alerts

**Key Alert Rules**:

#### Flux Reconciliation Monitoring
- `FluxKustomizationStuck` - Detects stuck Kustomization reconciliations (>10min)
- `FluxHelmReleaseStuck` - Detects stuck HelmRelease reconciliations (>10min)  
- `FluxGitRepositoryStuck` - Detects stuck Git source reconciliations (>5min)
- `FluxHighReconciliationErrorRate` - High error rate detection (>10%)
- `FluxControllerDown` - Controller availability monitoring
- `FluxSystemDegraded` - System-wide health monitoring (>20% failure rate)

#### GitOps Resilience Patterns
- `GitOpsResourceStuckTerminating` - Detects stuck pod termination (>5min)
- `GitOpsNamespaceStuckTerminating` - Critical namespace termination issues (>10min)
- `GitOpsDeploymentRolloutStuck` - Stuck deployment rollouts (>10min)
- `GitOpsResourceConflict` - Resource management conflicts
- `GitOpsCRDMissing` - Missing Custom Resource Definitions
- `GitOpsPerformanceDegraded` - Slow reconciliation detection (95th percentile >60s)

**Documentation**: See [Flux Alerting Strategy](monitoring/flux-alerting-strategy.md) for comprehensive alert configuration details and troubleshooting procedures.

## Testing and Validation

### Comprehensive Testing Suite

The GitOps resilience patterns include a comprehensive testing infrastructure for validating Tasks 3.1 (Error Pattern Detection) and 3.2 (Resource Recreation Automation).

#### Quick Validation Commands
```bash
# Test Tasks 3.1 & 3.2 status
./tests/validation/test-tasks-3.1-3.2.sh

# Comprehensive error pattern testing
./tests/validation/test-pattern-simulation.sh

# Runtime functionality validation
./tests/validation/test-error-pattern-runtime.sh

# Health check after system disruptions
./tests/validation/post-outage-health-check.sh
```

#### Test Categories
- **Configuration Tests**: Validate YAML syntax, Kustomization builds, recovery patterns
- **Runtime Tests**: Verify active monitoring, pod health, event processing
- **Integration Tests**: End-to-end testing with real resource creation and error simulation
- **Health Assessment**: Comprehensive system health validation after disruptions

#### Success Indicators
- ✅ Error pattern detector pod is Running
- ✅ Configuration loaded with expected number of patterns (20+)
- ✅ Real-time Kubernetes event monitoring is active
- ✅ Recovery patterns and RBAC permissions are configured
- ✅ Pattern detection processing Flux events

See [Testing Suite Documentation](../tests/README.md) and [Error Pattern Detection Testing Guide](testing/error-pattern-detection-testing.md) for detailed usage.

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Kustomization Build Failures
**Symptoms**: Validation script fails, YAML syntax errors
**Solution**: 
```bash
# Check specific directory
kubectl kustomize apps/example-app/base/

# Fix YAML syntax and resource references
```

#### 2. Immutable Field Conflicts
**Symptoms**: "field is immutable" errors in Flux logs
**Solution**:
```bash
# Detect conflicts before deployment
./scripts/check-immutable-fields.sh

# Use resource recreation strategy
kubectl delete deployment example-app
kubectl apply -f new-deployment.yaml
```

#### 3. Stuck Reconciliations
**Symptoms**: Kustomization shows "Progressing" for extended periods
**Solution**: See `docs/troubleshooting/flux-recovery-guide.md`

#### 4. Error Pattern Detection Issues
**Symptoms**: Pattern detector pod not running or no activity in logs
**Solution**:
```bash
# Check pod status
kubectl get pods -n flux-recovery -l app=error-pattern-detector

# View logs for troubleshooting
kubectl logs -n flux-recovery deployment/error-pattern-detector

# Run diagnostic tests
./tests/validation/test-error-pattern-runtime.sh

# Restart if needed
kubectl rollout restart deployment error-pattern-detector -n flux-recovery
```

## Future Enhancements

### Phase 1: Core Infrastructure (✅ Completed)
- ✅ Pre-commit validation infrastructure
- ✅ Immutable field conflict detection
- ✅ Reconciliation health monitoring with hybrid architecture
- ✅ Alert rules for stuck reconciliations
- ✅ GitOps health monitoring dashboard
- ✅ Emergency recovery procedures and tooling
- ✅ Error pattern detection system
- ✅ Automated recovery system integration

### Phase 2: Advanced Lifecycle Management (🚧 Planned)
- 🚧 **Resource lifecycle management patterns** (Tasks 5.1-5.4)
  - Blue-green deployment strategies for immutable resources
  - Atomic resource replacement tooling
  - Dependency-aware update ordering
  - Resource update strategy annotation framework

### Phase 3: Impact Analysis and Validation (🚧 Planned)
- 🚧 **Change impact analysis system** (Tasks 6.2-6.4, 6.1 complete)
  - Breaking change detection
  - Cascade effect analysis
  - Risk assessment automation
- 🚧 **Staged deployment validation pipeline** (Tasks 7.1-7.4)
  - Dry-run testing automation
  - Compatibility validation system
  - Staged rollout controller
  - Validation gate system

### Phase 4: State Consistency and Testing (🚧 Planned)
- 🚧 **Resource state consistency mechanisms** (Tasks 8.1-8.4)
  - Atomic operation patterns
  - State consistency validation tools
  - Conflict resolution system
  - State repair automation
- 🚧 **Comprehensive testing and validation framework** (Tasks 9.1-9.4)
  - Chaos engineering test suite
  - Automated recovery testing
  - End-to-end reconciliation tests
  - Performance testing for failure conditions

### Phase 5: Operational Excellence (🔄 Continuous)
- 🔄 **Code quality and documentation improvements**
- 🔄 **Continuous improvement feedback collection**
- 🔄 **SLI/SLO tracking and alerting refinement**

## References

- [GitOps Resilience Patterns Specification](.kiro/specs/gitops-resilience-patterns/)
- [Flux Recovery Guide](troubleshooting/flux-recovery-guide.md)
- [Validation Scripts Documentation](../scripts/README.md)
- [Implementation Plan](implementation-plan.md#gitops-resilience-patterns)