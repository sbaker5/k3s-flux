# Dependency-Aware Update Ordering

This document describes the dependency-aware update orchestrator that analyzes resource dependencies and orders updates with proper sequencing to prevent conflicts and ensure safe resource lifecycle management.

## Overview

The Update Orchestrator implements task 5.3 from the GitOps Resilience Patterns specification, providing:

- **Dependency Analysis**: Automatically discovers resource dependencies from various sources
- **Update Ordering**: Creates batches of updates that respect dependency relationships
- **Multiple Strategies**: Supports different update strategies (rolling, recreate, blue-green, atomic)
- **Safe Execution**: Validates updates before execution and provides rollback capabilities
- **Monitoring**: Integrates with Prometheus for metrics and observability

## Architecture

### Components

1. **DependencyAnalyzer**: Analyzes Kubernetes resources to build dependency graphs
2. **UpdateOrchestrator**: Main orchestrator that plans and executes updates
3. **CLI Tool**: Command-line interface for interactive use
4. **Kubernetes Controller**: Deployed controller for automated operations

### Dependency Detection

The system detects dependencies from multiple sources:

#### Owner References
```yaml
metadata:
  ownerReferences:
  - apiVersion: apps/v1
    kind: Deployment
    name: parent-deployment
```

#### Spec References
- ConfigMap and Secret references in environment variables
- Volume mounts referencing ConfigMaps, Secrets, and PVCs
- Service references in Ingress rules

#### Annotation-Based Dependencies
```yaml
metadata:
  annotations:
    # Custom dependency annotation
    gitops.flux.io/depends-on: "ConfigMap/app-config,Secret/app-secrets"
    
    # Flux dependency annotation
    kustomize.toolkit.fluxcd.io/depends-on: "namespace/kustomization-name"
    
    # Priority weight for ordering within batches
    gitops.flux.io/dependency-weight: "10"
```

## Update Strategies

### Rolling Update
- **Used for**: Deployments, StatefulSets, DaemonSets
- **Behavior**: Uses Kubernetes rolling update mechanism
- **Safety**: Maintains availability during updates

### Recreate
- **Used for**: Services (immutable ClusterIP), Jobs, Pods
- **Behavior**: Deletes existing resource and creates new one
- **Safety**: Brief downtime but ensures clean state

### Atomic
- **Used for**: ConfigMaps, Secrets, simple resources
- **Behavior**: Direct kubectl apply
- **Safety**: Fast updates with minimal risk

### Blue-Green (Future)
- **Used for**: Complex scenarios requiring zero downtime
- **Behavior**: Creates new version alongside old, then switches
- **Safety**: Zero downtime with instant rollback capability

## Usage

### CLI Tool

The `scripts/update-orchestrator.sh` script provides a command-line interface:

#### Plan Updates
```bash
# Plan updates for a directory of resources
./scripts/update-orchestrator.sh plan infrastructure/monitoring/

# Plan with dry-run (validation only)
./scripts/update-orchestrator.sh plan --dry-run apps/example-app/
```

#### Execute Updates
```bash
# Execute a previously created plan
./scripts/update-orchestrator.sh execute /tmp/update-orchestrator/plan-*.json
```

#### Analyze Dependencies
```bash
# Analyze dependencies without planning updates
./scripts/update-orchestrator.sh analyze clusters/k3s-flux/

# Analyze with specific output format
./scripts/update-orchestrator.sh analyze --output json infrastructure/
```

#### Validate Resources
```bash
# Validate resources without executing updates
./scripts/update-orchestrator.sh validate infrastructure/core/
```

#### Monitor Status
```bash
# Show current orchestrator status
./scripts/update-orchestrator.sh status

# Show configuration
./scripts/update-orchestrator.sh config
```

#### Rollback
```bash
# Rollback the last update operation
./scripts/update-orchestrator.sh rollback
```

### Python API

Direct usage of the Python orchestrator:

```python
from update_orchestrator import UpdateOrchestrator
import asyncio

async def main():
    # Create orchestrator
    orchestrator = UpdateOrchestrator(
        config_path='config.yaml'
    )
    
    # Load resources (from files, cluster, etc.)
    resources = [...]  # List of Kubernetes resource dictionaries
    
    # Plan updates
    batches = await orchestrator.plan_updates(resources, dry_run=True)
    
    # Show plan
    for batch in batches:
        print(f"Batch {batch.batch_id}: {len(batch.operations)} operations")
    
    # Execute updates
    success = await orchestrator.execute_updates()
    
    # Get status report
    report = orchestrator.get_status_report()
    print(f"Status: {report}")

# Run
asyncio.run(main())
```

## Configuration

The orchestrator is configured via `infrastructure/recovery/update-orchestrator-config.yaml`:

### Key Configuration Options

```yaml
# Timing configuration
batch_timeout: 600          # 10 minutes per batch
operation_timeout: 300      # 5 minutes per operation
max_retries: 3              # Maximum retry attempts

# Execution configuration
parallel_batches: false     # Execute batches sequentially for safety
validation_enabled: true    # Enable pre-execution validation
rollback_on_failure: true   # Rollback on batch failure

# Update strategies by resource type
strategies:
  Deployment: "rolling"
  StatefulSet: "rolling"
  Service: "recreate"        # ClusterIP is immutable
  ConfigMap: "atomic"
  Secret: "atomic"

# Resource priorities (higher = updated first within batch)
priorities:
  Namespace: 100
  ConfigMap: 70
  Secret: 70
  Service: 50
  Deployment: 40
```

