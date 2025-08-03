# GitOps Validation Scripts

## validate-kustomizations.sh

Simple validation script that checks if all major kustomization.yaml files can build successfully.

### Usage

```bash
# Run validation manually
./scripts/validate-kustomizations.sh

# Make executable if needed
chmod +x scripts/validate-kustomizations.sh
```

### What it checks

- `clusters/k3s-flux` - Main cluster configuration
- `infrastructure` - Core infrastructure components  
- `infrastructure/monitoring` - Prometheus/Grafana stack
- `infrastructure/longhorn/base` - Storage configuration
- `infrastructure/nginx-ingress` - Ingress controller
- `apps/*/base` - Application base configurations
- `apps/*/overlays/*` - Environment-specific overlays

### What it catches

- ✅ YAML syntax errors
- ✅ Missing resource files
- ✅ Invalid kustomization configurations
- ✅ Resource reference errors

### Exit codes

- `0` - All validations passed
- `1` - One or more validations failed

### Integration

This script is automatically run by:
- ✅ **Git pre-commit hook** - Blocks bad commits locally (simple, no dependencies)
- 🔄 CI/CD pipeline step (future)
- 🔧 Manual validation before commits

See [Pre-commit Setup](../docs/pre-commit-setup.md) for hook installation instructions.

## check-immutable-fields.sh

Advanced validation tool that detects changes to immutable Kubernetes fields between Git revisions that would cause reconciliation failures.

### Usage

```bash
# Check changes between HEAD~1 and HEAD (default)
./scripts/check-immutable-fields.sh

# Check changes between specific Git references
./scripts/check-immutable-fields.sh -b main -h feature-branch

# Enable verbose output for debugging
./scripts/check-immutable-fields.sh -v

# Check changes over multiple commits
./scripts/check-immutable-fields.sh -b HEAD~5
```

### What it detects

**Immutable fields by resource type:**
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

### What it catches

- ✅ Changes to immutable Kubernetes fields that would cause `field is immutable` errors
- ✅ Selector modifications that would break existing resources
- ✅ Storage class or capacity changes in PVCs
- ✅ Service type changes that would fail reconciliation
- ✅ Any field modification that requires resource recreation

### Exit codes

- `0` - No immutable field changes detected
- `1` - Immutable field violations found (would cause reconciliation failures)

### Integration

This script can be integrated into:
- ✅ **Git pre-commit hooks** - Prevent commits with immutable field conflicts
- ✅ **CI/CD pipelines** - Validate changes before deployment
- ✅ **Manual validation** - Check changes before applying to cluster
- 🔄 **Automated recovery systems** - Detect patterns requiring resource recreation

### Requirements

- `kubectl` - For kustomization building and validation
- `yq` (optional) - For precise YAML field extraction (falls back to awk/grep)
- Git repository with kustomization.yaml files

## test-alert-rules.sh

Validation script for testing PrometheusRule resources and alert rule syntax.

### Usage

```bash
# Test all alert rules in monitoring infrastructure
./scripts/test-alert-rules.sh

# Make executable if needed
chmod +x scripts/test-alert-rules.sh
```

### What it validates

- **YAML syntax** - Ensures all PrometheusRule files are valid YAML
- **Kubernetes resource structure** - Validates PrometheusRule CRD compliance
- **Alert rule syntax** - Checks PromQL expressions for syntax errors
- **Required metadata** - Ensures all alerts have summary and description
- **Integration** - Validates rules work with existing monitoring stack

### What it catches

- ✅ Invalid PromQL expressions
- ✅ Missing alert metadata (summary, description)
- ✅ Malformed PrometheusRule resources
- ✅ YAML syntax errors in alert files

### Exit codes

- `0` - All alert rules are valid
- `1` - One or more validation errors found

### Integration

This script is used for:
- ✅ **Manual validation** - Test alert rules before deployment
- ✅ **CI/CD validation** - Automated testing in pipelines
- 🔄 **Pre-commit hooks** - Validate alert changes before commit

## cleanup-stuck-monitoring.sh

Emergency cleanup script for stuck monitoring resources and PVCs in the hybrid monitoring architecture.

### Usage

```bash
# Clean up stuck monitoring resources
./scripts/cleanup-stuck-monitoring.sh

# Make executable if needed
chmod +x scripts/cleanup-stuck-monitoring.sh
```

