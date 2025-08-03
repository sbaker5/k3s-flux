# Monitoring Health Validation Guide

This guide covers the automated monitoring health validation scripts that ensure the k3s monitoring system is functioning correctly and accessible remotely via Tailscale.

## Overview

The monitoring health validation system consists of five main scripts:

1. **`monitoring-health-check.sh`** - Comprehensive monitoring system health validation
2. **`validate-remote-monitoring-access.sh`** - Remote access validation via Tailscale
3. **`validate-monitoring-service-references.sh`** - Service reference validation in documentation
4. **`test-remote-monitoring-connectivity.sh`** - End-to-end connectivity testing with functionality validation
5. **`comprehensive-remote-monitoring-test.sh`** - Orchestrates all remote monitoring validation tests

## Scripts Overview

### 1. Monitoring Health Check (`scripts/monitoring-health-check.sh`)

Performs comprehensive health validation of the monitoring system including:

- **Namespace Health**: Validates monitoring namespace exists and is active
- **Prometheus Health**: Checks Prometheus pods, services, and metrics endpoint
- **Grafana Health**: Validates Grafana pods and services
- **ServiceMonitors/PodMonitors**: Verifies metrics collection configuration
- **Metrics Collection**: Tests actual metrics endpoint accessibility
- **Storage Health**: Validates ephemeral storage design (bulletproof architecture)
- **Remote Access**: Tests port forwarding capabilities (optional)

#### Usage

```bash
# Basic health check
./scripts/monitoring-health-check.sh

# Include remote access testing
./scripts/monitoring-health-check.sh --remote

# Generate detailed report
./scripts/monitoring-health-check.sh --report

# Attempt to fix issues automatically
./scripts/monitoring-health-check.sh --fix

# Full validation with report and fixes
./scripts/monitoring-health-check.sh --remote --fix --report
```

#### Example Output

```
[2025-08-01 14:03:04] INFO: Monitoring System Health Check v1.0
[2025-08-01 14:03:04] INFO: ======================================
[2025-08-01 14:03:05] SUCCESS: Monitoring namespace exists
[2025-08-01 14:03:05] SUCCESS: All Prometheus pods are running
[2025-08-01 14:03:05] SUCCESS: Prometheus service exists: monitoring-core-prometheus-prometheus
[2025-08-01 14:03:05] SUCCESS: All Grafana pods are running
[2025-08-01 14:03:05] SUCCESS: Found 15 ServiceMonitor(s)
[2025-08-01 14:03:05] SUCCESS: Found 1 PodMonitor(s)
[2025-08-01 14:03:05] SUCCESS: Flux controllers PodMonitor exists
[2025-08-01 14:03:09] SUCCESS: Prometheus metrics endpoint accessible
[2025-08-01 14:03:09] INFO: Found 24 active metric targets
[2025-08-01 14:03:09] SUCCESS: No PVCs found - using ephemeral storage as designed
[2025-08-01 14:03:10] SUCCESS: Monitoring system health check completed successfully - no issues found
```

### 2. Remote Access Validation (`scripts/validate-remote-monitoring-access.sh`)

Validates remote access to monitoring services via Tailscale including:

- **Tailscale Connectivity**: Verifies Tailscale connection and IP assignment
- **Service References**: Validates monitoring services exist and have endpoints
- **Port Availability**: Checks if required ports (9090, 3000) are available
- **Port Forwarding**: Tests actual port forward establishment
- **Access Commands**: Generates ready-to-use remote access commands

#### Usage

```bash
# Basic remote access validation
./scripts/validate-remote-monitoring-access.sh

# Include HTTP connectivity testing
./scripts/validate-remote-monitoring-access.sh --test-connectivity

# Clean up existing port forwards only
./scripts/validate-remote-monitoring-access.sh --cleanup
```

#### Generated Access Commands

The script generates ready-to-use commands for remote access:

```bash
# Prometheus (metrics and queries)
kubectl port-forward -n monitoring service/monitoring-core-prometheus-prometheus 9090:9090 --address=0.0.0.0 &
# Access at: http://100.117.198.6:9090

# Grafana (dashboards and visualization)
kubectl port-forward -n monitoring service/monitoring-core-grafana 3000:80 --address=0.0.0.0 &
# Access at: http://100.117.198.6:3000

# Clean up port forwards when done:
pkill -f 'kubectl port-forward'
```

Commands are also saved to `/tmp/monitoring-remote-access-commands.sh` for easy execution.

### 3. Service Reference Validation (`scripts/validate-monitoring-service-references.sh`)

Validates that service references in documentation match actual deployed services:

