# Tailscale Security Hardening Guide

## Overview

This guide provides step-by-step procedures to secure the Tailscale subnet router configuration in the k3s cluster.

## Security Issues Addressed

### Critical Issues
- **Plaintext auth keys in Git** - Keys stored unencrypted in version control
- **Privileged containers** - Unnecessary elevated permissions
- **Unpinned image versions** - Using `:latest` tags creates supply chain risks

### High Priority Issues  
- **Missing health checks** - No failure detection mechanisms
- **Hardcoded network ranges** - Inflexible environment configuration
- **Insufficient resource limits** - Risk of resource exhaustion

### Medium Priority Issues
- **No environment separation** - Single configuration for all environments
- **Missing network policies** - Unrestricted network access
- **No monitoring/alerting** - Limited observability

## Quick Start

### Step 1: Immediate Security Fixes

Use the provided scripts to quickly secure your Tailscale configuration:

```bash
# 1. Set up SOPS encryption
./scripts/setup-sops-for-tailscale.sh

# 2. Revoke the exposed key in Tailscale admin console
# Go to: https://login.tailscale.com/admin/settings/keys

# 3. Create new encrypted secret
./scripts/create-encrypted-tailscale-secret.sh

# 4. Validate security configuration
./scripts/validate-tailscale-security.sh
```

### Step 2: Container Security Hardening

#### 2.1 Remove Privileged Access
```bash
#!/bin/bash
# scripts/harden-tailscale-container.sh

set -euo pipefail

SUBNET_ROUTER_FILE="infrastructure/tailscale/base/subnet-router.yaml"

echo "Hardening Tailscale container security..."

# Create backup
cp "$SUBNET_ROUTER_FILE" "${SUBNET_ROUTER_FILE}.backup"

# Remove privileged access and add specific capabilities
cat > /tmp/security-patch.yaml << 'EOF'
        securityContext:
          # Remove privileged access - use specific capabilities instead
          # privileged: true  # REMOVED FOR SECURITY
          capabilities:
            add:
              - CAP_NET_ADMIN    # Required for network interface management
              - CAP_SYS_ADMIN    # Required for routing table modifications
          # Additional security hardening
          runAsNonRoot: false      # Tailscale requires root for network operations
          readOnlyRootFilesystem: false  # Tailscale needs to write state files
          allowPrivilegeEscalation: false
EOF

# Apply the security patch
# Note: This is a simplified example - actual implementation would use yq or similar
echo "Manual edit required for $SUBNET_ROUTER_FILE:"
echo "1. Remove 'privileged: true' line"
echo "2. Add the security context from /tmp/security-patch.yaml"
echo "3. Verify the changes before committing"

echo "Security patch template created: /tmp/security-patch.yaml"
```

#### 2.2 Pin Image Version
```bash
#!/bin/bash
# scripts/pin-tailscale-image.sh

set -euo pipefail

SUBNET_ROUTER_FILE="infrastructure/tailscale/base/subnet-router.yaml"

echo "Pinning Tailscale image version..."

# Get latest stable version (example - check Tailscale releases)
LATEST_VERSION="v1.56.1"  # Update this to current stable version

# Replace latest tag with specific version
sed -i.bak "s|tailscale/tailscale:latest|tailscale/tailscale:$LATEST_VERSION|g" "$SUBNET_ROUTER_FILE"

echo "✅ Image version pinned to: tailscale/tailscale:$LATEST_VERSION"
echo "✅ Backup created: ${SUBNET_ROUTER_FILE}.bak"

# Verify the change
if grep -q "tailscale/tailscale:$LATEST_VERSION" "$SUBNET_ROUTER_FILE"; then
    echo "✅ Version pinning successful"
else
    echo "❌ Version pinning failed"
    exit 1
fi
```

### Step 3: Resource and Health Configuration

