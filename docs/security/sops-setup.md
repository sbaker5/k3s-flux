# SOPS Setup and Configuration Guide

## Overview

This guide covers setting up SOPS (Secrets OPerationS) for encrypting sensitive data in the GitOps repository. SOPS provides a secure way to store secrets in Git while maintaining the GitOps workflow.

## Current Security Status

⚠️ **CRITICAL**: As of the latest assessment, the following security issues exist:
- Tailscale auth key stored in plaintext in `infrastructure/tailscale/base/secret.yaml`
- No SOPS encryption implemented despite being planned in architecture
- Flux CD has SOPS support enabled but not configured

## Prerequisites

### Install SOPS
```bash
# macOS
brew install sops

# Linux
curl -LO https://github.com/mozilla/sops/releases/latest/download/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

### Install Age (Recommended Encryption Backend)
```bash
# macOS
brew install age

# Linux
curl -LO https://github.com/FiloSottile/age/releases/latest/download/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age /usr/local/bin/
sudo mv age/age-keygen /usr/local/bin/
```

## Setup Process

### Step 1: Generate Age Key Pair

```bash
# Generate a new age key pair
age-keygen -o ~/.config/sops/age/keys.txt

# The output will show your public key, save it for later
# Example: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### Step 2: Create SOPS Configuration

Create `.sops.yaml` in the repository root:

```yaml
# .sops.yaml
creation_rules:
  # Encrypt all secret files with age
  - path_regex: \.sops\.ya?ml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p  # Replace with your public key
  
  # Encrypt Tailscale secrets
  - path_regex: infrastructure/tailscale/.*/secret\.ya?ml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p  # Replace with your public key
  
  # Encrypt any file with .sops in the name
  - path_regex: .*\.sops\..*
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p  # Replace with your public key
```

### Step 3: Create Kubernetes Secret for SOPS

```bash
# Create the sops-age secret in flux-system namespace
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
```

### Step 4: Configure Flux for SOPS Decryption

Update your Flux Kustomizations to use SOPS decryption:

```yaml
# Example: clusters/k3s-flux/infrastructure-tailscale.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-tailscale
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/tailscale
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  # Add SOPS decryption
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

## Encrypting Secrets

### Encrypt the Tailscale Secret

1. **First, revoke the exposed key**:
   - Go to https://login.tailscale.com/admin/settings/keys
   - Find and revoke the key: `tskey-auth-kLVPjnrkY521CNTRL-Ur6BhWwo8FVQq2DWksJSEV9Z1JG1cR7y`

2. **Generate a new auth key**:
   - Create a new reusable, non-ephemeral key with tag:k8s

3. **Create encrypted secret**:
   ```bash
   # Create a new encrypted secret file
   cat > infrastructure/tailscale/base/secret.sops.yaml << EOF
   apiVersion: v1
   kind: Secret
   metadata:
     name: tailscale-auth
     namespace: tailscale
   type: Opaque
   stringData:
     TS_AUTHKEY: "your-new-tailscale-auth-key"
   EOF
   
   # Encrypt the file
   sops --encrypt --in-place infrastructure/tailscale/base/secret.sops.yaml
   ```

4. **Update kustomization to use encrypted file**:
   ```yaml
   # infrastructure/tailscale/base/kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - namespace.yaml
     - subnet-router.yaml
     - secret.sops.yaml  # Changed from secret.yaml
   ```

5. **Remove the plaintext secret**:
   ```bash
   git rm infrastructure/tailscale/base/secret.yaml
   ```

### General Secret Encryption Workflow

```bash
# Create a new secret file
cat > path/to/secret.sops.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-namespace
type: Opaque
stringData:
  key1: "sensitive-value-1"
  key2: "sensitive-value-2"
EOF

# Encrypt the file
sops --encrypt --in-place path/to/secret.sops.yaml

# The file is now encrypted and safe to commit
git add path/to/secret.sops.yaml
git commit -m "Add encrypted secret"
```

## Working with Encrypted Files

### Editing Encrypted Files
```bash
# Edit an encrypted file (opens in your default editor)
sops path/to/secret.sops.yaml

# View decrypted content without editing
sops --decrypt path/to/secret.sops.yaml
```

### Rotating Encryption Keys
```bash
# Generate new age key
age-keygen -o ~/.config/sops/age/keys-new.txt

