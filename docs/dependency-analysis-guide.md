# Resource Dependency Analysis Guide

This guide explains how to use the resource dependency mapping tools to analyze and visualize Kubernetes resource dependencies and understand change impact.

## Overview

The dependency analysis tools help you:

- **Identify Resource Dependencies**: Understand which resources depend on each other
- **Analyze Change Impact**: See what resources would be affected by changes
- **Visualize Relationships**: Create graphs showing resource dependencies
- **Assess Risk**: Understand the cascade effects of infrastructure changes

This addresses GitOps resilience requirements:
- **8.1**: Impact analysis SHALL identify affected resources
- **8.3**: Cascade effects SHALL be analyzed

## Tools Overview

### Core Components

1. **`dependency-analyzer.py`** - Python script that performs the actual analysis
2. **`analyze-dependencies.sh`** - Shell wrapper providing easy-to-use commands
3. **`dependency-analysis-config.yaml`** - Configuration for analysis behavior
4. **`test-dependency-analyzer.sh`** - Test suite to validate functionality

### Analysis Capabilities

- **Resource Discovery**: Load resources from cluster or manifest files
- **Dependency Detection**: Identify various types of resource relationships
- **Impact Analysis**: Determine cascade effects of changes
- **Visualization**: Generate dependency graphs
- **Risk Assessment**: Categorize impact levels

## Quick Start

### Prerequisites

```bash
# Install required Python packages
pip3 install pyyaml networkx matplotlib

# Ensure kubectl is available and configured
kubectl cluster-info
```

### Basic Usage

```bash
# Analyze entire cluster
./scripts/analyze-dependencies.sh cluster-analysis

# Analyze specific namespaces
./scripts/analyze-dependencies.sh cluster-analysis --namespaces flux-system,monitoring

# Analyze manifest files
./scripts/analyze-dependencies.sh manifest-analysis --manifests infrastructure/,apps/

# Analyze impact of changing a specific resource
./scripts/analyze-dependencies.sh impact-analysis --resource Deployment/nginx-ingress-controller/nginx-ingress

# Create visualization
./scripts/analyze-dependencies.sh visualize --namespaces monitoring --filter prometheus
```

## Detailed Usage

### Cluster Analysis

Analyze all resources currently deployed in your cluster:

```bash
# Full cluster analysis
./scripts/analyze-dependencies.sh cluster-analysis

# Limit to specific namespaces
./scripts/analyze-dependencies.sh cluster-analysis \
  --namespaces flux-system,monitoring,longhorn-system

# Custom output directory
./scripts/analyze-dependencies.sh cluster-analysis \
  --output-dir ./reports/cluster-analysis-$(date +%Y%m%d)
```

**Output:**
- `dependency-report.md` - Detailed analysis report
- `dependency-graph.png` - Visual dependency graph

### Manifest Analysis

Analyze resources from YAML manifest files (useful for pre-deployment analysis):

```bash
# Analyze infrastructure manifests
./scripts/analyze-dependencies.sh manifest-analysis \
  --manifests infrastructure/

# Analyze multiple directories
./scripts/analyze-dependencies.sh manifest-analysis \
  --manifests infrastructure/,apps/,clusters/

# Analyze specific files
./scripts/analyze-dependencies.sh manifest-analysis \
  --manifests infrastructure/monitoring/base/helm-release.yaml,apps/example-app/
```

**Use Cases:**
- Pre-deployment impact assessment
- CI/CD pipeline validation
- Infrastructure change review

### Impact Analysis

Analyze the impact of changes to a specific resource:

```bash
# Analyze impact of changing a deployment
./scripts/analyze-dependencies.sh impact-analysis \
  --resource Deployment/prometheus-core/monitoring

# Analyze with cluster data
./scripts/analyze-dependencies.sh impact-analysis \
  --resource Service/nginx-ingress-controller/nginx-ingress \
  --namespaces nginx-ingress

# Analyze with manifest data
./scripts/analyze-dependencies.sh impact-analysis \
  --resource HelmRelease/longhorn/longhorn-system \
  --manifests infrastructure/longhorn/
```

**Resource Format:**
- `Kind/Name` - For cluster-scoped resources
- `Kind/Name/Namespace` - For namespaced resources