### What it cleans up

- **Stuck PVCs** - Removes PersistentVolumeClaims with finalizer cleanup
- **Failed HelmReleases** - Cleans up stuck Helm deployments
- **Orphaned Helm secrets** - Removes leftover Helm release secrets
- **Monitoring kustomization** - Safely suspends/resumes for clean restart

### Safety features

- ✅ **Confirmation prompts** - Asks before destructive operations
- ✅ **Backup creation** - Creates resource backups before deletion
- ✅ **Graceful suspension** - Properly suspends Flux reconciliation
- ✅ **Status verification** - Checks resource states before proceeding

### When to use

- Monitoring stack stuck in failed state
- PVCs stuck in terminating state
- HelmReleases failing to upgrade/rollback
- Need to reset monitoring to clean state

### Integration

This script supports:
- ✅ **Emergency recovery** - Quick resolution of stuck monitoring
- ✅ **Maintenance operations** - Clean slate for monitoring updates
- ✅ **Troubleshooting** - Reset monitoring when debugging issues

### Example Output

```bash
[ERROR] Immutable field change detected in Deployment/my-app
[ERROR]   Field: spec.selector
[ERROR]   Before: app=my-app,version=v1
[ERROR]   After:  app=my-app,version=v2
[ERROR]   Namespace: default
[ERROR] 
[ERROR] Found 1 immutable field violation(s)
[ERROR] These changes would cause Kubernetes reconciliation failures.
[ERROR] Consider using resource replacement strategies or blue-green deployments.
```

## k3s2-pre-onboarding-validation.sh

Comprehensive validation script that ensures the k3s cluster is ready for k3s2 node onboarding. This script orchestrates multiple validation modules to verify cluster health, network connectivity, storage systems, and monitoring infrastructure.

### Usage

```bash
# Run comprehensive pre-onboarding validation
./scripts/k3s2-pre-onboarding-validation.sh

# Generate detailed validation report
./scripts/k3s2-pre-onboarding-validation.sh --report

# Attempt to fix identified issues (where possible)
./scripts/k3s2-pre-onboarding-validation.sh --fix

# Combined report generation and issue fixing
./scripts/k3s2-pre-onboarding-validation.sh --report --fix
```

### Validation Modules

The script includes four specialized validation modules:

#### 1. Cluster Readiness Validation (`cluster-readiness-validation.sh`)
- **k3s1 Control Plane Health**: Validates control plane node status and components
- **API Server Responsiveness**: Tests Kubernetes API server health endpoints
- **Flux System Health**: Verifies GitOps controllers are operational
- **Resource Availability**: Checks cluster capacity for additional nodes

#### 2. Network Connectivity Verification (`network-connectivity-verification.sh`)
- **Cluster Network Configuration**: Validates CIDR ranges and network policies
- **Flannel CNI Health**: Verifies container network interface functionality
- **NodePort Accessibility**: Tests ingress controller port availability
- **DNS Resolution**: Validates cluster DNS functionality

#### 3. Storage System Health Check (`storage-health-check.sh`)
- **Longhorn System Health**: Validates distributed storage system status
- **Storage Prerequisites**: Checks iSCSI and kernel module requirements
- **Disk Discovery System**: Verifies automated disk detection functionality
- **Storage Capacity**: Validates available storage for new node integration

#### 4. Monitoring System Validation (`monitoring-validation.sh`)
- **Prometheus Health**: Validates metrics collection system status
- **Grafana Accessibility**: Tests dashboard and visualization availability
- **ServiceMonitor/PodMonitor**: Verifies metric collection configurations
- **Alert Manager**: Validates alerting system functionality

### What it validates

- ✅ **Cluster Health**: Control plane, API server, and core components
- ✅ **Network Readiness**: CNI, ingress, and connectivity prerequisites
- ✅ **Storage Integration**: Longhorn health and expansion readiness
- ✅ **Monitoring Systems**: Metrics collection and alerting functionality
- ✅ **GitOps Operations**: Flux controllers and reconciliation health
- ✅ **Resource Capacity**: Available resources for node expansion

### What it catches

- ✅ Control plane component failures
- ✅ Network configuration issues
- ✅ Storage system problems
- ✅ Monitoring infrastructure failures
- ✅ GitOps reconciliation issues
- ✅ Resource capacity constraints

### Exit codes

