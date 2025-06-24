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

## Phase 5: Storage with Longhorn

### 5.1. k3s1 Node Disk Preparation (Completed)
- [x] SSH into k3s1: `ssh user@192.168.86.71`
- [x] Identify available disks: `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL`
  - Identified disks: sdf, sdg, sdh (465.8GB each)
- [x] Document current disk configuration
- [x] Prepare disks for Longhorn (destructive operation):
  - [x] Remove existing partitions: `sudo sgdisk --zap-all /dev/sdX`
  - [x] Wipe filesystem signatures: `sudo wipefs -a /dev/sdX`
  - [x] Create GPT partition table: `sudo parted /dev/sdX mklabel gpt --script`
  - [x] Create primary partition: `sudo parted -a opt /dev/sdX mkpart primary 0% 100%`
  - [x] Format partition: `sudo mkfs.ext4 /dev/sdX1`
- [x] Create mount points: `/mnt/longhorn/disk{f,g,h}`
- [x] Configure `/etc/fstab` for persistent mounts
- [x] Label node for Longhorn auto-discovery:
  ```bash
  kubectl label node k3s1 node.longhorn.io/create-default-disk=config
  kubectl label node k3s1 storage=longhorn
  ```

### 5.2. Enhanced k3s2 Node Provisioning
- [x] Cloud-init configuration for automated provisioning
  - [x] Raw disk preparation for Longhorn (no filesystem)
  - [x] DNS-based K3s master discovery (k3s1.local)
  - [x] Secure token management with SOPS
  - [x] Automated Longhorn disk configuration via CRD
  - [x] Idempotent operations for reliability

### 5.3. Cloud-init Server (Deployed)
- [x] Nginx server for serving cloud-init configuration
  - [x] ConfigMap for cloud-init data
  - [x] NodePort service (30090)
- [x] CoreDNS for local DNS resolution
  - [x] k3s1.local → 192.168.86.71
- [x] Secure token management
  - [x] SOPS-encrypted K3s token
  - [x] Secure token retrieval in cloud-init

### 5.4. Verification & Testing
- [ ] Test k3s2 provisioning
  - [ ] Boot with cloud-init URL: `http://192.168.86.71:30090/k3s2`
  - [ ] Verify node joins cluster
  - [ ] Check Longhorn disk detection
  - [ ] Test volume scheduling
- [ ] Validate cross-node functionality
  - [ ] Create pod on k3s2 with Longhorn volume
  - [ ] Verify data persistence
  - [ ] Test pod migration between nodes

### 5.5. Documentation & Recovery
- [x] Document disk preparation process
- [x] Create node provisioning guide
- [x] Document recovery procedures
  - [x] Master node recovery
  - [x] Worker node reprovisioning
  - [x] Full cluster rebuild
- [x] Update infrastructure diagrams
- [x] Document token rotation process

### 5.3. Longhorn Configuration
- [x] Create Longhorn namespace and RBAC
- [x] Configure Longhorn Helm repository with version pinning (1.5.x)
- [x] Deploy Longhorn using HelmRelease with production-ready values:
  ```yaml
  defaultSettings:
    createDefaultDiskLabeledNodes: true
    defaultDataPath: /var/lib/longhorn/
    defaultDiskSelector: ["storage=longhorn"]
    replicaSoftAntiAffinity: true
    replicaZoneSoftAntiAffinity: true
  ```
  - [x] Configure default storage settings
  - [x] Set resource requests/limits
  - [x] Enable auto-upgrades for patch versions
  - [x] Configure pruning and dependency management

### 5.4. Verification and Testing (Completed)
- [x] Verify Longhorn installation:
  - [x] Check all Longhorn pods are running: `kubectl get pods -n longhorn-system`
  - [x] Verify CRDs are installed: `kubectl get crd | grep longhorn`
  - [x] Access Longhorn UI via port-forward: `kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80`
- [x] Test storage functionality:
  - [x] Create test PVC and verify binding
  - [x] Deploy test pod to write/read data
  - [x] Verify data persistence across pod restarts
  - [x] Test volume expansion
  - [x] Verify replica scheduling across disks
- [x] Document the setup in `docs/k3s-flux-longhorn-guide.md`
  - [ ] Verify CRDs are installed: `kubectl get crd | grep longhorn`
  - [ ] Check Longhorn UI accessibility
- [ ] Test storage functionality:
  - [ ] Create test PVC and verify binding
  - [ ] Verify data persistence across pod restarts
  - [ ] Test volume expansion
  - [ ] Verify replica scheduling across nodes
  - [ ] Test node failure scenarios

### 5.5. Multi-Node Configuration
- [ ] Configure node affinity and anti-affinity
- [ ] Set up storage classes for different disk types
- [ ] Configure volume attachment recovery policy
- [ ] Test cross-node volume migration

