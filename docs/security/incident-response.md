# Security Incident Response Guide

## Overview

This guide provides procedures for responding to security incidents in the k3s GitOps cluster, including detection, containment, eradication, recovery, and lessons learned.

## Incident Classification

### Severity Levels

#### **CRITICAL** (P0)
- Plaintext secrets committed to Git
- Unauthorized cluster access
- Data breach or exfiltration
- Complete system compromise

#### **HIGH** (P1)
- Exposed authentication credentials
- Privilege escalation
- Malicious code deployment
- Service disruption due to security issue

#### **MEDIUM** (P2)
- Configuration vulnerabilities
- Outdated security components
- Policy violations
- Suspicious activity

#### **LOW** (P3)
- Security best practice deviations
- Non-critical misconfigurations
- Documentation gaps

## Current Known Security Issues

### **CRITICAL - Active Issues**

Based on the GitOps spec analysis, the following critical issues exist:

#### 1. Plaintext Tailscale Auth Key in Git
- **Issue**: `[REDACTED-EXPOSED-KEY]`
- **Location**: `infrastructure/tailscale/base/secret.yaml`
- **Risk**: Network access compromise, unauthorized cluster access
- **Status**: **IMMEDIATE ACTION REQUIRED**

#### 2. Privileged Tailscale Container
- **Issue**: `privileged: true` in subnet router configuration
- **Location**: `infrastructure/tailscale/base/subnet-router.yaml`
- **Risk**: Container escape, host compromise
- **Status**: **HIGH PRIORITY**

#### 3. Latest Image Tags
- **Issue**: Using `:latest` tag for Tailscale image
- **Location**: `infrastructure/tailscale/base/subnet-router.yaml`
- **Risk**: Supply chain attacks, unpredictable deployments
- **Status**: **HIGH PRIORITY**

## Incident Response Procedures

### Phase 1: Detection and Analysis

#### Automated Detection
```bash
#!/bin/bash
# scripts/security-scan.sh

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SECURITY: $*"
}

scan_for_plaintext_secrets() {
    log "Scanning for plaintext secrets..."
    
    # Check for common secret patterns
    if grep -r "password\|secret\|key\|token" --include="*.yaml" --include="*.yml" . | grep -v ".sops."; then
        log "CRITICAL: Potential plaintext secrets found"
        return 1
    fi
    
    # Check for specific known compromised keys
    if grep -r "tskey-auth-.*" --include="*.yaml" --include="*.yml" . 2>/dev/null | grep -v ".sops." | grep -v "PLACEHOLDER\|REDACTED"; then
        log "CRITICAL: Known compromised Tailscale key found"
        return 1
    fi
    
    return 0
}

scan_for_privileged_containers() {
    log "Scanning for privileged containers..."
    
    if grep -r "privileged: true" --include="*.yaml" --include="*.yml" .; then
        log "HIGH: Privileged containers found"
        return 1
    fi
    
    return 0
}

scan_for_latest_tags() {
    log "Scanning for :latest image tags..."
    
    if grep -r "image:.*:latest" --include="*.yaml" --include="*.yml" .; then
        log "MEDIUM: Latest image tags found"
        return 1
    fi
    
    return 0
}

# Run all scans
ISSUES_FOUND=0

if ! scan_for_plaintext_secrets; then
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if ! scan_for_privileged_containers; then
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if ! scan_for_latest_tags; then
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [[ $ISSUES_FOUND -gt 0 ]]; then
    log "Security scan completed with $ISSUES_FOUND issue(s) found"
    exit 1
else
    log "Security scan completed - no issues found"
    exit 0
fi
```

#### Manual Detection Checklist
- [ ] Review recent Git commits for sensitive data
- [ ] Check cluster access logs for unauthorized activity
- [ ] Verify Tailscale device list for unknown devices
- [ ] Review Kubernetes audit logs for suspicious API calls
- [ ] Check running pods for unexpected containers

### Phase 2: Containment

#### Immediate Containment Actions