## Deployment

### Kubernetes Controller

The orchestrator can be deployed as a Kubernetes controller:

```bash
# Deploy the orchestrator
kubectl apply -k infrastructure/recovery/

# Check deployment status
kubectl get pods -n flux-recovery -l app=update-orchestrator

# View logs
kubectl logs -n flux-recovery -l app=update-orchestrator -f
```

### Monitoring

The orchestrator exposes Prometheus metrics:

- `update_operations_total`: Total number of update operations
- `update_operations_duration_seconds`: Duration of update operations
- `update_batches_total`: Total number of update batches
- `update_failures_total`: Total number of failed updates
- `dependency_analysis_duration_seconds`: Time spent analyzing dependencies

## Safety Features

### Pre-execution Validation
- **Dry-run validation**: Uses `kubectl apply --dry-run` to validate resources
- **Dependency checking**: Ensures dependencies are ready before execution
- **Resource existence**: Verifies resources exist before attempting updates

### Rollback Capabilities
- **Automatic rollback**: Rolls back completed updates if a batch fails
- **Manual rollback**: CLI command to rollback the last operation
- **State tracking**: Maintains state to enable safe rollback operations

### Error Handling
- **Retry logic**: Configurable retry attempts with exponential backoff
- **Timeout handling**: Prevents operations from hanging indefinitely
- **Graceful degradation**: Continues with remaining operations when possible

## Testing

### Automated Tests

Run the test suite to validate functionality:

```bash
# Run all tests
./scripts/test-update-orchestrator.sh

# The test creates resources with various dependency patterns:
# - ConfigMap (no dependencies)
# - Secret (no dependencies)  
# - Service (no dependencies)
# - Deployment (depends on ConfigMap and Secret)
# - Ingress (depends on Service)
# - Job (depends on ConfigMap and Secret)
```

### Manual Testing

1. **Create test resources** with dependency annotations
2. **Run dependency analysis** to verify detection
3. **Plan updates** to check ordering
4. **Execute with dry-run** to validate safety
5. **Monitor execution** to verify proper sequencing

## Integration with GitOps

### Flux Integration

The orchestrator integrates with Flux CD:

```yaml
# Kustomization with dependency-aware updates
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-with-ordering
  annotations:
    gitops.flux.io/update-orchestrator: "enabled"
spec:
  # ... standard Kustomization spec
```

### Pre-commit Integration

Add to `.pre-commit-config.yaml`:

```yaml
repos:
- repo: local
  hooks:
  - id: update-orchestrator-validate
    name: Validate update ordering
    entry: ./scripts/update-orchestrator.sh validate
    language: script
    files: \.(yaml|yml)$
```

## Troubleshooting

### Common Issues

#### Circular Dependencies
```
Error: Circular dependencies detected for resources: [...]
```
**Solution**: Review dependency annotations and remove circular references

#### Timeout Errors
```
Error: Operation timeout for resource Deployment/app
```
**Solution**: Increase timeout in configuration or check resource health

#### Validation Failures
```
Error: Dry-run validation failed for resource
```
**Solution**: Fix resource definition or check cluster state

### Debug Mode

Enable verbose logging:

```bash
# CLI with verbose output
./scripts/update-orchestrator.sh plan --verbose infrastructure/

# Python with debug logging
export LOG_LEVEL=DEBUG
python3 infrastructure/recovery/update-orchestrator.py
```

### Monitoring

Check orchestrator metrics in Grafana:
- Update operation success/failure rates
- Dependency analysis performance
- Batch execution timing
- Resource update patterns

## Best Practices

### Dependency Annotations

1. **Be explicit**: Use dependency annotations for critical relationships
2. **Use weights**: Set priority weights for ordering within batches
3. **Avoid cycles**: Review dependency graphs to prevent circular dependencies

### Update Strategies

1. **Match resource types**: Use appropriate strategies for each resource type
2. **Consider downtime**: Use recreate strategy only when downtime is acceptable
3. **Test thoroughly**: Validate update plans with dry-run before execution

### Configuration

1. **Environment-specific**: Use different configurations for dev/staging/prod
2. **Conservative timeouts**: Set generous timeouts for production
3. **Enable rollback**: Always enable rollback in production environments

### Monitoring

1. **Track metrics**: Monitor update success rates and timing
2. **Set alerts**: Alert on failed updates or long-running operations
3. **Review logs**: Regularly review orchestrator logs for issues

## Requirements Addressed

This implementation addresses the following requirements from the GitOps Resilience Patterns specification:

- **Requirement 2.3**: "WHEN dependencies exist between resources THEN update order SHALL be controlled and validated"
- **Requirement 6.2**: "WHEN multi-resource updates are required THEN transaction-like behavior SHALL be implemented"

The system provides:
- ✅ Dependency analysis and ordering
- ✅ Controlled update sequencing
- ✅ Validation before execution
- ✅ Transaction-like batch behavior
- ✅ Rollback capabilities
- ✅ Multiple update strategies
- ✅ Monitoring and observability