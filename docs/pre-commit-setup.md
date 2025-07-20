# Pre-commit Hook Setup

This repository uses a simple Git pre-commit hook to validate infrastructure changes before they're committed.

## What Gets Validated

Every commit automatically runs:

- ✅ **YAML Syntax Validation** - Validates YAML syntax and structure
- ✅ **Kustomization Build Validation** - Ensures all kustomization.yaml files can build successfully
- ✅ **Immutable Field Change Detection** - Prevents changes to immutable Kubernetes fields
- ✅ **Flux Health Check Validation** - Verifies Flux system is healthy before committing
- ✅ **Kubernetes Dry-run Validation** - Validates resources against the cluster if available

### Validation Warnings

The validation may show deprecation warnings that don't block commits but should be addressed:

- `'commonLabels' is deprecated. Please use 'labels' instead` - Update kustomization.yaml files to use the newer `labels` field
- Missing or outdated API versions in Kubernetes resources

## Installation

### Automatic Setup (Recommended)

```bash
# Use the setup script to configure the pre-commit hook
./scripts/setup-pre-commit.sh
```

### Manual Setup

The pre-commit hook is already installed in the repository. If you need to reinstall it:

```bash
# The hook is already present in .git/hooks/pre-commit
# Just ensure it's executable
chmod +x .git/hooks/pre-commit
```

### Verify Installation

```bash
# Test the hook manually
.git/hooks/pre-commit

# Check hook status
ls -la .git/hooks/pre-commit
```

## Usage

Once installed, hooks run automatically on every `git commit`. 

### Normal Workflow
```bash
git add .
git commit -m "update infrastructure"
# Hooks run automatically - commit succeeds if all pass
```

### If Validation Fails
```bash
git add .
git commit -m "broken change"
# ❌ Hooks fail - commit is blocked
# Fix the issues, then try again
git add .
git commit -m "fixed change"
# ✅ Hooks pass - commit succeeds
```

### Skip Hooks (Emergency Only)
```bash
# Only use in emergencies - bypasses all validation
git commit -m "emergency fix" --no-verify
```

## What This Prevents

The pre-commit hooks catch issues **before** they reach Flux:

- YAML syntax errors and malformed manifests
- Kustomization build failures
- Changes to immutable Kubernetes fields that would cause reconciliation failures
- Flux system health issues that could prevent deployments
- Invalid Kubernetes resources that would fail cluster validation
- Missing resource files and broken dependencies

This prevents the stuck reconciliation states that require manual recovery and ensures GitOps resilience.

## Troubleshooting

### Hook Installation Issues
```bash
# The comprehensive pre-commit hook should already be installed
# If missing, use the setup script
./scripts/setup-pre-commit.sh

# Or ensure the hook is executable
chmod +x .git/hooks/pre-commit
```

### Manual Hook Execution
```bash
# Run the full pre-commit hook manually
.git/hooks/pre-commit

# Or run individual validation scripts directly
./scripts/validate-kustomizations.sh
./scripts/check-immutable-fields.sh
```

### Common Issues and Fixes

#### Deprecation Warnings
If you see warnings like `'commonLabels' is deprecated`, update your kustomization.yaml:

```yaml
# Old (deprecated)
commonLabels:
  app: example

# New (recommended)
labels:
- pairs:
    app: example
```

#### Missing Resource Files
If validation fails with "no such file or directory", check that all files listed in the `resources:` section exist:

```yaml
resources:
  - deployment.yaml
  - service.yaml
  - missing-file.yaml  # ❌ This file doesn't exist
```

#### YAML Syntax Errors
Use a YAML validator or IDE with YAML support to catch syntax issues before committing.

#### Flux Health Check Failures
If the Flux health check fails during pre-commit validation:

```bash
# Check Flux system status manually
flux check

# Check Flux controller pods
kubectl get pods -n flux-system

# Check for Flux reconciliation issues
flux get all -A
```

Common Flux issues:
- **Controllers not ready**: Wait for Flux controllers to start or restart them
- **Git repository access**: Verify SSH keys or authentication for Git repositories
- **CRD issues**: Ensure Flux CRDs are properly installed
- **Network connectivity**: Check cluster network access to Git repositories

#### Immutable Field Changes
If the hook detects immutable field changes:

```bash
# Check what fields changed
./scripts/check-immutable-fields.sh -v

# Common immutable fields that cause issues:
# - spec.selector in Deployments
# - spec.clusterIP in Services  
# - spec.accessModes in PVCs
# - spec.storageClassName in PVCs
```

To fix immutable field changes:
1. **Revert the change** if it was unintentional
2. **Delete and recreate** the resource if the change is necessary
3. **Use blue-green deployment** for zero-downtime updates

### Update Hook
The hook automatically uses the latest version of the validation scripts from the repository. The comprehensive pre-commit hook includes:

- **Step 1**: YAML syntax validation (all YAML files with yamllint)
- **Step 2**: Kustomization build validation (kustomization.yaml files with kubectl kustomize)
- **Step 3**: Immutable field change detection (prevents breaking changes)
- **Step 4**: Flux health check validation (ensures Flux system is healthy)
- **Step 5**: Kubernetes dry-run validation (standard K8s resources with kubectl apply --dry-run)

### Validation Strategy by File Type

**Kustomization Files (`kustomization.yaml`)**:
- ✅ Step 1: YAML syntax validation with yamllint
- ✅ Step 2: Build validation with `kubectl kustomize` (proper tool for kustomization files)
- ❌ Step 5: Skipped from kubectl dry-run (Kustomization is a Flux CRD, not standard K8s resource)

**Standard Kubernetes Resources (`.yaml` files)**:
- ✅ Step 1: YAML syntax validation with yamllint
- ❌ Step 2: Not applicable (only for kustomization files)
- ✅ Step 5: kubectl dry-run validation

**Flux Resources (HelmRelease, GitRepository, etc.)**:
- ✅ Step 1: YAML syntax validation with yamllint
- ✅ Step 4: Flux-specific validation (if Flux system is available)
- ✅ Step 5: kubectl dry-run validation (if CRDs are installed)

This approach ensures each file type is validated with the most appropriate tool, avoiding false failures while maintaining thorough validation coverage.