##### For Exposed Secrets
```bash
#!/bin/bash
# scripts/contain-secret-exposure.sh

SECRET_TYPE="${1:-}"
SECRET_VALUE="${2:-}"

case "$SECRET_TYPE" in
    "tailscale-auth")
        echo "CRITICAL: Containing Tailscale auth key exposure"
        
        # 1. Revoke the key immediately
        echo "Step 1: Revoke the exposed key in Tailscale admin console"
        echo "Go to: https://login.tailscale.com/admin/settings/keys"
        echo "Find and revoke key: $SECRET_VALUE"
        
        # 2. Remove from cluster
        kubectl delete secret tailscale-auth -n tailscale --ignore-not-found
        
        # 3. Restart Tailscale pod to force reconnection failure
        kubectl rollout restart deployment tailscale-subnet-router -n tailscale
        
        echo "Tailscale key containment completed"
        ;;
        
    "database-password")
        echo "HIGH: Containing database password exposure"
        
        # 1. Change password immediately
        echo "Step 1: Change database password through database admin"
        
        # 2. Update applications with new password
        echo "Step 2: Update application secrets"
        
        # 3. Restart affected applications
        kubectl rollout restart deployment -l app.kubernetes.io/uses-database=true
        
        echo "Database password containment completed"
        ;;
        
    *)
        echo "Unknown secret type: $SECRET_TYPE"
        echo "Manual containment required"
        ;;
esac
```

##### For Unauthorized Access
```bash
#!/bin/bash
# scripts/contain-unauthorized-access.sh

echo "CRITICAL: Containing unauthorized access"

# 1. Disable compromised user accounts
echo "Step 1: Disabling potentially compromised accounts"
# kubectl delete clusterrolebinding suspicious-user-binding

# 2. Rotate cluster certificates
echo "Step 2: Consider rotating cluster certificates"
# This requires cluster restart - coordinate with team

# 3. Enable additional audit logging
echo "Step 3: Enabling enhanced audit logging"
kubectl patch configmap audit-policy -n kube-system --patch '{"data":{"audit-policy.yaml":"# Enhanced audit policy"}}'

# 4. Block suspicious IP addresses
echo "Step 4: Review and block suspicious IP addresses"
# Update network policies or firewall rules

echo "Access containment measures applied"
```

### Phase 3: Eradication

#### Remove Threats from Git History
```bash
#!/bin/bash
# scripts/eradicate-git-secrets.sh

SECRET_FILE="${1:-}"

if [[ -z "$SECRET_FILE" ]]; then
    echo "Usage: $0 <secret-file-path>"
    exit 1
fi

echo "WARNING: This will rewrite Git history"
echo "Coordinate with team before proceeding"
read -p "Continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted"
    exit 1
fi

# Method 1: Using git filter-branch (works but deprecated)
git filter-branch --force --index-filter \
    "git rm --cached --ignore-unmatch '$SECRET_FILE'" \
    --prune-empty --tag-name-filter cat -- --all

# Method 2: Using BFG (recommended if available)
# java -jar bfg.jar --delete-files "$SECRET_FILE"

# Clean up
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo "Git history cleaned. Force push required:"
echo "git push --force-with-lease --all"
echo "git push --force-with-lease --tags"
```

#### Harden Configurations
```bash
#!/bin/bash
# scripts/harden-configurations.sh

echo "Applying security hardening..."

# 1. Fix Tailscale privileged container
echo "Step 1: Removing privileged access from Tailscale"
sed -i 's/privileged: true/# privileged: true/' infrastructure/tailscale/base/subnet-router.yaml

# Add specific capabilities instead
cat >> infrastructure/tailscale/base/subnet-router.yaml << 'EOF'
        securityContext:
          capabilities:
            add:
              - CAP_NET_ADMIN
              - CAP_SYS_ADMIN
EOF

# 2. Pin image versions
echo "Step 2: Pinning image versions"
sed -i 's|tailscale/tailscale:latest|tailscale/tailscale:v1.56.1|' infrastructure/tailscale/base/subnet-router.yaml

# 3. Add resource limits
echo "Step 3: Adding resource limits"
cat >> infrastructure/tailscale/base/subnet-router.yaml << 'EOF'
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
          limits:
            cpu: 200m
            memory: 200Mi
EOF

# 4. Add health checks
echo "Step 4: Adding health checks"
cat >> infrastructure/tailscale/base/subnet-router.yaml << 'EOF'
        livenessProbe:
          exec:
            command:
              - /bin/sh
              - -c
              - "tailscale status"
          initialDelaySeconds: 30
          periodSeconds: 60
        readinessProbe:
          exec:
            command:
              - /bin/sh
              - -c
              - "tailscale status | grep -q 'active'"
          initialDelaySeconds: 10
          periodSeconds: 30
EOF

echo "Security hardening applied"
```

