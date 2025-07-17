
# Implementation Plan

- [x] 0. Validate Git repository access and configuration
  - Check current Git status and branch
  - Verify Git user configuration (name and email)
  - Test ability to commit and push changes to repository
  - Configure authentication token if needed
  - _Requirements: 6.1, 6.2_

- [x] 0.1 Create test commit to verify Git workflow
  - Make a small, safe change to test Git functionality
  - Commit the change with appropriate message
  - Push to remote repository and verify success
  - _Requirements: 6.1, 6.2_

- [x] 1. Resolve Longhorn namespace conflicts in kustomization
  - Remove duplicate namespace definitions from longhorn-crd.yaml
  - Update longhorn base kustomization to eliminate conflicts
  - Remove problematic namePrefix and namespace settings
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 2. Validate and fix longhorn base kustomization structure
  - Create clean namespace.yaml for longhorn-system
  - Update kustomization.yaml to reference only necessary resources
  - Test kustomization build locally before committing
  - _Requirements: 1.1, 1.4_

- [x] 3. Integrate k3s1 node configuration into infrastructure
  - Add k3s1-node-config to infrastructure kustomization resources
  - Verify disk mount exists at /mnt/longhorn/sdh1 on k3s1 node
  - Ensure longhorn-disk.cfg contains valid JSON ({}) 
  - _Requirements: 2.1, 2.2, 4.1, 4.2_

- [x] 4. Validate disk configuration on k3s1 node
  - SSH to k3s1 and verify /mnt/longhorn/sdh1 mount point exists
  - Check that longhorn-disk.cfg file contains '{}' (valid JSON)
  - Verify disk permissions are appropriate for Longhorn
  - _Requirements: 4.1, 4.2, 4.3_

- [x] 5. Apply infrastructure changes and test reconciliation
  - Commit namespace conflict fixes to Git repository
  - Force Flux reconciliation of infrastructure kustomization
  - Verify infrastructure kustomization reaches Ready state
  - _Requirements: 1.1, 3.1, 6.1, 6.2_

- [x] 6. Verify Longhorn Node CR creation and disk registration
  - Check that k3s1 Node CR appears in longhorn-system namespace
  - Verify disk UUIDs are assigned in Node CR status
  - Confirm disk shows as available in Longhorn UI
  - _Requirements: 2.2, 2.4, 4.4_

- [x] 7. Test Longhorn volume provisioning functionality
  - Create test PVC using Longhorn storage class
  - Verify PVC binds successfully and volume is created
  - Test pod attachment to verify CSI functionality
  - Clean up test resources after validation
  - _Requirements: 2.4, 4.4_

- [ ] 8. Resolve monitoring PVC termination issues
  - Investigate stuck PVCs in Terminating state in monitoring namespace
  - Remove finalizers or force delete stuck PVCs if necessary
  - Clear any orphaned volume attachments or pods blocking PVC deletion
  - _Requirements: 5.1, 5.2_

- [ ] 9. Enable monitoring kustomization recovery
  - Verify infrastructure kustomization is healthy and ready
  - Force reconciliation of monitoring kustomization after PVC cleanup
  - Monitor monitoring stack deployment progress
  - _Requirements: 3.1, 3.2, 5.1_

- [ ] 10. Validate monitoring stack deployment
  - Check that prometheus-stack HelmRelease completes successfully
  - Verify all monitoring pods reach Running state (currently stuck in Init)
  - Test new PVC creation for monitoring components
  - _Requirements: 5.2, 5.3_

- [ ] 11. Address Longhorn node health warnings
  - Install missing nfs-common package on k3s1 node
  - Address multipathd configuration issue if needed
  - Load required kernel modules (dm_crypt) if encryption is needed
  - _Requirements: 4.3, 4.4_

- [ ] 12. Perform end-to-end validation and documentation
  - Run comprehensive health checks on all components
  - Document the resolution steps and lessons learned
  - Update operational procedures with new patterns
  - Create monitoring alerts for similar issues
  - _Requirements: 3.4, 5.4, 6.3, 6.4_