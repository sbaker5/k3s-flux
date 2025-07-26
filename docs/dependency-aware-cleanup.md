# Dependency-Aware Cleanup Procedures

## Overview

The dependency-aware cleanup system provides intelligent resource cleanup and recreation workflows that respect Kubernetes resource dependencies. This system prevents cascading failures and ensures proper ordering during recovery operations.

## Architecture

### Components

1. **Dependency Analyzer** - Discovers and maps resource dependencies
2. **Dependency Graph** - Maintains the relationship model between resources
3. **Cleanup Orchestrator** - Calculates optimal cleanup and recreation order
4. **Impact Analyzer** - Assesses the impact of resource failures

### Key Features

- **Automatic Dependency Discovery** - Scans cluster resources to build dependency graphs
- **Topological Sorting** - Calculates optimal cleanup and recreation order
- **Circular Dependency Detection** - Identifies and handles circular dependencies
- **Impact Analysis** - Assesses the blast radius of resource failures
- **Risk Assessment** - Evaluates recovery operation risk levels
- **Batch Processing** - Groups resources for parallel processing where safe

## Dependency Types

### Hard Dependencies
Resources that must be available for dependent resources to function:
- ConfigMaps/Secrets referenced by Deployments
- Services targeted by Ingress resources
- PVCs mounted by Pods

### Soft Dependencies
Preferred ordering but not strictly required:
- Monitoring resources depending on application resources
- Non-critical sidecars

### Circular Dependencies
Detected and handled through intelligent breaking:
- Temporary suspension of one resource in the cycle
- Priority-based selection of break point

## Resource Priority System

### Cleanup Priorities (Higher = Clean First)
1. **External Interfaces** (Ingress, LoadBalancer Services) - 50 points
2. **Application Services** - 30 points  
3. **Workloads** (Deployments, StatefulSets) - 20 points
4. **Configuration** (ConfigMaps, Secrets) - 10 points

### Recreation Priorities (Higher = Recreate First)
1. **Configuration** (ConfigMaps, Secrets) - 50 points
2. **Core Services** - 40 points
3. **Workloads** (Deployments, StatefulSets) - 30 points
4. **External Interfaces** (Ingress) - 20 points

### Namespace Modifiers
- **Critical Namespaces** (+25 points): flux-system, kube-system, longhorn-system
- **Application Namespaces** (base points)
- **Test Namespaces** (-10 points)

## Usage

### Automatic Operation

The dependency analyzer runs continuously and:
1. Discovers resource dependencies every 5 minutes
2. Maintains an up-to-date dependency graph
3. Responds to recovery requests from the error pattern detector
4. Generates cleanup and recreation plans automatically

### Manual Operation

You can trigger dependency analysis manually:

```bash
# Check analyzer status
kubectl get pods -n flux-recovery -l app=dependency-analyzer

# View analyzer logs
kubectl logs -n flux-recovery -l app=dependency-analyzer --tail=50

# Check dependency analysis state
kubectl get configmap dependency-analysis-state -n flux-recovery -o yaml
```

### Recovery Plan Structure

```yaml
recovery_plan:
  timestamp: "2024-01-15T10:30:00Z"
  failed_resources:
    - "default/Deployment/app"
    - "default/Service/app-service"
  
  cleanup_plan:
    total_batches: 3
    batches:
      - batch_number: 1
        resources: ["default/Ingress/app-ingress"]
        parallel_execution: true
        estimated_duration: "2-5 minutes"
      - batch_number: 2
        resources: ["default/Service/app-service"]
        parallel_execution: true
        estimated_duration: "2-5 minutes"
      - batch_number: 3
        resources: ["default/Deployment/app"]
        parallel_execution: true
        estimated_duration: "2-5 minutes"
  
  recreation_plan:
    total_batches: 3
    batches:
      - batch_number: 1
        resources: ["default/Deployment/app"]
        parallel_execution: true
        estimated_duration: "3-8 minutes"
      - batch_number: 2
        resources: ["default/Service/app-service"]
        parallel_execution: true
        estimated_duration: "3-8 minutes"
      - batch_number: 3
        resources: ["default/Ingress/app-ingress"]
        parallel_execution: true
        estimated_duration: "3-8 minutes"
  
  risk_assessment:
    level: "medium"
    factors:
      - "Medium impact: 3 resources affected"
    mitigation_required: false
    manual_oversight_recommended: false
  
  recommendations:
    - "Ensure cluster has sufficient resources before starting recovery"
    - "Monitor recovery progress and be prepared to intervene if needed"
```