**Output Shows:**
- **Direct Dependencies**: Resources this resource directly depends on
- **Indirect Dependencies**: Resources in the dependency chain
- **Direct Impact**: Resources that directly depend on this resource
- **Indirect Impact**: Resources that would be affected through cascade effects

### Visualization

Create visual dependency graphs:

```bash
# Visualize all dependencies
./scripts/analyze-dependencies.sh visualize

# Filter to specific resources
./scripts/analyze-dependencies.sh visualize \
  --filter monitoring \
  --namespaces monitoring

# Visualize from manifests
./scripts/analyze-dependencies.sh visualize \
  --manifests infrastructure/monitoring/ \
  --filter prometheus
```

**Visualization Features:**
- Color-coded nodes by resource type
- Different edge styles for relationship types
- Filtered views for complex environments
- High-resolution PNG output

## Understanding the Analysis

### Dependency Types

The analyzer identifies several types of relationships:

#### Direct References
- **ConfigMap/Secret References**: Environment variables, volume mounts
- **Service References**: Service names in specs
- **PVC References**: Storage volume claims
- **ServiceAccount References**: Pod service accounts

#### Selector Relationships
- **Service → Pod**: Services selecting pods via labels
- **Deployment → Pod**: Deployments managing pods
- **NetworkPolicy → Pod**: Policies applying to pods

#### Owner Relationships
- **Controller → Resource**: Resources created by controllers
- **Parent → Child**: Kubernetes owner references

#### Flux-Specific Relationships
- **Kustomization Dependencies**: `dependsOn` relationships
- **Source References**: GitRepository, HelmRepository references
- **HelmRelease → HelmChart**: Chart dependencies

### Risk Assessment

Resources are categorized by risk level:

#### High Risk Resources
- Deployments, StatefulSets, DaemonSets
- Services, Ingress controllers
- Storage classes, Persistent volumes

#### Medium Risk Resources
- ConfigMaps, Secrets
- RBAC resources (ServiceAccount, Role, RoleBinding)

#### Low Risk Resources
- Pods (managed by controllers)
- Jobs, CronJobs

### Impact Analysis Results

When analyzing impact, you'll see:

```
=== Impact Analysis for Deployment/nginx-ingress-controller/nginx-ingress ===

Direct Dependencies (2):
  - ConfigMap/nginx-ingress-controller-config (ns: nginx-ingress)
  - ServiceAccount/nginx-ingress-controller (ns: nginx-ingress)

Indirect Dependencies (1):
  - Secret/nginx-ingress-tls (ns: nginx-ingress)

Direct Impact (3):
  - Service/nginx-ingress-controller (ns: nginx-ingress)
  - Pod/nginx-ingress-controller-abc123 (ns: nginx-ingress)
  - Pod/nginx-ingress-controller-def456 (ns: nginx-ingress)

Indirect Impact (5):
  - Ingress/example-app-ingress (ns: example-app)
  - Ingress/monitoring-ingress (ns: monitoring)
  - Service/example-app-service (ns: example-app)
  - Pod/example-app-xyz789 (ns: example-app)
  - Pod/monitoring-grafana-uvw012 (ns: monitoring)

⚠️  Total resources that could be affected: 8
```

## Integration with GitOps Workflows

### Pre-Commit Analysis

Add dependency analysis to your pre-commit hooks:

```bash
# In .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: dependency-analysis
        name: Dependency Impact Analysis
        entry: ./scripts/analyze-dependencies.sh
        args: [manifest-analysis, --manifests, .]
        language: system
        pass_filenames: false
```

### CI/CD Integration

Use in GitHub Actions or similar:

```yaml
# .github/workflows/dependency-analysis.yml
name: Dependency Analysis
on:
  pull_request:
    paths:
      - 'infrastructure/**'
      - 'apps/**'

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'
      - name: Install dependencies
        run: pip install pyyaml networkx matplotlib
      - name: Run dependency analysis
        run: |
          ./scripts/analyze-dependencies.sh manifest-analysis \
            --manifests infrastructure/,apps/ \
            --output-dir ./analysis-results
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: dependency-analysis
          path: ./analysis-results/
```

### Change Review Process

