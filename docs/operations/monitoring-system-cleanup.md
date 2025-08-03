# Monitoring System Cleanup and Maintenance Guide

## Overview

This guide provides comprehensive procedures for maintaining a bulletproof monitoring system with ephemeral storage, comprehensive Flux metrics collection, and reliable remote access capabilities. The monitoring architecture is designed to remain operational even during storage failures and provides emergency access through Tailscale.

**Status**: 🚧 **Monitoring system cleanup in progress** - Tasks 1-3 and 6 from the monitoring-system-cleanup spec have been completed, with Task 7 (remote monitoring access validation) currently in progress. The system features bulletproof monitoring with ephemeral storage, optimized Flux metrics collection via PodMonitor, comprehensive cleanup automation, and validated remote access procedures. Task 7 implementation includes comprehensive remote access validation scripts and integration testing.

## Architecture Overview

### Bulletproof Monitoring Design

The monitoring system follows a bulletproof architecture with these key principles:

- **Ephemeral Storage**: Core monitoring uses `emptyDir` storage to avoid persistent storage dependencies
- **Dual Metrics Collection**: Both ServiceMonitor and PodMonitor ensure complete Flux controller coverage
- **Resource Limits**: Controlled resource usage prevents cluster impact
- **Short Retention**: 2-hour retention prevents resource exhaustion
- **Remote Access**: Tailscale provides secure remote access when MCP tools are unavailable

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    Bulletproof Monitoring Stack                 │
├─────────────────────────────────────────────────────────────────┤
│  Core Tier (Always Available)                                  │
│  ├─ Prometheus Core (2h retention, ephemeral)                  │
│  ├─ Grafana Core (ephemeral, essential dashboards)             │
│  ├─ ServiceMonitor (controllers with services)                 │
│  ├─ PodMonitor (all controllers via pods)                      │
│  └─ Remote Access (Tailscale subnet router)                    │
│                                                                 │
│  Status: BULLETPROOF - No storage dependencies                 │
└─────────────────────────────────────────────────────────────────┘
```

## Monitoring System Cleanup Procedures

### 1. Assessment and Health Check

Before performing cleanup, assess the current monitoring system state using the automated health validation scripts:

```bash
# Comprehensive monitoring system health check
./scripts/monitoring-health-check.sh --report

# Validate remote access capabilities
./scripts/validate-remote-monitoring-access.sh

# Check service reference consistency
./scripts/validate-monitoring-service-references.sh --report
```

**Manual Assessment** (if scripts are unavailable):

```bash
# Check monitoring namespace status
kubectl get namespace monitoring

# Check monitoring pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=monitoring-core

# Check for stuck resources
kubectl get pods -n monitoring --field-selector=status.phase!=Running

# Check PVC status (should be minimal for bulletproof design)
kubectl get pvc -n monitoring

# Check for stuck finalizers
kubectl get namespace monitoring -o yaml | grep finalizers
```

### 2. Automated Cleanup Script

Use the comprehensive monitoring cleanup script with multiple operation modes:

```bash
# Interactive cleanup with confirmation (recommended)
./scripts/cleanup-stuck-monitoring.sh

# Assessment only (no changes)
./scripts/cleanup-stuck-monitoring.sh assess

# Detect stuck resources only
./scripts/cleanup-stuck-monitoring.sh detect

# Clean up monitoring namespace only
./scripts/cleanup-stuck-monitoring.sh namespace
```

This script provides comprehensive cleanup functionality including:
- **Interactive confirmation** before cleanup operations
- **Health assessment** with detailed status reporting
- **Stuck resource detection** with automatic identification
- **Suspension of problematic HelmReleases** before cleanup
- **Cleanup of stuck pods, PVCs, and HelmReleases** with proper finalizer handling
- **Force reconciliation** of monitoring kustomization
- **System stabilization** waiting period with progress monitoring
- **Automatic resumption** of HelmReleases after successful cleanup
- **Comprehensive logging** with timestamped operations

For manual cleanup procedures, you can also use individual commands:

```bash
# Remove stuck PVCs
kubectl get pvc -n monitoring -o name | xargs -I {} kubectl patch {} -n monitoring -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl delete pvc --all -n monitoring --force --grace-period=0 2>/dev/null || true

