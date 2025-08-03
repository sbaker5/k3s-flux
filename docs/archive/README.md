# Documentation Archive

This directory contains outdated or consolidated documentation that has been superseded by newer versions.

## Archived Files

### `plan.md` (Archived: 2025-01-28)
- **Reason**: Extremely detailed but outdated planning document with old status information
- **Replacement**: Content consolidated into `docs/implementation-plan.md` with current status
- **Size**: 1005+ lines, mostly historical information
- **Note**: Contains valuable historical context but was too large and outdated for active use

### `tailscale-port-forwarding-guide.md` (Archived: 2025-01-28)
- **Reason**: Content merged into main Tailscale setup guide
- **Replacement**: `docs/tailscale-remote-access-setup.md` now includes port forwarding information
- **Content**: Specific port forwarding method validated on January 25, 2025
- **Note**: Key discovery about local port forwarding through k3s-remote context preserved in main guide

### `DOCUMENTATION_UPDATE_SUMMARY.md` (Archived: 2025-08-02)
- **Reason**: Development artifact - documentation change log that served its purpose
- **Content**: Detailed summary of documentation updates made during monitoring system cleanup implementation
- **Note**: The actual documentation has been updated; this was just tracking the changes

### `TASK_7_DOCUMENTATION_UPDATE.md` (Archived: 2025-08-02)
- **Reason**: Development artifact - task-specific documentation update summary
- **Content**: Summary of documentation changes for Task 7 remote monitoring access validation
- **Note**: Implementation details are now in the actual documentation files

### `prometheus-crd.yaml` (Archived: 2025-08-02)
- **Reason**: Development artifact - leftover CRD file from development work
- **Content**: Prometheus CustomResourceDefinition that was extracted during development
- **Note**: Not used in the actual deployment; CRDs are managed by the Prometheus Operator

## Archive Policy

Documents are archived when:
- They become outdated and are replaced by newer versions
- Content is consolidated into other documents
- They contain primarily historical information
- They duplicate information available elsewhere

Archived documents are kept for:
- Historical reference
- Recovery of specific technical details if needed
- Understanding the evolution of the system

## Accessing Archived Content

If you need information from archived documents:
1. Check if the information is available in current documentation
2. Review the replacement documents listed above
3. If specific details are needed, archived files can be accessed directly
4. Consider updating current documentation if important information is missing