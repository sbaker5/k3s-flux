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

### 🚧 In Progress Components

#### 1. Reconciliation Health Monitoring
**Target**: Hybrid monitoring architecture with bulletproof core and optional persistent storage

**Planned Features**:
- **Hybrid Storage Architecture**: Ephemeral core monitoring (emptyDir) + optional long-term storage (Longhorn)
- **Bulletproof Design**: Core monitoring remains operational during storage failures
- **ServiceMonitor for Flux controllers**: Comprehensive metrics collection
- **PrometheusRule for stuck reconciliations**: Automated alerting for failed reconciliations
- **Grafana dashboards**: Immediate visibility (core) + historical analysis (long-term)
- **KubeVirt Preparation**: Storage tier design ready for future VM workloads

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

#### 2. Automated Recovery System
**Target**: Pattern-based recovery automation for common failure scenarios

**Planned Features**:
- Error pattern detection and classification
- Automated resource recreation for immutable field conflicts
- HelmRelease rollback procedures
- Dependency-aware cleanup and recovery
- Recovery state tracking and retry logic

**Configuration**:
```yaml
# Recovery automation configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: flux-recovery-config
data:
  recovery-patterns.yaml: |
    patterns:
    - error_pattern: "field is immutable"
      recovery_action: "recreate_resource"
      max_retries: 3
      applies_to: ["Deployment", "Service", "StatefulSet"]
    - error_pattern: "dry-run failed.*Invalid.*spec.selector"
      recovery_action: "recreate_deployment"
      cleanup_dependencies: true
    - error_pattern: "HelmRelease.*failed.*upgrade"
      recovery_action: "rollback_helm_release"
      max_retries: 2
```

#### 3. Resource Lifecycle Management
**Target**: Blue-green deployment patterns for immutable resources

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

```yaml
groups:
- name: gitops-resilience
  rules:
  - alert: FluxReconciliationStuck
    expr: (time() - flux_kustomization_last_applied_revision_timestamp) > 300
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Flux reconciliation stuck"
      description: "Kustomization {{ $labels.name }} stuck for > 5 minutes"
  
  - alert: ImmutableFieldConflict
    expr: increase(flux_kustomization_reconcile_errors_total[5m]) > 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Potential immutable field conflict"
      description: "Reconciliation errors may indicate immutable field conflicts"
```

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

## Future Enhancements

### Phase 1: Advanced Monitoring (Q1 2024)
- Comprehensive Grafana dashboards
- Advanced alerting with escalation
- Performance metrics and SLI/SLO tracking

### Phase 2: Automated Recovery (Q2 2024)
- Kubernetes controller for recovery automation
- Pattern-based error classification
- Automated resource lifecycle management

### Phase 3: Advanced Deployment Patterns (Q3 2024)
- Canary deployments for infrastructure
- Progressive delivery with validation gates
- Multi-cluster resilience patterns

### Phase 4: Operational Excellence (Q4 2024)
- Chaos engineering test suite
- Continuous resilience validation
- Knowledge base automation

## References

- [GitOps Resilience Patterns Specification](.kiro/specs/gitops-resilience-patterns/)
- [Flux Recovery Guide](troubleshooting/flux-recovery-guide.md)
- [Validation Scripts Documentation](../scripts/README.md)
- [Implementation Plan](implementation-plan.md#gitops-resilience-patterns)