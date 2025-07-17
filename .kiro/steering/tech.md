# Technology Stack

## Core Technologies
- **Kubernetes Distribution**: k3s (lightweight Kubernetes)
- **GitOps**: Flux CD v2.6+ for continuous deployment
- **Storage**: Longhorn v1.9.0 for distributed block storage
- **Ingress**: NGINX Ingress Controller with NodePort (30080/30443)
- **Configuration Management**: Kustomize for YAML templating
- **Secrets**: SOPS for encrypted secrets management

## Infrastructure Components
- **Container Runtime**: containerd (built into k3s)
- **Service Mesh**: None (using standard Kubernetes networking)
- **Monitoring**: Prometheus + Grafana stack (kube-prometheus-stack)
- **DNS**: CoreDNS (built into k3s)
- **Load Balancer**: MetalLB or NodePort services

## Development Tools
- **CLI Tools**: kubectl, flux, helm
- **Package Manager**: Helm v3.0.0+ for complex applications
- **Version Control**: Git with GitHub integration
- **IDE**: VS Code with Kubernetes, Docker, YAML, and GitLens extensions

## Common Commands

### Cluster Management
```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Flux operations
flux check
flux get all -A
flux reconcile kustomization <name> -n flux-system
```

### Application Deployment
```bash
# Apply Kustomize configurations
kubectl apply -k apps/example-app/overlays/dev/
kubectl apply -k infrastructure/

# View resources
kubectl get pods,svc,ingress -A
kubectl describe kustomization <name> -n flux-system
```

### Storage Operations
```bash
# Longhorn status
kubectl get pods -n longhorn-system
kubectl get pv,pvc -A

# Access Longhorn UI
kubectl port-forward svc/longhorn-frontend 8080:80 -n longhorn-system
```

### Troubleshooting
```bash
# Controller logs
kubectl logs -n flux-system -l app=kustomize-controller
kubectl logs -n flux-system -l app=helm-controller

# Resource events
kubectl get events --sort-by='.lastTimestamp' -A
kubectl describe <resource-type> <resource-name> -n <namespace>
```

## Build and Test Patterns
- **GitOps Workflow**: All changes via Git commits, no direct kubectl apply
- **Environment Promotion**: Changes flow from dev → staging → prod
- **Validation**: Flux dry-run and health checks before deployment
- **Rollback**: Git revert for immediate rollback capability