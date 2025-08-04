# k3s2 Node Onboarding Orchestration System

## Overview

The k3s2 Node Onboarding Orchestration System provides a comprehensive, automated approach to adding the k3s2 worker node to the existing k3s cluster. The system coordinates all onboarding steps, provides progress tracking, status reporting, rollback capabilities, and comprehensive logging.

## Features

- **Automated Orchestration**: Coordinates all onboarding phases automatically
- **Progress Tracking**: Real-time progress monitoring with phase-by-phase status
- **State Management**: Persistent state tracking with resume capability
- **Rollback Support**: Complete rollback of failed onboarding attempts
- **Comprehensive Logging**: Detailed logging and troubleshooting output
- **Dry Run Mode**: Test the onboarding process without making changes
- **Status Reporting**: Check current onboarding status at any time
- **Error Recovery**: Resume interrupted onboarding processes

## Architecture

### Onboarding Phases

The orchestration system executes the following phases in sequence:

1. **Pre-validation** - Validate cluster readiness and prerequisites
2. **GitOps Activation** - Enable k3s2 configuration in Git repository
3. **Node Join Monitoring** - Monitor k3s2 joining the cluster
4. **Storage Integration** - Validate Longhorn storage integration
5. **Network Validation** - Verify network connectivity between nodes
6. **Monitoring Integration** - Ensure monitoring includes k3s2 metrics
7. **Security Validation** - Validate RBAC and security posture
8. **Post Validation** - Run comprehensive validation scripts
9. **Health Verification** - Final health and performance checks

### State Management

The system maintains persistent state in JSON format, tracking:
- Current phase execution status
- Phase completion timestamps
- Error messages and failure details
- Overall progress counters

State files are stored in `/tmp/k3s2-onboarding-state/` and can be used to resume interrupted processes.

## Usage

### Basic Onboarding

```bash
# Standard onboarding with progress reports
./scripts/k3s2-onboarding-orchestrator.sh --report

# Onboarding with automatic issue fixing
./scripts/k3s2-onboarding-orchestrator.sh --auto-fix --report
```

### Testing and Validation

```bash
# Dry run to test the process without changes
./scripts/k3s2-onboarding-orchestrator.sh --dry-run --verbose

# Skip pre-validation (not recommended)
./scripts/k3s2-onboarding-orchestrator.sh --skip-validation
```

### Status and Recovery

```bash
# Check current onboarding status
./scripts/k3s2-onboarding-orchestrator.sh --status

# Resume interrupted onboarding
./scripts/k3s2-onboarding-orchestrator.sh --resume --verbose

# Rollback failed onboarding
./scripts/k3s2-onboarding-orchestrator.sh --rollback
```

### Advanced Options