# Force delete namespace if stuck
kubectl patch namespace monitoring -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl delete namespace monitoring --force --grace-period=0 2>/dev/null || true

# Recreate clean namespace
kubectl create namespace monitoring 2>/dev/null || true
```

### 3. Stuck Resource Recovery

For specific stuck resource scenarios:

#### Stuck Namespace
```bash
# Force remove finalizers
kubectl patch namespace monitoring -p '{"metadata":{"finalizers":null}}'
kubectl delete namespace monitoring --force --grace-period=0

# Recreate namespace
kubectl create namespace monitoring
```

#### Stuck PVCs
```bash
# Remove PVC finalizers
kubectl get pvc -n monitoring -o name | xargs -I {} kubectl patch {} -n monitoring -p '{"metadata":{"finalizers":null}}'
kubectl delete pvc --all -n monitoring --force --grace-period=0
```

#### Stuck Pods
```bash
# Force delete stuck pods
kubectl delete pods --all -n monitoring --force --grace-period=0

# Check for pods stuck in terminating state
kubectl get pods -n monitoring --field-selector=status.phase=Terminating
```

## Flux Metrics Collection Configuration

### Optimized PodMonitor Strategy

The monitoring system uses an optimized PodMonitor approach for comprehensive Flux controller metrics collection:

#### Current Implementation
**PodMonitor Configuration** - Monitors all controllers directly via pods:
- `source-controller` - Git/OCI repository management
- `kustomize-controller` - Kustomization reconciliation  
- `helm-controller` - Helm release management
- `notification-controller` - Event notifications

**Key Features**:
- Direct pod access to metrics on port 8080 (http-prom)
- Comprehensive metric filtering to reduce cardinality
- Enhanced relabeling for better organization
- Cluster identification for multi-cluster setups

```yaml
# Optimized PodMonitor configuration
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: flux-controllers-pods
spec:
  namespaceSelector:
    matchNames:
      - flux-system
  selector:
    matchExpressions:
      - key: app
        operator: In
        values: [source-controller, kustomize-controller, helm-controller, notification-controller]
  podMetricsEndpoints:
  - port: http-prom
    interval: 30s
    scrapeTimeout: 10s
    # Enhanced relabeling and metric filtering
```

**Why PodMonitor Only**: Flux controller services don't expose the metrics port (8080), only HTTP port (80). PodMonitor provides direct access to the actual metrics endpoints.

### Advanced Metric Filtering and Optimization

The current implementation includes comprehensive metric filtering to reduce cardinality and improve performance:

```yaml
metricRelabelings:
  # Keep only relevant Flux and runtime metrics
  - sourceLabels: [__name__]
    regex: "flux_.*|gotk_.*|controller_runtime_.*|workqueue_.*|rest_client_.*|process_.*|go_.*"
    action: keep
  # Drop high-cardinality histogram buckets for performance
  - sourceLabels: [__name__]
    regex: "rest_client_request_duration_seconds_bucket|workqueue_queue_duration_seconds_bucket|controller_runtime_reconcile_time_seconds_bucket"
    action: drop
  # Drop verbose Go runtime metrics
  - sourceLabels: [__name__]
    regex: "go_gc_.*|go_memstats_.*_total|go_memstats_.*_bytes"
    action: drop
  # Keep essential Go metrics
  - sourceLabels: [__name__]
    regex: "go_goroutines|go_threads|go_memstats_alloc_bytes|go_memstats_heap_.*_bytes"
    action: keep
