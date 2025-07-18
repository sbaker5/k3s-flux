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