```bash
# Verbose logging for troubleshooting
./scripts/k3s2-onboarding-orchestrator.sh --verbose

# Generate detailed reports
./scripts/k3s2-onboarding-orchestrator.sh --report

# Help and usage information
./scripts/k3s2-onboarding-orchestrator.sh --help
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Simulate the onboarding process without making changes |
| `--skip-validation` | Skip pre-onboarding validation (not recommended) |
| `--auto-fix` | Automatically attempt to fix issues during validation |
| `--report` | Generate detailed progress and status reports |
| `--rollback` | Rollback a failed onboarding attempt |
| `--status` | Check current onboarding status |
| `--resume` | Resume a previously interrupted onboarding |
| `--verbose` | Enable verbose logging |
| `--help` | Show help message |

## Prerequisites

### Required Tools

- `kubectl` - Kubernetes command-line tool
- `flux` - Flux CLI for GitOps operations
- `jq` - JSON processor for state management
- `git` - Git version control for GitOps changes

### Cluster Requirements

- k3s1 control plane node must be healthy and ready
- Flux GitOps system must be operational
- Longhorn storage system must be running
- Git repository must be accessible for GitOps changes

### Network Requirements

- k3s2 node must be able to reach k3s1:6443 (Kubernetes API)
- Cluster network (Flannel VXLAN) must be functional
- NodePort services (30080/30443) must be accessible

## Phase Details

### Phase 1: Pre-validation

**Purpose**: Validate that the cluster is ready to accept k3s2

**Validations**:
- k3s1 control plane health
- Flux GitOps system status
- Core infrastructure components
- Resource capacity planning
- Network connectivity prerequisites
- Storage system readiness

**Dependencies**: None (first phase)

**Failure Impact**: Blocks onboarding until issues are resolved

### Phase 2: GitOps Activation

**Purpose**: Enable k3s2 configuration in the Git repository

**Actions**:
- Uncomment k3s2-node-config in `infrastructure/storage/kustomization.yaml`
- Commit changes to Git repository
- Push changes to remote repository
- Trigger Flux reconciliation

**Dependencies**: Pre-validation must pass

**Failure Impact**: k3s2 configuration won't be applied by Flux

### Phase 3: Node Join Monitoring

**Purpose**: Monitor k3s2 joining the cluster

**Monitoring**:
- Wait for k3s2 node to appear in cluster
- Verify node reaches Ready status
- Display node details and status
- Timeout after 5 minutes if node doesn't join

**Dependencies**: GitOps activation must complete

**Failure Impact**: Node hasn't joined - check cloud-init and network

### Phase 4: Storage Integration

**Purpose**: Validate Longhorn recognizes and configures k3s2

**Validations**:
- Longhorn node CRD creation for k3s2
- Node storage readiness status
- Disk discovery and configuration
- Storage capacity registration

**Dependencies**: Node must be joined and ready

**Failure Impact**: Storage redundancy won't be available

### Phase 5: Network Validation

**Purpose**: Verify network connectivity between nodes

**Tests**:
- Flannel CNI health on both nodes
- kube-proxy functionality
- Cross-node pod connectivity
- Service discovery and routing

**Dependencies**: Node and storage integration

**Failure Impact**: Network issues may affect pod scheduling

### Phase 6: Monitoring Integration

**Purpose**: Ensure monitoring includes k3s2 metrics

**Validations**:
- Node-exporter DaemonSet on k3s2
- Prometheus target discovery
- Grafana dashboard readiness
- Metrics collection verification

**Dependencies**: Network validation must pass

**Failure Impact**: k3s2 won't appear in monitoring dashboards

### Phase 7: Security Validation

**Purpose**: Validate RBAC and security posture

**Checks**:
- Node RBAC permissions
- SOPS secret decryption
- Network policies
- Security contexts

**Dependencies**: Monitoring integration

**Failure Impact**: Security vulnerabilities may exist

### Phase 8: Post Validation

**Purpose**: Run comprehensive validation scripts

**Scripts**:
- Cluster readiness validation
- Storage health checks
- Monitoring system validation
- Network connectivity verification

**Dependencies**: Security validation

**Failure Impact**: System may have undetected issues

### Phase 9: Health Verification

**Purpose**: Final comprehensive health and performance checks

**Verifications**:
- Multi-node cluster health
- Storage redundancy functionality
- Application distribution
- Network connectivity
- Monitoring integration
- GitOps reconciliation

**Dependencies**: Post validation must pass

**Failure Impact**: Onboarding considered incomplete

## State Management

### State File Location

State is stored in `/tmp/k3s2-onboarding-state/onboarding-state.json`

### State File Format

```json
{
    "timestamp": "2024-01-15T10:30:00Z",
    "current_phase": "storage_integration",
    "completed_phases": 3,
    "failed_phases": 0,
    "total_phases": 9,
    "phase_status": {
        "pre_validation": "completed",
        "gitops_activation": "completed",
        "node_join_monitoring": "completed",
        "storage_integration": "in_progress",
        "network_validation": "not_started",
        ...
    },
    "phase_errors": {
        "pre_validation": "",
        "gitops_activation": "",
        ...
    }
}
```

### Resume Capability

The `--resume` option allows continuing from the last successful phase:

1. Loads state from JSON file
2. Skips completed phases
3. Continues from the next incomplete phase
4. Maintains error history and timing information

## Logging and Reporting

### Log Files

- **Location**: `/tmp/k3s2-onboarding-logs/`
- **Format**: `k3s2-onboarding-YYYYMMDD-HHMMSS.log`
- **Content**: Timestamped log entries with severity levels

### Log Levels

- `INFO`: General information and progress updates
- `WARN`: Non-critical issues that don't stop onboarding
- `ERROR`: Critical issues that cause phase failures
- `SUCCESS`: Successful completion of operations
- `DEBUG`: Detailed troubleshooting information (verbose mode)
- `PROGRESS`: Phase progress and timing information

### Report Generation

When `--report` is specified, generates comprehensive reports:

- **Location**: `/tmp/k3s2-onboarding-logs/`
- **Format**: `k3s2-onboarding-report-YYYYMMDD-HHMMSS.md`
- **Content**: Executive summary, phase details, cluster state, recommendations

## Rollback System

### Rollback Process

The `--rollback` option performs complete onboarding rollback:

1. **Node Drain**: Gracefully drain k3s2 node of workloads
2. **Node Removal**: Remove k3s2 from cluster
3. **GitOps Deactivation**: Comment out k3s2-node-config in Git
4. **Flux Reconciliation**: Trigger Flux to apply deactivation
5. **State Cleanup**: Remove onboarding state files

### Rollback Safety

- Confirms rollback action with user prompt
- Supports dry-run mode for testing
- Maintains backup files for recovery
- Commits rollback changes to Git with descriptive messages

## Error Handling

### Phase Failure Handling

When a phase fails:

1. **Error Capture**: Detailed error message and context saved
2. **State Persistence**: Current state saved for resume capability
3. **Graceful Stop**: Onboarding stops at failed phase
4. **Recovery Options**: Status, resume, or rollback available

### Common Error Scenarios

| Error | Cause | Resolution |
|-------|-------|------------|
| Pre-validation failure | Cluster not ready | Fix cluster issues, re-run |
| Node join timeout | Network/cloud-init issues | Check k3s2 connectivity |
| Storage integration failure | Longhorn issues | Verify storage prerequisites |
| Network validation failure | CNI problems | Check Flannel configuration |
| GitOps activation failure | Git access issues | Verify repository permissions |

## Integration with Existing Scripts

The orchestrator integrates with existing validation scripts:

- `k3s2-pre-onboarding-validation.sh` - Pre-validation phase
- `cluster-readiness-validation.sh` - Cluster health checks
- `network-connectivity-verification.sh` - Network validation
- `storage-health-check.sh` - Storage system validation
- `monitoring-validation.sh` - Monitoring system checks
- `security-validation.sh` - Security posture validation
- `post-onboarding-health-verification.sh` - Final health verification

## Best Practices

### Before Onboarding

1. **Backup Critical Data**: Ensure important data is backed up
2. **Verify Prerequisites**: Run pre-validation to check readiness
3. **Plan Maintenance Window**: Schedule during low-usage periods
4. **Test with Dry Run**: Use `--dry-run` to test the process

### During Onboarding

1. **Monitor Progress**: Use `--verbose` for detailed progress tracking
2. **Don't Interrupt**: Let phases complete naturally
3. **Check Status**: Use `--status` if monitoring from another terminal
4. **Save Logs**: Keep log files for troubleshooting

### After Onboarding

1. **Verify Health**: Review final health verification results
2. **Monitor Performance**: Watch cluster performance and resource usage
3. **Test Applications**: Deploy test workloads to verify functionality
4. **Update Documentation**: Record any customizations or issues

### Troubleshooting

1. **Check Logs**: Review detailed log files for error context
2. **Verify Prerequisites**: Ensure all requirements are met
3. **Use Status Command**: Check current phase and error details
4. **Resume Carefully**: Fix issues before resuming
5. **Consider Rollback**: Use rollback for severe issues

## Security Considerations

### Git Repository Access

- Requires write access to Git repository for GitOps changes
- Commits are signed and include descriptive messages
- Changes are pushed to remote repository for audit trail

### Cluster Permissions

- Requires cluster-admin permissions for node management
- Uses existing kubectl configuration and context
- Respects existing RBAC policies and security contexts

### State File Security

- State files contain cluster information
- Stored in temporary directories with appropriate permissions
- Cleaned up after successful completion

## Performance Considerations

### Resource Usage

- Minimal resource overhead during execution
- Uses existing cluster resources for validation
- Temporary test pods are cleaned up automatically

### Timing

- Total onboarding time: 10-20 minutes (depending on cluster size)
- Phase timeouts prevent indefinite waiting
- Configurable wait times for different operations

### Scalability

- Designed for single node addition (k3s2)
- Can be adapted for additional nodes with modifications
- State management supports complex multi-phase operations

## Maintenance

### Regular Updates

- Keep validation scripts updated with cluster changes
- Update timeout values based on cluster performance
- Enhance error handling based on operational experience

### Monitoring

- Monitor onboarding success rates
- Track common failure points
- Update documentation based on user feedback

### Testing

- Regularly test dry-run mode
- Validate rollback functionality
- Test resume capability with interrupted processes

## Requirements Traceability

This orchestration system addresses the following requirements from the k3s1-node-onboarding spec:

- **Requirement 1.3**: Automated onboarding coordination and progress tracking
- **Requirement 7.1**: Comprehensive validation and troubleshooting tools
- **Requirement 7.2**: Clear error messages and resolution steps
- **Requirement 7.4**: Comprehensive logs and status information accessibility

## Conclusion

The k3s2 Node Onboarding Orchestration System provides a robust, automated approach to expanding the k3s cluster. With comprehensive error handling, state management, and rollback capabilities, it ensures reliable node onboarding while maintaining the bulletproof architecture principles of the cluster.

The system's modular design, extensive logging, and integration with existing validation scripts make it a powerful tool for cluster expansion and maintenance operations.