# MCP Tools Guide for GitOps Operations

## Overview

Model Context Protocol (MCP) tools provide enhanced interaction capabilities for Flux and Kubernetes operations. These tools offer more comprehensive diagnostics, better error handling, and integrated documentation lookup compared to standard CLI tools.

## Available MCP Tools

### Flux MCP Tools (`mcp_flux_*`)

**Cluster Status and Information:**
- `mcp_flux_get_flux_instance` - Get comprehensive Flux installation status and controller health
- `mcp_flux_get_kubeconfig_contexts` - List available Kubernetes contexts
- `mcp_flux_set_kubeconfig_context` - Switch between Kubernetes contexts

**Resource Management:**
- `mcp_flux_get_kubernetes_resources` - Get detailed information about Kubernetes and Flux resources
- `mcp_flux_get_kubernetes_api_versions` - List available API versions and resource kinds
- `mcp_flux_get_kubernetes_logs` - Retrieve pod logs with enhanced filtering
- `mcp_flux_get_kubernetes_metrics` - Get CPU and memory usage metrics

**Reconciliation Operations:**
- `mcp_flux_reconcile_flux_kustomization` - Trigger Kustomization reconciliation
- `mcp_flux_reconcile_flux_helmrelease` - Trigger HelmRelease reconciliation
- `mcp_flux_reconcile_flux_source` - Trigger source reconciliation (GitRepository, HelmRepository, etc.)
- `mcp_flux_reconcile_flux_resourceset` - Trigger ResourceSet reconciliation

**Lifecycle Management:**
- `mcp_flux_suspend_flux_reconciliation` - Suspend Flux resource reconciliation
- `mcp_flux_resume_flux_reconciliation` - Resume Flux resource reconciliation

**Resource Operations:**
- `mcp_flux_apply_kubernetes_manifest` - Apply Kubernetes YAML manifests
- `mcp_flux_delete_kubernetes_resource` - Delete specific Kubernetes resources

**Documentation and Troubleshooting:**
- `mcp_flux_search_flux_docs` - Search Flux documentation for troubleshooting and guidance

### Kubernetes MCP Tools (`mcp_kubernetes_*`)

**Resource Operations:**
- `mcp_kubernetes_kubectl_get` - Enhanced resource retrieval with filtering
- `mcp_kubernetes_kubectl_describe` - Detailed resource descriptions
- `mcp_kubernetes_kubectl_apply` - Apply manifests with validation
- `mcp_kubernetes_kubectl_delete` - Delete resources safely
- `mcp_kubernetes_kubectl_create` - Create resources with templates

**Monitoring and Logs:**
- `mcp_kubernetes_kubectl_logs` - Retrieve logs with advanced filtering
- `mcp_kubernetes_kubectl_scale` - Scale deployments and other resources
- `mcp_kubernetes_kubectl_rollout` - Manage rollouts and deployments

**Advanced Operations:**
- `mcp_kubernetes_kubectl_patch` - Patch resources with strategic merge
- `mcp_kubernetes_kubectl_context` - Manage Kubernetes contexts
- `mcp_kubernetes_explain_resource` - Get resource documentation
- `mcp_kubernetes_exec_in_pod` - Execute commands in pods
- `mcp_kubernetes_port_forward` - Set up port forwarding

**Helm Operations:**
- `mcp_kubernetes_install_helm_chart` - Install Helm charts
- `mcp_kubernetes_upgrade_helm_chart` - Upgrade Helm releases
- `mcp_kubernetes_uninstall_helm_chart` - Uninstall Helm releases

## Common Usage Patterns

### Checking Flux Health

**Traditional approach:**
```bash
flux check
kubectl get pods -n flux-system
flux get kustomizations -A
```

**MCP approach:**
```bash
# Get comprehensive Flux status
mcp_flux_get_flux_instance

# Get detailed resource information
mcp_flux_get_kubernetes_resources --apiVersion=v1 --kind=Pod --namespace=flux-system

# Check specific Kustomizations
mcp_flux_get_kubernetes_resources --apiVersion=kustomize.toolkit.fluxcd.io/v1 --kind=Kustomization
```

### Troubleshooting Reconciliation Issues

**Traditional approach:**
```bash
kubectl describe kustomization my-app -n flux-system
kubectl logs -n flux-system -l app=kustomize-controller
flux reconcile kustomization my-app -n flux-system
```

**MCP approach:**
```bash
# Get detailed resource status
mcp_flux_get_kubernetes_resources --apiVersion=kustomize.toolkit.fluxcd.io/v1 --kind=Kustomization --name=my-app --namespace=flux-system

# Get controller logs
mcp_flux_get_kubernetes_logs --pod_name=kustomize-controller-xxx --container_name=manager --pod_namespace=flux-system

# Trigger reconciliation
mcp_flux_reconcile_flux_kustomization --name=my-app --namespace=flux-system

# Search documentation for specific errors
mcp_flux_search_flux_docs --query="reconciliation failed"
```

### Managing HelmReleases

**Traditional approach:**
```bash
kubectl get helmreleases -A
helm list -A
flux reconcile helmrelease my-release -n my-namespace
```