1. **Before Making Changes**: Run impact analysis on affected resources
2. **Review Dependencies**: Understand what will be affected
3. **Plan Rollout**: Use dependency information to plan update order
4. **Validate Changes**: Re-run analysis after changes to confirm impact

## Advanced Usage

### Custom Configuration

Modify `scripts/dependency-analysis-config.yaml` to:

- Add custom reference patterns
- Define new relationship types
- Customize risk assessment rules
- Configure visualization settings

### Programmatic Usage

Use the Python script directly for custom analysis:

```python
from dependency_analyzer import DependencyAnalyzer

analyzer = DependencyAnalyzer()
analyzer.load_cluster_resources(['monitoring', 'flux-system'])
analyzer.analyze_dependencies()

# Get impact of changing a resource
resource_ref = ResourceRef(kind="Deployment", name="prometheus", namespace="monitoring")
impact = analyzer.find_impact_chain(resource_ref)
print(f"Resources affected: {len(impact['direct']) + len(impact['indirect'])}")
```

### Integration with Other Tools

The dependency analyzer can be integrated with:

- **Flux**: Analyze Kustomization and HelmRelease dependencies
- **ArgoCD**: Understand Application dependencies
- **Helm**: Analyze chart dependencies
- **Monitoring**: Alert on high-impact resource changes

## Troubleshooting

### Common Issues

#### Missing Python Packages
```bash
# Install required packages
pip3 install pyyaml networkx matplotlib

# On macOS with Homebrew
brew install python3
pip3 install pyyaml networkx matplotlib
```

#### Kubectl Access Issues
```bash
# Verify cluster access
kubectl cluster-info

# Check current context
kubectl config current-context

# List available contexts
kubectl config get-contexts
```

#### Large Graph Visualization
For clusters with many resources:
```bash
# Use filtering to reduce complexity
./scripts/analyze-dependencies.sh visualize \
  --filter "monitoring" \
  --namespaces monitoring

# Or analyze specific namespaces only
./scripts/analyze-dependencies.sh cluster-analysis \
  --namespaces flux-system,monitoring
```

### Validation

Test the tools with the included test suite:

```bash
# Run all tests
./scripts/test-dependency-analyzer.sh

# This will create test manifests and validate:
# - Manifest analysis works
# - Impact analysis works  
# - Visualization works
# - Expected dependencies are found
```

## Best Practices

### Regular Analysis
- Run dependency analysis before major infrastructure changes
- Include in CI/CD pipelines for automated validation
- Create baseline reports for comparison

### Change Management
- Use impact analysis to understand blast radius
- Plan changes in dependency order (dependencies first)
- Validate changes don't create circular dependencies

### Documentation
- Keep dependency graphs updated
- Document high-risk dependencies
- Share analysis results with team members

### Monitoring
- Monitor resources identified as high-impact
- Set up alerts for changes to critical dependencies
- Track dependency changes over time

## Examples

### Example 1: Monitoring Stack Analysis

```bash
# Analyze monitoring infrastructure
./scripts/analyze-dependencies.sh manifest-analysis \
  --manifests infrastructure/monitoring/ \
  --output-dir ./reports/monitoring-deps

# Check impact of upgrading Prometheus
./scripts/analyze-dependencies.sh impact-analysis \
  --resource HelmRelease/monitoring-core/monitoring \
  --manifests infrastructure/monitoring/
```

### Example 2: Application Deployment Analysis

```bash
# Before deploying new application
./scripts/analyze-dependencies.sh manifest-analysis \
  --manifests apps/new-app/ \
  --output-dir ./reports/new-app-deps

# Visualize application dependencies
./scripts/analyze-dependencies.sh visualize \
  --manifests apps/new-app/ \
  --filter new-app
```

### Example 3: Cluster-wide Impact Assessment

```bash
# Full cluster analysis
./scripts/analyze-dependencies.sh cluster-analysis \
  --output-dir ./reports/cluster-$(date +%Y%m%d)

# Check impact of infrastructure changes
./scripts/analyze-dependencies.sh impact-analysis \
  --resource Deployment/nginx-ingress-controller/nginx-ingress
```

This dependency analysis capability provides the foundation for understanding resource relationships and change impact, supporting safer GitOps operations and more resilient infrastructure management.