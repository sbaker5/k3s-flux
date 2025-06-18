# k3s with Flux GitOps Setup

This project sets up a local k3s cluster with Flux for GitOps.

## Documentation

- [Nginx Ingress Setup](docs/nginx-ingress-setup.md) - Configuration and usage of the Nginx Ingress Controller

## Prerequisites

- [k3d](https://k3d.io/) (for local k3s clusters) or k3s installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [flux](https://fluxcd.io/docs/installation/)
- [VS Code](https://code.visualstudio.com/)

## VS Code Setup

1. Open the project in VS Code
2. Install the recommended extensions when prompted
   - Kubernetes
   - Docker
   - YAML
   - GitLens
   - Terraform (optional)

## Project Structure

```
.
├── .vscode/               # VS Code settings
│   ├── extensions.json    # Recommended extensions
│   └── settings.json     # Workspace settings
├── clusters/             # Cluster configurations
│   └── production/       # Production cluster
│       └── flux-system/  # Flux components
└── .gitignore           # Git ignore rules
```

## Getting Started

1. **Start a local k3s cluster** (using k3d):
   ```bash
   k3d cluster create my-cluster
   ```

2. **Verify cluster access**:
   ```bash
   kubectl cluster-info
   ```

3. **Bootstrap Flux** (when ready):
   ```bash
   flux bootstrap github \
     --owner=<your-github-username> \
     --repository=k3s-flux \
     --branch=main \
     --path=./clusters/production \
     --personal
   ```

## Next Steps

1. Set up your Git repository
2. Configure Flux to manage your applications
3. Add your Kubernetes manifests
4. Set up CI/CD pipelines

## Useful Commands

- View Flux resources: `kubectl get kustomizations,kustomizations -A`
- Check Flux logs: `kubectl logs -n flux-system -l app=source-controller`
- Get cluster info: `kubectl cluster-info`