**MCP approach:**
```bash
# Get HelmRelease status
mcp_flux_get_kubernetes_resources --apiVersion=helm.toolkit.fluxcd.io/v2beta1 --kind=HelmRelease

# Reconcile specific HelmRelease
mcp_flux_reconcile_flux_helmrelease --name=my-release --namespace=my-namespace --with_source=true

# Get Helm-specific logs
mcp_flux_get_kubernetes_logs --pod_name=helm-controller-xxx --container_name=manager --pod_namespace=flux-system
```

## Advantages of MCP Tools

### Enhanced Error Handling
- More detailed error messages with context
- Integrated troubleshooting suggestions
- Automatic retry logic for transient failures

### Integrated Documentation
- Built-in documentation search
- Context-aware help and examples
- Links to relevant Flux documentation

### Better Resource Management
- Comprehensive resource filtering and selection
- Enhanced output formatting
- Integrated validation and dry-run capabilities

### Improved Diagnostics
- Detailed resource status and health checks
- Enhanced log filtering and analysis
- Integrated metrics and monitoring data

## Configuration

MCP tools can be configured through the `.kiro/settings/mcp.json` file:

```json
{
  "mcpServers": {
    "flux": {
      "command": "uvx",
      "args": ["flux-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": [
        "mcp_flux_get_flux_instance",
        "mcp_flux_get_kubernetes_resources",
        "mcp_flux_search_flux_docs"
      ]
    },
    "kubernetes": {
      "command": "uvx", 
      "args": ["kubernetes-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": [
        "mcp_kubernetes_kubectl_get",
        "mcp_kubernetes_kubectl_describe",
        "mcp_kubernetes_kubectl_logs"
      ]
    }
  }
}
```

## Monitoring System Integration

### Monitoring with MCP Tools

MCP tools provide enhanced monitoring capabilities for the bulletproof monitoring architecture:

**Monitoring Health Checks:**
```bash
# Check monitoring system status
mcp_flux_get_kubernetes_resources --apiVersion=v1 --kind=Pod --namespace=monitoring

# Get monitoring metrics
mcp_flux_get_kubernetes_metrics --pod_namespace=monitoring

# Check Flux metrics collection
mcp_flux_get_kubernetes_resources --apiVersion=monitoring.coreos.com/v1 --kind=ServiceMonitor --namespace=monitoring
mcp_flux_get_kubernetes_resources --apiVersion=monitoring.coreos.com/v1 --kind=PodMonitor --namespace=monitoring
```

**Remote Access Integration:**
When MCP tools are unavailable, use Tailscale remote access:
```bash
# SSH to cluster via Tailscale
ssh k3s1-tailscale

# Use emergency CLI for monitoring
./scripts/emergency-cli.sh status
./scripts/monitoring-health-assessment.sh

# Manual port forwarding for remote monitoring access
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-kube-prom-prometheus 9090:9090 --address=0.0.0.0 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0 &
```

## Best Practices

### When to Use MCP Tools
- **Troubleshooting**: Use MCP tools for comprehensive diagnostics
- **Complex Operations**: Use MCP tools for multi-step operations
- **Documentation Lookup**: Use MCP search for quick reference
- **Resource Management**: Use MCP tools for enhanced filtering and selection
- **Monitoring Operations**: Use MCP tools for monitoring system health checks

### When to Use Traditional CLI
- **Simple Operations**: Basic kubectl commands for quick checks
- **Scripting**: Traditional CLI tools for automation scripts
- **CI/CD Pipelines**: Standard tools for pipeline integration
- **Emergency Access**: Use traditional CLI via Tailscale when MCP tools are unavailable

### When to Use Remote Access
- **MCP Tool Failures**: Use Tailscale remote access when MCP tools are unavailable
- **Emergency Situations**: Direct SSH access for critical troubleshooting
- **Monitoring Access**: Remote access to Prometheus and Grafana dashboards
- **Offline Troubleshooting**: When working remotely without MCP connectivity

### Integration Strategy
- Use MCP tools interactively for troubleshooting and exploration
- Use traditional CLI tools for scripting and automation
- Use Tailscale remote access as backup when MCP tools fail
- Combine all approaches based on the specific use case and availability
- Document MCP tool usage in runbooks and procedures
- Maintain remote access procedures for emergency situations

## Troubleshooting MCP Tools

### Common Issues
1. **MCP Server Not Available**: Check MCP configuration and server status
2. **Authentication Issues**: Verify Kubernetes context and credentials
3. **Resource Not Found**: Check resource names, namespaces, and API versions

### Verification Commands
```bash
# Check MCP server status (if available through IDE)
# Verify Kubernetes context
mcp_flux_get_kubeconfig_contexts

# Test basic connectivity
mcp_flux_get_flux_instance

# Verify resource access
mcp_flux_get_kubernetes_resources --apiVersion=v1 --kind=Namespace
```

## See Also

- [Flux CD Documentation](https://fluxcd.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Troubleshooting Guide](troubleshooting/flux-recovery-guide.md)
- [GitOps Resilience Patterns](gitops-resilience-patterns.md)