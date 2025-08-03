# Network Security Architecture

## Overview

This document provides a comprehensive overview of the network security architecture for the k3s GitOps cluster, including the zero-trust model implemented through Tailscale, network segmentation strategies, and security controls.

## Security Architecture Principles

### Zero-Trust Network Model

The cluster implements a zero-trust security model where:

- **No implicit trust**: Every connection is verified regardless of location
- **Device-level authentication**: All access requires authenticated Tailscale devices
- **Encrypted communication**: All traffic is end-to-end encrypted via WireGuard
- **Minimal exposure**: No ports exposed to the public internet
- **Continuous verification**: Ongoing validation of device and user identity

### Defense in Depth

Multiple layers of security controls protect the cluster:

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layers                         │
├─────────────────────────────────────────────────────────────┤
│  1. Network Access Control (Tailscale)                     │
│     ├─ Device authentication and authorization             │
│     ├─ End-to-end encryption (WireGuard)                  │
│     └─ Network ACLs and traffic policies                  │
│                                                             │
│  2. Kubernetes RBAC                                        │
│     ├─ Service account isolation                          │
│     ├─ Namespace-based permissions                        │
│     └─ Resource-specific access controls                  │
│                                                             │
│  3. Container Security                                      │
│     ├─ Minimal capability sets                            │
│     ├─ Non-privileged containers where possible           │
│     └─ Resource limits and security contexts              │
│                                                             │
│  4. Secret Management                                       │
│     ├─ SOPS encryption for secrets at rest               │
│     ├─ Kubernetes secrets for runtime                     │
│     └─ Automated secret rotation                          │
│                                                             │
│  5. Network Segmentation                                   │
│     ├─ Namespace isolation                                │
│     ├─ Network policies (planned)                         │
│     └─ Service mesh (future consideration)                │
└─────────────────────────────────────────────────────────────┘
```

## Network Topology

### Physical Network Architecture

```mermaid
graph TB
    subgraph "Internet"
        Internet[Internet]
    end
    
    subgraph "Tailscale Network (Encrypted Overlay)"
        TS[Tailscale Coordination Server]
        Client1[Admin Laptop]
        Client2[Mobile Device]
        Client3[Remote Workstation]
    end
    
    subgraph "k3s Cluster Network"
        subgraph "Node: k3s1"
            TSRouter[Tailscale Subnet Router]
            K3sAPI[k3s API Server]
            Pods1[Pod Network 10.42.0.0/16]
        end
        
        subgraph "Services Network"
            Services[Service Network 10.43.0.0/16]
            Ingress[NGINX Ingress]
        end
    end
    
    Internet -.->|Encrypted WireGuard| TS
    TS <-->|Device Auth| Client1
    TS <-->|Device Auth| Client2
    TS <-->|Device Auth| Client3
    
    Client1 -.->|Encrypted Tunnel| TSRouter
    Client2 -.->|Encrypted Tunnel| TSRouter
    Client3 -.->|Encrypted Tunnel| TSRouter
    
    TSRouter --> K3sAPI
    TSRouter --> Pods1
    TSRouter --> Services
    TSRouter --> Ingress
    
    style TSRouter fill:#e1f5fe
    style TS fill:#f3e5f5
    style Internet fill:#ffebee
```

### Network Ranges and Segmentation

#### Tailscale Network
- **Range**: `100.64.0.0/10` (Tailscale CGNAT range)
- **Purpose**: Encrypted overlay network for device-to-device communication
- **Security**: All traffic encrypted with WireGuard, device authentication required

#### k3s Cluster Networks
- **Pod Network**: `10.42.0.0/16`
  - Default k3s pod CIDR
  - Where individual pods receive IP addresses
  - Accessible via Tailscale subnet router
  
- **Service Network**: `10.43.0.0/16`
  - Default k3s service CIDR
  - ClusterIP services and internal load balancing
  - Accessible via Tailscale subnet router

#### Host Network
- **Node Network**: Varies by deployment (e.g., `192.168.1.0/24`)
  - Physical/VM network where k3s nodes reside
  - Not directly advertised via Tailscale for security
  - Access only through k3s API and services

## Security Controls

### 1. Network Access Control

#### Tailscale Device Authentication
```yaml
# Device authentication requirements:
authentication:
  method: "device-based"
  providers:
    - "Google SSO"
    - "GitHub SSO" 
    - "Email verification"
  
  device_approval: "required"  # Manual approval for new devices
  key_expiry: "90d"           # Auth keys expire after 90 days
  
  # Access Control Lists (ACLs)
  acls:
    - src: "tag:admin"
      dst: "tag:k8s"
      ports: ["*"]
    - src: "tag:developer"
      dst: "tag:k8s"
      ports: ["443", "6443", "8080"]
