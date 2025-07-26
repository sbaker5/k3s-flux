# Error Pattern Detection Testing Guide

This document describes the testing infrastructure for Tasks 3.1 (Error Pattern Detection) and 3.2 (Resource Recreation Automation) of the GitOps Resilience Patterns system.

## Overview

The testing infrastructure provides comprehensive validation of the error pattern detection and resource recreation systems through multiple test scripts that verify both configuration and runtime functionality.

## Test Scripts

### 1. Configuration Validation Tests

#### `tests/validation/test-error-pattern-detection.sh`
**Purpose**: Validates the basic configuration and setup of the error pattern detection system.

**What it tests**:
- Configuration files exist and are valid YAML
- Kustomization builds successfully
- Recovery patterns are properly structured
- RBAC permissions are configured
- Controller script contains required components

**Usage**:
```bash
./tests/validation/test-error-pattern-detection.sh
```

**Expected outcome**: All configuration validation tests pass, confirming the system is properly configured.

### 2. Runtime Functionality Tests

#### `tests/validation/test-tasks-3.1-3.2.sh`
**Purpose**: Simple runtime verification of both tasks with clear pass/fail results.

**What it tests**:
- Task 3.1: Error pattern detection system is running and active
- Task 3.2: Resource recreation automation is configured and ready
- Basic health checks for all components

**Usage**:
```bash
./tests/validation/test-tasks-3.1-3.2.sh
```

**Expected outcome**: Confirms both tasks are operational with summary statistics.

#### `tests/validation/test-error-pattern-runtime.sh`
**Purpose**: Comprehensive runtime testing of the error pattern detection system.

**What it tests**:
- Recovery namespace exists and is active
- Error pattern detector pod is running
- Configuration is loaded properly
- Real-time event monitoring is active
- Flux events are being processed
- RBAC permissions are functional

**Usage**:
```bash
./tests/validation/test-error-pattern-runtime.sh
```

**Expected outcome**: Detailed verification of all runtime components.

#### `tests/validation/test-resource-recreation.sh`
**Purpose**: Focused testing of resource recreation automation capabilities.

**What it tests**:
- Recovery actions are defined in configuration
- Recovery action steps are properly structured
- RBAC permissions for resource recreation
- Immutable field patterns are configured
- Auto-recovery settings are configured
- HelmRelease recovery actions are available

**Usage**:
```bash
./tests/validation/test-resource-recreation.sh
```

**Expected outcome**: Confirms all resource recreation capabilities are configured and ready.

### 3. Simulation and Integration Tests

#### `tests/validation/test-pattern-simulation.sh`
**Purpose**: End-to-end testing with real resource creation and pattern detection simulation.

**What it tests**:
- Creates test deployments to trigger immutable field conflicts
- Verifies error pattern detection in real scenarios
- Validates recovery pattern configuration
- Tests RBAC permissions with actual operations
- Provides comprehensive system status summary

**Usage**:
```bash
./tests/validation/test-pattern-simulation.sh
```

**Expected outcome**: Demonstrates the system working with real Kubernetes resources and events.

### 4. Health and Recovery Tests

#### `tests/validation/post-outage-health-check.sh`
**Purpose**: Comprehensive health assessment after system disruptions (power outages, restarts, etc.).

**What it tests**:
- Cluster infrastructure health (nodes, core pods)
- Flux GitOps system health (controllers, kustomizations)
- Storage system health (Longhorn, PVCs)
- Monitoring system health
- Error pattern detection system health
- Current issues analysis and recommendations

**Usage**:
```bash
./tests/validation/post-outage-health-check.sh
```

**Expected outcome**: Complete health assessment with actionable recommendations.

## Test Results Interpretation

### Success Indicators

**Task 3.1 (Error Pattern Detection)**:
- ✅ Error pattern detector pod is Running
- ✅ Configuration loaded with expected number of patterns
- ✅ Real-time Kubernetes event monitoring is active
- ✅ Processing Flux events (visible in logs)
- ✅ RBAC permissions are functional

