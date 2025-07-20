---
inclusion: always
---

# macOS Development Environment

## Package Management
**ALWAYS use Homebrew (brew) for package installation on macOS. NEVER use pip, apt, yum, or other package managers.**

### Common Tools Installation
```bash
# YAML validation
brew install yamllint

# Python YAML library (if needed)
brew install python3

# Kubernetes tools
brew install kubectl
brew install kustomize
brew install helm

# Flux CLI
brew install fluxcd/tap/flux

# Git and development tools
brew install git
brew install jq
brew install curl
```

### Validation Commands
```bash
# YAML syntax validation - USE THIS instead of python yaml module
yamllint file.yaml

# Kubernetes resource validation
kubectl apply --dry-run=client -f file.yaml

# Kustomization validation
kubectl kustomize path/to/kustomization/

# JSON processing
jq '.data' file.json
```

## Pre-commit Hook Issues

### YAML Validation Failures
The pre-commit hooks use a multi-step validation strategy. Understanding this helps debug validation issues:

**Validation Flow by File Type:**

1. **Kustomization files** (`kustomization.yaml`):
   - ✅ YAML syntax: `yamllint -d relaxed`
   - ✅ Build validation: `kubectl kustomize path/` (proper tool)
   - ❌ kubectl dry-run: SKIPPED (Kustomization is Flux CRD, not standard K8s)

2. **Standard Kubernetes resources** (`.yaml` files):
   - ✅ YAML syntax: `yamllint -d relaxed`
   - ✅ kubectl dry-run: `kubectl apply --dry-run=client`

3. **Custom Resource Definitions**: May not be installed in validation environment
   - ServiceMonitor, PodMonitor, HelmRelease, etc.
   - These are valid but kubectl dry-run may fail if CRDs aren't installed

### Bypassing Validation (When Necessary)
```bash
# Only use when you're confident the YAML is correct
git commit --no-verify -m "message"

# Better: Fix the validation script to handle macOS properly
```

## File System Differences

### Case Sensitivity
- macOS filesystem is case-insensitive by default
- Be careful with file naming in Git repositories
- Use consistent casing for all files

### Path Separators
- Use forward slashes (/) in all scripts and documentation
- Works on both macOS and Linux

## Development Workflow

### Port Forwarding
```bash
# Always specify address for external access
kubectl port-forward svc/service-name 8080:80 --address=0.0.0.0 &

# Check running port forwards
ps aux | grep "kubectl port-forward"

# Kill port forwards
pkill -f "kubectl port-forward"
```

### Process Management
```bash
# Background processes
command &

# List background jobs
jobs

# Kill by process name
pkill -f "process-name"
```

## Troubleshooting

### Common macOS Issues
1. **Command not found**: Install via brew first
2. **Permission denied**: Use sudo only when necessary, prefer brew
3. **Port already in use**: Kill existing port forwards first
4. **Python module not found**: Install via brew, not pip directly

### Environment Variables
```bash
# Check current shell
echo $SHELL  # Should be /bin/zsh on modern macOS

# PATH issues
echo $PATH
which kubectl
which brew
```

## Best Practices

### Never Do This on macOS:
- `pip install` without brew python first
- `apt-get` or `yum` commands
- Assume Linux-specific paths (/usr/bin/, /etc/)
- Use `sudo pip` for system packages

### Always Do This:
- `brew install` for system tools
- Check if tool exists before trying to install
- Use `which command` to verify installation
- Test commands before using in scripts