```

#### Network Traffic Encryption
- **Protocol**: WireGuard (modern, audited VPN protocol)
- **Encryption**: ChaCha20Poly1305 or AES-256-GCM
- **Key Exchange**: Curve25519
- **Authentication**: BLAKE2s
- **Perfect Forward Secrecy**: Yes

### 2. Kubernetes Security

#### Service Account Security
```yaml
# Tailscale service account (minimal permissions)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tailscale
  namespace: tailscale
  annotations:
    security.k3s-flux.io/risk-level: "low"
    security.k3s-flux.io/permissions: "secrets:create,get,update,patch"
```

#### RBAC Configuration
- **Principle**: Least privilege access
- **Scope**: Namespace-isolated permissions
- **Audit**: Regular permission reviews
- **Monitoring**: RBAC violation alerts

### 3. Container Security

#### Security Contexts
```yaml
# Example security context for Tailscale
securityContext:
  # Minimal capabilities
  capabilities:
    add: ["NET_ADMIN"]  # Only what's required
    drop: ["ALL"]       # Drop everything else
  
  # Security hardening (where possible)
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  readOnlyRootFilesystem: true
```

#### Resource Limits
```yaml
resources:
  requests:
    cpu: 10m
    memory: 10Mi
  limits:
    cpu: 100m      # Prevent resource exhaustion
    memory: 100Mi  # Limit memory usage
```

### 4. Secret Management Security

#### SOPS Encryption
```yaml
# Encrypted secret example
apiVersion: v1
kind: Secret
metadata:
  name: tailscale-auth
  namespace: tailscale
type: Opaque
stringData:
  TS_AUTHKEY: ENC[AES256_GCM,data:...,tag:...,type:str]
```

#### Secret Rotation Strategy
- **Frequency**: 90-day maximum age
- **Automation**: Automated rotation scripts
- **Validation**: Pre-commit hooks prevent plaintext secrets
- **Monitoring**: Alerts for secret age and rotation failures

## Security Monitoring

### Network Security Metrics

#### Tailscale Monitoring
```yaml
# Prometheus metrics for Tailscale security
metrics:
  - tailscale_device_count
  - tailscale_connection_status
  - tailscale_traffic_bytes_total
  - tailscale_auth_failures_total
```

#### Kubernetes Security Metrics
```yaml
# Security-related Kubernetes metrics
metrics:
  - kube_pod_container_status_running{privileged="true"}
  - apiserver_audit_total{verb!~"get|list|watch"}
  - kube_secret_created
  - rbac_authorization_decisions_total
```

### Security Alerts

#### Critical Security Alerts
```yaml
groups:
- name: security-critical
  rules:
  - alert: PrivilegedContainerCreated
    expr: increase(kube_pod_container_status_running{privileged="true"}[5m]) > 0
    labels:
      severity: critical
    annotations:
      summary: "Privileged container detected"
      
  - alert: UnauthorizedAPIAccess
    expr: increase(apiserver_audit_total{verb!~"get|list|watch"}[5m]) > 100
    labels:
      severity: critical
    annotations:
      summary: "Unusual API activity detected"
```

#### Network Security Alerts
```yaml
- alert: TailscaleConnectionLost
  expr: tailscale_connection_status == 0
  for: 5m
  labels:
    severity: high
  annotations:
    summary: "Tailscale subnet router disconnected"
    
- alert: UnknownDeviceConnected
  expr: increase(tailscale_device_count[1h]) > 0
  labels:
    severity: warning
  annotations:
    summary: "New device connected to Tailscale network"