#### 3.1 Add Resource Limits and Health Checks
```bash
#!/bin/bash
# scripts/add-tailscale-resources-health.sh

set -euo pipefail

echo "Adding resource limits and health checks..."

# Create resource and health configuration
cat > /tmp/resources-health-patch.yaml << 'EOF'
        # Resource limits for security and stability
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
          limits:
            cpu: 200m      # Increased from 100m for stability
            memory: 200Mi  # Increased from 100Mi for stability
        
        # Health checks to detect failures
        livenessProbe:
          exec:
            command:
              - /bin/sh
              - -c
              - "tailscale status --json | jq -e '.BackendState == \"Running\"'"
          initialDelaySeconds: 30
          periodSeconds: 60
          timeoutSeconds: 10
          failureThreshold: 3
        
        readinessProbe:
          exec:
            command:
              - /bin/sh
              - -c
              - "tailscale status --json | jq -e '.Self.Online == true'"
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        
        # Startup probe for initial connection
        startupProbe:
          exec:
            command:
              - /bin/sh
              - -c
              - "tailscale status --json | jq -e '.BackendState != \"NeedsLogin\"'"
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 30  # Allow up to 5 minutes for startup
EOF

echo "Resource and health configuration created: /tmp/resources-health-patch.yaml"
echo "Manual integration required into subnet-router.yaml"
```

### Step 4: Environment-Specific Configuration

#### 4.1 Create Environment Overlays
```bash
#!/bin/bash
# scripts/create-tailscale-overlays.sh

set -euo pipefail

echo "Creating environment-specific Tailscale overlays..."

# Create overlay directories
mkdir -p infrastructure/tailscale/overlays/{dev,staging,prod}

# Development overlay
cat > infrastructure/tailscale/overlays/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: tailscale

resources:
  - ../../base

patches:
  - target:
      kind: Deployment
      name: tailscale-subnet-router
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: "10.42.0.0/16,10.43.0.0/16,192.168.1.0/24"  # Dev network ranges
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "100m"  # Lower limits for dev
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "128Mi"

commonLabels:
  environment: dev
EOF

# Staging overlay
cat > infrastructure/tailscale/overlays/staging/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: tailscale

resources:
  - ../../base

patches:
  - target:
      kind: Deployment
      name: tailscale-subnet-router
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: "10.42.0.0/16,10.43.0.0/16,192.168.2.0/24"  # Staging network ranges
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "150m"  # Medium limits for staging
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "150Mi"

commonLabels:
  environment: staging
EOF

# Production overlay
cat > infrastructure/tailscale/overlays/prod/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: tailscale

resources:
  - ../../base

patches:
  - target:
      kind: Deployment
      name: tailscale-subnet-router
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: "10.42.0.0/16,10.43.0.0/16,192.168.86.0/24"  # Production network ranges
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "200m"  # Higher limits for production
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "200Mi"

commonLabels:
  environment: prod
EOF

echo "✅ Environment overlays created:"
echo "  - infrastructure/tailscale/overlays/dev/"
echo "  - infrastructure/tailscale/overlays/staging/"
echo "  - infrastructure/tailscale/overlays/prod/"
```

#### 4.2 Update Flux Kustomizations
```bash
#!/bin/bash
# scripts/update-flux-tailscale-kustomizations.sh

set -euo pipefail

echo "Updating Flux Kustomizations for environment-specific Tailscale..."

# Update main cluster kustomization to use production overlay
cat > clusters/k3s-flux/infrastructure-tailscale.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-tailscale
  namespace: flux-system
  labels:
    app.kubernetes.io/name: tailscale
    app.kubernetes.io/part-of: k3s-flux-infrastructure
spec:
  interval: 10m
  path: ./infrastructure/tailscale/overlays/prod  # Use production overlay
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  timeout: 5m
  wait: true
  # SOPS decryption for encrypted secrets
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  # Health checks
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: tailscale-subnet-router
      namespace: tailscale
  dependsOn:
    - name: infrastructure-core
      namespace: flux-system
EOF

echo "✅ Flux Kustomization updated: clusters/k3s-flux/infrastructure-tailscale.yaml"
echo "✅ Now uses production overlay with SOPS decryption"
```

### Step 5: Network Security Configuration