## Configuration

### Analysis Settings

The dependency analyzer can be configured via the `dependency-analysis-state` ConfigMap:

```yaml
config:
  analysis_interval: 300  # 5 minutes
  dependency_cache_ttl: 1800  # 30 minutes
  max_concurrent_recoveries: 3
  enable_predictive_analysis: true
  enable_impact_scoring: true
```

### Pattern Integration

The system integrates with the error pattern detector through shared configuration:

```yaml
# In recovery-patterns-config.yaml
recovery_actions:
  recreate_with_dependencies:
    description: "Recreate resource with dependency-aware ordering"
    steps:
      - "analyze_dependencies"
      - "calculate_cleanup_order"
      - "execute_cleanup_batches"
      - "calculate_recreation_order"
      - "execute_recreation_batches"
      - "verify_recovery"
    timeout: 900
```

## Monitoring and Observability

### Metrics

The dependency analyzer exposes metrics for monitoring:

- `dependency_analysis_duration_seconds` - Time taken for dependency discovery
- `dependency_graph_resources_total` - Total resources in dependency graph
- `dependency_graph_relations_total` - Total dependency relations
- `circular_dependencies_detected_total` - Number of circular dependencies found
- `recovery_operations_total` - Total recovery operations executed
- `recovery_operation_duration_seconds` - Time taken for recovery operations

### Logs

Key log events to monitor:

```
🔍 Discovering resource dependencies...
✅ Discovered 45 resources with 67 dependencies
⚠️  Circular dependency detected: namespace/Kind/name -> namespace/Kind/name2
📋 Planning cleanup and recreation for 3 resources
📊 Recovery Plan Generated: 2 cleanup batches, 2 recreation batches
🧹 Executing cleanup batch: [namespace/Kind/name]
🔨 Executing recreation batch: [namespace/Kind/name]
```

### Alerts

Recommended alerts:

```yaml
- alert: DependencyAnalyzerDown
  expr: up{job="dependency-analyzer"} == 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Dependency analyzer is down"

- alert: CircularDependenciesDetected
  expr: circular_dependencies_detected_total > 0
  for: 1m
  labels:
    severity: warning
  annotations:
    summary: "Circular dependencies detected in cluster"

- alert: RecoveryOperationFailed
  expr: increase(recovery_operations_failed_total[5m]) > 0
  labels:
    severity: critical
  annotations:
    summary: "Dependency-aware recovery operation failed"
```

## Testing

### Automated Testing

Run the comprehensive test suite:

```bash
# Run dependency cleanup tests
./tests/validation/test-dependency-cleanup.sh

# Keep test resources for manual inspection
KEEP_TEST_RESOURCES=true ./tests/validation/test-dependency-cleanup.sh
```

### Manual Testing

1. **Create Test Resources with Dependencies**:
   ```bash
   kubectl create namespace dep-test
   kubectl apply -f tests/kubernetes/manifests/dependency-test.yaml
   ```

2. **Verify Dependency Discovery**:
   ```bash
   kubectl logs -n flux-recovery -l app=dependency-analyzer --tail=20
   ```

3. **Simulate Resource Failure**:
   ```bash
   kubectl delete deployment test-app -n dep-test
   # Watch for automatic recovery
   ```

4. **Check Recovery Plan**:
   ```bash
   kubectl get configmap dependency-analysis-state -n flux-recovery -o yaml
   ```

## Troubleshooting

### Common Issues

