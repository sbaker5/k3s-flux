# Requirements Document

## Introduction

This spec addresses the current Longhorn infrastructure issues in the k3s-flux GitOps setup, including namespace conflicts, missing Node CRs, and blocked monitoring deployment. The goal is to systematically resolve these issues while establishing robust, maintainable infrastructure patterns that follow GitOps best practices.

## Requirements

### Requirement 1: Resolve Longhorn Kustomization Conflicts

**User Story:** As a platform engineer, I want the Longhorn infrastructure kustomization to build and apply successfully, so that all Longhorn components are properly managed by Flux.

#### Acceptance Criteria

1. WHEN the infrastructure kustomization is reconciled THEN it SHALL complete without namespace conflicts
2. WHEN multiple kustomizations reference the same namespace THEN they SHALL NOT create duplicate namespace resources
3. WHEN the longhorn-crd.yaml is processed THEN it SHALL NOT conflict with other namespace definitions
4. WHEN the infrastructure kustomization builds THEN it SHALL produce valid Kubernetes manifests

### Requirement 2: Establish Longhorn Node Management

**User Story:** As a platform engineer, I want Longhorn nodes to be declaratively managed through GitOps, so that disk configuration is consistent and reproducible.

#### Acceptance Criteria

1. WHEN a k3s node exists THEN a corresponding Longhorn Node CR SHALL be created automatically
2. WHEN the k3s1-node-config is applied THEN the Longhorn Node CR SHALL appear in the cluster
3. WHEN disk paths are configured THEN they SHALL be validated and properly mounted
4. WHEN Node CRs are created THEN disk UUIDs SHALL be automatically assigned by Longhorn

### Requirement 3: Enable Infrastructure Dependencies

**User Story:** As a platform engineer, I want monitoring and other dependent services to deploy only after infrastructure is healthy, so that deployment order is predictable and reliable.

#### Acceptance Criteria

1. WHEN infrastructure kustomization is healthy THEN dependent kustomizations SHALL be allowed to proceed
2. WHEN Longhorn is not ready THEN monitoring deployment SHALL wait appropriately
3. WHEN infrastructure components fail THEN clear error messages SHALL be provided
4. WHEN dependencies are resolved THEN automatic reconciliation SHALL resume

### Requirement 4: Validate Disk Configuration

**User Story:** As a platform engineer, I want to ensure that Longhorn disk mounts and configuration are correct before Node CRs are applied, so that storage provisioning works reliably.

#### Acceptance Criteria

1. WHEN disk paths are specified THEN they SHALL exist on the target node
2. WHEN longhorn-disk.cfg files are required THEN they SHALL contain valid JSON
3. WHEN disks are mounted THEN they SHALL have appropriate permissions
4. WHEN Node CRs reference disks THEN the disks SHALL be available for scheduling

### Requirement 5: Establish Monitoring Recovery

**User Story:** As a platform engineer, I want monitoring to deploy successfully after infrastructure issues are resolved, so that I have visibility into cluster health.

#### Acceptance Criteria

1. WHEN infrastructure kustomization is healthy THEN monitoring kustomization SHALL proceed
2. WHEN PVCs are required THEN Longhorn SHALL provision volumes successfully
3. WHEN monitoring components deploy THEN they SHALL reach ready state
4. WHEN storage issues are resolved THEN monitoring SHALL automatically recover

### Requirement 6: Implement GitOps Best Practices

**User Story:** As a platform engineer, I want infrastructure configurations to follow GitOps principles, so that changes are traceable, reversible, and consistent.

#### Acceptance Criteria

1. WHEN infrastructure changes are made THEN they SHALL be committed to Git first
2. WHEN conflicts occur THEN they SHALL be resolved through declarative configuration
3. WHEN manual interventions are needed THEN they SHALL be documented and automated
4. WHEN recovery procedures are established THEN they SHALL be repeatable and tested