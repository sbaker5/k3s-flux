# Application Management with Kustomize Overlays

This document explains the application deployment strategy using Kustomize overlays in this repository, including how to manage environments and implement the "offline until needed" functionality.

## Table of Contents
1. [Overview](#overview)
2. [Directory Structure](#directory-structure)
3. [Environment-Specific Configurations](#environment-specific-configurations)
4. [Offline Until Needed Functionality](#offline-until-needed-functionality)
5. [Managing Environments](#managing-environments)
6. [Best Practices](#best-practices)

## Overview

This repository uses a GitOps approach with Flux CD and Kustomize for managing Kubernetes applications. The key features include:

- **Environment Isolation**: Separate configurations for dev, staging, and prod
- **Resource Efficiency**: Ability to scale down non-production environments when not in use
- **Declarative Configuration**: All configurations are version-controlled in Git
- **Automated Reconciliation**: Flux CD ensures the cluster state matches the Git repository

## Directory Structure

```
apps/
  example-app/
    base/                  # Base configuration
      kustomization.yaml   # References all base resources
      deployment.yaml      # Base deployment
      service.yaml        # Base service
      
    overlays/
      dev/                 # Development environment
        kustomization.yaml # References base + dev patches
        
      staging/            # Staging environment
        kustomization.yaml # References base + staging patches
        
      prod/               # Production environment
        kustomization.yaml # References base + prod patches
```

## Environment-Specific Configurations

Each environment has its own overlay with specific configurations:

### Development (`overlays/dev`)
- **Purpose**: Local development and testing
- **Replicas**: 1 (can be scaled to 0 when not in use)
- **Resource Limits**: Lower than production
- **Image Tags**: `:dev-latest` or feature branch tags
- **Debugging Tools**: Additional sidecar containers if needed

### Staging (`overlays/staging`)
- **Purpose**: Pre-production testing
- **Replicas**: 2-3
- **Resource Limits**: Similar to production
- **Image Tags**: Release candidates (`:vX.Y.Z-rc.N`)
- **Data**: Synthetic or anonymized production data

### Production (`overlays/prod`)
- **Purpose**: Live traffic
- **Replicas**: Auto-scaled based on load
- **Resource Limits**: Optimized for production workload
- **Image Tags**: Versioned tags only (`:vX.Y.Z`)
- **High Availability**: Multiple replicas across nodes

## Offline Until Needed Functionality

Non-production environments can be taken offline to save resources when not in use.

### Taking an Environment Offline

1. **Scale Down Application**
   ```bash
   # Scale down the deployment
   kubectl scale deployment example-app --replicas=0 -n example-app-dev
   ```

2. **Suspend Flux Reconciliation (Optional)**
   ```bash
   # Suspend reconciliation for the environment
   flux suspend kustomization example-app-dev -n flux-system
   ```

### Bringing an Environment Online

1. **Resume Flux Reconciliation (if suspended)**
   ```bash
   flux resume kustomization example-app-dev -n flux-system
   ```

2. **Scale Up Application**
   ```bash
   # Scale up the deployment
   kubectl scale deployment example-app --replicas=1 -n example-app-dev
   ```

### Automated Scaling with CronJobs

For predictable usage patterns, you can set up CronJobs to scale environments on a schedule:

```yaml
# Example CronJob to scale up dev environment on weekdays at 8 AM
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-up-dev
  namespace: flux-system
spec:
  schedule: "0 8 * * 1-5"  # Weekdays at 8 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: kubectl
            image: bitnami/kubectl
            command:
            - /bin/sh
            - -c
            - |
              kubectl scale deployment example-app --replicas=1 -n example-app-dev
              kubectl rollout status deployment/example-app -n example-app-dev
          restartPolicy: OnFailure
```

## Managing Environments

### Creating a New Environment

1. Create a new overlay directory:
   ```bash
   mkdir -p apps/example-app/overlays/new-env
   ```

2. Create a kustomization.yaml that references the base:
   ```yaml
   # apps/example-app/overlays/new-env/kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
   - ../../base
   namespace: example-app-new-env
   
   # Add environment-specific patches
   patches:
   - target:
       kind: Deployment
       name: example-app
     patch: |
       - op: replace
         path: /spec/replicas
         value: 1
       - op: replace
         path: /spec/template/spec/containers/0/resources/limits
         value:
           cpu: "1"
           memory: "512Mi"
   ```

3. Create a Flux Kustomization for the new environment:
   ```yaml
   # clusters/k3s-flux/apps-example-app-new-env.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: example-app-new-env
     namespace: flux-system
   spec:
     interval: 5m
     path: ./apps/example-app/overlays/new-env
     prune: true
     sourceRef:
       kind: GitRepository
       name: flux-system
     targetNamespace: example-app-new-env
   ```

### Deleting an Environment

1. Delete the Flux Kustomization:
   ```bash
   kubectl delete kustomization example-app-new-env -n flux-system
   ```

2. Remove the overlay directory and commit the changes:
   ```bash
   git rm -r apps/example-app/overlays/new-env
   git commit -m "Remove new-env overlay"
   git push
   ```

## Best Practices

1. **Keep Base Configurations Minimal**: Only include common configurations in the base
2. **Use Meaningful Labels**: Add environment-specific labels for better observability
3. **Document Changes**: Update documentation when adding new environments or changing configurations
4. **Test Thoroughly**: Always test changes in dev before promoting to staging/prod
5. **Monitor Resource Usage**: Keep an eye on cluster resources, especially when bringing environments online
6. **Automate Where Possible**: Use CI/CD pipelines and automation to manage environments
7. **Security**: Apply least privilege principles to RBAC and network policies
8. **Backup**: Ensure critical data is backed up before making significant changes

## Troubleshooting

### Environment Not Updating
- Check Flux reconciliation status: `flux get kustomizations -A`
- View logs: `kubectl logs -n flux-system -l app=kustomize-controller`
- Check for errors: `kubectl get events -A --sort-by='.lastTimestamp'`

### Application Not Starting
- Check pod status: `kubectl get pods -n example-app-dev`
- View logs: `kubectl logs -n example-app-dev deployment/example-app`
- Check resource usage: `kubectl top pods -n example-app-dev`

### Scaling Issues
- Check HPA status: `kubectl get hpa -n example-app-prod`
- View pod distribution: `kubectl get pods -n example-app-prod -o wide`