#### 5.1 Create Network Policies
```bash
#!/bin/bash
# scripts/create-tailscale-network-policies.sh

set -euo pipefail

echo "Creating network policies for Tailscale..."

cat > infrastructure/tailscale/base/network-policy.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tailscale-subnet-router
  namespace: tailscale
  labels:
    app.kubernetes.io/name: tailscale
    app.kubernetes.io/component: network-policy
spec:
  podSelector:
    matchLabels:
      app: tailscale-subnet-router
  policyTypes:
  - Ingress
  - Egress
  
  # Ingress rules - very restrictive
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system  # Allow kube-system for health checks
    ports:
    - protocol: TCP
      port: 8080  # Health check port (if added)
  
  # Egress rules - allow necessary Tailscale communication
  egress:
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  
  # Allow Tailscale control plane communication
  - to: []
    ports:
    - protocol: TCP
      port: 443  # HTTPS to Tailscale control plane
    - protocol: UDP
      port: 41641  # Tailscale default port
  
  # Allow communication to cluster networks
  - to:
    - namespaceSelector: {}  # All namespaces in cluster
    ports:
    - protocol: TCP
      port: 6443  # Kubernetes API
  
  # Allow ICMP for connectivity testing
  - to: []
    ports:
    - protocol: ICMP
EOF

# Add to kustomization
echo "  - network-policy.yaml" >> infrastructure/tailscale/base/kustomization.yaml

echo "✅ Network policy created: infrastructure/tailscale/base/network-policy.yaml"
echo "✅ Added to base kustomization"
```

### Step 6: Monitoring and Alerting

#### 6.1 Add Tailscale Monitoring
```bash
#!/bin/bash
# scripts/add-tailscale-monitoring.sh

set -euo pipefail

echo "Adding Tailscale monitoring configuration..."

# Create ServiceMonitor for Tailscale metrics (if metrics are exposed)
cat > infrastructure/tailscale/base/service-monitor.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tailscale-subnet-router
  namespace: tailscale
  labels:
    app.kubernetes.io/name: tailscale
    app.kubernetes.io/component: monitoring
    monitoring.k3s-flux.io/component: tailscale-metrics
spec:
  selector:
    matchLabels:
      app: tailscale-subnet-router
  endpoints:
  - port: metrics  # If Tailscale exposes metrics
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
    honorLabels: true
    relabelings:
    - sourceLabels: [__meta_kubernetes_service_name]
      targetLabel: service
    - sourceLabels: [__meta_kubernetes_namespace]
      targetLabel: namespace
    - targetLabel: cluster
      replacement: k3s-flux
    metricRelabelings:
    # Keep only Tailscale-specific metrics
    - sourceLabels: [__name__]
      regex: "tailscale_.*"
      action: keep
EOF

# Create PrometheusRule for Tailscale alerts
cat > infrastructure/tailscale/base/prometheus-rule.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: tailscale-alerts
  namespace: tailscale
  labels:
    app.kubernetes.io/name: tailscale
    app.kubernetes.io/component: alerting
spec:
  groups:
  - name: tailscale
    rules:
    - alert: TailscaleSubnetRouterDown
      expr: |
        up{job="tailscale-subnet-router"} == 0
      for: 2m
      labels:
        severity: critical
        component: tailscale
      annotations:
        summary: "Tailscale subnet router is down"
        description: "The Tailscale subnet router has been down for more than 2 minutes"
        runbook_url: "https://github.com/your-org/k3s-flux/blob/main/docs/troubleshooting/tailscale-troubleshooting.md"
    
    - alert: TailscaleConnectionUnstable
      expr: |
        rate(tailscale_connection_errors_total[5m]) > 0.1
      for: 5m
      labels:
        severity: warning
        component: tailscale
      annotations:
        summary: "Tailscale connection is unstable"
        description: "Tailscale is experiencing connection errors at a rate of {{ $value }} per second"
    
    - alert: TailscalePodRestartingFrequently
      expr: |
        rate(kube_pod_container_status_restarts_total{namespace="tailscale", pod=~"tailscale-subnet-router-.*"}[15m]) > 0
      for: 5m
      labels:
        severity: warning
        component: tailscale
      annotations:
        summary: "Tailscale pod restarting frequently"
        description: "Tailscale pod {{ $labels.pod }} has restarted {{ $value }} times in the last 15 minutes"
EOF

# Add to kustomization
cat >> infrastructure/tailscale/base/kustomization.yaml << 'EOF'
  - service-monitor.yaml
  - prometheus-rule.yaml
EOF

echo "✅ Tailscale monitoring added:"
echo "  - ServiceMonitor for metrics collection"
echo "  - PrometheusRule for alerting"
echo "  - Added to base kustomization"
```

