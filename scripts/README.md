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

## post-onboarding-health-verification.sh

Comprehensive health verification system that validates all systems are operational and properly distributed across both k3s1 and k3s2 nodes after successful onboarding.

### Usage

```bash
# Run comprehensive post-onboarding health verification
./scripts/post-onboarding-health-verification.sh

# Generate detailed health report
./scripts/post-onboarding-health-verification.sh --report

# Attempt to fix identified issues (where possible)
./scripts/post-onboarding-health-verification.sh --fix

# Include performance and load distribution tests
./scripts/post-onboarding-health-verification.sh --performance

# Combined comprehensive verification with reporting
./scripts/post-onboarding-health-verification.sh --report --performance
```

### Verification Modules

The script performs comprehensive validation across six key areas:

#### 1. Multi-Node Cluster Health
- **Node Status**: Validates both k3s1 and k3s2 are Ready
- **Node Roles**: Verifies control plane and worker node assignments
- **Resource Capacity**: Checks CPU, memory, and pod capacity on both nodes
- **System Pod Distribution**: Validates system components across nodes

#### 2. Storage Redundancy Verification
- **Longhorn Node Health**: Ensures both nodes are ready for storage
- **Disk Configuration**: Validates disk setup on both nodes
- **Volume Replica Distribution**: Checks existing volumes have cross-node replicas
- **Default Replica Settings**: Verifies configuration for automatic redundancy

#### 3. Application Distribution Verification
- **Pod Distribution**: Validates applications are scheduled across both nodes
- **Deployment Health**: Checks all deployments are healthy and distributed
- **DaemonSet Distribution**: Ensures system DaemonSets run on both nodes
- **Load Balancing**: Verifies reasonable distribution ratios

#### 4. Network Connectivity Verification
- **CNI Health**: Validates Flannel network overlay across nodes
- **Cross-Node Connectivity**: Tests pod-to-pod communication between nodes
- **Service Accessibility**: Verifies services work from both nodes
- **NodePort Functionality**: Tests ingress accessibility on both nodes

#### 5. Monitoring Integration Verification
- **Node Metrics**: Ensures both nodes are being monitored
- **Prometheus Targets**: Validates metric collection from both nodes
- **Grafana Integration**: Confirms dashboards show multi-node data
- **Alert Coverage**: Verifies alerting covers both nodes

#### 6. GitOps Reconciliation Verification
- **Flux Controller Health**: Validates all GitOps controllers are operational
- **k3s2 Configuration**: Confirms k3s2-specific resources are applied
- **Kustomization Status**: Checks all configurations are reconciled
- **Multi-Node Management**: Verifies GitOps manages both nodes

### Performance Testing (Optional)

When using `--performance`, additional tests are performed:

#### Load Distribution Testing
- **Pod Scheduling**: Creates test deployment to validate scheduler distribution
- **Balance Analysis**: Measures distribution ratios and balance quality
- **Scalability Assessment**: Evaluates cluster capacity and headroom

#### Storage Performance Testing
- **Cross-Node Storage**: Tests storage provisioning on both nodes
- **I/O Performance**: Measures read/write speeds across nodes
- **Redundancy Validation**: Confirms storage redundancy is functional

### What it validates

- ✅ **Multi-Node Operations**: Both nodes operational and integrated
- ✅ **Storage Redundancy**: Distributed storage working across nodes
- ✅ **Application Distribution**: Workloads properly distributed
- ✅ **Network Connectivity**: Cross-node communication functional
- ✅ **Monitoring Coverage**: Both nodes monitored and alerting
- ✅ **GitOps Management**: Declarative management of both nodes

### What it catches

- ✅ Node readiness issues
- ✅ Storage redundancy failures
- ✅ Application scheduling problems
- ✅ Network connectivity issues
- ✅ Monitoring integration gaps
- ✅ GitOps reconciliation failures

### Exit codes

- `0` - All verifications passed, k3s2 onboarding fully successful
- `1-5` - Number of failed verification areas (specific issues identified)

### Report Generation

When using `--report`, generates detailed markdown report at:
```
/tmp/post-onboarding-reports/post-onboarding-health-YYYYMMDD-HHMMSS.md
```

### Integration

This script is designed for:
- ✅ **Post-deployment validation** - Verify successful k3s2 onboarding
- ✅ **Operational verification** - Confirm multi-node cluster health
- ✅ **Automated testing** - Integration with deployment pipelines
- ✅ **Health monitoring** - Regular multi-node cluster assessments

