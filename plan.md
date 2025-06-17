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
  - [ ] Verify Nginx Ingress installation
    - [ ] Check Helm release status
    - [ ] Verify pod deployment
    - [ ] Check service creation (should be NodePort)
    - [ ] Test ingress functionality (ports 30080/30443)
  - [ ] Configure default backend
  - [ ] Set up basic routing rules
  - [ ] (Future) Enable ServiceMonitor in Phase 6 with Prometheus

## Phase 4: Application Management
- [ ] Set up application deployment workflow
  - [ ] Create base Kustomize structure for apps
  - [ ] Implement environment overlays
  - [ ] Configure Flux Kustomization CRDs
  - [ ] Set up dependency management with dependsOn
  - [ ] Enable pruning for clean resource cleanup

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
Verify Nginx Ingress Controller deployment with NodePort configuration

## Next Steps
1. Commit and push HelmRelease changes to Git
2. Monitor Flux reconciliation
3. Verify service is using NodePort (30080/30443)
4. Test HTTP/HTTPS access to Nginx Ingress
5. Document the NodePort configuration for future reference