### Step 7: Documentation and Validation

#### 7.1 Add Inline Documentation
```bash
#!/bin/bash
# scripts/document-tailscale-config.sh

set -euo pipefail

echo "Adding comprehensive documentation to Tailscale configuration..."

# Add detailed comments to subnet-router.yaml
cat > /tmp/documented-subnet-router-header.yaml << 'EOF'
# Tailscale Subnet Router Configuration
# 
# This deployment creates a Tailscale subnet router that advertises the k3s cluster
# networks to the Tailscale network, enabling secure remote access to cluster services.
#
# Security Model:
# - Uses specific capabilities (CAP_NET_ADMIN, CAP_SYS_ADMIN) instead of privileged mode
# - Runs with minimal required permissions
# - Network policies restrict ingress/egress traffic
# - Encrypted auth key stored with SOPS
# - Resource limits prevent resource exhaustion
#
# Network Architecture:
# - Advertises pod CIDR (10.42.0.0/16) and service CIDR (10.43.0.0/16)
# - Advertises host network (192.168.86.0/24) for node access
# - Enables kubectl port-forward through Tailscale routing
# - Provides emergency SSH access to cluster nodes
#
# Health Checks:
# - Liveness probe ensures Tailscale daemon is running
# - Readiness probe verifies connection to Tailscale control plane
# - Startup probe allows time for initial authentication
#
# Monitoring:
# - ServiceMonitor collects connection metrics
# - PrometheusRule alerts on connection issues
# - Logs available via kubectl logs
#
EOF

echo "Documentation header created: /tmp/documented-subnet-router-header.yaml"
echo "Manual integration required into subnet-router.yaml"
```

#### 7.2 Create Validation Script
```bash
#!/bin/bash
# scripts/validate-tailscale-hardening.sh

set -euo pipefail

echo "Validating Tailscale security hardening..."

VALIDATION_ERRORS=0

validate_file_exists() {
    local file="$1"
    local description="$2"
    
    if [[ -f "$file" ]]; then
        echo "✅ $description: $file"
    else
        echo "❌ $description: $file (missing)"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
}

validate_no_plaintext_secrets() {
    echo "Checking for plaintext secrets..."
    
    if grep -r "tskey-auth-" --include="*.yaml" --include="*.yml" infrastructure/tailscale/ 2>/dev/null | grep -v ".sops."; then
        echo "❌ Plaintext Tailscale auth key found"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    else
        echo "✅ No plaintext auth keys found"
    fi
}

validate_sops_encryption() {
    echo "Validating SOPS encryption..."
    
    local sops_file="infrastructure/tailscale/base/secret.sops.yaml"
    if [[ -f "$sops_file" ]]; then
        if sops --decrypt "$sops_file" >/dev/null 2>&1; then
            echo "✅ SOPS encryption working"
        else
            echo "❌ SOPS decryption failed"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi
    else
        echo "❌ SOPS encrypted secret not found"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
}

validate_no_privileged_containers() {
    echo "Checking for privileged containers..."
    
    if grep -r "privileged: true" infrastructure/tailscale/ 2>/dev/null; then
        echo "❌ Privileged containers found"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    else
        echo "✅ No privileged containers found"
    fi
}

validate_pinned_images() {
    echo "Checking for pinned image versions..."
    
    if grep -r ":latest" infrastructure/tailscale/ 2>/dev/null; then
        echo "❌ Latest image tags found"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    else
        echo "✅ All images use specific versions"
    fi
}

validate_environment_overlays() {
    echo "Checking environment overlays..."
    
    local overlays=("dev" "staging" "prod")
    for env in "${overlays[@]}"; do
        validate_file_exists "infrastructure/tailscale/overlays/$env/kustomization.yaml" "Environment overlay ($env)"
    done
}

validate_monitoring_config() {
    echo "Checking monitoring configuration..."
    
    validate_file_exists "infrastructure/tailscale/base/service-monitor.yaml" "ServiceMonitor"
    validate_file_exists "infrastructure/tailscale/base/prometheus-rule.yaml" "PrometheusRule"
}

validate_network_policies() {
    echo "Checking network policies..."
    
    validate_file_exists "infrastructure/tailscale/base/network-policy.yaml" "NetworkPolicy"
}

# Run all validations
echo "Starting Tailscale security validation..."
echo "========================================"

validate_file_exists "infrastructure/tailscale/base/secret.sops.yaml" "Encrypted secret"
validate_no_plaintext_secrets
validate_sops_encryption
validate_no_privileged_containers
validate_pinned_images
validate_environment_overlays
validate_monitoring_config
validate_network_policies

echo "========================================"

if [[ $VALIDATION_ERRORS -eq 0 ]]; then
    echo "✅ All validations passed! Tailscale hardening is complete."
    exit 0
else
    echo "❌ $VALIDATION_ERRORS validation error(s) found. Please address the issues above."
    exit 1
fi
```

