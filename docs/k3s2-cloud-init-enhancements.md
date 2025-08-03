# K3s2 Cloud-Init Configuration Enhancements

## Overview

This document describes the enhancements made to the k3s2 cloud-init configuration to provide robust node onboarding with improved error handling, logging, validation, retry mechanisms, and health check endpoints.

## Enhanced Features

### 1. Comprehensive Logging System

**Location**: `/opt/k3s-onboarding/onboarding.log`

- **Timestamped entries**: All log entries include ISO 8601 timestamps
- **Structured logging**: Clear SUCCESS/ERROR/WARNING prefixes
- **Detailed progress tracking**: Each step of the onboarding process is logged
- **Error context**: Failed operations include specific error messages

**Example log entries**:
```
[2025-01-15T10:30:15-05:00] Starting k3s2 onboarding process
[2025-01-15T10:30:16-05:00] SUCCESS: packages_installed completed
[2025-01-15T10:30:17-05:00] SUCCESS: iscsi_enabled completed
[2025-01-15T10:30:18-05:00] K3s installation attempt 1 of 5
[2025-01-15T10:30:25-05:00] SUCCESS: k3s_installed completed
```

### 2. Status Tracking and Monitoring

**Location**: `/opt/k3s-onboarding/status.json`

Real-time JSON status file that tracks:
- Overall onboarding status (`initializing`, `completed`)
- Individual step completion status
- Timestamp of last update
- Array of errors encountered

**Status structure**:
```json
{
  "status": "initializing",
  "timestamp": "2025-01-15T10:30:15-05:00",
  "steps": {
    "packages_installed": true,
    "iscsi_enabled": true,
    "k3s_installed": false,
    "cluster_joined": false,
    "node_labeled": false,
    "health_check_ready": false
  },
  "errors": []
}
```

### 3. Health Check Endpoint

**Service**: `k3s-onboarding-health.service`
**Port**: 8080
**Protocol**: HTTP

Provides a simple HTTP endpoint that returns the current onboarding status as JSON. This allows external monitoring systems to check the onboarding progress.

**Usage**:
```bash
# Check onboarding status
curl http://k3s2:8080

# Monitor onboarding progress
watch -n 5 'curl -s http://k3s2:8080 | jq .'
```

### 4. Retry Mechanisms

#### K3s Installation Retry
- **Max retries**: 5 attempts
- **Retry delay**: 30 seconds between attempts
- **Pre-validation**: Cluster connectivity check before each attempt
- **Timeout handling**: 60-second timeout for k3s agent readiness

#### Node Labeling Retry
- **Max retries**: 3 attempts
- **Retry delay**: 10 seconds between attempts
- **Overwrite protection**: Uses `--overwrite` flag to handle existing labels

#### Cluster Join Validation
- **Timeout**: 120 seconds maximum wait
- **Check interval**: 5 seconds between checks
- **Validation**: Confirms node appears in cluster and reaches "Ready" state

### 5. Pre-Installation Validation

#### Cluster Connectivity Validation
- **Network check**: Tests TCP connectivity to k3s1:6443
- **API server check**: Validates API server response with timeout
- **Failure handling**: Prevents installation attempts when cluster is unreachable

#### Package Dependencies
Enhanced package list includes:
- `open-iscsi`: Required for Longhorn storage
- `jq`: JSON processing for status tracking
- `curl`: HTTP operations and k3s installation
- `wget`: Additional download capabilities
- `netcat-openbsd`: Network connectivity testing
- `systemd-journal-remote`: Enhanced logging capabilities

### 6. Error Handling and Recovery

#### Graceful Failure Handling
- **Non-fatal errors**: Node labeling failures don't stop the process
- **Fatal errors**: K3s installation and cluster join failures halt execution
- **Error context**: All failures include descriptive error messages
- **Status preservation**: Error states are recorded in status.json

#### Recovery Scenarios
- **Network interruptions**: Automatic retry with connectivity validation
- **Temporary API server unavailability**: Retry mechanism handles transient issues
- **Resource conflicts**: Label overwrite handling prevents conflicts

## Implementation Details

### File Structure
```
/opt/k3s-onboarding/
├── onboarding.log          # Main log file
├── status.json             # Real-time status tracking
├── health-check.sh         # Status management functions
└── k3s-install-with-retry.sh  # Main installation script
```

### Systemd Service
```ini
[Unit]
Description=K3s Onboarding Health Check Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do nc -l -p 8080 -c "echo -e \"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n$(cat /opt/k3s-onboarding/status.json)\""; done'
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
```

## Requirements Compliance

### Requirement 1.1: Automatic Cluster Join
✅ **Enhanced**: Retry mechanism with connectivity validation ensures reliable cluster join

### Requirement 1.2: Node Labeling
✅ **Enhanced**: Retry mechanism with overwrite protection ensures labels are applied

### Requirement 1.4: GitOps Detection
✅ **Enhanced**: Health check endpoint allows Flux to monitor onboarding progress

## Monitoring and Troubleshooting

### Real-time Monitoring
```bash
# Monitor onboarding progress
tail -f /opt/k3s-onboarding/onboarding.log

# Check current status
cat /opt/k3s-onboarding/status.json | jq .

# Health check endpoint
curl http://k3s2:8080 | jq .
```

### Common Issues and Resolution

#### Network Connectivity Issues
- **Symptom**: Repeated connectivity validation failures
- **Resolution**: Check network configuration and firewall rules
- **Log pattern**: `ERROR: Cannot reach k3s1 API server`

#### K3s Agent Startup Issues
- **Symptom**: K3s installation succeeds but agent fails to start
- **Resolution**: Check systemd service status and logs
- **Log pattern**: `K3s agent failed to become ready within timeout`

#### Cluster Join Failures
- **Symptom**: Node doesn't appear in cluster or remains NotReady
- **Resolution**: Verify cluster token and network policies
- **Log pattern**: `Node failed to join cluster within timeout`

## Testing and Validation

The enhanced configuration includes comprehensive validation tests:

```bash
# Run validation tests
./tests/validation/test-k3s2-cloud-init-enhanced.sh
```

**Test coverage**:
- YAML syntax validation
- Required package verification
- Health check script structure
- Retry mechanism implementation
- Logging system validation
- Status tracking verification
- Health check endpoint configuration
- Connectivity validation logic
- Node labeling with retry
- Error handling implementation

## Future Enhancements

### Potential Improvements
1. **Metrics integration**: Export onboarding metrics to Prometheus
2. **Webhook notifications**: Send status updates to external systems
3. **Configuration validation**: Pre-flight checks for cluster configuration
4. **Backup and recovery**: Automated backup of critical configuration files
5. **Multi-cluster support**: Support for joining different clusters based on configuration

### Integration Opportunities
1. **Flux monitoring**: Integration with Flux health checks
2. **Grafana dashboards**: Visualization of onboarding metrics
3. **Alerting**: Automated alerts for onboarding failures
4. **Automation**: Trigger additional configuration based on onboarding status