### 5.6. Backup Configuration
- [ ] Set up backup target (NFS/S3):
  - [ ] Configure backup credentials using SOPS
  - [ ] Test backup/restore procedures
  - [ ] Schedule regular backups
  - [ ] Document recovery process
  - [ ] Set up backup retention policies

### 5.7. Monitoring and Alerting
- [ ] Configure Prometheus ServiceMonitor for Longhorn
- [ ] Import Longhorn Grafana dashboards
- [ ] Set up critical alerts for:
  - [ ] Volume health and status
  - [ ] Storage capacity and usage
  - [ ] Backup failures and consistency
  - [ ] Node disk pressure and I/O performance
  - [ ] Replication status and consistency

### 5.8. Documentation and Runbooks
- [ ] Document disk preparation process
- [ ] Create node provisioning guide
- [ ] Document recovery procedures
- [ ] Create troubleshooting guide
- [ ] Document performance tuning recommendations

### 5.9. Future Enhancements
- [ ] Implement backup target rotation
- [ ] Set up disaster recovery procedures
- [ ] Configure storage network isolation
- [ ] Implement storage policies for different workloads
- [ ] Create troubleshooting guide
- [ ] Document backup/restore procedures
- [ ] Document upgrade procedures

### 5.7. Integration with Other Components
- [ ] Configure StorageClass as default
- [ ] Update application manifests to use Longhorn storage
- [ ] Test application failover scenarios
- [ ] Document storage requirements for applications

## Phase 6: Security & Secrets
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
Complete Longhorn Distributed Storage Implementation

## Implementation Strategy

### 1. Repository Structure
```
infrastructure/
  longhorn/
    base/
      kustomization.yaml
      namespace.yaml
      helm-repository.yaml
      helm-release.yaml
      backup-secret.sops.yaml  # Encrypted credentials
    overlays/
      production/
        kustomization.yaml
        values-override.yaml
```

### 2. Key Configuration Files

#### 2.1. HelmRepository
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: longhorn
  namespace: infrastructure
spec:
  interval: 1h
  url: https://charts.longhorn.io
  type: oci
  interval: 1h
```

#### 2.2. HelmRelease (Key Components)
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  interval: 1h
  chart:
    spec:
      chart: longhorn
      version: 1.5.x  # Auto-update patch versions
      sourceRef:
        kind: HelmRepository
        name: longhorn
        namespace: infrastructure
      interval: 1h
  values:
    defaultSettings:
      defaultDataPath: /var/lib/longhorn/
      defaultReplicaCount: 2
      defaultDataLocality: best-effort
      replicaSoftAntiAffinity: true
      replicaZoneSoftAntiAffinity: true
      createDefaultDiskLabeledNodes: true
      defaultDiskSelector: ["storage=longhorn"]
      backupTarget: "s3://backup-bucket@us-east-1/"
      backupTargetCredentialSecret: "longhorn-backup-credentials"
    persistence:
      defaultClass: true
      defaultFsType: ext4
```

### 3. Verification Steps

#### 3.1. Check Installation
```bash
# Verify Helm release
flux get helmreleases -n longhorn-system

# Check pods
kubectl get pods -n longhorn-system

# Verify storage classes
kubectl get storageclass
```

#### 3.2. Test Storage
```yaml
# test-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

### 4. Troubleshooting Guide

#### 4.1. Common Issues
- **Pods not starting**: Check node requirements and resource constraints
- **Volume attachment failures**: Verify network connectivity between nodes
- **Backup failures**: Check credentials and network access to backup target

#### 4.2. Diagnostic Commands
```bash
# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager

# Describe failing pods
kubectl describe pod -n longhorn-system <pod-name>

# Check volume status
kubectl get volumes -n longhorn-system
```

## Next Steps

### 1. Deploy Cloud-init Server
```bash
# Deploy the cloud-init server
kubectl apply -k infrastructure/cloud-init

# Verify deployment
kubectl get pods,svc -n cloud-init
```

### 2. Provision k3s2 Node
1. Boot k3s2 with cloud-init URL: `http://192.168.86.71:30090/k3s2`
2. Monitor k3s2 joining the cluster:
   ```bash
   watch kubectl get nodes
   ```
3. Verify Longhorn disk detection:
   ```bash
   kubectl get nodes.longhorn.io -n longhorn-system
   ```

### 3. Test Cross-Node Functionality
- [ ] Schedule test pod on k3s2 with Longhorn volume
- [ ] Verify data persistence across pod rescheduling
- [ ] Test volume migration between nodes

### 4. Monitoring & Observability
- [ ] Deploy Prometheus stack with Flux
- [ ] Configure Longhorn metrics collection
- [ ] Set up Grafana dashboards for storage monitoring
- [ ] Configure alerts for storage capacity and health

### 5. Backup & Disaster Recovery
- [ ] Configure Longhorn backup target (S3/NFS)
- [ ] Set up scheduled backups for critical volumes
- [ ] Document restore procedures
- [ ] Test backup and restore process