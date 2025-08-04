---
inclusion: always
title: Flux GitOps Standards and Patterns
description: Standards for working with Flux CD resources and GitOps workflows
---

# Flux GitOps Standards and Patterns

## Purpose

This document defines standards and patterns for working with Flux CD resources in our k3s cluster. It provides guidance on resource structure, naming conventions, and operational patterns.

## Why These Standards Matter

- **Consistency**: Standardized patterns make resources predictable and maintainable
- **Troubleshooting**: Consistent labeling and structure simplifies debugging
- **Automation**: Predictable patterns enable better tooling and automation
- **Team Collaboration**: Clear conventions reduce cognitive load for team members

## Flux Custom Resources Overview

Flux consists of the following Kubernetes controllers and custom resource definitions (CRDs):

### Source Controller
- **GitRepository**: Points to a Git repository containing Kubernetes manifests or Helm charts
- **OCIRepository**: Points to a container registry containing OCI artifacts (manifests or Helm charts)
- **Bucket**: Points to an S3-compatible bucket containing manifests
- **HelmRepository**: Points to a Helm chart repository
- **HelmChart**: References a chart from a HelmRepository or a GitRepository

### Kustomize Controller
- **Kustomization**: Builds and applies Kubernetes manifests from sources

### Helm Controller
- **HelmRelease**: Manages Helm chart releases from sources

### Notification Controller
- **Provider**: Represents a notification service (Slack, MS Teams, etc.)
- **Alert**: Configures events to be forwarded to providers
- **Receiver**: Defines webhooks for triggering reconciliations

### Image Automation Controllers
- **ImageRepository**: Scans container registries for new tags
- **ImagePolicy**: Selects the latest image tag based on policy
- **ImageUpdateAutomation**: Updates Git repository with new image tags

## Resource Naming Standards

### GitRepository Resources
```yaml
# ✅ GOOD - Clear, descriptive names
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: k3s-flux-infrastructure
  namespace: flux-system
```

### Kustomization Resources
```yaml
# ✅ GOOD - Hierarchical naming with dependencies
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-core
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure-base
```

### HelmRelease Resources
```yaml
# ✅ GOOD - Component name with environment context
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: monitoring-core
  namespace: monitoring
```

## Dependency Management Patterns

### Infrastructure Dependencies
Follow the bulletproof architecture pattern:

```yaml
# 1. Core infrastructure (no dependencies)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-core
spec:
  # No dependsOn - this is foundational

---
# 2. Storage infrastructure (depends on core)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-storage
spec:
  dependsOn:
    - name: infrastructure-core

---
# 3. Applications (depend only on core - bulletproof)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps-production
spec:
  dependsOn:
    - name: infrastructure-core
    # Note: NOT dependent on storage
```

## Labeling Standards

### Required Labels
All Flux resources should include these labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: component-name
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure|application
    environment: dev|staging|prod
    monitoring.k3s-flux.io/enabled: "true"  # For monitoring discovery
```

### Example with Full Labels
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: longhorn
  namespace: longhorn-system
  labels:
    app.kubernetes.io/name: longhorn
    app.kubernetes.io/part-of: k3s-flux
    app.kubernetes.io/component: infrastructure
    environment: prod
    monitoring.k3s-flux.io/enabled: "true"
```

## Configuration Management Patterns

### Values Management for HelmReleases
```yaml
# ✅ GOOD - External values with clear references
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
spec:
  valuesFrom:
    - kind: ConfigMap
      name: longhorn-config
      valuesKey: values.yaml
    - kind: Secret
      name: longhorn-secrets
      valuesKey: secrets.yaml
```

### Substitution for Kustomizations
```yaml
# ✅ GOOD - Environment-specific substitutions
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
spec:
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-config
      - kind: Secret
        name: cluster-secrets
```

## Operational Standards

### MCP Tool Usage
When working with Flux resources, prefer MCP tools:

```bash
# ✅ GOOD - Use MCP tools for Flux operations
mcp_flux_get_flux_instance  # Check Flux installation status
mcp_flux_get_kubernetes_resources  # Get K8s/Flux resources
mcp_flux_reconcile_flux_kustomization  # Trigger reconciliation

# ✅ ACCEPTABLE - Direct flux CLI when MCP unavailable
flux check
flux get all -A
flux reconcile kustomization <name> -n flux-system
```

### Resource Identification
To determine if a Kubernetes resource is Flux-managed:
- Search the metadata field for `fluxcd` labels
- Check for `kustomize.toolkit.fluxcd.io/` or `helm.toolkit.fluxcd.io/` annotations
- Look for owner references to Flux controllers

### Documentation Requirements
When creating Flux resources:
- Include comments explaining complex configurations
- Document dependency relationships
- Reference related resources in comments
- Include troubleshooting notes for common issues

## Common Anti-Patterns to Avoid

### ❌ Avoid Direct kubectl apply
```bash
# ❌ BAD - Bypasses GitOps
kubectl apply -f infrastructure/

# ✅ GOOD - Use GitOps workflow
git commit -m "Update infrastructure"
git push origin main
```

### ❌ Avoid Circular Dependencies
```yaml
# ❌ BAD - Creates circular dependency
spec:
  dependsOn:
    - name: app-b  # app-b depends on app-a
```

### ❌ Avoid Storage Dependencies for Apps
```yaml
# ❌ BAD - Breaks bulletproof architecture
spec:
  dependsOn:
    - name: infrastructure-storage  # Apps should not depend on storage
```

## Troubleshooting Integration

For complex troubleshooting scenarios, use the specialized troubleshooting guide:
- Include `#flux-troubleshooting` in your chat for detailed debugging workflows
- Use systematic approaches for HelmRelease and Kustomization analysis
- Follow multi-cluster comparison procedures when needed