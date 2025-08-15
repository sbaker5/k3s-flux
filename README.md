# k3s Cluster with Flux GitOps

This project sets up a production-grade k3s cluster with Flux CD for GitOps, Longhorn for distributed storage, and NGINX Ingress for service exposure.

## 📚 Documentation

**📖 [Complete Documentation Index](docs/README.md)** - Start here for organized access to all documentation

> **New!** Documentation has been reorganized into logical folders: `setup/`, `guides/`, `operations/`, etc. The main docs folder now has a clear structure to help you find what you need quickly.

### Quick Start - What You Need Most
- **[Longhorn Infrastructure Recovery](docs/longhorn-infrastructure-recovery-completion.md)** - ✅ **COMPLETED** - Comprehensive Longhorn infrastructure recovery implementation
- **[k3s2 Node Onboarding Status](docs/k3s2-onboarding-status.md)** - 🚀 **Ready for Deployment** - Complete infrastructure prepared
- **[k3s2 Onboarding Completion Summary](docs/k3s2-onboarding-completion-summary.md)** - ✅ **Implementation Complete** - Comprehensive completion status
- **[Monitoring Guide](docs/guides/monitoring-user-guide.md)** - How to access and read your dashboards
- **[Remote Access Guide](docs/guides/remote-access-quick-reference.md)** - Access your cluster from anywhere
- **[Application Management](docs/application-management.md)** - Deploy and manage applications

### Setup Guides
- **[Longhorn Setup](docs/setup/longhorn-setup.md)** - Distributed storage setup
- **[Remote Access Setup](docs/setup/tailscale-remote-access-setup.md)** - Tailscale configuration
- **[NGINX Ingress Setup](docs/setup/nginx-ingress-setup.md)** - Ingress controller setup

### Operations & Troubleshooting
- **[Monitoring Operations](docs/operations/monitoring-system-cleanup.md)** - Fix monitoring issues
- **[Flux Recovery](docs/troubleshooting/flux-recovery-guide.md)** - Fix GitOps issues
- **[Dependency Cleanup](docs/operations/dependency-aware-cleanup.md)** - Clean up stuck resources
- **[MCP Tools Guide](docs/mcp-tools-guide.md)** - Enhanced cluster interaction with specialized Flux troubleshooting workflows

### Architecture & Reference
- [Architecture Overview](docs/architecture-overview.md) - System design, components, and data flows
- [GitOps Resilience Patterns](docs/gitops-resilience-patterns.md) - Comprehensive resilience system
- [MCP Tools Guide](docs/mcp-tools-guide.md) - Enhanced cluster interaction tools
- [Error Pattern Detection](docs/error-pattern-detection.md) - Advanced error detection system

### Security
- [Security Documentation](docs/security/) - **🚨 CRITICAL**: Comprehensive security guides and incident response
- [SOPS Setup Guide](docs/security/sops-setup.md) - Encrypted secrets management implementation
- [Secret Management Guide](docs/security/secret-management.md) - Secret lifecycle and rotation procedures
- [Incident Response Guide](docs/security/incident-response.md) - Security incident response procedures
- [Tailscale Hardening Guide](docs/security/tailscale-hardening.md) - **UPDATED**: Network security improvements and exposed credential remediation

