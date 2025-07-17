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