```

**Enhanced Relabeling**:
- Controller name extraction and normalization
- Cluster identification (`cluster: k3s-flux`)
- Component labeling for better organization
- Instance labeling for Grafana dashboard compatibility

## Monitoring Health Validation

### Automated Health Validation Scripts

The monitoring system includes comprehensive health validation scripts for operational excellence:

#### 1. Monitoring Health Check (`scripts/monitoring-health-check.sh`)

Comprehensive monitoring system health validation:

```bash
# Basic health check
./scripts/monitoring-health-check.sh

# Include remote access testing
./scripts/monitoring-health-check.sh --remote

# Generate detailed report
./scripts/monitoring-health-check.sh --report --remote
```

**Validates**:
- Monitoring namespace health
- Prometheus and Grafana pod status
- ServiceMonitor and PodMonitor configuration
- Metrics collection endpoints
- Storage architecture (ephemeral design)
- Remote access capabilities

#### 2. Remote Access Validation (`scripts/validate-remote-monitoring-access.sh`)

Validates remote access via Tailscale:

```bash
# Validate remote access setup
./scripts/validate-remote-monitoring-access.sh

# Test actual HTTP connectivity
./scripts/validate-remote-monitoring-access.sh --test-connectivity

# Generate ready-to-use access commands
# Commands saved to: /tmp/monitoring-remote-access-commands.sh
```

**Features**:
- Tailscale connectivity verification
- Service endpoint validation
- Port availability checking
- Automated command generation

#### 3. Service Reference Validation (`scripts/validate-monitoring-service-references.sh`)

Ensures documentation matches actual deployments:

```bash
# Validate service references
./scripts/validate-monitoring-service-references.sh --report

# Generate current service template
# Template saved to: /tmp/monitoring-service-references.md
```

**Validates**:
- Documentation service references
- Script service discovery patterns
- Service name consistency

### Health Validation Integration

```bash
# Run complete health validation
./scripts/monitoring-health-check.sh --remote --report
./scripts/validate-remote-monitoring-access.sh --test-connectivity
./scripts/validate-monitoring-service-references.sh --report

# Use in automation
if ./scripts/monitoring-health-check.sh; then
    echo "Monitoring system healthy"
else
    echo "Issues detected - check reports"
fi
```

### Advanced Remote Access Testing

#### 4. Comprehensive Connectivity Testing (`scripts/test-remote-monitoring-connectivity.sh`)

End-to-end connectivity testing with functionality validation:

```bash
# Basic connectivity tests
./scripts/test-remote-monitoring-connectivity.sh

# Full testing with performance and dashboard tests
./scripts/test-remote-monitoring-connectivity.sh --full-test --dashboard-test
```

**Features**:
- HTTP connectivity testing via Tailscale IP
- Prometheus API functionality validation
- Grafana interface accessibility testing
- Network performance measurement
- Dashboard functionality testing

#### 5. Comprehensive Test Suite (`scripts/comprehensive-remote-monitoring-test.sh`)

Orchestrates all remote monitoring validation tests:

```bash
# Complete test suite
./scripts/comprehensive-remote-monitoring-test.sh

# Full testing with detailed reporting
./scripts/comprehensive-remote-monitoring-test.sh --full --report
```

**Test Coverage**:
- Monitoring system health check
- Remote access validation
- Connectivity testing
- Service reference validation
- Access command generation
- Troubleshooting guide generation

For detailed information, see [Monitoring Health Validation Guide](monitoring/monitoring-health-validation.md).

## Remote Access Configuration

### Tailscale Remote Access

The monitoring system includes Tailscale for secure remote access when MCP tools are unavailable:

#### Automated Remote Access Setup

Use the validation script to generate access commands:

```bash
# Validate and generate access commands
./scripts/validate-remote-monitoring-access.sh

# Use generated commands
source /tmp/monitoring-remote-access-commands.sh
```

#### Manual Remote Access Setup

```bash
# Forward Prometheus for remote access
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 --address=0.0.0.0 &

# Forward Grafana for remote access
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0 &