### Phase 4: Recovery

#### Restore Secure Operations
```bash
#!/bin/bash
# scripts/recover-secure-operations.sh

echo "Starting secure recovery process..."

# 1. Generate new secrets
echo "Step 1: Generating new secrets"

# Generate new Tailscale auth key
echo "Generate new Tailscale auth key:"
echo "1. Go to: https://login.tailscale.com/admin/settings/keys"
echo "2. Create new key with settings:"
echo "   - Reusable: Yes"
echo "   - Ephemeral: No"
echo "   - Tags: tag:k8s"
echo "3. Copy the new key"

read -p "Enter new Tailscale auth key: " NEW_TAILSCALE_KEY

# 2. Create encrypted secret
echo "Step 2: Creating encrypted secret"
cat > infrastructure/tailscale/base/secret.sops.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: tailscale-auth
  namespace: tailscale
type: Opaque
stringData:
  TS_AUTHKEY: "$NEW_TAILSCALE_KEY"
EOF

# Encrypt the secret
sops --encrypt --in-place infrastructure/tailscale/base/secret.sops.yaml

# 3. Update kustomization
echo "Step 3: Updating kustomization"
sed -i 's/secret.yaml/secret.sops.yaml/' infrastructure/tailscale/base/kustomization.yaml

# 4. Remove old plaintext secret
echo "Step 4: Removing plaintext secret"
git rm infrastructure/tailscale/base/secret.yaml

# 5. Commit changes
echo "Step 5: Committing secure changes"
git add .
git commit -m "security: Implement SOPS encryption for Tailscale secrets

- Encrypt Tailscale auth key with SOPS
- Remove privileged container access
- Pin image versions
- Add resource limits and health checks
- Remove plaintext secret from repository

Resolves: GitOps spec Task 12.1-12.6"

# 6. Deploy changes
echo "Step 6: Deploying secure configuration"
git push
flux reconcile kustomization infrastructure-tailscale -n flux-system

echo "Secure recovery completed"
```

#### Validation and Testing
```bash
#!/bin/bash
# scripts/validate-security-recovery.sh

echo "Validating security recovery..."

# 1. Verify SOPS encryption
echo "Step 1: Validating SOPS encryption"
if sops --decrypt infrastructure/tailscale/base/secret.sops.yaml >/dev/null 2>&1; then
    echo "✅ SOPS encryption working"
else
    echo "❌ SOPS encryption failed"
    exit 1
fi

# 2. Verify no plaintext secrets
echo "Step 2: Scanning for plaintext secrets"
if ! grep -r "tskey-auth-" --include="*.yaml" --include="*.yml" . 2>/dev/null; then
    echo "✅ No plaintext secrets found"
else
    echo "❌ Plaintext secrets still present"
    exit 1
fi

# 3. Verify Tailscale deployment
echo "Step 3: Validating Tailscale deployment"
if kubectl get pods -n tailscale -l app=tailscale-subnet-router | grep -q Running; then
    echo "✅ Tailscale pod running"
else
    echo "❌ Tailscale pod not running"
    exit 1
fi

# 4. Verify security hardening
echo "Step 4: Validating security hardening"
if ! grep -q "privileged: true" infrastructure/tailscale/base/subnet-router.yaml; then
    echo "✅ Privileged access removed"
else
    echo "❌ Privileged access still present"
    exit 1
fi

if grep -q "tailscale/tailscale:v" infrastructure/tailscale/base/subnet-router.yaml; then
    echo "✅ Image version pinned"
else
    echo "❌ Image version not pinned"
    exit 1
fi

echo "Security recovery validation completed successfully"
```

### Phase 5: Lessons Learned

