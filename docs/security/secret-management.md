# Secret Management Guide

## Overview

This guide provides comprehensive procedures for managing secrets in the k3s GitOps cluster, including creation, rotation, backup, and emergency procedures.

## Secret Management Architecture

### Current State Analysis

Based on the codebase analysis:

**✅ Implemented**:
- Kubernetes native secrets for basic use cases
- Flux CD with SOPS support (CRDs configured)
- Tailscale auth key management (currently plaintext - needs encryption)

**❌ Missing**:
- SOPS encryption implementation
- Secret rotation procedures
- Environment-specific secret isolation
- Automated secret validation

### Secret Categories

#### 1. Infrastructure Secrets
- **Tailscale Auth Keys**: Network access authentication
- **Git Repository Access**: SSH keys for Flux
- **Container Registry**: Image pull secrets (if needed)
- **Backup Credentials**: S3/NFS backup access

#### 2. Application Secrets
- **Database Credentials**: Application database access
- **API Keys**: External service authentication
- **TLS Certificates**: HTTPS/TLS termination
- **Service-to-Service**: Inter-service authentication

#### 3. Operational Secrets
- **Monitoring Credentials**: Grafana admin passwords
- **Emergency Access**: Break-glass credentials
- **Encryption Keys**: SOPS age keys, backup encryption

## Secret Lifecycle Management

### 1. Secret Creation

#### Using SOPS (Recommended)
```bash
# Create encrypted secret template
cat > path/to/secret.sops.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-application-secret
  namespace: my-namespace
  labels:
    app.kubernetes.io/name: my-app
    app.kubernetes.io/managed-by: flux
type: Opaque
stringData:
  # Database credentials
  DB_USERNAME: "app_user"
  DB_PASSWORD: "secure_random_password"
  DB_HOST: "database.example.com"
  
  # API keys
  API_KEY: "api_key_value"
  API_SECRET: "api_secret_value"
  
  # TLS certificates
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    [certificate content]
    -----END CERTIFICATE-----
  tls.key: |
    -----BEGIN PRIVATE KEY-----
    [private key content]
    -----END PRIVATE KEY-----
EOF

# Encrypt the secret
sops --encrypt --in-place path/to/secret.sops.yaml

# Verify encryption
sops --decrypt path/to/secret.sops.yaml
```

#### Environment-Specific Secrets
```bash
# Development environment
infrastructure/
└── overlays/
    └── dev/
        ├── kustomization.yaml
        └── secrets.sops.yaml

# Staging environment  
infrastructure/
└── overlays/
    └── staging/
        ├── kustomization.yaml
        └── secrets.sops.yaml

# Production environment
infrastructure/
└── overlays/
    └── prod/
        ├── kustomization.yaml
        └── secrets.sops.yaml
```

### 2. Secret Rotation

#### Automated Rotation Strategy
```bash
#!/bin/bash
# scripts/rotate-secrets.sh

set -euo pipefail

NAMESPACE="${1:-default}"
SECRET_NAME="${2:-}"

if [[ -z "$SECRET_NAME" ]]; then
    echo "Usage: $0 <namespace> <secret-name>"
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

rotate_secret() {
    local namespace="$1"
    local secret_name="$2"
    local secret_file="infrastructure/overlays/prod/${secret_name}.sops.yaml"
    
    log "Starting rotation for secret: $namespace/$secret_name"
    
    # Backup current secret
    kubectl get secret "$secret_name" -n "$namespace" -o yaml > "/tmp/${secret_name}-backup-$(date +%Y%m%d-%H%M%S).yaml"
    
    # Generate new credentials (example for database)
    case "$secret_name" in
        "database-credentials")
            NEW_PASSWORD=$(openssl rand -base64 32)
            # Update database with new password
            # Update secret file with new password
            sops --decrypt "$secret_file" | \
                sed "s/DB_PASSWORD: .*/DB_PASSWORD: \"$NEW_PASSWORD\"/" | \
                sops --encrypt /dev/stdin > "$secret_file.tmp"
            mv "$secret_file.tmp" "$secret_file"
            ;;
        "api-credentials")
            # Rotate API keys through provider API
            # Update secret file
            ;;
        *)
            log "Unknown secret type: $secret_name"
            return 1
            ;;
    esac
    
    # Commit changes
    git add "$secret_file"
    git commit -m "rotate: Update $secret_name credentials"
    git push
    
    # Force Flux reconciliation
    flux reconcile kustomization infrastructure-prod -n flux-system
    
    log "Secret rotation completed for: $namespace/$secret_name"
}

rotate_secret "$NAMESPACE" "$SECRET_NAME"
```

