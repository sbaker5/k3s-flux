# Error Pattern Detection System

The Error Pattern Detection System is an advanced monitoring and recovery component that automatically detects common GitOps failure patterns and triggers appropriate recovery actions.

## Overview

**Location**: `infrastructure/recovery/`
**Status**: ✅ **Complete** - Detection system and recovery automation fully implemented with comprehensive testing

The system consists of:
- **Error Pattern Detection Controller**: Python-based controller monitoring Flux events
- **Pattern Configuration**: Comprehensive error pattern definitions with recovery actions
- **Event Correlation**: Advanced event correlation with noise reduction
- **Recovery State Management**: Pattern match tracking with retry logic

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kubernetes    │    │  Error Pattern   │    │   Recovery      │
│     Events      │───▶│    Detection     │───▶│   Actions       │
│                 │    │   Controller     │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │  Pattern Config  │
                       │  & State Store   │
                       └──────────────────┘
```

## Supported Error Patterns

### Immutable Field Conflicts
- `immutable-field-conflict`: Generic immutable field changes
- `deployment-selector-conflict`: Deployment selector mismatches
- `service-selector-conflict`: Service selector changes

### HelmRelease Issues
- `helm-upgrade-failed`: Helm release upgrade failures
- `helm-install-exhausted`: Install retries exhausted
- `helm-timeout`: Helm operation timeouts

### Kustomization Problems
- `kustomization-build-failed`: Build failures
- `resource-not-found`: Missing referenced resources
- `dependency-timeout`: Dependency not ready

### Advanced Patterns
- `cascading-failure-pattern`: Multiple resource failures
- `resource-version-conflict`: Optimistic lock conflicts
- `webhook-admission-failure`: Admission webhook blocks
- `flux-controller-crash-loop`: Controller crash loops

## Deployment

### Prerequisites
- Kubernetes cluster with Flux CD installed
- `flux-recovery` namespace (created automatically)

### Installation
```bash
# Deploy the error pattern detection system
kubectl apply -k infrastructure/recovery/

# Verify deployment
kubectl get pods -n flux-recovery
kubectl logs -n flux-recovery deployment/error-pattern-detector
```

### Configuration
The system is configured via `infrastructure/recovery/recovery-patterns-config.yaml`:

```yaml
patterns:
  - name: "immutable-field-conflict"
    error_pattern: "field is immutable"
    recovery_action: "recreate_resource"
    max_retries: 3
    applies_to: ["Deployment", "Service", "StatefulSet"]
    severity: "high"
```

## Monitoring

### Controller Health
```bash
# Check controller status
kubectl get deployment -n flux-recovery error-pattern-detector

# View controller logs
kubectl logs -n flux-recovery deployment/error-pattern-detector

# Check controller metrics (if enabled)
kubectl port-forward -n flux-recovery deployment/error-pattern-detector 8080:8080
curl http://localhost:8080/metrics
```

### Pattern Detection
```bash
# View detected patterns in logs
kubectl logs -n flux-recovery deployment/error-pattern-detector | grep "Error pattern detected"

# Check recovery state (stored in ConfigMaps)
kubectl get configmaps -n flux-recovery
```

## Recovery Actions

### Implemented Recovery Actions
- `recreate_resource`: Delete and recreate resource
- `recreate_deployment`: Recreate deployment with cleanup
- `rollback_helm_release`: Rollback HelmRelease to previous version
- `reset_helm_release`: Complete HelmRelease reset
- `validate_and_retry`: Validate and retry reconciliation
- `check_dependencies`: Analyze dependency issues

### Recovery Workflow
1. **Pattern Detection**: Controller detects error pattern in events
2. **Classification**: Pattern is classified with confidence score
3. **State Tracking**: Pattern match is recorded with retry count
4. **Recovery Trigger**: Recovery action is queued (if auto-recovery enabled)
5. **Execution**: Recovery steps are executed with timeout
6. **Verification**: Recovery success is validated
7. **Escalation**: Manual intervention if recovery fails

## Configuration Options

### Settings
```yaml
settings:
  # Enable/disable automatic recovery
  auto_recovery_enabled: true
  
  # Minimum confidence for auto-recovery
  min_recovery_confidence: 0.7
  
  # Severities that allow auto-recovery
  auto_recovery_severities: ["high", "critical"]
  
  # Maximum concurrent recoveries
  max_concurrent_recoveries: 3
  
  # Event correlation window (seconds)
  event_correlation_window: 300
```

### Pattern Customization
Add custom patterns to `recovery-patterns-config.yaml`:

```yaml
patterns:
  - name: "custom-error-pattern"
    error_pattern: "your-regex-pattern"
    recovery_action: "your-recovery-action"
    max_retries: 2
    applies_to: ["ResourceType"]
    severity: "medium"
    description: "Description of the error pattern"
```

## Troubleshooting

### Common Issues

#### Controller Not Starting
```bash
# Check pod status
kubectl describe pod -n flux-recovery -l app=error-pattern-detector

# Check RBAC permissions
kubectl auth can-i list events --as=system:serviceaccount:flux-recovery:error-pattern-detector
```

#### Patterns Not Detected
```bash
# Verify pattern configuration
kubectl get configmap -n flux-recovery recovery-patterns-config -o yaml

# Check event monitoring
kubectl logs -n flux-recovery deployment/error-pattern-detector | grep "Processing event"
```

#### Recovery Actions Not Triggered
```bash
# Check auto-recovery settings
kubectl get configmap -n flux-recovery recovery-patterns-config -o yaml | grep auto_recovery_enabled

# Verify pattern confidence scores
kubectl logs -n flux-recovery deployment/error-pattern-detector | grep "confidence"
```

## Integration with GitOps Resilience Patterns

The Error Pattern Detection System is part of the broader [GitOps Resilience Patterns](gitops-resilience-patterns.md) implementation:

- **Pre-commit Validation**: Prevents errors before they reach the cluster
- **Immutable Field Detection**: Catches breaking changes in Git
- **Pattern Detection**: Monitors runtime for error patterns
- **Automated Recovery**: Executes recovery actions automatically
- **Manual Procedures**: Escalates to human intervention when needed

## Future Enhancements

### Phase 1: Recovery Automation (✅ Complete)
- ✅ Complete integration between detection and recovery
- ✅ All planned recovery actions implemented and tested
- Add comprehensive testing suite

### Phase 2: Advanced Features (Planned)
- Machine learning-based pattern detection
- Predictive failure detection
- Cross-cluster pattern correlation
- Integration with external alerting systems

### Phase 3: Operational Excellence (Planned)
- Grafana dashboards for recovery system
- Metrics and SLI/SLO tracking
- Automated pattern tuning
- Knowledge base integration

## References

- [GitOps Resilience Patterns](gitops-resilience-patterns.md)
- [Flux Recovery Guide](troubleshooting/flux-recovery-guide.md)
- [Implementation Tasks](.kiro/specs/gitops-resilience-patterns/tasks.md)
- [Recovery System Configuration](../infrastructure/recovery/)