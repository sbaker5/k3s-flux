# Application Management with Kustomize and Flux

This document outlines the GitOps-based application deployment strategy using Kustomize and Flux in this repository. It covers environment management, Ingress configuration, and resource optimization.

## Table of Contents
1. [Overview](#overview)
2. [Directory Structure](#directory-structure)
3. [Environment-Specific Configurations](#environment-specific-configurations)
4. [Ingress Configuration](#ingress-configuration)
5. [Offline Until Needed](#offline-until-needed)
6. [Managing Environments](#managing-environments)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Overview

This repository implements a GitOps workflow using Flux CD and Kustomize for managing Kubernetes applications. The architecture is designed for:

- **GitOps Workflow**: All changes are made through Git commits
- **Environment Isolation**: Separate configurations for dev, staging, and prod
- **Resource Efficiency**: Scale-to-zero for non-production environments
- **Declarative Configuration**: Infrastructure as Code (IaC) approach
- **Automated Reconciliation**: Flux CD maintains cluster state
- **Secure Access**: Ingress-based routing with authentication

### Key Components

1. **Flux CD**: GitOps operator for Kubernetes
2. **Kustomize**: Template-free YAML customization
3. **NGINX Ingress**: External access to services
4. **Longhorn**: Distributed block storage

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
- **Replicas**: 1 (scalable to 0)
- **Resource Requests/Limits**: 
  ```yaml
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
  ```
- **Image Tags**: `:dev-latest` or feature branch tags
- **Features**:
  - Debugging sidecars
  - Local development tooling
  - No production data

### Staging (`overlays/staging`)
- **Purpose**: Pre-production testing
- **Replicas**: 2 (fixed)
- **Resource Requests/Limits**:
  ```yaml
  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
  ```
- **Image Tags**: Release candidates (`:vX.Y.Z-rc.N`)
- **Data**: Synthetic or anonymized production data
- **Features**:
  - Production-like configuration
  - Performance testing
  - Integration testing

### Production (`overlays/prod`)
- **Purpose**: Live traffic
- **Replicas**: 2+ (auto-scaled)
- **Resource Requests/Limits**:
  ```yaml
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "2000m"
      memory: "2Gi"
  ```
- **Image Tags**: Versioned tags only (`:vX.Y.Z`)
- **Features**:
  - High availability
  - Horizontal Pod Autoscaler (HPA)
  - Production monitoring

## Ingress Configuration

### Basic Ingress Example
```yaml
# apps/example-app/base/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /example-app(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: example-app
            port:
              number: 80
```

### Environment-Specific Ingress
Each environment can have its own Ingress configuration:

```yaml
# apps/example-app/overlays/dev/ingress-patch.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Environment "Development" always;
spec:
  rules:
  - host: dev.example.com
    http:
      paths:
      - path: /example-app(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: example-app
            port:
              number: 80
```

## Offline Until Needed

Non-production environments can be scaled down when not in use to save resources.

### Taking an Environment Offline

1. **Scale Down Application**
   ```bash
   # Scale down all deployments in the namespace
   kubectl scale deployment --all --replicas=0 -n example-app-dev
   ```

2. **Suspend Flux Reconciliation**
   ```bash
   # Suspend reconciliation for the environment
   flux suspend kustomization example-app-dev -n flux-system
   ```

3. **Verify Resources**
   ```bash
   # Check pod status
   kubectl get pods -n example-app-dev
   
   # Check Flux status
   flux get kustomizations -n flux-system
   ```

### Bringing an Environment Online

1. **Resume Flux Reconciliation**
   ```bash
   flux resume kustomization example-app-dev -n flux-system
   ```

2. **Scale Up Application**
   ```bash
   # Scale up deployments
   kubectl scale deployment --all --replicas=1 -n example-app-dev
   ```

3. **Verify Status**
   ```bash
   # Check pod status
   kubectl get pods -n example-app-dev
   
   # Check application logs
   kubectl logs -n example-app-dev -l app=example-app
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

### GitOps Workflow
1. **Branch Strategy**
   - `main`: Production-ready code
   - `staging`: Pre-production testing
   - `feature/*`: New features
   - `bugfix/*`: Bug fixes

2. **Git Hook Integration**
   - **Pre-commit validation**: Automatic YAML syntax, Kustomization build, and immutable field validation
   - **Post-commit monitoring** (🚧 in development): Real-time Flux reconciliation status after git push
   - **MCP tool integration**: Enhanced monitoring and troubleshooting capabilities

3. **Commit Conventions**
   ```
   type(scope): description
   
   Detailed description if needed
   
   Fixes #issue-number
   ```
   
   Types:
   - feat: New feature
   - fix: Bug fix
   - docs: Documentation changes
   - style: Code style changes
   - refactor: Code refactoring
   - test: Adding tests
   - chore: Maintenance tasks

### Kubernetes Resources
1. **Resource Management**
   - Always set resource requests and limits
   - Use Quality of Service (QoS) classes
   - Implement Horizontal Pod Autoscaling (HPA)

2. **Security**
   - Use NetworkPolicies
   - Implement Pod Security Standards
   - Use PodDisruptionBudgets
   - Enable automatic secret rotation

3. **Monitoring**
   - Include Prometheus annotations
   - Configure liveness/readiness probes
   - Set up logging and metrics

## Troubleshooting

### Common Issues
- Check for errors: `kubectl get events -A --sort-by='.lastTimestamp'`

### Application Not Starting
- Check pod status: `kubectl get pods -n example-app-dev`
- View logs: `kubectl logs -n example-app-dev deployment/example-app`
- Check resource usage: `kubectl top pods -n example-app-dev`

### Scaling Issues
- Check HPA status: `kubectl get hpa -n example-app-prod`
- View pod distribution: `kubectl get pods -n example-app-prod -o wide`