## storage-redundancy-validator.sh

Specialized validation tool focused specifically on storage redundancy across k3s1 and k3s2 nodes, ensuring Longhorn volumes are properly distributed for high availability.

### Usage

```bash
# Validate existing storage redundancy configuration
./scripts/storage-redundancy-validator.sh

# Create test volume to validate redundancy functionality
./scripts/storage-redundancy-validator.sh --create-test-volume

# Generate detailed storage redundancy report
./scripts/storage-redundancy-validator.sh --report

# Combined test volume creation and reporting
./scripts/storage-redundancy-validator.sh --create-test-volume --report
```

### Validation Areas

#### 1. Longhorn Node Configuration
- **Node Registration**: Validates both k3s1 and k3s2 are registered in Longhorn
- **Node Readiness**: Ensures both nodes are ready and schedulable for storage
- **Disk Configuration**: Verifies disk setup and mount points on both nodes
- **Storage Capacity**: Checks available storage capacity on each node

#### 2. Storage Class Configuration
- **Longhorn Storage Class**: Validates storage class exists and is configured
- **Replica Count Settings**: Checks default replica count for redundancy
- **Default Class Status**: Verifies if Longhorn is the default storage class
- **Parameter Validation**: Ensures storage class parameters support redundancy

#### 3. Existing Volume Analysis
- **Volume Inventory**: Catalogs all existing Longhorn volumes
- **Replica Distribution**: Analyzes replica placement across nodes
- **Redundancy Status**: Identifies volumes with/without redundancy
- **Health Assessment**: Validates volume health and accessibility

#### 4. Test Volume Validation (Optional)
- **Dynamic Provisioning**: Creates test PVC to validate provisioning
- **Replica Creation**: Verifies test volume gets proper replica count
- **Cross-Node Distribution**: Confirms replicas are placed on different nodes
- **Data Persistence**: Tests basic I/O operations on test volume

### What it validates

- ✅ **Node Readiness**: Both nodes ready for storage operations
- ✅ **Disk Configuration**: Proper disk setup and mount points
- ✅ **Replica Settings**: Default configuration supports redundancy
- ✅ **Volume Distribution**: Existing volumes have cross-node replicas
- ✅ **Dynamic Provisioning**: New volumes get proper redundancy
- ✅ **Data Accessibility**: Storage is accessible from both nodes

### What it catches

- ✅ Missing or misconfigured Longhorn nodes
- ✅ Incorrect replica count settings
- ✅ Volumes without redundancy
- ✅ Storage provisioning failures
- ✅ Cross-node distribution issues
- ✅ Disk configuration problems

### Exit codes

- `0` - Storage redundancy is properly configured and functional
- `1` - Issues found that require attention
- `2` - Critical failures in storage redundancy

## application-deployment-verifier.sh

Validation tool that ensures applications can be deployed and distributed correctly across k3s1 and k3s2 nodes, verifying the cluster's application hosting capabilities.

### Usage

```bash
# Verify existing application deployments
./scripts/application-deployment-verifier.sh

# Deploy test application to validate deployment capabilities
./scripts/application-deployment-verifier.sh --deploy-test-app

# Generate detailed application deployment report
./scripts/application-deployment-verifier.sh --report

# Combined test deployment and reporting
./scripts/application-deployment-verifier.sh --deploy-test-app --report
```

### Verification Areas

#### 1. Existing Deployment Analysis
- **Deployment Health**: Validates all existing deployments are healthy
- **Pod Distribution**: Analyzes pod placement across k3s1 and k3s2
- **Replica Balance**: Checks distribution ratios for multi-replica deployments
- **Node Utilization**: Evaluates how well both nodes are utilized

#### 2. Service Accessibility Verification
- **Service Discovery**: Validates services are properly configured
- **NodePort Testing**: Tests NodePort services on both nodes
- **Load Balancing**: Verifies traffic can reach pods on both nodes
- **Service Endpoints**: Confirms service endpoints include both nodes

#### 3. Ingress Controller Distribution
- **NGINX Ingress**: Validates ingress controller deployment
- **Multi-Node Availability**: Ensures ingress works from both nodes
- **Traffic Routing**: Verifies ingress can route to pods on either node
- **High Availability**: Confirms ingress controller redundancy