- `0` - All validations passed, cluster ready for k3s2 onboarding
- `1` - Critical issues found, onboarding not recommended
- `2` - Warnings present, onboarding possible with caution

### Report Generation

When using `--report`, the script generates a detailed markdown report at:
```
/tmp/k3s2-validation-reports/k3s2-pre-onboarding-YYYYMMDD-HHMMSS.md
```

The report includes:
- **Executive Summary**: Overall readiness status
- **Detailed Results**: Per-module validation results
- **Issue Analysis**: Identified problems and recommendations
- **Next Steps**: Specific actions required before onboarding

### Integration

This script is designed for:
- ✅ **Pre-deployment validation** - Verify cluster readiness before k3s2 onboarding
- ✅ **Automated testing** - Integration with CI/CD pipelines
- ✅ **Operational procedures** - Regular cluster health assessments
- ✅ **Troubleshooting** - Systematic diagnosis of cluster issues

### Requirements

- `kubectl` - Kubernetes cluster access
- `flux` CLI - GitOps system validation
- `curl` - HTTP endpoint testing
- Cluster admin permissions for comprehensive validation

### Example Output

```bash
$ ./scripts/k3s2-pre-onboarding-validation.sh --report

k3s2 Pre-Onboarding Validation v1.0
===================================

=== CLUSTER READINESS VALIDATION ===
✅ k3s1 node status: Ready
✅ Control plane: k3s embedded (no separate pods)
✅ API server health check: OK
✅ Flux system health: All controllers operational

=== NETWORK CONNECTIVITY VERIFICATION ===
✅ Cluster CIDR: matches k3s default (10.42.0.0/16)
✅ Service CIDR: matches k3s default (10.43.0.0/16)
✅ Flannel CNI: configuration found
✅ NodePort services: accessible on ports 30080, 30443

=== STORAGE SYSTEM HEALTH CHECK ===
✅ Longhorn manager: 1/1 pods running
✅ Longhorn driver deployer: 1/1 pods running
✅ Storage prerequisites: iSCSI daemon active
✅ Disk discovery: DaemonSet operational

=== MONITORING SYSTEM VALIDATION ===
✅ Prometheus pods: 1/1 running
✅ Grafana service: accessible
✅ ServiceMonitor/PodMonitor: configurations valid
✅ Alert Manager: operational

=== VALIDATION SUMMARY ===
✅ All validation checks passed (24/24)
✅ Cluster is ready for k3s2 node onboarding
📄 Detailed report: /tmp/k3s2-validation-reports/k3s2-pre-onboarding-20250131-143022.md

Next steps:
1. Prepare k3s2 hardware/VM
2. Deploy with cloud-init configuration
3. Monitor onboarding progress via HTTP endpoint
```
## 
Development Best Practices

### Script Development Best Practices

When developing or modifying shell scripts, especially validation scripts, follow these critical best practices:

#### Critical Guidelines
- **NEVER use `((var++))` with `set -euo pipefail`** - Use `$((var + 1))` instead
- **Add `|| true` to test functions** that should continue even after failures
- **Always use timeouts** for network operations (`--connect-timeout`, `--timeout`)
- **Implement cleanup functions** and use `trap cleanup_function EXIT`
- **Account for k3s architecture** - embedded components, not separate pods

#### Required Resources
- **[Script Development Best Practices](../.kiro/steering/08-script-development-best-practices.md)** - **CRITICAL**: Comprehensive best practices automatically applied when working with shell scripts
- **[Validation Script Development](../docs/troubleshooting/validation-script-development.md)** - Detailed lessons learned and troubleshooting patterns
- **[Validation Test Cases](../tests/validation/)** - Example validation patterns and test scenarios

#### Key Patterns
- Use consistent logging functions with timestamps
- Implement proper error handling for strict mode
- Include resource cleanup and timeout handling
- Test with both passing and failing conditions
- Provide progress indicators for long operations

### Script Development Checklist

When creating new validation scripts:

- [ ] Use consistent logging functions with timestamps
- [ ] Implement proper error handling for `set -euo pipefail`
- [ ] Add timeout handling for network operations
- [ ] Include resource cleanup functions
- [ ] Test with both passing and failing conditions
- [ ] Account for k3s architecture differences
- [ ] Provide progress indicators for long operations
- [ ] Generate structured output (JSON/markdown reports)
- [ ] Include usage examples and exit code documentation