## Implementation Checklist

### Immediate Actions (Critical)
- [ ] **Revoke exposed Tailscale auth key** in admin console
- [ ] **Generate new encrypted auth key** with SOPS
- [ ] **Remove privileged container access**
- [ ] **Pin image version** to specific tag
- [ ] **Remove plaintext secret** from Git
- [ ] **Clean Git history** of exposed credentials

### Security Hardening (High Priority)
- [ ] **Add specific capabilities** instead of privileged mode
- [ ] **Implement resource limits** and health checks
- [ ] **Create network policies** for traffic restriction
- [ ] **Add environment overlays** for configuration isolation
- [ ] **Update Flux Kustomizations** with SOPS decryption

### Monitoring and Documentation (Medium Priority)
- [ ] **Add ServiceMonitor** for metrics collection
- [ ] **Create PrometheusRule** for alerting
- [ ] **Document security model** with inline comments
- [ ] **Create validation scripts** for ongoing security checks
- [ ] **Update architecture documentation** with security details

### Operational Procedures (Low Priority)
- [ ] **Create incident response procedures** for Tailscale issues
- [ ] **Add emergency CLI commands** for Tailscale management
- [ ] **Implement automated security scanning** in CI/CD
- [ ] **Create runbooks** for common Tailscale operations

## Testing and Validation

### Pre-deployment Testing
```bash
# Validate configuration before applying
kubectl kustomize infrastructure/tailscale/overlays/prod

# Test SOPS decryption
sops --decrypt infrastructure/tailscale/base/secret.sops.yaml

# Run security validation
./scripts/validate-tailscale-hardening.sh
```

### Post-deployment Validation
```bash
# Check pod status
kubectl get pods -n tailscale

# Verify Tailscale connection
kubectl exec -n tailscale deployment/tailscale-subnet-router -- tailscale status

# Test remote access
kubectl --context=k3s-remote get nodes

# Validate network policies
kubectl describe networkpolicy -n tailscale
```

## Rollback Procedures

If issues occur during hardening:

```bash
#!/bin/bash
# scripts/rollback-tailscale-hardening.sh

echo "Rolling back Tailscale hardening changes..."

# Restore from backup
git checkout HEAD~1 -- infrastructure/tailscale/

# Apply old configuration
flux reconcile kustomization infrastructure-tailscale -n flux-system

# Verify rollback
kubectl get pods -n tailscale

echo "Rollback completed. Investigate issues before re-attempting hardening."
```

## See Also

- [SOPS Setup Guide](sops-setup.md) - Implementing encrypted secrets
- [Secret Management Guide](secret-management.md) - Comprehensive secret procedures
- [Incident Response Guide](incident-response.md) - Security incident procedures
- [Remote Access Guide](../setup/tailscale-remote-access-setup.md) - Tailscale setup and usage
- [Architecture Overview](../architecture-overview.md) - System security architecture