---
inclusion: manual
---

# Validation and Troubleshooting Context

When working on validation scripts, troubleshooting, or diagnostic tools, always reference these key resources:

## Critical Development Resources

### Script Development Lessons Learned
**File**: `#[[file:docs/troubleshooting/validation-script-development.md]]`

This document contains critical lessons learned from developing the k3s2 pre-onboarding validation scripts, including:
- Bash scripting pitfalls with `set -euo pipefail`
- k3s architecture differences from standard Kubernetes
- Error handling patterns for validation scripts
- Resource cleanup and timeout strategies
- Module sourcing and path resolution issues

### Existing Validation Patterns
**Directory**: `tests/validation/`
**Key Files**:
- `test-k3s2-node-onboarding.sh` - Node onboarding validation patterns
- `post-outage-health-check.sh` - Health check patterns
- `run-validation-tests.sh` - Test orchestration patterns

### Script Development Best Practices
**File**: `scripts/README.md` (Development Best Practices section)

Contains quick reference for:
- Common scripting pitfalls and solutions
- Development checklist for new scripts
- k3s-specific validation considerations

## Architecture Context

### k3s Specific Considerations
- **Control plane**: Embedded components, not separate pods
- **etcd**: Embedded, no separate pods
- **CNI**: Flannel may not have traditional DaemonSet structure
- **Version detection**: Requires special handling for k3s versions

### Bulletproof Architecture Principles
- Core infrastructure (networking, ingress) must remain operational
- Storage infrastructure can fail without breaking core services
- Monitoring uses ephemeral storage by design
- Applications depend only on core services

### Technology Stack Context
**File**: `#[[file:.kiro/steering/01-tech.md]]`

Contains information about:
- Core technologies (k3s, Flux, Longhorn, NGINX Ingress)
- Common commands and troubleshooting approaches
- MCP tools for cluster interaction

## When to Use This Context

Include this steering rule (`#validation-troubleshooting`) when:
- Developing new validation scripts
- Creating health check utilities
- Building diagnostic tools
- Troubleshooting cluster issues
- Working on error detection systems
- Implementing monitoring or alerting validation

## Key Patterns to Follow

1. **Modular Design**: Break complex validation into focused modules
2. **Error Resilience**: Continue testing even when individual tests fail
3. **Resource Management**: Always clean up temporary resources
4. **Progress Indicators**: Provide feedback for long-running operations
5. **Comprehensive Reporting**: Generate structured output for analysis
6. **k3s Awareness**: Account for embedded component architecture

## Common Validation Categories

- **Cluster Health**: Control plane, API server, core components
- **Network Connectivity**: CNI, ingress, DNS, external connectivity
- **Storage Systems**: Longhorn health, disk discovery, capacity
- **Monitoring Infrastructure**: Prometheus, Grafana, ServiceMonitors
- **GitOps Operations**: Flux controllers, reconciliation status
- **Security Posture**: RBAC, secrets, network policies