# Access from remote machine using Tailscale IP
# http://100.x.x.x:9090 (Prometheus)
# http://100.x.x.x:3000 (Grafana)
```

### kubectl Context Management

Configure kubectl contexts for local and remote access:

```bash
# Local context (default)
kubectl config use-context default

# Remote context via Tailscale
kubectl config use-context k3s-remote

# Verify current context
kubectl config current-context
```

## Monitoring Health Validation

### Automated Health Check Script

Use the existing monitoring health assessment script:

```bash
# Run the monitoring health assessment
./scripts/monitoring-health-assessment.sh
```

This script provides comprehensive health assessment including:
- Monitoring namespace status check
- Detection of stuck resources with deletion timestamps
- PVC, pod, and HelmRelease status validation
- Configuration conflict detection
- Recent events analysis
- CRD status verification
- Automated cleanup recommendations

The script will provide detailed output with color-coded status indicators:
- ✅ **Success**: Component is healthy and operational
- ⚠️ **Warning**: Minor issues detected, system operational
- ❌ **Error**: Critical issues requiring attention

For manual health checks, you can also use individual commands:

```bash
# Check monitoring namespace
kubectl get namespace monitoring

# Check monitoring pods
kubectl get pods -n monitoring

# Check HelmRelease status
kubectl get helmrelease -n monitoring

# Check recent events
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

## Emergency Procedures

### When MCP Tools Are Unavailable

1. **Use Tailscale Remote Access**:
   ```bash
   # SSH to k3s node via Tailscale
   ssh k3s1-tailscale
   
   # Use emergency CLI
   ./scripts/emergency-cli.sh status
   ./scripts/emergency-cli.sh interactive
   ```

2. **Direct kubectl Access**:
   ```bash
   # Switch to remote context
   kubectl config use-context k3s-remote
   
   # Check cluster status
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

3. **Manual Service Access**:
   ```bash
   # Forward services for remote access
   kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090 --address=0.0.0.0 &
   kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0 &
   
   # Access via Tailscale IP: http://100.x.x.x:9090, http://100.x.x.x:3000
   ```

### Recovery from Complete Monitoring Failure

1. **Clean Deployment**:
   ```bash
   # Run cleanup script
   ./scripts/cleanup-stuck-monitoring.sh
   
   # Redeploy monitoring
   flux reconcile kustomization infrastructure-monitoring -n flux-system
   ```

2. **Validate Recovery**:
   ```bash
   # Run health check
   ./scripts/monitoring-health-assessment.sh
   
   # Check metrics collection
   kubectl get servicemonitor,podmonitor -n monitoring
   ```

## Best Practices

### Monitoring System Maintenance

1. **Regular Health Checks**: Run validation scripts weekly
2. **Resource Monitoring**: Monitor monitoring system resource usage
3. **Metric Cardinality**: Regularly review metric cardinality and filtering
4. **Remote Access Testing**: Test remote access procedures monthly

### Troubleshooting Guidelines

1. **Start with Health Check**: Always run the health validation script first
2. **Check Resource Limits**: Ensure monitoring components have adequate resources
3. **Verify Network Connectivity**: Test both local and remote access methods
4. **Review Logs**: Check Flux controller and monitoring component logs

### Documentation Updates

Keep the following documentation current:
- Remote access procedures and Tailscale configuration
- kubectl context switching procedures
- Emergency access methods and troubleshooting steps
- Monitoring component resource requirements and limits

## See Also

- [Remote Access Setup Guide](tailscale-remote-access-setup.md) - Complete Tailscale setup procedures
- [Remote Access Quick Reference](../guides/remote-access-quick-reference.md) - Quick commands for remote access
- [MCP Tools Guide](../mcp-tools-guide.md) - Enhanced cluster interaction tools
- [Monitoring Architecture](../infrastructure/monitoring/README.md) - Detailed monitoring architecture documentation
- [Flux Monitoring Guide](../.kiro/steering/06-flux-monitoring.md) - Comprehensive Flux metrics collection details