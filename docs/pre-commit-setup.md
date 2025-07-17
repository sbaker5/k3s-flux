# Pre-commit Hook Setup

This repository uses a simple Git pre-commit hook to validate infrastructure changes before they're committed.

## What Gets Validated

Every commit automatically runs:

- ✅ **Kustomization Build Validation** - Ensures all kustomization.yaml files can build successfully

## Installation

### For New Contributors

```bash
# Set up the pre-commit hook (simple, no dependencies)
echo '#!/bin/bash
./scripts/validate-kustomizations.sh' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Verify Installation

```bash
# Test the hook manually
.git/hooks/pre-commit
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

- Missing resource files
- YAML syntax errors  
- Kustomization build failures
- Invalid Kubernetes manifests

This prevents the stuck reconciliation states that require manual recovery.

## Troubleshooting

### Hook Installation Issues
```bash
# Reinstall the hook
echo '#!/bin/bash
./scripts/validate-kustomizations.sh' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Manual Hook Execution
```bash
# Run the hook manually
.git/hooks/pre-commit

# Or run the validation script directly
./scripts/validate-kustomizations.sh
```

### Update Hook
The hook automatically uses the latest version of the validation script from the repository.