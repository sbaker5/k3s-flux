# k3s Cluster with Flux GitOps

This project sets up a production-grade k3s cluster with Flux CD for GitOps, Longhorn for distributed storage, and NGINX Ingress for service exposure.

## 📚 Documentation

### Quick Start
- [Getting Started](#-getting-started)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)

### Core Components
- [Flux CD Setup](docs/k3s-flux-longhorn-guide.md) - Guide to setting up Flux CD with k3s
- [NGINX Ingress](docs/nginx-ingress-setup.md) - Configuration and usage of the NGINX Ingress Controller
- [Longhorn Storage](docs/longhorn-setup.md) - Distributed block storage setup and management
- [Application Management](docs/application-management.md) - Managing applications with Kustomize

### Operations
- [Troubleshooting Guide](docs/troubleshooting/flux-recovery-guide.md) - Recovering from common issues
- [Backup & Recovery](docs/longhorn-setup.md#backup-configuration) - Data backup and recovery procedures
- [Test Resources](#test-resources) - Test configurations and examples

## 🚀 Getting Started

### Prerequisites

- [k3s](https://k3s.io/) installed on all nodes
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (v1.24+)
- [flux](https://fluxcd.io/docs/installation/) CLI (v2.0.0+)
- [Git](https://git-scm.com/)
- [Helm](https://helm.sh/) (v3.0.0+)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/k3s-flux.git
   cd k3s-flux
   ```

2. **Bootstrap Flux**
   ```bash
   flux bootstrap github \
     --owner=your-org \
     --repository=k3s-flux \
     --branch=main \
     --path=./clusters/k3s-flux \
     --personal
   ```

3. **Verify Installation**
   ```bash
   flux check
   kubectl get pods -n flux-system
   ```

## 🏗️ Project Structure

```
.
├── .github/               # GitHub workflows and issue templates
├── .vscode/               # VS Code settings and extensions
├── clusters/              # Cluster configurations
│   └── k3s-flux/          # Main cluster configuration
│       ├── flux-system/   # Flux bootstrap manifests
│       ├── apps.yaml       # Applications Kustomization
│       └── infrastructure.yaml  # Infrastructure components
├── infrastructure/        # Infrastructure components
│   ├── k3s-config/        # k3s configuration
│   ├── monitoring/        # Monitoring stack
│   └── networking/        # Ingress and network policies
├── docs/                  # Documentation
│   ├── troubleshooting/   # Troubleshooting guides
│   ├── application-management.md
│   ├── longhorn-setup.md
│   └── nginx-ingress-setup.md
└── apps/                  # Application deployments
    └── example-app/       # Example application
        ├── base/          # Base resources
        └── overlays/      # Environment-specific configs
```

## 🔧 VS Code Setup

1. **Install Recommended Extensions**
   - [Kubernetes](https://marketplace.visualstudio.com/items?itemName=ms-kubernetes-tools.vscode-kubernetes-tools)
   - [Docker](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-docker)
   - [YAML](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)
   - [GitLens](https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens)
   - [Terraform](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform) (optional)

2. **Recommended Settings**
   - Enable YAML schema validation
   - Set default formatter for YAML files
   - Enable Kubernetes intellisense

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🧪 Test Resources

Test configurations and examples are organized in the `tests/` directory:

```
tests/
├── kubernetes/
│   ├── examples/          # Example application configurations
│   ├── manifests/         # Test Kubernetes manifests
│   └── patches/           # Patch files for testing
```

### Using Test Resources

1. **Apply a test namespace**:
   ```bash
   kubectl apply -f tests/kubernetes/manifests/test-namespace.yaml
   ```

2. **Apply a test pod**:
   ```bash
   kubectl apply -f tests/kubernetes/manifests/example-pod.yaml
   ```

3. **Clean up**:
   ```bash
   kubectl delete -f tests/kubernetes/manifests/test-namespace.yaml
   ```

## 🙏 Acknowledgments

- [Flux CD](https://fluxcd.io/)
- [k3s](https://k3s.io/)
- [Longhorn](https://longhorn.io/)
- [NGINX Ingress](https://kubernetes.github.io/ingress-nginx/)

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