### Testing & Validation
- [Testing Suite](tests/README.md) - Comprehensive testing tools for GitOps resilience patterns
- [Error Pattern Detection Testing](docs/testing/error-pattern-detection-testing.md) - Detailed testing guide for Tasks 3.1 & 3.2
- [Health Check Scripts](tests/validation/) - Automated health assessment and validation tools
- [Monitoring System Cleanup](docs/operations/monitoring-system-cleanup.md) - 🚧 **In Progress** - Bulletproof monitoring maintenance, cleanup automation, comprehensive health validation scripts, and remote access validation (Task 7 in progress)
- [Test Resources](#test-resources) - Test configurations and examples

### Advanced Features
- **GitOps Resilience Patterns** - Comprehensive resilience system preventing infrastructure lock-ups and ensuring reliable deployments
  - ✅ **Pre-commit validation infrastructure** - Kustomization build validation and syntax checking
  - ✅ **Immutable field conflict detection** - Advanced tool detecting breaking changes across 10+ resource types
  - 🚧 **Git-Flux reconciliation monitoring** - Intelligent post-commit hook providing real-time Flux reconciliation feedback and deployment status visibility
  - ✅ **Reconciliation health monitoring** - Complete hybrid monitoring architecture with bulletproof core tier
  - ✅ **Alert rules for stuck reconciliations** - Comprehensive PrometheusRule resources for proactive detection
  - ✅ **GitOps health monitoring dashboard** - Grafana dashboard for Flux reconciliation visibility and performance tracking
  - ✅ **Emergency recovery procedures** - Manual intervention guides and operational runbooks
  - 🚧 **System state backup and restore capabilities** - Automated backup of Flux configurations and cluster state (Task 4.3 in progress)
  - ✅ **Comprehensive troubleshooting documentation** - Recovery procedures for common failure scenarios
  - ✅ **Error pattern detection system** - Advanced controller monitoring 20+ error patterns with real-time event correlation
  - ✅ **Automated recovery system** - Complete error pattern detection and resource recreation automation
  - ✅ **Longhorn Infrastructure Recovery** - Comprehensive distributed storage implementation with bulletproof architecture, GitOps integration, and monitoring
  - ✅ **Multi-node cluster expansion** - k3s2 worker node onboarding with automated storage integration (GitOps configuration ready, cloud-init enhanced, pre-onboarding validation scripts completed, monitoring integration completed, comprehensive onboarding orchestration completed, ready for deployment)
  - 🚧 **GitOps Update Management** - Comprehensive update management system with automated detection, safe patching, validation testing, and rollback capabilities (specification complete, core detection infrastructure in development with enhanced reliability patterns)
  - 🚧 **Resource lifecycle management** - Blue-green deployment patterns for immutable resources (Tasks 5.1-5.4 planned)
  - 🚧 **Change impact analysis** - Dependency mapping and cascade effect analysis (Tasks 6.2-6.4 planned, 6.1 complete)
  - 🚧 **Staged deployment validation** - Multi-stage rollout with validation gates (Tasks 7.1-7.4 planned)
  - 🚧 **Resource state consistency** - Atomic operations and conflict resolution (Tasks 8.1-8.4 planned)
  - 🚧 **Comprehensive testing framework** - Chaos engineering and automated recovery testing (Tasks 9.1-9.4 planned)
  - 🔄 **Code quality improvements** - Enhanced validation scripts, documentation accuracy, and operational excellence

See [GitOps Resilience Patterns Spec](.kiro/specs/gitops-resilience-patterns/), [k3s2 Node Onboarding Spec](.kiro/specs/k3s1-node-onboarding/), and [GitOps Update Management Spec](.kiro/specs/gitops-update-management/) for detailed implementation roadmaps and [Validation Scripts](scripts/README.md) for current tooling.

## 🚀 Getting Started

### Prerequisites

- [k3s](https://k3s.io/) installed on all nodes
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (v1.24+)
- [flux](https://fluxcd.io/docs/installation/) CLI (v2.0.0+)
- [Git](https://git-scm.com/)
- [Helm](https://helm.sh/) (v3.0.0+)
- **MCP Tools** (recommended): Flux and Kubernetes MCP servers for enhanced cluster interaction with comprehensive built-in guidance

#### macOS Development Environment
For macOS users, install prerequisites using Homebrew:
```bash
# Install core tools
brew install kubectl kustomize helm git jq curl

# Install Flux CLI
brew install fluxcd/tap/flux

# Install YAML validation tools
brew install yamllint
```

See [macOS Environment Guide](.kiro/steering/macos-environment.md) for comprehensive macOS-specific setup and troubleshooting.

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

4. **Run Health Checks**
   ```bash
   # Quick system validation
   ./tests/validation/test-tasks-3.1-3.2.sh
   
   # Comprehensive health check
   ./tests/validation/post-outage-health-check.sh
   ```

## 🧪 Testing & Validation

This project includes comprehensive testing tools for validating the GitOps resilience patterns, specifically Tasks 3.1 (Error Pattern Detection) and 3.2 (Resource Recreation Automation):

### Quick Health Checks
```bash
# After system disruptions (power outages, restarts)
./tests/validation/post-outage-health-check.sh

# Verify error pattern detection system (Tasks 3.1 & 3.2)
./tests/validation/test-tasks-3.1-3.2.sh

# Pre-onboarding validation (comprehensive cluster readiness check)
./scripts/k3s2-pre-onboarding-validation.sh --report

# Test k3s2 node onboarding readiness and status
./tests/validation/test-k3s2-node-onboarding.sh

# Full system validation with simulation
./tests/validation/test-pattern-simulation.sh

# Test error pattern detection runtime
./tests/validation/test-error-pattern-runtime.sh
```

### Test Categories
- **Configuration Validation**: YAML syntax, Kustomization builds, recovery patterns setup
- **Runtime Validation**: Active monitoring, pod health, event processing, pattern detection
- **Integration Testing**: End-to-end testing with real resource creation and error simulation
- **Health Assessment**: Comprehensive system health after disruptions
- **Recovery Testing**: Resource recreation automation and RBAC validation

### Test Results Interpretation
- ✅ **Success**: Error pattern detector running, patterns configured, RBAC functional
- ⚠️ **Warning**: Non-critical issues detected, system operational with minor problems
- ❌ **Failure**: Critical systems not operational, requires immediate attention

See [Testing Suite Documentation](tests/README.md) and [Error Pattern Detection Testing Guide](docs/testing/error-pattern-detection-testing.md) for detailed usage and troubleshooting.

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
│   ├── cloud-init/        # Node bootstrap configurations
│   ├── k3s1-node-config/  # k3s1 (control plane) node configuration
│   ├── k3s2-node-config/  # k3s2 (worker) node configuration
│   ├── storage/           # Storage discovery and configuration
│   ├── monitoring/        # Monitoring stack
│   └── networking/        # Ingress and network policies
├── docs/                  # Documentation
│   ├── setup/             # Component setup guides
│   ├── guides/            # User guides and quick references
│   ├── operations/        # Maintenance and troubleshooting
│   ├── troubleshooting/   # Recovery procedures
│   └── security/          # Security configuration
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

### Development Guidelines

When developing shell scripts, especially validation scripts, follow the comprehensive best practices in:
- **[Script Development Best Practices](.kiro/steering/08-script-development-best-practices.md)** - **CRITICAL**: Comprehensive best practices automatically applied when working with shell scripts
- **[Validation Script Development](docs/troubleshooting/validation-script-development.md)** - Detailed lessons learned and troubleshooting patterns
- **[Scripts README](scripts/README.md)** - Development checklist and usage examples
- **[Git Hook Setup](docs/pre-commit-setup.md)** - Pre-commit validation and post-commit monitoring configuration

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

### GitOps Operations
- View Flux resources: `kubectl get kustomizations,kustomizations -A`
- Check Flux logs: `kubectl logs -n flux-system -l app=source-controller`
- Get cluster info: `kubectl cluster-info`
- Validate kustomizations: `./scripts/validate-kustomizations.sh`
- Check for immutable field conflicts: `./scripts/check-immutable-fields.sh`
- Monitor Flux reconciliation: Automatic post-commit monitoring provides real-time deployment feedback

### MCP-Enhanced Operations (Recommended)
- Check Flux installation: Use MCP Flux tools for comprehensive status with automatic guidance
- Trigger reconciliation: Use MCP Flux reconciliation tools with systematic workflows
- Get resource details: Use MCP Kubernetes tools for enhanced resource inspection with best practices
- Search Flux docs: Use MCP Flux documentation search for troubleshooting with integrated help
- **Always-Available Guidance**: Comprehensive Kubernetes operations guidance automatically included in all interactions

### Monitoring Operations
- **Quick Access**: `kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &` then visit http://localhost:3000
- **System Cleanup**: `./scripts/cleanup-stuck-monitoring.sh` - Comprehensive monitoring cleanup with interactive confirmation
- **Health Check**: `./scripts/monitoring-health-check.sh` - Complete system health validation
- **Remote Access**: Use k3s-remote context with local port-forward for seamless remote monitoring access
- **Emergency Access**: `ssh k3s1-tailscale` for direct node access when MCP tools fail

**📖 See [Monitoring User Guide](docs/guides/monitoring-user-guide.md) for complete usage instructions**

### Recovery System Operations
- Deploy error pattern detection: `kubectl apply -k infrastructure/recovery/`
- Check recovery system status: `kubectl get pods -n flux-recovery -l app=error-pattern-detector`
- View detected error patterns: `kubectl logs -n flux-recovery deployment/error-pattern-detector`
- Monitor recovery system health: `kubectl describe deployment -n flux-recovery error-pattern-detector`
- Test error pattern detection: `./tests/validation/test-tasks-3.1-3.2.sh`
- Run comprehensive validation: `./tests/validation/test-pattern-simulation.sh`
