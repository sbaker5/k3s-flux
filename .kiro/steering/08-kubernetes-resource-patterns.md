---
inclusion: fileMatch
fileMatchPattern: "**/*.yaml"
title: Kubernetes Resource Patterns and Standards
description: Standard patterns for Kubernetes resource definitions
---

# Kubernetes Resource Patterns and Standards

## Purpose

This document defines standard patterns for creating and managing Kubernetes resources in our k3s cluster, ensuring consistency and maintainability.

## Why These Patterns Matter

- **Consistency**: Standardized resource definitions reduce cognitive load
- **Troubleshooting**: Predictable patterns make debugging easier
- **Automation**: Standard labels and annotations enable better tooling
- **Security**: Consistent RBAC and security patterns reduce vulnerabilities

## Resource Labeling Standards

### Required Labels
All Kubernetes resources should include these labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: component-name
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: frontend|backend|database
    app.kubernetes.io/managed-by: flux|helm|kubectl
    environment: dev|staging|prod
```

### Example Application Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: production
  labels:
    app.kubernetes.io/name: web-app
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/version: "2.1.0"
    app.kubernetes.io/component: frontend
    app.kubernetes.io/managed-by: flux
    environment: prod
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: web-app
      app.kubernetes.io/component: frontend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: web-app
        app.kubernetes.io/component: frontend
        environment: prod
```

## Resource Limits and Requests

### Why Resource Limits Matter
- **Stability**: Prevents resource starvation and cluster instability
- **Scheduling**: Helps Kubernetes make better scheduling decisions
- **Cost Control**: Enables better resource utilization and planning

### Standard Resource Patterns

```yaml
# Small applications (web frontends, APIs)
resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi

# Medium applications (databases, processing services)
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 1Gi

# Large applications (data processing, ML workloads)
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

## Security Patterns

### ServiceAccount Standards
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: production
  labels:
    app.kubernetes.io/name: web-app
    app.kubernetes.io/part-of: k3s-flux
automountServiceAccountToken: false  # Disable unless needed
```

### Network Policy Example
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-app-netpol
  namespace: production
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: web-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

## Storage Patterns

### PersistentVolumeClaim Standards
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: production
  labels:
    app.kubernetes.io/name: web-app
    app.kubernetes.io/part-of: k3s-flux
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn  # Use Longhorn for distributed storage
  resources:
    requests:
      storage: 10Gi
```

## Configuration Management

### ConfigMap Patterns
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
  labels:
    app.kubernetes.io/name: web-app
    app.kubernetes.io/part-of: k3s-flux
data:
  app.properties: |
    server.port=8080
    logging.level.root=INFO
    # Environment-specific configuration
```

### Secret Management
```yaml
# Use SOPS for encrypted secrets in Git
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: production
  labels:
    app.kubernetes.io/name: web-app
    app.kubernetes.io/part-of: k3s-flux
type: Opaque
data:
  # Values encrypted with SOPS
  database-password: <encrypted-value>
```

## Health Check Patterns

### Liveness and Readiness Probes
```yaml
spec:
  containers:
  - name: app
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
```

## Anti-Patterns to Avoid

### ❌ Missing Resource Limits
```yaml
# ❌ BAD - No resource limits
spec:
  containers:
  - name: app
    image: myapp:latest
    # Missing resources section
```

### ❌ Hardcoded Values
```yaml
# ❌ BAD - Hardcoded configuration
env:
- name: DATABASE_URL
  value: "postgres://user:password@db:5432/mydb"

# ✅ GOOD - Use ConfigMap/Secret references
env:
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: app-secrets
      key: database-url
```

### ❌ Overprivileged ServiceAccounts
```yaml
# ❌ BAD - Using default ServiceAccount with broad permissions
spec:
  serviceAccountName: default

# ✅ GOOD - Dedicated ServiceAccount with minimal permissions
spec:
  serviceAccountName: app-service-account
```

## Validation Checklist

Before applying any Kubernetes resource:

- [ ] All required labels are present
- [ ] Resource limits and requests are defined
- [ ] ServiceAccount follows least privilege principle
- [ ] Secrets are encrypted with SOPS
- [ ] Health checks are configured appropriately
- [ ] Network policies restrict traffic as needed
- [ ] Storage uses appropriate StorageClass