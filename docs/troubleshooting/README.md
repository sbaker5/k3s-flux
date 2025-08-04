# Troubleshooting Documentation

This directory contains comprehensive troubleshooting guides and procedures for the k3s-flux GitOps cluster.

## Available Guides

### [Flux Recovery Guide](flux-recovery-guide.md)
Complete recovery procedures for Flux CD control plane failures, including:
- Quick recovery steps for common issues
- Systematic troubleshooting workflows
- Phase-by-phase recovery procedures
- k3s-specific considerations
- Common issues and solutions

### [Validation Script Development](validation-script-development.md)
Lessons learned and best practices for developing validation scripts, including:
- Common pitfalls and solutions
- Error handling strategies
- k3s architecture considerations
- Development workflow recommendations

## Advanced Troubleshooting

### MCP-Based Troubleshooting Workflows
For enhanced troubleshooting capabilities, specialized workflows are available through the development environment:

- **Flux Troubleshooting Workflows** (`.kiro/steering/04-flux-troubleshooting.md`): Systematic procedures for HelmRelease and Kustomization troubleshooting, multi-cluster comparisons, and resource analysis
- **MCP Tools Guide** (`../mcp-tools-guide.md`): Enhanced cluster interaction tools with integrated troubleshooting capabilities and always-available comprehensive guidance

### When to Use Each Approach

**Use Traditional CLI Methods When:**
- MCP tools are unavailable
- Working in CI/CD pipelines
- Emergency situations requiring direct cluster access
- Scripting and automation scenarios

**Use MCP-Based Workflows When:**
- Interactive troubleshooting and diagnosis
- Complex multi-resource analysis
- Documentation lookup during troubleshooting
- Systematic investigation of Flux issues

**Use Remote Access Methods When:**
- MCP tools and local access are unavailable
- Emergency cluster access is needed
- Direct node troubleshooting is required

## Emergency Procedures

### Quick Access Methods
1. **Local kubectl**: Standard cluster access via kubeconfig
2. **MCP Tools**: Enhanced troubleshooting via development environment
3. **Tailscale Remote Access**: Emergency access via VPN when other methods fail
4. **Emergency CLI**: Direct SSH access with automated troubleshooting scripts

### Escalation Path
1. Start with automated health checks (`./tests/validation/post-outage-health-check.sh`)
2. Use MCP-based troubleshooting workflows for systematic analysis
3. Fall back to traditional CLI methods if MCP tools are unavailable
4. Use remote access methods for emergency situations
5. Consult recovery guides for comprehensive restoration procedures

## Related Documentation

- [MCP Tools Guide](../mcp-tools-guide.md) - Enhanced troubleshooting capabilities
- [GitOps Resilience Patterns](../gitops-resilience-patterns.md) - Comprehensive resilience system
- [Script Development Best Practices](../../.kiro/steering/08-script-development-best-practices.md) - Critical development guidelines
- [Emergency CLI](../../scripts/emergency-cli.sh) - Emergency cluster access tools