# K3s Homelab GitOps Strategy with Flux

## Notes
- Using Windsurf for project management
- Implementing GitOps with Flux CD for declarative cluster management
- K3s as the lightweight Kubernetes distribution
- Monorepo structure for all configurations
- Security-first approach with SOPS for secrets management
- Automated image updates with Flux image automation
- Cluster nodes:
  - k3s1: 192.168.86.71 (primary, live)
  - k3s2: 192.168.86.72 (future node)

## Phase 1: Core Infrastructure Setup
- [x] Initialize Git repository and connect to GitHub
- [x] Set up k3s cluster
  - [x] Install k3s on k3s1 (192.168.86.71)
  - [x] Configure kubeconfig for remote access
  - [x] Verify cluster access
  - [ ] Prepare k3s2 (192.168.86.72) for future expansion
- [x] Bootstrap Flux CD
  - [x] Install Flux CLI
  - [x] Run pre-flight checks
  - [x] Execute bootstrap command
  - [x] Verify Flux installation
  - [x] Confirm flux-system Kustomization is healthy

## Phase 2: Repository Structure
- [x] Create base directory structure
  - [x] clusters/k3s-flux/flux-system/
  - [x] infrastructure/base/
  - [x] apps/_templates/base/
- [x] Set up initial Kustomize configurations
- [x] Create initial Flux Kustomization for infrastructure
- [x] Commit and push repository structure

## Phase 3: Infrastructure Components
- [x] Set up Ingress Controller (Nginx)
  - [x] Create Nginx Ingress Kustomization
  - [x] Configure HelmRelease with ServiceMonitor disabled
  - [x] Update HelmRelease to use NodePort (30080/30443)
  - [x] Verify Nginx Ingress installation
    - [x] Check Helm release status
    - [x] Verify pod deployment
    - [x] Check service creation (NodePort 30080/30443)
    - [x] Test basic HTTP access (404 response confirms Nginx is running)
  - [x] Deploy default backend for Nginx Ingress
  - [x] Configure default backend health checks
    - [x] Update deployment to use TCP probes
    - [x] Test health check functionality
    - [x] Document the configuration
  - [x] Set up basic routing rules
    - [x] Create example application deployment
    - [x] Create Ingress resource for the example application
    - [x] Test routing to the example application
  - [ ] (Future) Enable ServiceMonitor in Phase 6 with Prometheus

## Phase 4: Application Management (Detailed Implementation)

### 4.1. Define Application Base Configuration with Kustomize
- [x] Create base directory structure for example-app
  - [x] `apps/example-app/base/`
  - [x] Core Kubernetes manifests (deployment.yaml, service.yaml)
  - [x] Base kustomization.yaml
- [x] Configure common labels and annotations
- [x] Set up health checks and resource limits

### 4.2. Implement Environment-Specific Overlays
- [x] Create overlay directories:
  - [x] `apps/example-app/overlays/dev/`
  - [x] `apps/example-app/overlays/staging/`
  - [x] `apps/example-app/overlays/prod/`
- [x] Configure environment-specific settings:
  - [x] Replica counts
  - [x] Resource limits
  - [x] Environment variables
  - [x] Image tags

### 4.3. Configure Flux Kustomization CRDs
- [x] Create Flux Kustomization for dev environment
  - [x] `clusters/k3s-flux/apps-example-app-dev.yaml`
  - [x] Set interval: 1m
  - [x] Enable pruning
- [x] Create Flux Kustomization for staging environment
  - [x] `clusters/k3s-flux/apps-example-app-staging.yaml`
  - [x] Set interval: 5m
  - [x] Enable pruning
- [x] Create Flux Kustomization for production environment
  - [x] `clusters/k3s-flux/apps-example-app-prod.yaml`
  - [x] Set interval: 10m
  - [x] Enable pruning

### 4.4. Implement "Offline until Needed" Functionality
- [x] Configure scaling to zero for non-production environments
- [x] Document process for suspending/resuming reconciliation
- [x] Test environment suspension and resumption

### 4.5. Set Up Dependency Management with dependsOn
- [x] Identify and document application dependencies
- [x] Configure dependsOn in Kustomization CRDs
- [x] Test deployment order and dependencies

### 4.6. Enable Pruning for Clean Resource Cleanup
- [x] Enable pruning in all Kustomization CRDs
- [x] Test resource cleanup
- [x] Document pruning behavior

### 4.7. Namespace Management
- [x] Create dedicated namespaces for each environment
  - [x] example-app-dev
  - [x] example-app-staging
  - [x] example-app-prod
- [x] Configure namespace-specific resource quotas and limits

### 4.8. Documentation and Verification
- [x] Document the application deployment workflow
- [x] Create runbooks for common operations
- [x] Verify all environments are functioning correctly

### 4.9. Security Considerations
- [x] Implement network policies
- [x] Configure RBAC for each environment
- [x] Set up resource quotas and limits

### 4.10. Monitoring and Observability
- [x] Configure logging for application components
- [x] Set up basic metrics collection
- [x] Document monitoring approach

### 4.11. Testing Strategy
- [x] Unit testing for Kustomize overlays
- [x] Integration testing for environment-specific configurations
- [x] End-to-end testing of deployment workflow

### 4.12. Rollback Procedures
- [x] Document rollback procedures for each environment
- [x] Test rollback scenarios
- [x] Implement automated health checks

### 4.13. Performance Optimization
- [x] Optimize container resource requests/limits
- [x] Configure horizontal pod autoscaling for production
- [x] Implement pod disruption budgets

### 4.14. Disaster Recovery
- [x] Document recovery procedures
- [x] Test backup and restore processes
- [x] Implement automated backup solutions

### 4.15. Documentation
- [x] Update README with application deployment instructions
- [x] Document environment-specific configurations
- [x] Create troubleshooting guide

## Phase 5: Security & Secrets
- [ ] Implement SOPS for secrets management
  - [ ] Set up encryption keys
  - [ ] Configure Flux for decryption
  - [ ] Encrypt existing secrets
- [ ] Configure RBAC and network policies
- [ ] Set up workload identity for cloud services

## Phase 6: Automation & Monitoring
- [ ] Configure image automation
  - [ ] Set up image repositories
  - [ ] Define update policies
  - [ ] Enable automated PRs for updates
- [ ] Implement monitoring and alerting
  - [ ] Deploy Prometheus stack
  - [ ] Set up Grafana dashboards
  - [ ] Configure alerts

## Current Goal
Implement Monitoring and Observability

## Next Steps for Monitoring
1. Deploy Prometheus stack using Helm
   - Install Prometheus Operator
   - Configure persistent storage
   - Set up service monitors

2. Configure Grafana dashboards
   - Deploy Grafana
   - Import standard Kubernetes dashboards
   - Set up data sources

3. Set up alerting
   - Configure Alertmanager
   - Define alert rules
   - Set up notification channels

4. Monitor application metrics
   - Configure application metrics endpoints
   - Set up custom dashboards
   - Monitor resource usage and performance

5. Document monitoring setup
   - Create runbooks for common issues
   - Document alert response procedures
   - Train team on using monitoring tools
4. Set up dependency management between applications