```

## Threat Model

### Identified Threats and Mitigations

#### 1. Network-Based Attacks

**Threat**: Man-in-the-middle attacks on network traffic
- **Mitigation**: End-to-end encryption via WireGuard
- **Detection**: Connection integrity monitoring
- **Response**: Automatic connection re-establishment

**Threat**: Unauthorized network access
- **Mitigation**: Device-based authentication, no exposed ports
- **Detection**: Device connection monitoring
- **Response**: Device revocation, access audit

#### 2. Container Escape Attacks

**Threat**: Privileged container exploitation
- **Mitigation**: Minimal capabilities, security contexts
- **Detection**: Privileged container alerts
- **Response**: Container termination, security review

**Threat**: Resource exhaustion attacks
- **Mitigation**: Resource limits and quotas
- **Detection**: Resource usage monitoring
- **Response**: Pod eviction, resource scaling

#### 3. Credential Compromise

**Threat**: Exposed authentication keys
- **Mitigation**: SOPS encryption, secret rotation
- **Detection**: Secret scanning, age monitoring
- **Response**: Immediate key revocation and rotation

**Threat**: Kubernetes API abuse
- **Mitigation**: RBAC, audit logging
- **Detection**: Unusual API activity alerts
- **Response**: Account suspension, access review

## Compliance and Auditing

### Security Audit Checklist

#### Network Security
- [ ] All traffic encrypted in transit
- [ ] No ports exposed to public internet
- [ ] Device authentication enforced
- [ ] Network ACLs properly configured
- [ ] Connection monitoring active

#### Container Security
- [ ] Minimal capabilities granted
- [ ] Resource limits configured
- [ ] Security contexts applied
- [ ] Privileged containers minimized
- [ ] Image versions pinned

#### Secret Management
- [ ] All secrets encrypted with SOPS
- [ ] Regular secret rotation performed
- [ ] Secret age monitoring active
- [ ] Pre-commit hooks prevent plaintext secrets
- [ ] Backup and recovery procedures tested

#### Access Control
- [ ] RBAC follows least privilege
- [ ] Service accounts properly scoped
- [ ] Regular permission reviews conducted
- [ ] Audit logging enabled
- [ ] Unauthorized access alerts configured

### Compliance Frameworks

#### Security Standards Alignment
- **NIST Cybersecurity Framework**: Identify, Protect, Detect, Respond, Recover
- **CIS Controls**: Critical security controls implementation
- **Kubernetes Security Benchmarks**: CIS Kubernetes Benchmark compliance
- **Zero Trust Architecture**: NIST SP 800-207 principles

## Future Security Enhancements

### Short-term (1-3 months)
- [ ] Implement Kubernetes Network Policies
- [ ] Add Pod Security Standards enforcement
- [ ] Enhance secret rotation automation
- [ ] Implement security scanning in CI/CD

### Medium-term (3-6 months)
- [ ] Add service mesh for micro-segmentation
- [ ] Implement runtime security monitoring
- [ ] Add vulnerability scanning for containers
- [ ] Enhance audit logging and SIEM integration

### Long-term (6-12 months)
- [ ] Implement certificate-based authentication
- [ ] Add behavioral analysis for anomaly detection
- [ ] Implement zero-trust micro-segmentation
- [ ] Add compliance automation and reporting

## Emergency Procedures

### Security Incident Response

#### Network Compromise
```bash
# Immediate response to network security incident
emergency-cli.sh security network-incident

# Steps performed:
# 1. Isolate affected network segments
# 2. Revoke compromised device access
# 3. Rotate network authentication keys
# 4. Enable enhanced monitoring
# 5. Generate incident report
```

#### Container Security Incident
```bash
# Response to container security compromise
emergency-cli.sh security container-incident

# Steps performed:
# 1. Terminate compromised containers
# 2. Isolate affected nodes
# 3. Audit container configurations
# 4. Apply security patches
# 5. Restore from known-good state
```

### Recovery Procedures

#### Network Access Recovery
```bash
# Restore network access after security incident
emergency-cli.sh security network-recovery

# Steps performed:
# 1. Validate network configuration
# 2. Test device authentication
# 3. Verify encryption status
# 4. Restore monitoring
# 5. Document lessons learned
```

## See Also

- [Tailscale Hardening Guide](tailscale-hardening.md) - Specific Tailscale security improvements
- [Secret Management Guide](secret-management.md) - Comprehensive secret security
- [Incident Response Guide](incident-response.md) - Security incident procedures
- [Architecture Overview](../architecture-overview.md) - Overall system architecture
- [SOPS Setup Guide](sops-setup.md) - Secret encryption implementation