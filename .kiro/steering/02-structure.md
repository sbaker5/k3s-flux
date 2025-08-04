---
inclusion: always
---

# Project Structure and Organization

## Repository Layout

```
├── .kiro/                     # Kiro AI assistant configuration
│   ├── specs/                 # Feature specifications and requirements
│   └── steering/              # AI guidance rules (this directory)
├── clusters/                  # Cluster-specific configurations
│   └── k3s-flux/              # Main cluster configuration
│       ├── flux-system/       # Flux bootstrap manifests
│       ├── infrastructure-*.yaml  # Infrastructure kustomizations
│       └── *-kustomization.yaml  # Application kustomizations
├── infrastructure/            # Infrastructure components
│   ├── core/                  # Core networking and ingress
│   ├── longhorn/              # Distributed storage
│   ├── monitoring/            # Prometheus/Grafana stack
│   ├── nginx-ingress/         # Ingress controller
│   └── storage/               # Storage utilities and discovery
├── apps/                      # Application deployments
│   └── */                     # Individual applications
│       ├── base/              # Base Kubernetes manifests
│       └── overlays/          # Environment-specific configs
│           ├── dev/           # Development environment
│           ├── staging/       # Staging environment
│           └── prod/          # Production environment
├── docs/                      # Documentation
│   ├── troubleshooting/       # Troubleshooting guides
│   └── *.md                   # Setup and operational guides
└── tests/                     # Test configurations and examples
    └── kubernetes/            # Kubernetes test manifests
```

## Architecture Patterns

### Bulletproof Architecture
- **Core Infrastructure**: Always available (networking, ingress)
- **Storage Infrastructure**: Can fail without breaking core services
- **Applications**: Only depend on core, remain deployable during storage issues

### GitOps Principles
- **Single Source of Truth**: All configuration in Git
- **Declarative**: Desired state defined in YAML
- **Automated**: Flux reconciles cluster state
- **Auditable**: All changes tracked in Git history

## File Naming Conventions

### Kustomization Files
- `kustomization.yaml` - Standard Kustomize configuration
- `*-kustomization.yaml` - Flux Kustomization CRDs in clusters/

### Infrastructure Components
- `helm-release.yaml` - Helm application deployments
- `helm-repository.yaml` - Helm chart repositories
- `namespace.yaml` - Namespace definitions
- `*-patch.yaml` - Kustomize patches for modifications

### Application Structure
- `deployment.yaml` - Kubernetes Deployment
- `service.yaml` - Kubernetes Service
- `ingress.yaml` - Ingress routing rules
- `pvc.yaml` - PersistentVolumeClaim for storage

## Dependency Management

### Infrastructure Dependencies
1. **Core** (nginx-ingress, networking) - No dependencies
2. **Storage** (longhorn) - Depends on core
3. **Monitoring** - Depends on storage (for PVCs)
4. **Applications** - Depend only on core (bulletproof)

### Kustomization Dependencies
Use `dependsOn` in Flux Kustomizations:
```yaml
spec:
  dependsOn:
    - name: infrastructure-core
      namespace: flux-system
```

## Environment Management

### Overlay Pattern
- **Base**: Common configuration shared across environments
- **Overlays**: Environment-specific patches and configurations
- **Promotion**: Changes flow dev → staging → prod

### Resource Naming
- Use `namePrefix` in Kustomize for environment isolation
- Include environment in labels: `environment: dev|staging|prod`
- Namespace separation: `app-dev`, `app-staging`, `app-prod`

## Best Practices

### File Organization
- Keep related resources together in directories
- Use consistent naming across similar components
- Separate base configurations from environment-specific overlays
- Group infrastructure by function (networking, storage, monitoring)

### Configuration Management
- Avoid hardcoded values - use Kustomize patches
- Store secrets encrypted with SOPS
- Use ConfigMaps for non-sensitive configuration
- Implement proper resource limits and requests

### Documentation
- Document complex configurations inline with comments
- Maintain setup guides in `docs/`
- Include troubleshooting procedures
- Keep README.md current with project status