#### Incident Report Template
```markdown
# Security Incident Report

**Incident ID**: SEC-$(date +%Y%m%d-%H%M%S)
**Date**: $(date)
**Severity**: [CRITICAL/HIGH/MEDIUM/LOW]
**Status**: [OPEN/CONTAINED/RESOLVED/CLOSED]

## Executive Summary
Brief description of the incident and its impact.

## Timeline
- **Detection**: When and how the incident was discovered
- **Containment**: Actions taken to contain the threat
- **Eradication**: Steps to remove the threat
- **Recovery**: Restoration of normal operations
- **Lessons Learned**: Post-incident analysis

## Technical Details

### Root Cause
What caused the security incident?

### Impact Assessment
- Systems affected
- Data compromised
- Service disruption
- Financial impact

### Attack Vector
How did the security breach occur?

## Response Actions

### Immediate Actions Taken
- [ ] Threat contained
- [ ] Affected systems isolated
- [ ] Stakeholders notified
- [ ] Evidence preserved

### Remediation Steps
- [ ] Vulnerabilities patched
- [ ] Configurations hardened
- [ ] Secrets rotated
- [ ] Access reviewed

## Lessons Learned

### What Went Well
- Effective detection mechanisms
- Quick response time
- Good communication

### Areas for Improvement
- Detection could be faster
- Response procedures need refinement
- Additional monitoring required

### Action Items
- [ ] Update security policies
- [ ] Implement additional monitoring
- [ ] Conduct security training
- [ ] Review access controls

## Recommendations

### Short-term (1-2 weeks)
- Immediate security improvements
- Process updates

### Medium-term (1-3 months)
- Infrastructure improvements
- Tool implementations

### Long-term (3-12 months)
- Strategic security initiatives
- Compliance improvements

## Appendices
- Logs and evidence
- Communication records
- Technical analysis
```

## Prevention Measures

### Automated Security Scanning
```bash
#!/bin/bash
# .github/workflows/security-scan.yml equivalent

# Add to pre-commit hooks
cat >> .pre-commit-config.yaml << 'EOF'
repos:
  - repo: local
    hooks:
      - id: security-scan
        name: Security Scan
        entry: ./scripts/security-scan.sh
        language: script
        pass_filenames: false
      - id: secret-detection
        name: Secret Detection
        entry: ./scripts/detect-secrets.sh
        language: script
        files: '.*\.(yaml|yml|json)$'
EOF
```

### Monitoring and Alerting
```yaml
# infrastructure/monitoring/core/security-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: security-alerts
  namespace: monitoring
spec:
  groups:
  - name: security
    rules:
    - alert: UnauthorizedAPIAccess
      expr: |
        increase(apiserver_audit_total{verb!~"get|list|watch"}[5m]) > 100
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Unusual API activity detected"
        description: "High number of non-read API calls: {{ $value }}"
    
    - alert: PrivilegedPodCreated
      expr: |
        increase(kube_pod_container_status_running{container=~".*privileged.*"}[5m]) > 0
      for: 0m
      labels:
        severity: high
      annotations:
        summary: "Privileged pod created"
        description: "A privileged container was started"
    
    - alert: SecretAccessed
      expr: |
        increase(kube_secret_info[5m]) > 0
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "Secret accessed"
        description: "Secret {{ $labels.secret }} was accessed"
```

## Emergency Contacts

### Internal Team
- **Security Lead**: [Contact Information]
- **Infrastructure Lead**: [Contact Information]
- **On-Call Engineer**: [Contact Information]

### External Resources
- **Tailscale Support**: https://tailscale.com/contact/support
- **Kubernetes Security**: https://kubernetes.io/docs/concepts/security/
- **SOPS Documentation**: https://github.com/mozilla/sops

## Integration with Emergency CLI

### Future Emergency CLI Security Commands
```bash
# These commands will be available after GitOps Task 11.8 completion

# Run security scan
emergency-cli.sh security scan

# Respond to incident
emergency-cli.sh security incident-response <severity>

# Rotate compromised secrets
emergency-cli.sh security rotate-secrets <type>

# Harden configurations
emergency-cli.sh security harden

# Generate incident report
emergency-cli.sh security incident-report <incident-id>
```

## See Also

- [SOPS Setup Guide](sops-setup.md) - Implementing encrypted secrets
- [Secret Management Guide](secret-management.md) - Comprehensive secret procedures
- [Tailscale Hardening Guide](tailscale-hardening.md) - Network security improvements
- [Architecture Overview](../architecture-overview.md) - System security architecture