**Task 3.2 (Resource Recreation)**:
- ✅ Recovery patterns configuration exists and is valid
- ✅ Recovery actions are defined with proper steps
- ✅ RBAC permissions for resource operations are configured
- ✅ Auto-recovery settings are configured
- ✅ Immutable field patterns are available

### Common Issues and Troubleshooting

#### Pod CrashLoopBackOff
**Symptoms**: Error pattern detector pod keeps restarting
**Causes**: 
- Script exits instead of running continuously
- Configuration loading failures
- RBAC permission issues

**Resolution**:
```bash
# Check pod logs
kubectl logs -n flux-recovery -l app=error-pattern-detector

# Check configuration
kubectl get configmap recovery-patterns-config -n flux-recovery -o yaml

# Restart deployment
kubectl rollout restart deployment error-pattern-detector -n flux-recovery
```

#### No Pattern Detection Activity
**Symptoms**: No recent log entries showing event processing
**Causes**:
- Kubernetes event monitoring not working
- No Flux events being generated
- Pattern matching logic issues

**Resolution**:
```bash
# Check if Flux is generating events
kubectl get events -A --field-selector type=Warning

# Check Flux resource status
kubectl get kustomizations,helmreleases -A

# Verify RBAC permissions
kubectl auth can-i get events --as=system:serviceaccount:flux-recovery:error-pattern-detector
```

#### Configuration Not Loading
**Symptoms**: "Failed to load config" errors in logs
**Causes**:
- ConfigMap not mounted properly
- YAML syntax errors in configuration
- File path issues

**Resolution**:
```bash
# Validate configuration YAML
kubectl get configmap recovery-patterns-config -n flux-recovery -o jsonpath='{.data.recovery-patterns\.yaml}' | yamllint -

# Check pod volume mounts
kubectl describe pod -n flux-recovery -l app=error-pattern-detector
```

## Production Monitoring

### Key Metrics to Monitor

1. **Pod Health**: Error pattern detector pod should be Running
2. **Log Activity**: Regular log entries showing event processing
3. **Pattern Matches**: Alerts when error patterns are detected
4. **Recovery Actions**: Tracking of automated recovery attempts

### Monitoring Commands

```bash
# Check system status
kubectl get pods -n flux-recovery

# Monitor real-time activity
kubectl logs -n flux-recovery -l app=error-pattern-detector -f

# Check recent pattern detection
kubectl logs -n flux-recovery -l app=error-pattern-detector --tail=50 --since=1h

# Verify configuration
kubectl get configmap recovery-patterns-config -n flux-recovery -o yaml
```

### Integration with Existing Monitoring

The error pattern detection system integrates with your existing Prometheus/Grafana monitoring stack:

- **Metrics**: System exposes metrics about pattern detection and recovery actions
- **Alerts**: PrometheusRules can alert on stuck reconciliations and recovery failures
- **Dashboards**: Grafana dashboards show GitOps health and recovery activity

## Continuous Testing Strategy

### Automated Testing
- Run configuration validation tests in CI/CD pipeline
- Include runtime tests in deployment verification
- Schedule periodic health checks

### Manual Testing
- Run simulation tests after major changes
- Perform health checks after system disruptions
- Validate new error patterns before deployment

### Test Data Management
- Test scripts clean up resources automatically
- Use dedicated test namespaces when possible
- Avoid testing in production namespaces

## Future Enhancements

### Planned Test Improvements
1. **Chaos Engineering**: Automated failure injection tests
2. **Performance Testing**: Load testing for high-volume event processing
3. **Recovery Validation**: Automated verification of recovery effectiveness
4. **Multi-Cluster Testing**: Validation across multiple cluster environments

### Monitoring Enhancements
1. **Metrics Collection**: Detailed metrics on pattern detection accuracy
2. **Alert Tuning**: Fine-tuned alerts for different error patterns
3. **Dashboard Improvements**: Enhanced visualization of recovery operations
4. **Trend Analysis**: Historical analysis of error patterns and recovery success rates

## Conclusion

This testing infrastructure provides comprehensive validation of the GitOps resilience patterns system, ensuring both tasks 3.1 and 3.2 are functioning correctly in production environments. Regular execution of these tests helps maintain system reliability and catch issues early.