# Update .sops.yaml with new public key
# Re-encrypt all files with new key
find . -name "*.sops.yaml" -exec sops updatekeys {} \;

# Update Kubernetes secret
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=$HOME/.config/sops/age/keys-new.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Validation and Testing

### Test SOPS Configuration
```bash
# Test encryption
echo "test: secret-value" | sops --encrypt --input-type yaml --output-type yaml /dev/stdin

# Test decryption
sops --decrypt infrastructure/tailscale/base/secret.sops.yaml
```

### Test Flux Decryption
```bash
# Check if Flux can decrypt secrets
kubectl get events -n flux-system | grep -i sops

# Check kustomization status
flux get kustomizations -A
```

## Security Best Practices

### Key Management
- **Store age keys securely**: Never commit private keys to Git
- **Backup keys**: Store private keys in a secure location (password manager, encrypted backup)
- **Rotate keys regularly**: Update encryption keys periodically
- **Use separate keys per environment**: Different keys for dev/staging/prod

### File Organization
```
infrastructure/
├── base/
│   ├── config.yaml          # Non-sensitive configuration
│   └── secret.sops.yaml     # Encrypted secrets
└── overlays/
    ├── dev/
    │   └── secret.sops.yaml  # Dev-specific encrypted secrets
    ├── staging/
    │   └── secret.sops.yaml  # Staging-specific encrypted secrets
    └── prod/
        └── secret.sops.yaml  # Production-specific encrypted secrets
```

### Git Hooks Integration
Add to pre-commit hooks to prevent plaintext secrets:

```bash
# Add to .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: check-sops-encryption
        name: Check SOPS Encryption
        entry: ./scripts/check-sops-encryption.sh
        language: script
        files: '.*secret.*\.ya?ml$'
```

## Troubleshooting

### Common Issues

#### SOPS Command Not Found
```bash
# Verify installation
which sops
sops --version

# Reinstall if needed
brew reinstall sops
```

#### Age Key Issues
```bash
# Check age key format
cat ~/.config/sops/age/keys.txt

# Verify public key matches .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt
```

#### Flux Decryption Failures
```bash
# Check sops-age secret exists
kubectl get secret sops-age -n flux-system

# Check kustomization events
kubectl describe kustomization infrastructure-tailscale -n flux-system

# Check controller logs
kubectl logs -n flux-system -l app=kustomize-controller
```

#### Permission Denied Errors
```bash
# Fix age key permissions
chmod 600 ~/.config/sops/age/keys.txt

# Ensure SOPS config is readable
chmod 644 .sops.yaml
```

## Emergency Procedures

### If Private Key is Lost
1. Generate new age key pair
2. Update .sops.yaml with new public key
3. Re-encrypt all secret files with new key
4. Update Kubernetes sops-age secret
5. Force reconciliation of affected kustomizations

### If Secret is Accidentally Committed in Plaintext
1. **Immediately revoke/rotate the exposed secret**
2. Remove from Git history:
   ```bash
   # Using git filter-branch (destructive)
   git filter-branch --force --index-filter \
     'git rm --cached --ignore-unmatch path/to/secret.yaml' \
     --prune-empty --tag-name-filter cat -- --all
   
   # Or using BFG (recommended)
   java -jar bfg.jar --delete-files secret.yaml
   git reflog expire --expire=now --all && git gc --prune=now --aggressive
   ```
3. Force push to update remote history (coordinate with team)
4. Create new encrypted version of the secret

## Integration with CI/CD

### GitHub Actions Example
```yaml
# .github/workflows/deploy.yml
- name: Setup SOPS
  run: |
    curl -LO https://github.com/mozilla/sops/releases/latest/download/sops-v3.8.1.linux.amd64
    sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
    sudo chmod +x /usr/local/bin/sops

- name: Decrypt secrets for validation
  env:
    SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
  run: |
    echo "$SOPS_AGE_KEY" > /tmp/age.key
    export SOPS_AGE_KEY_FILE=/tmp/age.key
    sops --decrypt infrastructure/tailscale/base/secret.sops.yaml
```

## See Also

- [Secret Management Guide](secret-management.md) - Comprehensive secret management procedures
- [Incident Response Guide](incident-response.md) - Security incident response procedures
- [Tailscale Hardening Guide](tailscale-hardening.md) - Tailscale-specific security improvements