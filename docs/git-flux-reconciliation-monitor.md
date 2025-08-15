# Git-Flux Reconciliation Monitor

🚧 **Status**: In Development - Task 1 (Kiro agent hook configuration) in progress - See [Requirements Specification](../.kiro/specs/git-flux-reconciliation-monitor/requirements.md)

## Overview

The Git-Flux Reconciliation Monitor is an intelligent git hook system that automatically monitors Flux reconciliation after commits are pushed to the repository. It provides real-time feedback on GitOps deployment status, showing which resources are being reconciled, their current state, and any failures that occur during the process.

## Features

### Real-time Monitoring
- **Automatic Triggering**: Monitors Flux reconciliation after git push operations
- **Live Status Updates**: Real-time display of reconciliation progress in the terminal
- **Resource Tracking**: Shows which Kustomizations and HelmReleases are being processed
- **Dependency Visualization**: Displays reconciliation order and dependency relationships

### Error Detection and Reporting
- **Detailed Error Information**: Comprehensive error messages from Flux controllers
- **Validation Failure Analysis**: Identifies which resources failed validation and why
- **Dependency Issue Detection**: Shows which dependencies are blocking reconciliation
- **Timeout Monitoring**: Indicates resources that are taking too long to reconcile

### MCP Tool Integration
- **Enhanced Monitoring**: Uses MCP Flux tools for comprehensive status queries
- **Integrated Troubleshooting**: Seamless transition from monitoring to interactive debugging
- **Documentation Lookup**: Automatic contextual help for common reconciliation issues
- **Consistent Interface**: Maintains consistency with other Kiro tools and workflows

## Architecture

### Hook Integration
The monitor integrates with Git's post-commit and post-receive hooks to:
1. Detect when changes are pushed to the repository
2. Identify affected Flux resources based on changed files
3. Monitor reconciliation status using MCP Flux tools
4. Provide real-time feedback to the developer

### MCP Tool Usage
The monitor leverages several MCP tools:
- `mcp_flux_get_flux_instance` - Verify Flux system availability
- `mcp_flux_get_kubernetes_resources` - Query resource status and events
- `mcp_flux_reconcile_flux_kustomization` - Trigger manual reconciliation if needed
- `mcp_flux_search_flux_docs` - Provide contextual help for errors

### Configuration
The monitor supports configuration via a repository-based config file:
```yaml
# .flux-monitor.yaml
timeout: 300s
verbosity: info
monitor:
  kustomizations: true
  helmreleases: true
  sources: true
output:
  format: structured
  colors: true
```

## Usage

### Automatic Operation
Once installed, the monitor runs automatically after git push operations:

```bash
git add .
git commit -m "update application configuration"
git push origin main

# Monitor automatically starts and shows:
# ✓ Flux system healthy
# → Monitoring reconciliation for 3 resources...
# ✓ infrastructure-core: Ready (2s)
# → example-app-dev: Reconciling...
# ✓ example-app-dev: Ready (15s)
# ✅ All resources reconciled successfully
```

### Error Scenarios
When reconciliation fails, the monitor provides detailed diagnostics:

```bash
git push origin main

# Monitor shows detailed error information:
# ✓ Flux system healthy
# → Monitoring reconciliation for 2 resources...
# ✗ example-app-dev: Failed
#   Error: validation failed
#   Resource: Deployment/example-app
#   Issue: spec.selector is immutable
#   
# 💡 Suggestion: Use 'mcp_flux_search_flux_docs --query="immutable field"' for help
# 🔧 Next steps:
#   1. Review the deployment selector configuration
#   2. Consider using blue-green deployment strategy
#   3. Check pre-commit validation setup
```

### Manual Control
The monitor provides options for manual control:
- **Cancel monitoring**: Ctrl+C to stop monitoring session
- **Extend timeout**: Configure longer timeouts for complex deployments
- **Verbose output**: Enable detailed logging for troubleshooting

## Configuration

### Repository Configuration
Create `.flux-monitor.yaml` in your repository root:

```yaml
# Monitoring behavior
timeout: 300s              # Maximum time to wait for reconciliation
verbosity: info            # Log level: debug, info, warn, error
parallel_monitoring: true  # Monitor multiple resources simultaneously

# Resource types to monitor
monitor:
  kustomizations: true     # Monitor Kustomization resources
  helmreleases: true       # Monitor HelmRelease resources
  sources: true           # Monitor source resources (GitRepository, etc.)

# Output formatting
output:
  format: structured      # Output format: structured, simple, json
  colors: true           # Enable colored output
  timestamps: false      # Include timestamps in output
  
# Error handling
error_handling:
  retry_attempts: 3      # Number of retry attempts for transient failures
  retry_delay: 5s        # Delay between retry attempts
  fail_fast: false       # Stop monitoring on first failure
```