#### Manual Rotation Process
```bash
# 1. Decrypt existing secret
sops --decrypt infrastructure/overlays/prod/app-secrets.sops.yaml > /tmp/app-secrets.yaml

# 2. Update credentials in the decrypted file
# Edit /tmp/app-secrets.yaml with new values

# 3. Re-encrypt with updated values
sops --encrypt /tmp/app-secrets.yaml > infrastructure/overlays/prod/app-secrets.sops.yaml

# 4. Clean up temporary file
rm /tmp/app-secrets.yaml

# 5. Commit and push changes
git add infrastructure/overlays/prod/app-secrets.sops.yaml
git commit -m "rotate: Update application secrets"
git push

# 6. Force reconciliation
flux reconcile kustomization infrastructure-prod -n flux-system
```

### 3. Secret Validation

#### Pre-commit Validation Script
```bash
#!/bin/bash
# scripts/validate-secrets.sh

set -euo pipefail

validate_secret_encryption() {
    local file="$1"
    
    # Check if file should be encrypted
    if [[ "$file" =~ secret.*\.ya?ml$ ]] && [[ ! "$file" =~ \.sops\. ]]; then
        if grep -q "kind: Secret" "$file" 2>/dev/null; then
            echo "ERROR: Unencrypted secret found: $file"
            echo "Secrets must be encrypted with SOPS. Use: sops --encrypt --in-place $file"
            return 1
        fi
    fi
    
    # Validate SOPS encrypted files
    if [[ "$file" =~ \.sops\.ya?ml$ ]]; then
        if ! sops --decrypt "$file" >/dev/null 2>&1; then
            echo "ERROR: Cannot decrypt SOPS file: $file"
            echo "File may be corrupted or you may not have the correct decryption key"
            return 1
        fi
        
        # Validate decrypted content is valid YAML
        if ! sops --decrypt "$file" | yq eval . >/dev/null 2>&1; then
            echo "ERROR: Decrypted content is not valid YAML: $file"
            return 1
        fi
    fi
    
    return 0
}

# Validate all secret files
find . -name "*.yaml" -o -name "*.yml" | while read -r file; do
    validate_secret_encryption "$file"
done
```

#### Runtime Secret Validation
```bash
#!/bin/bash
# scripts/check-secret-health.sh

check_secret_health() {
    local namespace="$1"
    local secret_name="$2"
    
    # Check if secret exists
    if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        echo "ERROR: Secret $secret_name not found in namespace $namespace"
        return 1
    fi
    
    # Check secret age
    local created=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}')
    local age_days=$(( ($(date +%s) - $(date -d "$created" +%s)) / 86400 ))
    
    if [[ $age_days -gt 90 ]]; then
        echo "WARNING: Secret $secret_name is $age_days days old (consider rotation)"
    fi
    
    # Check for required keys
    local keys=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data}' | jq -r 'keys[]')
    echo "Secret $secret_name contains keys: $keys"
    
    return 0
}

# Check all secrets in monitoring namespace
kubectl get secrets -n monitoring -o name | while read -r secret; do
    secret_name=$(basename "$secret")
    check_secret_health "monitoring" "$secret_name"
done
```

## Environment-Specific Secret Management

### Development Environment
```yaml
# infrastructure/overlays/dev/secrets.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: dev
type: Opaque
stringData:
  # Development database (can use weaker credentials)
  DB_PASSWORD: "dev_password_123"
  API_KEY: "dev_api_key"
  
  # Development TLS (self-signed certificates OK)
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    [dev certificate]
    -----END CERTIFICATE-----
```