1. **Analyzer Not Discovering Resources**
   - Check RBAC permissions
   - Verify cluster connectivity
   - Review analyzer logs for errors

2. **Circular Dependencies Not Resolved**
   - Check dependency breaking logic
   - Verify priority calculations
   - Review circular dependency detection logs

3. **Recovery Operations Timing Out**
   - Increase timeout values in configuration
   - Check cluster resource availability
   - Verify network connectivity

4. **High Memory Usage**
   - Reduce dependency cache TTL
   - Limit monitored namespaces
   - Increase analyzer resource limits

### Debug Commands

```bash
# Check analyzer status
kubectl get pods -n flux-recovery -l app=dependency-analyzer -o wide

# View detailed logs
kubectl logs -n flux-recovery -l app=dependency-analyzer --previous

# Check RBAC permissions
kubectl auth can-i --list --as=system:serviceaccount:flux-recovery:dependency-analyzer

# Verify configuration
kubectl get configmap dependency-analysis-state -n flux-recovery -o yaml

# Check resource discovery
kubectl get events -n flux-recovery --field-selector involvedObject.name=dependency-analyzer
```

## Integration with GitOps Workflow

### Flux Integration

The dependency analyzer integrates seamlessly with Flux:

1. **Kustomization Dependencies** - Respects Flux `dependsOn` relationships
2. **HelmRelease Dependencies** - Understands Helm chart dependencies
3. **Source Dependencies** - Maps GitRepository and HelmRepository relationships

### Recovery Workflow

1. **Error Detection** - Error pattern detector identifies stuck reconciliation
2. **Dependency Analysis** - Analyzer calculates impact and recovery plan
3. **Cleanup Execution** - Resources cleaned up in dependency-aware order
4. **Recreation Execution** - Resources recreated in proper dependency order
5. **Verification** - System health validated post-recovery

## Best Practices

### Resource Design

1. **Minimize Circular Dependencies** - Design resources with clear hierarchies
2. **Use Proper Labels** - Label resources for better dependency discovery
3. **Document Dependencies** - Use annotations to document complex relationships
4. **Test Recovery Scenarios** - Regularly test recovery procedures

### Operational Practices

1. **Monitor Dependency Health** - Watch for circular dependencies
2. **Review Recovery Plans** - Validate generated recovery plans
3. **Test in Staging** - Test dependency changes in non-production first
4. **Maintain Documentation** - Keep dependency documentation current

### Performance Optimization

1. **Limit Scope** - Configure monitored namespaces appropriately
2. **Tune Cache Settings** - Adjust cache TTL based on cluster size
3. **Resource Limits** - Set appropriate CPU and memory limits
4. **Batch Sizing** - Configure optimal batch sizes for your cluster

## Future Enhancements

### Planned Features

1. **Machine Learning** - Predictive failure analysis based on dependency patterns
2. **Multi-Cluster Support** - Cross-cluster dependency analysis
3. **Custom Resource Support** - Enhanced support for CRDs and operators
4. **Visual Dependency Maps** - Graphical representation of dependencies
5. **Policy Engine** - Configurable policies for dependency handling

### Integration Roadmap

1. **Prometheus Integration** - Enhanced metrics and alerting
2. **Grafana Dashboards** - Visual dependency and recovery monitoring
3. **Slack/Teams Notifications** - Recovery operation notifications
4. **API Gateway** - REST API for external integrations
5. **Webhook Support** - External system notifications

## Conclusion

The dependency-aware cleanup system provides robust, intelligent resource recovery that respects the complex relationships between Kubernetes resources. By automatically discovering dependencies and calculating optimal recovery orders, it minimizes downtime and prevents cascading failures during GitOps recovery operations.

The system is designed to be:
- **Automatic** - Requires minimal manual intervention
- **Intelligent** - Makes smart decisions about recovery ordering
- **Safe** - Prevents operations that could cause additional failures
- **Observable** - Provides comprehensive monitoring and logging
- **Extensible** - Can be enhanced with additional features and integrations