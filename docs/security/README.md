# Security Documentation

This directory contains comprehensive security documentation for the k3s GitOps cluster, including setup procedures, incident response, and hardening guides.

## 🚨 Current Security Status

### **CRITICAL Issues Requiring Immediate Attention**

Based on the GitOps resilience patterns spec analysis:

1. **Plaintext Tailscale Auth Key in Git** 
   - **Key**: `tskey-auth-kLVPjnrkY521CNTRL-Ur6BhWwo8FVQq2DWksJSEV9Z1JG1cR7y`
   - **Location**: `infrastructure/tailscale/base/secret.yaml`
   - **Action**: [Incident Response Guide](incident-response.md#phase-2-containment)

2. **Privileged Container Configuration**
   - **Issue**: `privileged: true` in Tailscale subnet router
   - **Risk**: Container escape, host compromise
   - **Action**: [Tailscale Hardening Guide](tailscale-hardening.md#step-2-container-security-hardening)

3. **No SOPS Encryption Implementation**
   - **Issue**: Secrets stored in plaintext despite SOPS support
   - **Risk**: Credential exposure, compliance violations
   - **Action**: [SOPS Setup Guide](sops-setup.md#setup-process)

## 📚 Documentation Overview

### Core Security Guides

#### [SOPS Setup Guide](sops-setup.md)
Complete guide for implementing SOPS (Secrets OPerationS) encryption:
- Age key generation and management
- Flux CD integration with SOPS
- Secret encryption workflows
- Troubleshooting and validation

#### [Secret Management Guide](secret-management.md)
Comprehensive secret lifecycle management:
- Secret creation and rotation procedures
- Environment-specific secret isolation
- Backup and recovery strategies
- Monitoring and alerting for secrets

#### [Incident Response Guide](incident-response.md)
Security incident response procedures:
- Incident classification and severity levels
- Detection and containment procedures
- Eradication and recovery processes
- Lessons learned and prevention measures

#### [Network Security Architecture](network-security-architecture.md)
Comprehensive network security model and implementation:
- Zero-trust architecture with Tailscale
- Network topology and traffic flow analysis
- Security controls and threat mitigation
- Monitoring and incident response procedures

#### [Tailscale Hardening Guide](tailscale-hardening.md)
Specific security improvements for Tailscale:
- Container security hardening
- Network policy implementation
- Resource limits and health checks
- Environment-specific configurations

## 🛠️ Quick Start Security Implementation

### Immediate Actions (Next 24 Hours)

1. **Revoke Exposed Credentials**
   ```bash
   # Go to Tailscale admin console and revoke the exposed key
   # https://login.tailscale.com/admin/settings/keys
   ```

2. **Implement SOPS Encryption**
   ```bash
   # Install SOPS and Age
   brew install sops age
   
   # Follow the SOPS setup guide
   ./scripts/setup-sops.sh  # (to be created)
   ```

3. **Harden Tailscale Configuration**
   ```bash
   # Remove privileged access and pin image versions
   ./scripts/harden-tailscale.sh  # (to be created)
   ```

### Short-term Goals (Next Week)

- [ ] Complete SOPS implementation for all secrets
- [ ] Implement Tailscale security hardening
- [ ] Create environment-specific secret isolation
- [ ] Add security monitoring and alerting
- [ ] Document incident response procedures

### Medium-term Goals (Next Month)

- [ ] Implement automated secret rotation
- [ ] Add security scanning to CI/CD pipeline
- [ ] Create comprehensive security testing
- [ ] Establish security metrics and SLOs
- [ ] Conduct security training for team

## 🔧 Available Scripts and Tools

### Security Scripts

The following security automation scripts are available:

```bash
scripts/
├── security-validation.sh           # ✅ Comprehensive security validation
└── security/ (planned)
    ├── setup-sops.sh                # SOPS installation and configuration
    ├── generate-secure-tailscale-key.sh # New encrypted Tailscale auth key
    ├── harden-tailscale.sh          # Container and network hardening
    ├── rotate-secrets.sh            # Automated secret rotation
    ├── security-scan.sh             # Automated security scanning
    ├── incident-response.sh         # Incident response automation
    └── backup-secrets.sh            # Secret backup procedures
```

#### Security Validation Script

The `scripts/security-validation.sh` script provides comprehensive security validation:

```bash
# Run basic security validation
./scripts/security-validation.sh

# Generate detailed security report
./scripts/security-validation.sh --report

# Attempt to fix identified issues
./scripts/security-validation.sh --fix

# Full validation with report and fixes
./scripts/security-validation.sh --fix --report
```

**Validation Areas**:
- Network security configuration (Tailscale, exposed services)
- Container security (privileged containers, resource limits)
- Secret management (SOPS encryption, secret age)
- RBAC configuration (overly permissive roles)
- Security monitoring (Prometheus rules, audit logging)

### Emergency Procedures

```bash
# Security incident response
./scripts/security/incident-response.sh <severity>

# Emergency secret rotation
./scripts/security/rotate-secrets.sh <namespace> <secret-name>

# Security validation
./scripts/security/validate-security.sh
```

## 🔍 Security Architecture

### Current Implementation Status

**✅ Implemented:**
- Kubernetes RBAC and service accounts
- Tailscale zero-trust network access
- Flux CD with SOPS support (CRDs configured)
- Network segmentation via namespaces

**❌ Missing:**
- SOPS encryption for secrets
- Container security hardening
- Network policies for traffic restriction
- Automated secret rotation
- Security monitoring and alerting

### Security Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Architecture                    │
├─────────────────────────────────────────────────────────────┤
│  Network Security                                           │
│  ├─ Tailscale (zero-trust, encrypted)                      │
│  ├─ Network Policies (traffic restriction)                 │
│  └─ No exposed ports to internet                           │
│                                                             │
│  Access Control                                             │
│  ├─ Kubernetes RBAC                                        │
│  ├─ Service account isolation                              │
│  └─ Device-level authentication                            │
│                                                             │
│  Secret Management                                          │
│  ├─ SOPS encryption (planned)                              │
│  ├─ Environment isolation                                  │
│  └─ Automated rotation (planned)                           │
│                                                             │
│  Container Security                                         │
│  ├─ Non-privileged containers (planned)                    │
│  ├─ Resource limits                                        │
│  └─ Security contexts                                      │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Security Metrics and Monitoring

### Key Security Metrics

- **Secret Age**: Track secret rotation frequency
- **Failed Authentication**: Monitor unauthorized access attempts
- **Privileged Containers**: Alert on privileged container creation
- **Network Policy Violations**: Track blocked network traffic
- **SOPS Decryption Failures**: Monitor encryption/decryption issues

### Monitoring Integration

Security monitoring integrates with the existing bulletproof monitoring system:

```yaml
# Example PrometheusRule for security monitoring
groups:
- name: security
  rules:
  - alert: PlaintextSecretDetected
    expr: |
      increase(git_commits_with_secrets_total[5m]) > 0
    labels:
      severity: critical
  - alert: PrivilegedContainerCreated
    expr: |
      increase(kube_pod_container_status_running{privileged="true"}[5m]) > 0
    labels:
      severity: high
```

## 🔗 Integration Points

### GitOps Integration
- Pre-commit hooks for secret detection
- SOPS decryption in Flux Kustomizations
- Automated security validation in CI/CD

### Monitoring Integration
- Security metrics in Prometheus
- Security alerts in Grafana
- Integration with existing bulletproof monitoring

### Emergency CLI Integration
Future integration with emergency CLI (after GitOps Task 11.8):
```bash
emergency-cli.sh security scan
emergency-cli.sh security incident-response
emergency-cli.sh security rotate-secrets
```

## 📖 Related Documentation

### Security Documentation Updates
- [Security Documentation Update Summary](security-documentation-update-summary.md) - Recent security documentation improvements

### Internal Documentation
- [Architecture Overview](../architecture-overview.md) - System security architecture
- [Remote Access Guide](../setup/tailscale-remote-access-setup.md) - Tailscale setup and usage
- [GitOps Resilience Patterns](../gitops-resilience-patterns.md) - Security resilience patterns
- [Monitoring System](../operations/monitoring-system-cleanup.md) - Security monitoring integration

### External Resources
- [SOPS Documentation](https://github.com/mozilla/sops)
- [Age Encryption](https://github.com/FiloSottile/age)
- [Tailscale Security Model](https://tailscale.com/security/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)

## 🆘 Emergency Contacts

### Security Incidents
- **Internal Security Lead**: [Contact Information]
- **Infrastructure Team**: [Contact Information]
- **On-Call Engineer**: [Contact Information]

### External Support
- **Tailscale Support**: https://tailscale.com/contact/support
- **Kubernetes Security**: https://kubernetes.io/docs/concepts/security/

---

**⚠️ Remember**: Security is everyone's responsibility. If you discover a security issue, follow the [Incident Response Guide](incident-response.md) immediately.