- **Service Discovery**: Discovers actual monitoring services in the cluster
- **Documentation Validation**: Checks service references in documentation files
- **Script Validation**: Verifies scripts use dynamic service discovery
- **Template Generation**: Creates current service reference templates

#### Usage

```bash
# Basic service reference validation
./scripts/validate-monitoring-service-references.sh

# Generate detailed validation report
./scripts/validate-monitoring-service-references.sh --report

# Update documentation with current service names (planned)
./scripts/validate-monitoring-service-references.sh --update-docs
```

#### Validated Files

The script checks service references in:

- `docs/setup/tailscale-remote-access-setup.md`
- `docs/operations/monitoring-system-cleanup.md`
- `docs/architecture-overview.md`
- `README.md`
- `scripts/monitoring-health-check.sh`
- `scripts/validate-remote-monitoring-access.sh`
- `scripts/monitoring-health-assessment.sh`

### 4. Remote Monitoring Connectivity Test (`scripts/test-remote-monitoring-connectivity.sh`)

Performs comprehensive end-to-end testing of remote monitoring access via Tailscale:

- **HTTP Connectivity**: Tests actual HTTP requests to Prometheus and Grafana
- **API Functionality**: Validates Prometheus queries and Grafana health endpoints
- **Network Performance**: Measures response times via Tailscale (optional)
- **Dashboard Testing**: Tests Grafana dashboard functionality (optional)
- **Process Management**: Handles port forward setup and cleanup

#### Usage

```bash
# Basic connectivity tests
./scripts/test-remote-monitoring-connectivity.sh

# Full testing with performance measurement
./scripts/test-remote-monitoring-connectivity.sh --full-test

# Include dashboard functionality testing
./scripts/test-remote-monitoring-connectivity.sh --dashboard-test

# Complete testing with all features
./scripts/test-remote-monitoring-connectivity.sh --full-test --dashboard-test
```

#### Example Output

```
[2025-08-01 14:29:37] SUCCESS: Prometheus accessible via Tailscale IP: 100.117.198.6:9090
[2025-08-01 14:29:37] SUCCESS: Grafana accessible via Tailscale IP: 100.117.198.6:3000
[2025-08-01 14:29:37] SUCCESS: Prometheus query successful - found 24 targets
[2025-08-01 14:29:37] SUCCESS: Flux controller metrics available - found 18 controller metrics
[2025-08-01 14:29:38] SUCCESS: Grafana health check passed
[2025-08-01 14:29:38] SUCCESS: All remote monitoring connectivity tests passed!
```

### 5. Comprehensive Remote Monitoring Test Suite (`scripts/comprehensive-remote-monitoring-test.sh`)

Orchestrates all remote monitoring validation tests in a single comprehensive suite:

- **Health Check Integration**: Runs monitoring health check with remote access
- **Access Validation**: Validates remote access setup and connectivity
- **Connectivity Testing**: Performs end-to-end connectivity tests
- **Service Validation**: Checks service reference consistency
- **Report Generation**: Creates comprehensive test reports
- **Troubleshooting**: Generates troubleshooting guides

#### Usage

```bash
# Complete test suite
./scripts/comprehensive-remote-monitoring-test.sh

# Full testing with all optional features
./scripts/comprehensive-remote-monitoring-test.sh --full

# Generate comprehensive report
./scripts/comprehensive-remote-monitoring-test.sh --report

# Full testing with detailed reporting
./scripts/comprehensive-remote-monitoring-test.sh --full --report
```

#### Test Coverage

The comprehensive test suite validates:
- Monitoring system health (namespace, pods, services)
- Remote access capabilities (Tailscale, port forwarding)
- HTTP connectivity (local and remote endpoints)
- API functionality (Prometheus queries, Grafana health)
- Service reference consistency (documentation accuracy)
- Performance metrics (response times, network latency)
- Dashboard functionality (Grafana interface testing)

## Integration with Existing Systems

### Health Check Integration

The monitoring health validation integrates with existing health check systems:

```bash
# Run as part of post-outage validation
./scripts/monitoring-health-check.sh --report

# Include in automated health checks
if ./scripts/monitoring-health-check.sh; then
    echo "Monitoring system healthy"
else
    echo "Monitoring system issues detected"
    # Trigger alerts or remediation
fi
```

### Remote Access Best Practices

#### Process Management

Always clean up port forwards when done:

```bash
# Start monitoring access
./scripts/validate-remote-monitoring-access.sh

# Use the generated commands
source /tmp/monitoring-remote-access-commands.sh

# Clean up when done
pkill -f 'kubectl port-forward'
```

