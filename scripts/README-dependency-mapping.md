# Enhanced Resource Dependency Mapping Tools

This directory contains enhanced dependency analysis tools specifically designed for GitOps resilience patterns.

## Requirements Addressed

- **8.1**: Impact analysis SHALL identify affected resources
- **8.3**: Cascade effects SHALL be analyzed

## Tools Overview

### 1. Enhanced Dependency Mapper (`enhanced-dependency-mapper.py`)
Advanced Python tool with GitOps-specific pattern detection, risk assessment, and enhanced visualization.

### 2. Enhanced Dependency Analysis Script (`enhanced-dependency-analysis.sh`)
User-friendly wrapper script providing multiple analysis commands with comprehensive output.

### 3. Test Suite (`test-enhanced-dependency-mapper.sh`)
Comprehensive test suite validating all enhanced dependency mapping functionality.

## Installation (macOS)

Following the project's macOS environment guidelines, install dependencies using Homebrew:

```bash
# Core dependencies
brew install python3
brew install kubectl

# Enhanced visualization (optional but recommended)
brew install python-matplotlib

# YAML and NetworkX may be included with brew python3
# If not available, basic functionality will still work
```

## Quick Start

### Full Analysis
```bash
# Complete analysis of entire cluster
./scripts/enhanced-dependency-analysis.sh full-analysis

# Analyze specific namespaces
./scripts/enhanced-dependency-analysis.sh full-analysis --namespaces flux-system,monitoring
```

### Manifest Analysis
```bash
# Analyze infrastructure manifests
./scripts/enhanced-dependency-analysis.sh manifest-analysis --manifests infrastructure/,apps/
```

### Impact Analysis
```bash
# Analyze impact of changing a specific resource
./scripts/enhanced-dependency-analysis.sh impact-analysis --resource Deployment/nginx-ingress-controller/nginx-ingress
```

### Risk Assessment
```bash
# Generate comprehensive risk assessment
./scripts/enhanced-dependency-analysis.sh risk-assessment --cluster
```

### Visualization
```bash
# Create enhanced dependency graph with risk coloring
./scripts/enhanced-dependency-analysis.sh visualize --namespaces monitoring --filter prometheus
```

## Features

### GitOps-Specific Analysis
- **Flux Dependencies**: Detects Kustomization `dependsOn`, HelmRelease chart sources, and GitRepository references
- **Source Relationships**: Identifies `sources_from`, `chart_from`, and `values_from` relationships
- **Infrastructure Patterns**: Recognizes critical infrastructure components and their dependencies

### Risk Assessment
- **Risk Levels**: Categorizes resources as critical, high, medium, or low risk
- **Single Points of Failure**: Identifies critical resources with many dependents
- **Circular Dependencies**: Detects and warns about circular dependency chains
- **Recovery Time Estimation**: Provides estimated recovery times for different impact levels

### Enhanced Visualization
- **Risk-Based Coloring**: Nodes colored by risk level (red=critical, orange=high, yellow=medium, green=low)
- **Dependency Count Sizing**: Node size reflects number of dependencies
- **Namespace Clustering**: Groups resources by namespace for better organization
- **Relationship Differentiation**: Different edge styles for different relationship types

### Export and Integration
- **JSON Export**: Structured data export for integration with other tools
- **Comprehensive Reports**: Markdown reports with executive summaries and recommendations
- **Multiple Output Formats**: Text, PNG, and JSON outputs available

## Output Files

### Reports
- `enhanced-dependency-report.md`: Comprehensive analysis with risk assessment
- `impact-report.md`: Specific resource impact analysis
- `risk-assessment-report.md`: Risk-focused analysis with recommendations

### Visualizations
- `enhanced-dependency-graph.png`: Risk-colored dependency graph
- `enhanced-dependency-graph.txt`: Text-based visualization (fallback)

### Data Export
- `dependency-data.json`: Structured data for integration with other tools

## Testing

Run the comprehensive test suite:

```bash
./scripts/test-enhanced-dependency-mapper.sh
```

The test suite validates:
- GitOps-specific dependency detection
- Risk assessment accuracy
- Enhanced visualization generation
- JSON export functionality
- Full analysis workflow

## Architecture

### Enhanced Features Over Basic Tools
1. **GitOps Pattern Detection**: Recognizes Flux-specific resource relationships
2. **Risk Assessment Engine**: Evaluates dependency risks and provides recommendations
3. **Advanced Visualization**: Risk-based coloring and namespace clustering
4. **Recovery Planning**: Estimates recovery times and identifies critical paths
5. **Integration Ready**: JSON export for use with other GitOps tools

### Fallback Behavior
The tools gracefully degrade when optional dependencies are missing:
- **Without PyYAML**: Basic JSON parsing for simple YAML files
- **Without NetworkX**: Simple graph implementation for basic analysis
- **Without Matplotlib**: Text-based visualization as fallback

## Integration with GitOps Workflows

These tools are designed to integrate with GitOps resilience patterns:

1. **Pre-deployment Analysis**: Assess impact before applying changes
2. **Risk Monitoring**: Regular risk assessment of infrastructure
3. **Recovery Planning**: Understand cascade effects for incident response
4. **Change Impact**: Evaluate proposed changes before implementation

## Troubleshooting

### Common Issues

1. **No resources found**: Ensure YAML files are valid and contain Kubernetes resources
2. **Visualization not generated**: Install `brew install python-matplotlib`
3. **Limited functionality**: Install full Python dependencies via brew
4. **Permission errors**: Ensure kubectl access to cluster

### Debug Mode
Add `--verbose` to any command for detailed logging:

```bash
./scripts/enhanced-dependency-analysis.sh full-analysis --verbose
```

## Contributing

When modifying these tools:
1. Follow the script development best practices in the steering rules
2. Use brew for all macOS package references
3. Maintain fallback behavior for missing dependencies
4. Update tests when adding new features
5. Document new functionality in this README