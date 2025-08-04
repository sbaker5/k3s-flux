# Implementation Plan

- [x] 1. Prepare GitOps configuration for k3s2 activation
  - Update infrastructure/storage/kustomization.yaml to include k3s2-node-config
  - Verify k3s2 node configuration files are properly structured
  - Create Flux Kustomization for k3s2-specific resources
  - _Requirements: 3.1, 3.2, 3.3_

- [x] 2. Enhance cloud-init configuration for robust node onboarding
  - Update cloud-init configuration with improved error handling and logging
  - Add validation steps for successful k3s installation
  - Implement retry mechanisms for cluster join operations
  - Create health check endpoints for onboarding status monitoring
  - _Requirements: 1.1, 1.2, 1.4_

- [x] 3. Create pre-onboarding validation scripts
  - Implement cluster readiness validation script
  - Create network connectivity verification tools
  - Build storage system health check utilities
  - Develop monitoring system validation scripts
  - _Requirements: 7.1, 7.2_

- [x] 4. Implement k3s2 node monitoring integration
  - Update monitoring configurations to include k3s2 node metrics
  - Enhance Prometheus ServiceMonitor and PodMonitor for multi-node setup
  - Create k3s2-specific Grafana dashboard panels
  - Implement alerting rules for k3s2 node health monitoring
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 5. Enhance storage discovery and configuration automation
  - Improve disk discovery DaemonSet with better error handling
  - Add validation for storage prerequisites (iSCSI, kernel modules)
  - Implement storage health verification after disk preparation
  - Create automated Longhorn node registration validation
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 6. Create comprehensive onboarding validation suite
  - Implement real-time node join monitoring scripts
  - Create storage integration validation tools
  - Build network connectivity verification utilities
  - Develop GitOps reconciliation monitoring scripts
  - **REFACTOR**: Apply validation script development best practices from docs/troubleshooting/validation-script-development.md
    - ✅ Standardize error handling patterns across all validation scripts
    - ✅ Implement Strategy pattern for Kubernetes distribution detection
    - ✅ Add Template Method pattern for consistent validation script structure
    - ✅ Extract hardcoded timeouts and resource limits to configuration
    - ✅ Add proper input validation and security measures
    - ✅ Implement parallel test execution for independent validations
    - ✅ Establish consistent function naming conventions
    - ✅ Created comprehensive steering rule: `.kiro/steering/08-script-development-best-practices.md`
    - ✅ Updated documentation references to point to new steering rule
  - **ENHANCEMENT**: Added specialized Flux troubleshooting workflows
    - ✅ Created comprehensive Flux troubleshooting steering rule: `.kiro/steering/04-flux-troubleshooting.md`
    - ✅ Integrated systematic HelmRelease and Kustomization troubleshooting procedures
    - ✅ Added multi-cluster comparison workflows for configuration drift detection
    - ✅ Enhanced MCP tools documentation with advanced troubleshooting capabilities
    - ✅ Updated troubleshooting documentation structure with comprehensive guides
  - _Requirements: 7.3, 7.4_

- [ ] 7. Implement security and RBAC validation for multi-node setup
  - Verify SOPS secret decryption works on k3s2
  - Validate RBAC policies apply correctly to new node
  - Test Tailscale VPN connectivity to k3s2
  - Implement security posture validation scripts
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 8. Create post-onboarding health verification system
  - Implement comprehensive cluster health check script
  - Create storage redundancy validation tools
  - Build application deployment verification across nodes
  - Develop performance and load distribution testing utilities
  - _Requirements: 7.3, 2.4, 4.3_

- [ ] 9. Implement rollback and recovery procedures
  - Create node drain and removal scripts for emergency situations
  - Implement graceful node shutdown procedures
  - Build cluster state restoration utilities
  - Create documentation for manual recovery procedures
  - _Requirements: 7.2, 7.4_

- [x] 10. Create onboarding orchestration script
  - Implement master onboarding script that coordinates all steps
  - Add progress tracking and status reporting
  - Implement rollback capabilities for failed onboarding
  - Create comprehensive logging and troubleshooting output
  - _Requirements: 1.3, 7.1, 7.2, 7.4_