### Production Environment
```yaml
# infrastructure/overlays/prod/secrets.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: prod
type: Opaque
stringData:
  # Production database (strong credentials required)
  DB_PASSWORD: "prod_secure_random_password_xyz789"
  API_KEY: "prod_api_key_with_limited_scope"
  
  # Production TLS (CA-signed certificates)
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    [production certificate]
    -----END CERTIFICATE-----
```

## Secret Backup and Recovery

### Backup Strategy
```bash
#!/bin/bash
# scripts/backup-secrets.sh

BACKUP_DIR="/secure/backup/secrets/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup encrypted secret files from Git
find . -name "*.sops.yaml" -exec cp {} "$BACKUP_DIR/" \;

# Backup SOPS age keys (encrypted)
gpg --symmetric --cipher-algo AES256 ~/.config/sops/age/keys.txt
mv ~/.config/sops/age/keys.txt.gpg "$BACKUP_DIR/"

# Backup Kubernetes secrets (for disaster recovery)
kubectl get secrets --all-namespaces -o yaml > "$BACKUP_DIR/k8s-secrets-backup.yaml"

# Create backup manifest
cat > "$BACKUP_DIR/backup-manifest.txt" << EOF
Backup created: $(date)
Git commit: $(git rev-parse HEAD)
Cluster: $(kubectl config current-context)
Secrets backed up:
$(find "$BACKUP_DIR" -name "*.sops.yaml" | wc -l) SOPS encrypted files
$(kubectl get secrets --all-namespaces --no-headers | wc -l) Kubernetes secrets
EOF

echo "Backup completed: $BACKUP_DIR"
```

### Recovery Procedures
```bash
#!/bin/bash
# scripts/recover-secrets.sh

BACKUP_DIR="${1:-}"
if [[ -z "$BACKUP_DIR" ]]; then
    echo "Usage: $0 <backup-directory>"
    exit 1
fi

# Restore SOPS age keys
if [[ -f "$BACKUP_DIR/keys.txt.gpg" ]]; then
    gpg --decrypt "$BACKUP_DIR/keys.txt.gpg" > ~/.config/sops/age/keys.txt
    chmod 600 ~/.config/sops/age/keys.txt
fi

# Restore encrypted secret files
find "$BACKUP_DIR" -name "*.sops.yaml" -exec cp {} . \;

# Recreate Kubernetes sops-age secret
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=~/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -

# Force reconciliation
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization --all -n flux-system

echo "Secret recovery completed"
```

## Emergency Procedures

### Break-Glass Access
```bash
#!/bin/bash
# scripts/emergency-secret-access.sh

# For emergency access when SOPS keys are unavailable
# This should only be used in extreme circumstances

NAMESPACE="${1:-}"
SECRET_NAME="${2:-}"

if [[ -z "$NAMESPACE" || -z "$SECRET_NAME" ]]; then
    echo "Usage: $0 <namespace> <secret-name>"
    echo "WARNING: This provides direct access to secret values"
    exit 1
fi

echo "WARNING: Emergency secret access requested"
echo "Namespace: $NAMESPACE"
echo "Secret: $SECRET_NAME"
echo "Timestamp: $(date)"

# Log the access
echo "$(date): Emergency access to $NAMESPACE/$SECRET_NAME by $(whoami)" >> /var/log/emergency-secret-access.log

# Display secret (base64 decoded)
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | \
    jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
```