#### 4. Test Application Deployment (Optional)
- **Multi-Replica Deployment**: Creates test app with multiple replicas
- **Cross-Node Scheduling**: Validates pods are scheduled on both nodes
- **Service Creation**: Tests service creation and accessibility
- **Application Functionality**: Verifies application works on both nodes

### What it validates

- ✅ **Application Health**: All deployments are healthy and operational
- ✅ **Multi-Node Distribution**: Applications utilize both nodes
- ✅ **Service Accessibility**: Services work from both nodes
- ✅ **Load Balancing**: Traffic is distributed across nodes
- ✅ **Ingress Functionality**: External access works via both nodes
- ✅ **Deployment Capabilities**: New applications can be deployed successfully

### What it catches

- ✅ Unhealthy deployments
- ✅ Single-node scheduling issues
- ✅ Service accessibility problems
- ✅ Ingress controller issues
- ✅ Load balancing failures
- ✅ Application deployment problems

### Exit codes

- `0` - Application deployment and distribution is working correctly
- `1` - Issues found that need attention
- `2` - Critical application deployment failures

## performance-load-tester.sh

Performance and load distribution testing utility that validates performance characteristics and load distribution across k3s1 and k3s2 nodes.

### Usage

```bash
# Run basic performance and distribution tests
./scripts/performance-load-tester.sh

# Include network performance testing
./scripts/performance-load-tester.sh --run-load-test

# Include storage performance testing
./scripts/performance-load-tester.sh --run-storage-test

# Generate detailed performance report
./scripts/performance-load-tester.sh --report

# Comprehensive performance testing with reporting
./scripts/performance-load-tester.sh --run-load-test --run-storage-test --report
```

### Testing Areas

#### 1. Node Resource Utilization
- **CPU Usage**: Monitors current CPU utilization on both nodes
- **Memory Usage**: Tracks memory consumption across nodes
- **Resource Availability**: Assesses available capacity for scaling
- **Utilization Balance**: Evaluates resource distribution between nodes

#### 2. Pod Scheduling Distribution
- **Scheduler Testing**: Creates test deployment to validate scheduling
- **Distribution Analysis**: Measures pod placement across nodes
- **Balance Quality**: Evaluates how evenly pods are distributed
- **Scaling Behavior**: Tests how scheduler handles multiple replicas

#### 3. Network Performance Testing (Optional)
- **Cross-Node Bandwidth**: Measures network performance between nodes
- **Latency Testing**: Evaluates network latency between nodes
- **Throughput Analysis**: Tests sustained network throughput
- **Performance Benchmarking**: Compares against expected performance

#### 4. Storage Performance Testing (Optional)
- **I/O Performance**: Tests read/write speeds on both nodes
- **Cross-Node Storage**: Validates storage performance across nodes
- **Provisioning Speed**: Measures PVC creation and binding times
- **Storage Redundancy**: Tests performance with replicated storage

#### 5. Cluster Scalability Assessment
- **Capacity Analysis**: Evaluates current vs. maximum cluster capacity
- **Headroom Calculation**: Determines available scaling capacity
- **Resource Limits**: Identifies potential scaling bottlenecks
- **Growth Planning**: Provides insights for capacity planning

### What it tests

- ✅ **Resource Utilization**: Current and available capacity on both nodes
- ✅ **Load Distribution**: How evenly workloads are distributed
- ✅ **Network Performance**: Cross-node communication performance
- ✅ **Storage Performance**: I/O performance across nodes
- ✅ **Scalability**: Cluster's ability to handle additional workloads
- ✅ **Performance Baselines**: Establishes performance benchmarks

### What it identifies

- ✅ Resource utilization imbalances
- ✅ Network performance bottlenecks
- ✅ Storage performance issues
- ✅ Scheduling distribution problems
- ✅ Scalability limitations
- ✅ Performance regressions

### Exit codes

- `0` - Performance and load distribution is optimal
- `1` - Performance issues or imbalances detected
- `2` - Critical performance problems found

### Performance Metrics

The script provides detailed metrics including:
- **Node Resource Usage**: CPU/memory utilization percentages
- **Pod Distribution**: Exact pod counts and distribution ratios
- **Network Bandwidth**: Measured throughput between nodes
- **Storage I/O**: Read/write speeds in MB/s
- **Scalability Headroom**: Available capacity for growth
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