### Global Configuration
Configure MCP tools in `.kiro/settings/mcp.json`:

```json
{
  "mcpServers": {
    "flux": {
      "command": "uvx",
      "args": ["flux-mcp-server@latest"],
      "autoApprove": [
        "mcp_flux_get_flux_instance",
        "mcp_flux_get_kubernetes_resources",
        "mcp_flux_search_flux_docs"
      ]
    }
  }
}
```

## Installation

### Prerequisites
- Git repository with Flux CD configured
- MCP Flux tools installed and configured
- Kubernetes cluster access
- Flux controllers running and healthy

### Setup Process
1. **Install the hook** (when available):
   ```bash
   # Installation script will be provided
   ./scripts/setup-git-flux-monitor.sh
   ```

2. **Configure monitoring**:
   ```bash
   # Create repository configuration
   cp .flux-monitor.yaml.example .flux-monitor.yaml
   # Edit configuration as needed
   ```

3. **Test the setup**:
   ```bash
   # Test with a simple change
   echo "# test" >> README.md
   git add README.md
   git commit -m "test: verify git-flux monitor"
   git push origin main
   ```

## Integration with Existing Workflows

### Pre-commit Validation
The monitor complements existing pre-commit validation:
- **Pre-commit**: Validates syntax, builds, and immutable fields
- **Post-commit**: Monitors actual deployment and reconciliation
- **Combined**: Complete GitOps safety and visibility

### MCP Tool Ecosystem
The monitor integrates seamlessly with other MCP tools:
- **Monitoring**: Automatic transition to interactive troubleshooting
- **Documentation**: Contextual help and guidance
- **Operations**: Consistent interface and behavior

### CI/CD Integration
The monitor can be integrated with CI/CD pipelines:
- **Local Development**: Real-time feedback during development
- **CI/CD Pipelines**: Automated monitoring in deployment pipelines
- **Remote Monitoring**: Support for remote development workflows

## Troubleshooting

### Common Issues

#### Monitor Not Starting
```bash
# Check git hook installation
ls -la .git/hooks/post-commit .git/hooks/post-receive

# Verify MCP tool availability
mcp_flux_get_flux_instance

# Check repository configuration
cat .flux-monitor.yaml
```

#### Timeout Issues
```bash
# Increase timeout in configuration
timeout: 600s  # 10 minutes

# Check resource status manually
mcp_flux_get_kubernetes_resources --apiVersion=kustomize.toolkit.fluxcd.io/v1 --kind=Kustomization
```

#### MCP Tool Failures
```bash
# Verify MCP server status
# Check .kiro/settings/mcp.json configuration

# Fall back to traditional tools if needed
flux get kustomizations -A
kubectl get kustomizations -A
```

### Debug Mode
Enable debug logging for detailed troubleshooting:

```yaml
# .flux-monitor.yaml
verbosity: debug
output:
  timestamps: true
```

## Development Status

### Current Implementation
🚧 **In Development** - Currently working on Kiro agent hook configuration (Task 1). This involves:

- Creating JSON configuration file for the Flux reconciliation monitor hook
- Configuring trigger to activate on git push events or file changes in GitOps directories  
- Defining agent prompt that uses MCP Flux tools to monitor reconciliation status
- Testing hook configuration and ensuring integration with Kiro's hook system

**Progress**: Task 1 is currently in progress after initial completion, indicating refinements or issues are being addressed. The Kiro agent hook configuration file exists at `.kiro/hooks/flux-reconciliation-monitor.kiro.hook` but may need adjustments for proper integration.

See [Requirements Document](../.kiro/specs/git-flux-reconciliation-monitor/requirements.md) and [Implementation Tasks](../.kiro/specs/git-flux-reconciliation-monitor/tasks.md) for detailed specifications and current progress.

### Planned Features
- **Multi-cluster Support**: Monitor reconciliation across multiple clusters
- **Notification Integration**: Send alerts to Slack, Teams, or email
- **Dashboard Integration**: Web-based monitoring dashboard
- **Metrics Collection**: Prometheus metrics for reconciliation monitoring
- **Advanced Filtering**: Custom resource selection and filtering

### Contributing
The git-flux-reconciliation-monitor is being developed as part of the GitOps Resilience Patterns initiative. See the [specification](.kiro/specs/git-flux-reconciliation-monitor/) for implementation details and contribution guidelines.

## See Also

- [Pre-commit Setup](pre-commit-setup.md) - Git hook configuration and validation
- [MCP Tools Guide](mcp-tools-guide.md) - MCP tool usage and integration
- [Flux Recovery Guide](troubleshooting/flux-recovery-guide.md) - Manual troubleshooting procedures
- [GitOps Resilience Patterns](gitops-resilience-patterns.md) - Overall resilience system architecture
- [Application Management](application-management.md) - GitOps workflow and best practices