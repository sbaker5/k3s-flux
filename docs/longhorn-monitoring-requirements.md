# Longhorn Monitoring Requirements

## Overview
This document outlines the monitoring requirements for Longhorn distributed storage to ensure proper configuration and operational health.

## Current State
- **Status**: Longhorn is deployed and operational
- **Monitoring**: Basic metrics collection via ServiceMonitor (already implemented)
- **Dashboards**: Longhorn dashboard available in Grafana
- **Health**: All pods running, storage provisioning functional

## Monitoring Requirements

### 1. Storage Health Monitoring
- **Volume Status**: Monitor volume creation, attachment, and health states
- **Replica Health**: Track replica count, synchronization status, and placement
- **Node Storage**: Monitor disk usage, available space, and disk health
- **Performance**: Track I/O latency, throughput, and IOPS

### 2. Configuration Validation
- **Node Configuration**: Validate disk mounts and configuration files
- **Storage Classes**: Ensure proper storage class configuration
- **Backup Configuration**: Monitor backup target connectivity and status
- **Network Connectivity**: Validate inter-node communication for replication

### 3. Operational Metrics
- **Resource Usage**: CPU, memory, and network usage of Longhorn components
- **Error Rates**: Track failed operations, timeouts, and retries
- **Capacity Planning**: Monitor storage growth trends and capacity utilization
- **Backup Operations**: Track backup success rates and timing

### 4. Alerting Requirements
- **Critical Alerts**:
  - Volume unavailable or degraded
  - Node disk full or failing
  - Backup failures
  - Network partition affecting replicas
- **Warning Alerts**:
  - High disk usage (>80%)
  - Slow I/O performance
  - Replica count below desired
  - Long-running operations

## Implementation Plan

### Phase 1: Enhanced Metrics Collection (Future)
- Extend existing ServiceMonitor with additional Longhorn-specific metrics
- Add custom metrics for configuration validation
- Implement health check endpoints for critical components

### Phase 2: Advanced Dashboards (Future)
- Create comprehensive Longhorn operational dashboard
- Add capacity planning and trend analysis views
- Implement drill-down capabilities for troubleshooting

### Phase 3: Automated Validation (Future)
- Create scripts to validate Longhorn configuration
- Implement automated health checks for storage operations
- Add integration with emergency CLI for storage-specific diagnostics

### Phase 4: Predictive Monitoring (Future)
- Implement disk failure prediction based on metrics
- Add capacity forecasting and alerting
- Create automated remediation for common issues

## Current Monitoring Implementation

### Existing ServiceMonitor
```yaml
# Location: infrastructure/monitoring/core/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: longhorn
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: longhorn-manager
  endpoints:
    - port: manager
      path: /metrics
```

### Available Metrics
- `longhorn_volume_*`: Volume-related metrics
- `longhorn_node_*`: Node storage metrics  
- `longhorn_disk_*`: Disk usage and health metrics
- `longhorn_instance_manager_*`: Instance manager metrics

### Grafana Dashboard
- **Name**: Longhorn Dashboard
- **Source**: https://raw.githubusercontent.com/longhorn/longhorn/v1.5.1/deploy/longhorn-grafana-dashboard.json
- **Location**: Configured in Grafana Core HelmRelease

## Integration Points

### Emergency CLI Integration
Future enhancement to add Longhorn-specific commands:
- `emergency-cli.sh storage-status` - Check Longhorn health
- `emergency-cli.sh storage-cleanup` - Clean up stuck volumes
- `emergency-cli.sh storage-validate` - Validate configuration

### Health Check Integration
Future enhancement to monitoring health checks:
- Validate all volumes are healthy
- Check replica distribution and health
- Verify backup target connectivity
- Test storage provisioning functionality

## Notes
- Longhorn monitoring is currently functional with basic metrics
- No immediate action required - system is operational
- Future enhancements should focus on predictive monitoring and automation
- Consider integration with cluster-wide storage policies and quotas