#### Security Considerations

- Port forwards bind to `0.0.0.0` for Tailscale access
- Only accessible via Tailscale network (encrypted)
- No ports exposed to public internet
- Automatic cleanup prevents port conflicts

### Monitoring Architecture Validation

The scripts validate the bulletproof monitoring architecture:

#### Ephemeral Storage Design

```bash
# Validates no PVCs are used (ephemeral design)
[2025-08-01 14:03:09] SUCCESS: No PVCs found - using ephemeral storage as designed
[2025-08-01 14:03:09] SUCCESS: Found 4 pod(s) using emptyDir volumes (ephemeral design)
```

#### Service Discovery

Scripts use dynamic service discovery instead of hardcoded names:

```bash
# Good: Dynamic discovery
local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||')

# Bad: Hardcoded names
local prometheus_service="monitoring-core-prometheus-prometheus"
```

## Troubleshooting

### Common Issues

#### 1. Prometheus Service Not Found

**Symptom**: `ERROR: Prometheus service not found`

**Solution**: Check if Prometheus is deployed:
```bash
kubectl get pods -n monitoring | grep prometheus
kubectl get services -n monitoring | grep prometheus
```

#### 2. Port Forward Failures

**Symptom**: `ERROR: Prometheus port forward failed to establish`

**Solutions**:
```bash
# Check if ports are in use
lsof -i :9090
lsof -i :3000

# Clean up existing port forwards
pkill -f 'kubectl port-forward'

# Check service endpoints
kubectl get endpoints -n monitoring
```

#### 3. Tailscale Connectivity Issues

**Symptom**: `ERROR: Tailscale is not connected`

**Solutions**:
```bash
# Check Tailscale status
tailscale status

# Reconnect if needed
tailscale up

# Check subnet router
kubectl get pods -n tailscale
```

#### 4. Service Reference Mismatches

**Symptom**: Service references in documentation don't match actual services

**Solutions**:
```bash
# Generate current service template
./scripts/validate-monitoring-service-references.sh --report

# Use the generated template to update documentation
cat /tmp/monitoring-service-references.md
```

### Debug Mode

Enable verbose output for troubleshooting:

```bash
# Add debug output to scripts
set -x  # Add to script for verbose execution

# Check kubectl connectivity
kubectl cluster-info
kubectl get nodes

# Verify monitoring namespace
kubectl describe namespace monitoring
```

## Automation and CI/CD Integration

### Pre-commit Hooks

Add monitoring validation to pre-commit hooks:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: monitoring-health-check
        name: Monitoring Health Check
        entry: ./scripts/monitoring-health-check.sh
        language: script
        pass_filenames: false
```

### Automated Health Checks

Run periodic health checks:

```bash
#!/bin/bash
# scripts/periodic-monitoring-health.sh

# Run health check every hour
while true; do
    if ./scripts/monitoring-health-check.sh --report; then
        echo "$(date): Monitoring system healthy"
    else
        echo "$(date): Monitoring system issues detected"
        # Send alert or trigger remediation
    fi
    sleep 3600
done
```

### CI/CD Pipeline Integration

```yaml
# .github/workflows/monitoring-health.yml
name: Monitoring Health Check
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  health-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup kubectl
        uses: azure/setup-kubectl@v3
      - name: Run monitoring health check
        run: |
          ./scripts/monitoring-health-check.sh --report
          ./scripts/validate-remote-monitoring-access.sh
          ./scripts/validate-monitoring-service-references.sh --report
```

## Future Enhancements

### Planned Features

1. **Automatic Documentation Updates**: Update service references automatically
2. **Alert Integration**: Send alerts on health check failures
3. **Performance Metrics**: Track health check execution time and success rates
4. **Dashboard Integration**: Display health status in Grafana dashboards
5. **Multi-Cluster Support**: Extend validation to multiple clusters

### Extension Points

The scripts are designed for extensibility:

```bash
# Add custom health checks
add_custom_health_check() {
    log "Running custom health check..."
    # Custom validation logic
    return 0
}

# Extend service discovery
discover_custom_services() {
    # Custom service discovery logic
    return 0
}
```

## See Also

- [Monitoring System Cleanup](../operations/monitoring-system-cleanup.md) - Overall monitoring system documentation
- [Tailscale Remote Access Setup](../setup/tailscale-remote-access-setup.md) - Remote access configuration
- [Architecture Overview](../architecture-overview.md) - System architecture details
- [GitOps Resilience Patterns](../gitops-resilience-patterns.md) - Resilience and recovery patterns