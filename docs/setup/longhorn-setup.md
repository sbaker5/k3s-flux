# Longhorn Distributed Storage Setup

This document outlines the setup, configuration, and operation of Longhorn distributed storage in our K3s cluster managed by Flux CD.

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Accessing the UI](#accessing-the-ui)
5. [Verification](#verification)
6. [Usage](#usage)
7. [Backup Configuration](#backup-configuration)
8. [Monitoring](#monitoring)
9. [Troubleshooting](#troubleshooting)
10. [Maintenance](#maintenance)
11. [Recovery Procedures](#recovery-procedures)

## Overview

Longhorn provides enterprise-grade persistent storage for Kubernetes workloads with the following key features:

### Key Features
- **Distributed Block Storage**: Reliable storage replicated across nodes
- **High Availability**: Automatic failover for stateful applications
- **Point-in-Time Snapshots**: Create lightweight snapshots without performance impact
- **Backup and Restore**: Schedule backups to S3 or NFS targets
- **Intuitive UI**: Built-in dashboard for monitoring and management
- **CSI Integration**: Seamless Kubernetes storage integration

### Version Information
- **Longhorn Version**: 1.5.1
- **Deployment Method**: Flux CD v2
- **Kubernetes Version**: v1.24+
- **Storage Class**: `longhorn` (default)
- **UI Access**: Available via NGINX Ingress at `/longhorn` path

### Current Configuration
- **Replica Count**: 2 (configurable per volume, distributed across nodes)
- **Default Data Path**: `/var/lib/longhorn/` (k3s1), `/mnt/longhorn/sdb1` (k3s2)
- **Node Scheduling**: Enabled for all worker nodes (k3s1, k3s2 when available)
- **Backup Target**: Not configured by default
- **Multi-Node**: Supports automatic expansion when k3s2 joins cluster

## Architecture

Longhorn's architecture is designed for reliability and performance in a distributed environment.

### Core Components

#### Control Plane
- **longhorn-manager**: Central controller managing volume and node operations
- **longhorn-ui**: Web dashboard for monitoring and management
- **longhorn-csi-plugin**: Container Storage Interface driver for Kubernetes integration
- **longhorn-driver**: Handles volume provisioning and management

#### Data Plane
- **instance-manager**: Manages volume replicas and engine instances
- **share-manager**: Handles ReadWriteMany (RWX) volumes
- **csi-***: CSI plugin components for Kubernetes integration

### Data Flow
1. User creates a PersistentVolumeClaim (PVC) with `storageClassName: longhorn`
2. Longhorn CSI provisions a new volume
3. Volume replicas are created across nodes based on replica count
4. Data is synchronously replicated between replicas
5. Snapshots and backups can be scheduled or triggered manually

### High Availability
- **Replication**: Configurable replica count (default: 2, distributed across nodes)
- **Node Failure**: Automatic failover to healthy replicas on other nodes
- **Volume Recovery**: Automatic rebuilding of failed replicas
- **Multi-Node Support**: Replicas distributed across k3s1 and k3s2 for true redundancy

### Storage Backend
- **Local Storage**: Utilizes node-local storage in `/var/lib/longhorn/`
- **Filesystem**: ext4 (default)
- **Thin Provisioning**: Space-efficient storage allocation

## Installation

Longhorn is deployed using Flux CD with GitOps principles. The configuration is stored in the cluster's Git repository under `infrastructure/longhorn/`.

### Multi-Node Considerations

The Longhorn setup is designed to automatically expand when additional nodes join the cluster:

- **k3s1**: Primary node with storage at `/var/lib/longhorn/`
- **k3s2**: Worker node with dedicated storage at `/mnt/longhorn/sdb1` (when available)
- **Automatic Discovery**: Disk discovery DaemonSet automatically detects and prepares storage on new nodes
- **GitOps Managed**: Node-specific configurations managed through Flux Kustomizations

See [Multi-Node Cluster Expansion Guide](multi-node-cluster-expansion.md) for detailed k3s2 onboarding procedures.

### Prerequisites

Before installation, ensure all nodes meet these requirements:

1. **System Requirements**
   - Open-iSCSI installed and configured
   - NFS client utilities (for backup support)
   - Minimum 1 CPU core and 2GB RAM per node
   - At least 10GB free disk space per node
   - Kernel modules: `nvme`, `nvme_core`, `nvme_tcp` (if using NVMe)

2. **k3s Specific Requirements**
   - k3s version 1.24 or higher
   - Container runtime: containerd (default with k3s)
   - Ensure local-path provisioner is not conflicting

### Installation Steps

1. **Add Longhorn Helm Repository**
   ```yaml
   # infrastructure/longhorn/helm-repository.yaml
   apiVersion: source.toolkit.fluxcd.io/v1beta2
   kind: HelmRepository
   metadata:
     name: longhorn
     namespace: flux-system
   spec:
     interval: 1h
     url: https://charts.longhorn.io
   ```

2. **Create Longhorn Namespace**
   ```yaml
   # infrastructure/longhorn/namespace.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: longhorn-system
   ```

3. **Deploy Longhorn**
   ```yaml
   # infrastructure/longhorn/release.yaml
   apiVersion: helm.toolkit.fluxcd.io/v2beta1
   kind: HelmRelease
   metadata:
     name: longhorn
     namespace: longhorn-system
   spec:
     interval: 1h
     chart:
       spec:
         chart: longhorn
         sourceRef:
           kind: HelmRepository
           name: longhorn
           namespace: flux-system
         version: "1.5.x"
     values:
       defaultSettings:
         defaultDataPath: /var/lib/longhorn/
         replicaCount: "2"
         defaultReplicaCount: "2"
         backupTarget: ""
         backupTargetCredentialSecret: ""
         createDefaultDiskLabeledNodes: true
         defaultDataLocality: disabled
         guaranteeEngineCPU: false
         kubernetesClusterAutoscalerEnabled: false
         priorityClass: ""
       persistence:
         defaultClass: true
         defaultClassReplicaCount: 2
         reclaimPolicy: Delete
         defaultFsType: ext4
       service:
         ui:
           type: ClusterIP
           nodePort: null
   ```

## Accessing the UI

Longhorn provides a web-based UI for monitoring and management. It's exposed through the NGINX Ingress Controller.

### Access URL
- **UI URL**: `http://<node-ip>:30080/longhorn`
- **Authentication**: None by default (consider adding authentication for production)

### UI Features
- **Dashboard**: Overview of cluster status
- **Volume Management**: Create and manage volumes
- **Node View**: Monitor node status and disk usage
- **Backup & Restore**: Manage backups and restores
- **Settings**: Configure Longhorn settings

### Access via CLI

```bash
# Port-forward to access UI locally
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Then access at http://localhost:8080
```

## Verification

### Check Longhorn Components

```bash
# Verify all Longhorn pods are running
kubectl get pods -n longhorn-system

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager

# Verify storage class
kubectl get storageclass
```

### Test Volume Creation

1. **Create a test PVC**
   ```yaml
   # test-pvc.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: test-pvc
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: longhorn
     resources:
       requests:
         storage: 1Gi
   ```

   ```bash
   kubectl apply -f test-pvc.yaml
   ```

2. **Verify Volume Status**
   ```bash
   # Check PVC status
   kubectl get pvc test-pvc
   
   # Check Longhorn volume
   kubectl get volumes -n longhorn-system
   ```

3. **Cleanup**
   ```bash
   kubectl delete -f test-pvc.yaml
   ```

### Prerequisites

Before installation, ensure all nodes meet these requirements:
- Open-iSCSI installed and configured
- NFS client utilities (for backup support)
- Minimum 1 CPU core and 2GB RAM per node
- At least 10GB free disk space per node
- Kernel modules: `nvme`, `nvme_core`, `nvme_tcp`, `nvme_rdma` (if using NVMe)

### Repository Structure

```
infrastructure/
  longhorn/
    base/
      kustomization.yaml
      namespace.yaml
      helm-repository.yaml
      helm-release.yaml
```

### 1. Namespace Configuration

```yaml
# infrastructure/longhorn/base/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: longhorn-system
  labels:
    app.kubernetes.io/name: longhorn
    app.kubernetes.io/instance: longhorn
    app.kubernetes.io/managed-by: flux
```

### 2. Helm Repository

```yaml
# infrastructure/longhorn/base/helm-repository.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: longhorn-longhorn
  namespace: longhorn-system
  labels:
    app.kubernetes.io/name: longhorn
    app.kubernetes.io/instance: longhorn
    app.kubernetes.io/managed-by: flux
    app.kubernetes.io/part-of: longhorn
spec:
  interval: 1h
  url: https://charts.longhorn.io
```

### 3. Helm Release

```yaml
# infrastructure/longhorn/base/helm-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: longhorn
  namespace: longhorn-system
  labels:
    app.kubernetes.io/name: longhorn
    app.kubernetes.io/instance: longhorn
    app.kubernetes.io/managed-by: flux
spec:
  interval: 1h
  chart:
    spec:
      chart: longhorn
      version: "1.5.1"  # Pinned version
      sourceRef:
        kind: HelmRepository
        name: longhorn-longhorn
        namespace: longhorn-system
      interval: 1h
  values:
    # Storage settings
    defaultSettings:
      defaultClass: true
      defaultDataPath: /var/lib/longhorn/
      defaultReplicaCount: 2
      defaultDataLocality: best-effort
      
      # Resource management
      guaranteedEngineManagerCpu: 15  # 15% of system CPU
      guaranteedReplicaManagerCpu: 15  # 15% of system CPU
      
      # Disk and node configuration
      createDefaultDiskLabeledNodes: true
      defaultDiskSelector: ["storage=longhorn"]
      
      # Replica and backup settings
      replicaAutoBalance: best-effort
      replicaSoftAntiAffinity: true
      replicaZoneSoftAntiAffinity: true
      replicaReplenishmentWaitInterval: 600  # 10 minutes
      concurrentReplicaRebuildPerNodeLimit: 5
      concurrentVolumeBackupRestorePerNodeLimit: 5
      
      # Backup configuration
      backupTarget: ""  # Configured separately
      backupTargetCredentialSecret: ""
      backupstorePollInterval: 300  # 5 minutes
    
    # Configure persistence
    persistence:
      defaultClass: true
      defaultFsType: ext4
      reclaimPolicy: Delete
    
    # Configure the UI
    service:
      ui:
        type: ClusterIP
        nodePort: null
        annotations: {}
```

### 4. Kustomization

```yaml
# infrastructure/longhorn/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helm-repository.yaml
  - helm-release.yaml

# Common labels to apply to all resources
commonLabels:
  app.kubernetes.io/name: longhorn
  app.kubernetes.io/instance: longhorn
  app.kubernetes.io/managed-by: flux
  app.kubernetes.io/part-of: k3s-flux

# Name prefix for all resources
namePrefix: longhorn-

# Set the namespace for all resources
namespace: longhorn-system
```

### Node Preparation

Label nodes to schedule Longhorn components:

```bash
kubectl label node <node-name> storage=longhorn
```

### Deployment

Commit and push the changes to trigger Flux reconciliation:

```bash
git add infrastructure/longhorn/
git commit -m "feat: add Longhorn storage configuration"
git push
```

Flux will automatically deploy Longhorn to the cluster.

## Verification

After deployment, verify that all Longhorn components are functioning correctly.

### 1. Verify Pod Status

Check that all Longhorn pods are running:

```bash
kubectl get pods -n longhorn-system --sort-by='.metadata.name'
```

Expected output:
```
NAME                                                READY   STATUS    RESTARTS   AGE
csi-attacher-547747c45f-9cfmg                       1/1     Running   0          5m
csi-provisioner-8649bdf768-7qmj6                    1/1     Running   0          5m
csi-resizer-565567749d-bc9r4                        1/1     Running   0          5m
csi-snapshotter-75d66bc486-9vjkh                    1/1     Running   0          5m
engine-image-ei-74783864-rg7l8                      1/1     Running   0          5m
instance-manager-2e3e4f4f6ac33be14ae6750ba89459ad   1/1     Running   0          5m
longhorn-csi-plugin-sp42m                           3/3     Running   0          5m
longhorn-driver-deployer-5d7447f9d5-9nm6t           1/1     Running   0          5m
longhorn-manager-2xw9s                              1/1     Running   0          5m
longhorn-ui-597cc55bcd-54w87                        1/1     Running   0          5m
```

### 2. Verify StorageClass

Check that Longhorn is set as the default storage class:

```bash
kubectl get storageclass
```

Expected output:
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  3d
longhorn (default)     driver.longhorn.io      Delete          Immediate              true                   5m
```

### 3. Verify Volume Creation

Test volume creation with a sample PVC:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: longhorn-system
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF
```

Check the PVC status:

```bash
kubectl get pvc -n longhorn-system
```

### 4. Verify Volume Status

List all volumes in Longhorn:

```bash
kubectl get volumes -n longhorn-system
```

Get detailed volume information:

```bash
kubectl describe volume -n longhorn-system $(kubectl get pv -o jsonpath='{.items[?(@.spec.claimRef.name=="test-pvc")].metadata.name}')
```

### 5. Access Longhorn UI

Port-forward the Longhorn UI service:

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

Access the UI at http://localhost:8080

### 6. Verify CSI Integration

Check that the CSI driver is registered:

```bash
kubectl get csidriver
```

Expected output:
```
NAME                     ATTACHREQUIRED   PODINFOONMOUNT   MODES                  AGE
longhorn.io              true              true              Persistent            5m
```

### 7. Verify Node Status

Check that all nodes are ready for Longhorn:

```bash
kubectl get nodes -l storage=longhorn -o wide
```

### 8. Check System Components

Verify system deployments and daemonsets:

```bash
kubectl get deployments -n longhorn-system
kubectl get daemonsets -n longhorn-system
```

### 9. Check Logs for Errors

Inspect logs for any issues:

```bash
# Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager

# CSI plugin logs
kubectl logs -n longhorn-system -l app=longhorn-csi-plugin
```

## Usage

### 1. Basic Volume Operations

#### Create a PersistentVolumeClaim (PVC)

```yaml
# examples/storage/pvc-basic.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: my-app
  labels:
    app: my-app
    storage: longhorn
spec:
  accessModes:
    - ReadWriteOnce  # Supported: ReadWriteOnce, ReadWriteMany
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi  # Minimum 1Gi
```

#### Create a Pod with Persistent Storage

```yaml
# examples/workloads/pod-with-pvc.yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
  namespace: my-app
  labels:
    app: my-app
spec:
  containers:
  - name: app
    image: nginx:latest
    volumeMounts:
    - name: app-storage
      mountPath: /data
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
  volumes:
  - name: app-storage
    persistentVolumeClaim:
      claimName: app-data
      readOnly: false
```

### 2. Advanced Volume Configuration

#### Volume with Multiple Replicas

```yaml
# examples/storage/pvc-replicated.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-replicated
  namespace: my-app
  annotations:
    longhorn.io/replica-count: "3"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

#### Volume with Custom Settings

```yaml
# examples/storage/pvc-custom.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-custom
  namespace: my-app
  annotations:
    longhorn.io/replica-count: "2"
    longhorn.io/stale-replica-timeout: "30"  # minutes
    longhorn.io/disk-selector: "ssd"
    longhorn.io/node-selector: "storage-node"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 20Gi
```

### 3. Using with Workloads

#### Deployment with Persistent Storage

```yaml
# examples/workloads/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployment
  namespace: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: my-app:1.0.0
        volumeMounts:
        - name: app-data
          mountPath: /data
        ports:
        - containerPort: 8080
      volumes:
      - name: app-data
        persistentVolumeClaim:
          claimName: app-data
```

#### StatefulSet with Volume Claims

```yaml
# examples/workloads/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database
  namespace: my-app
spec:
  serviceName: database
  replicas: 3
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: database
        image: postgres:13
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
  volumeClaimTemplates:
  - metadata:
      name: data
      labels:
        app: database
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: longhorn
      resources:
        requests:
          storage: 10Gi
```

### 4. Volume Operations

#### Expand a Volume

1. Edit the PVC to request more storage:
   ```bash
   kubectl edit pvc app-data -n my-app
   ```
   Update `spec.resources.requests.storage` to the new size.

2. Verify the expansion:
   ```bash
   kubectl get pvc app-data -n my-app
   kubectl get pv  # Check the corresponding PV
   ```

#### Create a Snapshot

```bash
# Create a VolumeSnapshotClass
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: longhorn-snapshot
driver: driver.longhorn.io
deletionPolicy: Delete
EOF

# Create a snapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: app-data-snapshot
  namespace: my-app
spec:
  volumeSnapshotClassName: longhorn-snapshot
  source:
    persistentVolumeClaimName: app-data
EOF

# List snapshots
kubectl get volumesnapshot -n my-app
```

#### Clone a Volume

```bash
# Create a new PVC from a snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-clone
  namespace: my-app
spec:
  storageClassName: longhorn
  dataSource:
    name: app-data-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
```

### 5. Best Practices

#### Resource Management
- **Replica Count**: Use 3 replicas for production workloads requiring high availability
- **Node Affinity**: Use node selectors to control volume placement
- **Resource Requests**: Set appropriate CPU/memory requests for Longhorn components

#### Performance Considerations
- **Replica Placement**: Spread replicas across failure domains
- **Disk Type**: Use SSDs for better performance
- **Filesystem**: XFS is recommended for better performance with Longhorn

#### Monitoring
- Enable Prometheus monitoring for Longhorn metrics
- Set up alerts for volume health and capacity
- Monitor disk space on nodes

## Backup Configuration

Longhorn supports backing up persistent volume data to external storage such as S3 or NFS. This section covers setting up and managing backups.

### 1. Configure Backup Target

#### S3-Compatible Storage

1. Create a Kubernetes secret with S3 credentials:

```bash
# Create from literals
kubectl create secret generic longhorn-backup-secret \
  --from-literal=AWS_ACCESS_KEY_ID=your-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-secret-key \
  --from-literal=AWS_ENDPOINTS=https://s3.us-east-1.amazonaws.com \
  -n longhorn-system

# Or from an existing AWS credentials file
kubectl create secret generic longhorn-backup-secret \
  --from-file=~/.aws/credentials \
  -n longhorn-system
```

2. Update the Longhorn HelmRelease with backup configuration:

```yaml
# infrastructure/longhorn/base/helm-release.yaml
values:
  defaultSettings:
    backupTarget: s3://backup-bucket@us-east-1/
    backupTargetCredentialSecret: longhorn-backup-secret
    backupstorePollInterval: 300  # 5 minutes
    allowRecurringJobWhileVolumeDetached: true
```

#### NFS Backup Target

```yaml
values:
  defaultSettings:
    backupTarget: nfs://nfs-server:/export/path
    backupstorePollInterval: 300
```

### 2. Configuring Backup Schedules

#### Using Longhorn UI

1. Access the Longhorn UI
2. Navigate to Backup > Backup Volume
3. Select a volume and click "Create Backup"
4. Configure the backup schedule (hourly/daily/weekly/monthly)

#### Using Kubernetes CronJob

```yaml
# examples/backup/backup-cronjob.yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: longhorn-backup
  namespace: longhorn-system
spec:
  schedule: "0 * * * *"  # Hourly
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup-creator
            image: longhornio/longhorn-manager:v1.5.1
            command:
            - longhorn
            - backup
            - create
            - --label
            - app=my-app
            - --volume
            - my-volume
            - --namespace
            - my-app
          restartPolicy: OnFailure
```

### 3. Managing Backups

#### List Backups

```bash
# List all backups
kubectl get backups -n longhorn-system

# Get backup details
kubectl describe backup <backup-name> -n longhorn-system
```

#### Restore from Backup

1. Create a new PVC from a backup:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-volume
  namespace: my-app
  annotations:
    longhorn.io/from-backup: "s3://backup-bucket@us-east-1/backup-volume-name"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

2. Or restore in-place (replace existing volume):

```bash
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Volume
metadata:
  name: existing-volume
  namespace: longhorn-system
spec:
  fromBackup: "s3://backup-bucket@us-east-1/backup-volume-name"
  size: 10Gi
  numberOfReplicas: 3
  staleReplicaTimeout: 20
  diskSelector:
    - default-disk
  nodeSelector: []
EOF
```

### 4. Backup Retention Policy

Configure backup retention in the Helm values:

```yaml
values:
  defaultSettings:
    backupCompressionMethod: "lz4"  # or "gzip", "none"
    backupConcurrentLimit: 5
    backupMaxSize: 524288000  # 500MB
    backupMaxCount: 100  # Keep last 100 backups
    backupCleanupOnFailure: true
```

### 5. Monitoring Backups

Check backup status:

```bash
# View backup status
kubectl get backups -n longhorn-system

# View backup volume status
kubectl get backupvolumes -n longhorn-system

# View backup target status
kubectl get backuptargets -n longhorn-system
```

### 6. Disaster Recovery

---

### Validated Upgrade, Disk Cleanup, and Recovery Workflow (2025-06)

- **Sequential Upgrades:**
  - Upgrade Longhorn one minor version at a time (do not skip). Use the latest patch for each minor version if needed.
- **Disk Registration:**
  - Register disks declaratively via Node CR YAML. Avoid manual registration in the UI.
  - After a disk wipe/reformat, always create a longhorn-disk.cfg file at the disk root containing '{}' (valid JSON). **Never leave this file empty!**

> **Warning:** longhorn-disk.cfg must contain '{}' (empty JSON object). An empty file will cause disk registration to fail with a JSON parse error.
- **Duplicate Disk/Node Cleanup:**
  1. Disable scheduling and evict all replicas from the disk.
  2. Remove the disk from the Node CR and apply.
  3. If stuck, delete the Node CR (removes node from Longhorn), wipe/reformat disks, remove longhorn-disk.cfg, and re-register declaratively.
  4. Restart longhorn-manager pods to force reconciliation.
- **Recovery Observations:**
  - Disk/node reconciliation can take 5–10+ minutes after a full reset.
  - UI may be temporarily uneditable if duplicates exist; full reset resolves this.
- **Reference:**
  - See `docs/k3s-flux-longhorn-guide.md` for full step-by-step and troubleshooting.

---

#### Export Backup Configuration

```bash
# Get backup target configuration
kubectl get backuptargets -n longhorn-system -o yaml > backup-target.yaml

# Get all backup CRs
kubectl get backups -n longhorn-system -o yaml > all-backups.yaml
```

#### Restore Cluster from Backup

1. Install Longhorn in the new cluster
2. Configure the same backup target
3. Restore volumes from backup as needed

### 7. Troubleshooting Backups

#### Common Issues

1. **Backup Failing**
   ```bash
   # Check backup controller logs
   kubectl logs -n longhorn-system -l app=longhorn-manager | grep backup
   
   # Check backup target status
   kubectl describe backuptarget -n longhorn-system
   ```

2. **Slow Backups**
   - Check network bandwidth between cluster and backup target
   - Consider enabling compression
   - Verify sufficient resources for backup jobs

3. **Authentication Failures**
   - Verify S3 credentials are correct
   - Check IAM permissions for the backup bucket
   - Ensure the backup target URL is accessible

## Troubleshooting

### Common Issues

#### Pods in CrashLoopBackOff
```bash
kubectl logs -n longhorn-system -l app=longhorn-manager
kubectl describe pod -n longhorn-system <pod-name>
```

#### Volume Attachment Issues
```bash
kubectl get volumes -n longhorn-system
kubectl describe volume <volume-name> -n longhorn-system
```

#### Storage Not Available
```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

## Maintenance

### Upgrading Longhorn
1. Update the chart version in the HelmRelease
2. Monitor the upgrade process:

```bash
kubectl get pods -n longhorn-system -w
```

### Scaling
To scale Longhorn to additional nodes, ensure the nodes have the required labels and taints.

### Monitoring
Longhorn provides Prometheus metrics. Configure Prometheus to scrape these metrics for monitoring.
