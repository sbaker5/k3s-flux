# Longhorn Distributed Storage Setup

This document outlines the setup and configuration of Longhorn distributed storage in the K3s cluster.

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Verification](#verification)
5. [Usage](#usage)
6. [Backup Configuration](#backup-configuration)
7. [Troubleshooting](#troubleshooting)
8. [Maintenance](#maintenance)

## Overview

Longhorn provides persistent storage for Kubernetes workloads with features like:
- Replication across nodes
- Backup and restore
- Snapshot support
- Distributed block storage

## Architecture

Longhorn consists of several components:
- **longhorn-manager**: Manages volume and node controllers
- **longhorn-ui**: Web interface for Longhorn
- **longhorn-driver**: CSI driver for Kubernetes
- **instance-manager**: Manages volume replicas

## Installation

Longhorn is installed using Flux CD with the following configuration:

### Helm Repository
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: longhorn
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.longhorn.io
```

### Helm Release
```yaml
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
      version: 1.5.1
      sourceRef:
        kind: HelmRepository
        name: longhorn
        namespace: flux-system
  values:
    # Configuration values...
```

## Verification

### Check Pod Status
```bash
kubectl get pods -n longhorn-system
```

### Verify StorageClass
```bash
kubectl get storageclass
```

### Check Volume Status
```bash
kubectl get volumes -n longhorn-system
```

## Usage

### Create a PVC
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: example-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

### Mount in a Pod
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  containers:
  - name: example
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: example-pvc
```

## Backup Configuration

### Configure Backup Target
1. Update the HelmRelease with backup target configuration:

```yaml
values:
  defaultSettings:
    backupTarget: s3://backup-bucket@us-east-1/
    backupTargetCredentialSecret: longhorn-backup-secret
```

2. Create a secret with credentials:

```bash
kubectl create secret generic longhorn-backup-secret \
  --from-literal=AWS_ACCESS_KEY_ID=xxx \
  --from-literal=AWS_SECRET_ACCESS_KEY=xxx \
  --from-literal=AWS_ENDPOINTS=xxx \
  -n longhorn-system
```

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