### Secret Compromise Response
```bash
#!/bin/bash
# scripts/secret-compromise-response.sh

SECRET_NAME="${1:-}"
NAMESPACE="${2:-}"

if [[ -z "$SECRET_NAME" || -z "$NAMESPACE" ]]; then
    echo "Usage: $0 <secret-name> <namespace>"
    exit 1
fi

echo "SECURITY INCIDENT: Secret compromise response initiated"
echo "Secret: $NAMESPACE/$SECRET_NAME"
echo "Timestamp: $(date)"

# 1. Immediately rotate the compromised secret
echo "Step 1: Rotating compromised secret..."
./scripts/rotate-secrets.sh "$NAMESPACE" "$SECRET_NAME"

# 2. Check for unauthorized access
echo "Step 2: Checking for unauthorized access..."
kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$SECRET_NAME"

# 3. Update dependent applications
echo "Step 3: Restarting dependent applications..."
kubectl rollout restart deployment -n "$NAMESPACE" -l app.kubernetes.io/uses-secret="$SECRET_NAME"

# 4. Audit recent changes
echo "Step 4: Auditing recent changes..."
git log --oneline -10 --grep="$SECRET_NAME"

# 5. Generate incident report
cat > "/tmp/incident-report-$(date +%Y%m%d-%H%M%S).md" << EOF
# Security Incident Report

**Date**: $(date)
**Incident**: Secret compromise
**Affected Secret**: $NAMESPACE/$SECRET_NAME
**Response Actions**:
1. Secret rotated at $(date)
2. Dependent applications restarted
3. Access audit completed
4. Git history reviewed

**Next Steps**:
- [ ] Review access logs for unauthorized usage
- [ ] Update monitoring alerts for this secret
- [ ] Consider additional security measures
- [ ] Document lessons learned
EOF

echo "Incident response completed. Report generated in /tmp/"
```

## Monitoring and Alerting

### Secret Expiration Monitoring
```yaml
# infrastructure/monitoring/core/secret-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: secret-monitoring
  namespace: monitoring
spec:
  groups:
  - name: secrets
    rules:
    - alert: SecretExpiringSoon
      expr: |
        (time() - kube_secret_created) / 86400 > 80
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "Secret {{ $labels.secret }} is expiring soon"
        description: "Secret {{ $labels.secret }} in namespace {{ $labels.namespace }} is {{ $value }} days old"
    
    - alert: SecretNotRotated
      expr: |
        (time() - kube_secret_created) / 86400 > 90
      for: 1h
      labels:
        severity: critical
      annotations:
        summary: "Secret {{ $labels.secret }} requires rotation"
        description: "Secret {{ $labels.secret }} in namespace {{ $labels.namespace }} has not been rotated in {{ $value }} days"
```

### Secret Access Monitoring
```bash
# Monitor secret access patterns
kubectl get events --all-namespaces --field-selector reason=SecretMount -w
```

## Integration with Emergency CLI

### Future Emergency CLI Commands
```bash
# These commands will be available after GitOps Task 11.8 completion

# List all secrets and their ages
emergency-cli.sh secrets list

# Check secret health across all namespaces
emergency-cli.sh secrets health-check

# Rotate a specific secret
emergency-cli.sh secrets rotate <namespace> <secret-name>

# Emergency secret access (logged)
emergency-cli.sh secrets emergency-access <namespace> <secret-name>

# Validate SOPS encryption
emergency-cli.sh secrets validate-encryption
```

## Best Practices Summary

### Security
- ✅ Always encrypt secrets with SOPS before committing
- ✅ Use environment-specific encryption keys
- ✅ Rotate secrets regularly (90-day maximum)
- ✅ Monitor secret access and age
- ✅ Backup encryption keys securely

### Operations
- ✅ Validate secrets in pre-commit hooks
- ✅ Use descriptive secret names and labels
- ✅ Document secret dependencies
- ✅ Test secret rotation procedures
- ✅ Maintain incident response procedures

### Development
- ✅ Use weaker credentials in development
- ✅ Never use production secrets in development
- ✅ Provide clear secret templates
- ✅ Document secret requirements for applications

## See Also

- [SOPS Setup Guide](sops-setup.md) - Detailed SOPS configuration
- [Incident Response Guide](incident-response.md) - Security incident procedures
- [Tailscale Hardening Guide](tailscale-hardening.md) - Network security improvements
- [Architecture Overview](../architecture-overview.md) - System security architecture