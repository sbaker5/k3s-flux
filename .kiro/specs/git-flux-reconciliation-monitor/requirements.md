# Requirements Document

## Introduction

This feature implements an intelligent git push hook that automatically monitors Flux reconciliation after changes are pushed to the repository. The hook will provide real-time feedback on GitOps deployment status, showing which resources are being reconciled, their current state, and any failures that occur during the process. This enhances the developer experience by providing immediate visibility into the impact of their changes on the Kubernetes cluster.

## Requirements

### Requirement 1

**User Story:** As a developer, I want to automatically see the status of Flux reconciliation after I push changes, so that I can immediately know if my GitOps changes are being applied successfully.

#### Acceptance Criteria

1. WHEN a git push is made to the repository THEN the hook SHALL automatically trigger monitoring using `mcp_flux_get_flux_instance` to verify Flux availability
2. WHEN Flux begins reconciling resources THEN the hook SHALL use `mcp_flux_get_kubernetes_resources` to display real-time status updates in the terminal
3. WHEN reconciliation completes successfully THEN the hook SHALL use MCP Flux tools to display a success summary with affected resources
4. WHEN reconciliation fails THEN the hook SHALL use `mcp_flux_get_kubernetes_resources` to display detailed error information and affected resources
5. WHEN the monitoring times out THEN the hook SHALL display a timeout message with current status from MCP Flux queries

### Requirement 2

**User Story:** As a developer, I want to see which specific Flux resources are being reconciled, so that I can understand the scope and impact of my changes.

#### Acceptance Criteria

1. WHEN monitoring begins THEN the hook SHALL use `mcp_flux_get_kubernetes_resources` with Kustomization and HelmRelease kinds to identify all relevant resources
2. WHEN a Kustomization starts reconciling THEN the hook SHALL use MCP Flux tools to show its name, namespace, and current phase
3. WHEN a HelmRelease starts reconciling THEN the hook SHALL use MCP Flux tools to show its name, namespace, and current phase
4. WHEN resources have dependencies THEN the hook SHALL parse `dependsOn` fields from MCP queries to show the dependency chain and reconciliation order
5. WHEN multiple resources are reconciling THEN the hook SHALL use structured MCP responses to display them in a readable format

### Requirement 3

**User Story:** As a developer, I want detailed error information when reconciliation fails, so that I can quickly identify and fix issues.

#### Acceptance Criteria

1. WHEN a reconciliation fails THEN the hook SHALL use `mcp_flux_get_kubernetes_resources` to extract and display the specific error message from Flux resource status
2. WHEN there are validation errors THEN the hook SHALL parse MCP resource responses to show which resources failed validation and why
3. WHEN there are dependency failures THEN the hook SHALL use MCP queries to identify and show which dependencies are blocking reconciliation
4. WHEN there are timeout issues THEN the hook SHALL use MCP Flux tools to indicate which resources are taking too long based on their status conditions
5. WHEN there are multiple errors THEN the hook SHALL analyze MCP responses to prioritize and display them in order of severity

### Requirement 4

**User Story:** As a developer, I want the hook to be configurable, so that I can customize the monitoring behavior for different projects and workflows.

#### Acceptance Criteria

1. WHEN the hook is installed THEN it SHALL support configuration via a config file in the repository
2. WHEN configured THEN the hook SHALL allow setting custom timeout values for monitoring
3. WHEN configured THEN the hook SHALL allow enabling/disabling specific types of monitoring (Kustomizations, HelmReleases)
4. WHEN configured THEN the hook SHALL allow setting verbosity levels for output
5. WHEN no config is present THEN the hook SHALL use sensible defaults for all settings

### Requirement 5

**User Story:** As a developer, I want the hook to work seamlessly with my existing git workflow, so that it doesn't interfere with my development process.

#### Acceptance Criteria

1. WHEN the hook is triggered THEN it SHALL run asynchronously without blocking the git push process
2. WHEN the hook encounters errors THEN it SHALL not prevent the push from completing
3. WHEN the hook is running THEN it SHALL provide a way to cancel monitoring if needed
4. WHEN multiple pushes are made quickly THEN the hook SHALL handle overlapping monitoring sessions gracefully
5. WHEN the cluster is unreachable THEN the hook SHALL fail gracefully with an informative message

### Requirement 6

**User Story:** As a developer, I want the hook to integrate with Kiro's agent system using MCP Flux tools, so that I can leverage existing tooling and maintain consistency with the project's architecture.

#### Acceptance Criteria

1. WHEN monitoring Flux resources THEN the hook SHALL primarily use `mcp_flux_get_kubernetes_resources`, `mcp_flux_get_flux_instance`, and `mcp_flux_reconcile_flux_kustomization` for querying status
2. WHEN checking Kubernetes events THEN the hook SHALL use `mcp_kubernetes_kubectl_get` with resourceType "events" for additional context
3. WHEN triggering reconciliation THEN the hook SHALL use `mcp_flux_reconcile_flux_kustomization` and `mcp_flux_reconcile_flux_helmrelease` as needed
4. WHEN searching for documentation THEN the hook SHALL use `mcp_flux_search_flux_docs` to provide contextual help for errors
5. WHEN the hook needs to interact with the cluster THEN it SHALL use MCP tools exclusively rather than direct kubectl or flux CLI commands