# K3s Cluster with FluxCD and Longhorn - Complete Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Phase 0: Pre-requisites](#phase-0-pre-requisites)
   - [Ubuntu Server Installation](#ubuntu-server-installation)
   - [System-level Prerequisites](#system-level-prerequisites)
3. [Phase 1: K3s Cluster Setup](#phase-1-k3s-cluster-setup)
   - [K3s Server Installation (Master)](#k3s-server-installation-master)
   - [K3s Agent Installation (Workers)](#k3s-agent-installation-workers)
   - [Initial Cluster Verification](#initial-cluster-verification)
4. [Phase 2: FluxCD Bootstrap](#phase-2-fluxcd-bootstrap)
   - [Flux CLI Installation](#flux-cli-installation)
   - [GitHub PAT Setup](#github-pat-setup)
   - [Repository Bootstrap](#repository-bootstrap)
   - [Initial Verification](#initial-verification)
5. [Phase 3: Longhorn Configuration](#phase-3-longhorn-configuration)
   - [Disk Preparation](#disk-preparation)
   - [Installation via FluxCD](#installation-via-fluxcd)
   - [Node Labeling](#node-labeling)
   - [Explicit Disk Registration](#explicit-disk-registration)
   - [UI Access Configuration](#ui-access-configuration)
   - [Verification](#verification)
6. [Phase 4: Post-installation](#phase-4-post-installation)
   - [Final Checks](#final-checks)
   - [GitOps Best Practices](#gitops-best-practices)
   - [Recovery Procedures](#recovery-procedures)

## Introduction

This guide provides a comprehensive, step-by-step walkthrough for setting up a production-grade K3s cluster with FluxCD for GitOps and Longhorn for distributed storage. The guide is designed to be reproducible and follows infrastructure-as-code principles.

## Phase 0: Pre-requisites

### Ubuntu Server Installation

1. **Download Ubuntu Server**
   - Download Ubuntu Server 22.04 LTS from [ubuntu.com/download/server](https://ubuntu.com/download/server)
   - Create a bootable USB using tools like Rufus or balenaEtcher

2. **Installation Steps**
   - Boot from the USB drive
   - Select "Install Ubuntu Server"
   - Choose language and keyboard layout
   - Configure network (use DHCP unless static IP is required)
   - Set up storage (use entire disk with LVM recommended)
   - Create a user account with sudo privileges
   - Install OpenSSH server when prompted
   - Install additional packages: standard system utilities

3. **Post-Installation**
   ```bash
   # Update package lists
   sudo apt update && sudo apt upgrade -y
   
   # Install common utilities
   sudo apt install -y curl wget git jq vim htop tmux
   
   # Enable passwordless sudo for the current user
   echo "$(whoami) ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$(whoami)
   ```

### System-level Prerequisites

1. **Install Required Packages**
   ```bash
   # Install open-iscsi (required for Longhorn)
   sudo apt install -y open-iscsi
   
   # Install additional kernel modules if needed
   sudo apt install -y linux-modules-extra-$(uname -r)
   
   # Enable and start iscsid service
   sudo systemctl enable --now iscsid
   ```

2. **Disable Swap**
   ```bash
   # Disable swap immediately
   sudo swapoff -a
   
   # Comment out swap in /etc/fstab
   sudo sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
   ```

## Phase 1: K3s Cluster Setup

### K3s Server Installation (Master)

1. **Install K3s Server**
   ```bash
   # Install K3s server
   curl -sfL https://get.k3s.io | sh -
   
   # Check K3s service status
   sudo systemctl status k3s
   ```

2. **Retrieve Node Token**
   ```bash
   # Get the node token for joining workers
   sudo cat /var/lib/rancher/k3s/server/node-token
   ```

3. **Configure kubectl**
   ```bash
   # Install kubectl if not already installed
   sudo apt install -y kubectl
   
   # Copy kubeconfig to user's home directory
   mkdir -p ~/.kube
   sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
   sudo chown $(id -u):$(id -g) ~/.kube/config
   
   # Set KUBECONFIG in .bashrc
   echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
   source ~/.bashrc
   
   # Verify cluster access
   kubectl get nodes
   ```

### K3s Agent Installation (Workers)

1. **On each worker node**, run:
   ```bash
   # Replace with your master node IP and token
   export K3S_URL="https://<MASTER_IP>:6443"
   export K3S_TOKEN="<NODE_TOKEN>"
   
   # Install K3s agent
   curl -sfL https://get.k3s.io | K3S_URL=$K3S_URL K3S_TOKEN=$K3S_TOKEN sh -
   ```

### Initial Cluster Verification

```bash
# Check node status
kubectl get nodes -o wide

# Check system pods
kubectl get pods -A
```

## Phase 2: FluxCD Bootstrap

### Flux CLI Installation

#### On macOS:
```bash
brew install fluxcd/tap/flux
```

#### On Linux:
```bash
# Download and install flux
curl -s https://fluxcd.io/install.sh | sudo bash

# Verify installation
flux --version
```

### GitHub PAT Setup

1. **Generate GitHub Personal Access Token**
   - Go to GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
   - Generate new token with `repo` scope
   - Copy the token (you won't be able to see it again)

2. **Export Environment Variables**
   ```bash
   export GITHUB_USER=<your-github-username>
   export GITHUB_TOKEN=<your-github-token>
   ```

### Repository Bootstrap

1. **Bootstrap Flux**
   ```bash
   flux bootstrap github \
     --owner=$GITHUB_USER \
     --repository=<your-repo-name> \
     --branch=main \
     --path=./clusters/my-cluster \
     --personal
   ```

2. **Clone the Repository**
   ```bash
   git clone https://github.com/$GITHUB_USER/<your-repo-name>.git
   cd <your-repo-name>
   ```

### Initial Verification

```bash
# Check Flux components
flux check --pre

# Verify Flux pods
kubectl get pods -n flux-system

# Check reconciliation status
flux get kustomizations -A

# Manually trigger sync if needed
flux reconcile kustomization flux-system -n flux-system
```

## Phase 3: Longhorn Configuration

### Disk Preparation

1. **Identify Available Disks**
   ```bash
   # List all block devices
   lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL
   
   # Identify unused disks (typically /dev/sdX where X is a letter)
   # WARNING: The following commands will destroy data on the specified disks
   ```

2. **Prepare Disks for Longhorn**
   ```bash
   # WARNING: This will erase all data on the specified disks
   DISKS=("/dev/sdb" "/dev/sdc")  # Update with your disk paths
   
   for DISK in "${DISKS[@]}"; do
     echo "Preparing $DISK for Longhorn..."
     
     # Unmount any existing partitions
     sudo umount "${DISK}*" 2>/dev/null || true
     
     # Clear existing partition table
     sudo sgdisk --zap-all "$DISK"
     sudo wipefs -a "$DISK"
     
     # Create new partition table and single partition
     sudo parted "$DISK" mklabel gpt --script
     sudo parted -a opt "$DISK" mkpart primary 0% 100% --script
     
     # Create filesystem (Longhorn works best with ext4)
     sudo mkfs.ext4 -F "${DISK}1"
     
     # Create mount point and mount
     MOUNT_POINT="/mnt/longhorn/$(basename $DISK)"
     sudo mkdir -p "$MOUNT_POINT"
     echo "${DISK}1 $MOUNT_POINT ext4 defaults 0 0" | sudo tee -a /etc/fstab
     sudo mount -a
     
     echo "$DISK prepared and mounted at $MOUNT_POINT"
   done
   ```

### Installation via FluxCD

1. **Create Longhorn Directory Structure**
   ```bash
   mkdir -p infrastructure/longhorn/base
   ```

2. **Create HelmRepository** (`infrastructure/longhorn/base/helm-repository.yaml`):
   ```yaml
   apiVersion: source.toolkit.fluxcd.io/v1beta2
   kind: HelmRepository
   metadata:
     name: longhorn
     namespace: flux-system
   spec:
     interval: 30m
     url: https://charts.longhorn.io
   ```

3. **Create HelmRelease** (`infrastructure/longhorn/base/helm-release.yaml`):
   ```yaml
   apiVersion: helm.toolkit.fluxcd.io/v2beta1
   kind: HelmRelease
   metadata:
     name: longhorn
     namespace: longhorn-system
   spec:
     interval: 30m
     chart:
       spec:
         chart: longhorn
         version: 1.5.x
         sourceRef:
           kind: HelmRepository
           name: longhorn
           namespace: flux-system
     values:
       defaultSettings:
         createDefaultDiskLabeledNodes: true
         defaultDataPath: /var/lib/longhorn/
         defaultDiskSelector: ["storage=longhorn"]
         replicaSoftAntiAffinity: true
         replicaZoneSoftAntiAffinity: true
   ```

4. **Create Kustomization** (`infrastructure/longhorn/base/kustomization.yaml`):
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: longhorn
     namespace: flux-system
   spec:
     interval: 10m
     path: ./infrastructure/longhorn/base
     prune: true
     sourceRef:
       kind: GitRepository
       name: flux-system
     targetNamespace: longhorn-system
   ```

5. **Commit and Push Changes**
   ```bash
   git add .
   git commit -m "Add Longhorn configuration"
   git push origin main
   ```

### Node Labeling

Label each node for Longhorn disk discovery:

```bash
# For each node (k3s1, k3s2, etc.)
kubectl label node <node-name> node.longhorn.io/create-default-disk=config
kubectl label node <node-name> storage=longhorn
```

### Explicit Disk Registration

If auto-discovery fails, manually register disks:

```yaml
# Create a patch file (e.g., longhorn-disk-patch.yaml)
# Apply the patch:
# kubectl -n longhorn-system patch nodes.longhorn.io <node-name> --type merge --patch-file longhorn-disk-patch.yaml
```

Example patch file:
```yaml
spec:
  disks:
    default-disk-1ce5f99de6c0284:
      allowScheduling: false
      diskType: filesystem
      evictionRequested: false
      path: /var/lib/longhorn/
      storageReserved: 6287233843
      tags: []
    disk-sdf1:
      allowScheduling: true
      diskType: filesystem
      evictionRequested: false
      path: /mnt/longhorn/diskf
      storageReserved: 0
      tags: []
    disk-sdg1:
      allowScheduling: true
      diskType: filesystem
      evictionRequested: false
      path: /mnt/longhorn/diskg
      storageReserved: 0
      tags: []
    disk-sdh1:
      allowScheduling: true
      diskType: filesystem
      evictionRequested: false
      path: /mnt/longhorn/diskh
      storageReserved: 0
      tags: []
```

### UI Access Configuration

1. **Create Ingress for Longhorn UI**
   ```yaml
   # infrastructure/monitoring/longhorn-ingress.yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: longhorn
     namespace: longhorn-system
     annotations:
       nginx.ingress.kubernetes.io/rewrite-target: /
   spec:
     ingressClassName: nginx
     rules:
     - http:
         paths:
         - path: /longhorn
           pathType: Prefix
           backend:
             service:
               name: longhorn-frontend
               port:
                 number: 80
   ```

2. **Apply the Ingress**
   ```bash
   kubectl apply -f infrastructure/monitoring/longhorn-ingress.yaml
   ```

3. **Access the UI**
   - URL: `http://<node-ip>:30080/longhorn`
   - The UI should be accessible through the NGINX Ingress

### Verification

1. **Check Longhorn Components**
   ```bash
   # Verify all pods are running
   kubectl get pods -n longhorn-system
   
   # Check Longhorn manager logs
   kubectl logs -n longhorn-system -l app=longhorn-manager
   
   # Verify UI service is accessible
   curl -I http://localhost:30080/longhorn
   ```

2. **Test Volume Creation**
   ```yaml
   # test-volume.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: test-volume
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: longhorn
     resources:
       requests:
         storage: 1Gi
   ```
   
   ```bash
   # Apply the test volume
   kubectl apply -f test-volume.yaml
   
   # Verify the volume is created
   kubectl get pvc test-volume
   
   # Check volume in Longhorn UI
   # Go to Volumes section in the UI at http://<node-ip>:30080/longhorn
   ```

3. **Verify Storage Classes**
   ```bash
   # List available storage classes
   kubectl get storageclass
   
   # Verify Longhorn is the default
   kubectl get storageclass -o json | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name'
   ```

## Troubleshooting

### Longhorn UI Not Accessible
1. **Check Ingress Status**
   ```bash
   kubectl get ingress -n longhorn-system
   kubectl describe ingress longhorn -n longhorn-system
   ```

2. **Check NGINX Ingress Logs**
   ```bash
   kubectl logs -n infrastructure -l app.kubernetes.io/name=ingress-nginx
   ```

3. **Verify Service Endpoints**
   ```bash
   kubectl get endpoints -n longhorn-system longhorn-frontend
   ```

### Volume Creation Issues
1. **Check Node Disk Pressure**
   ```bash
   kubectl describe nodes | grep -A 10 "Conditions:"
   ```

2. **Check Longhorn Manager Logs**
   ```bash
   kubectl logs -n longhorn-system -l app=longhorn-manager
   ```

3. **Verify Disk Mounts**
   ```bash
   # On each node
   df -h /mnt/longhorn/*
   mount | grep longhorn
   ```

## Phase 4: Post-installation

### Final Checks

```bash
# Check Flux status
flux check

# Get all Flux resources
flux get all -A

# Check Longhorn UI (if installed)
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
```

### GitOps Best Practices

1. **Repository Structure**
   ```
   ./
   ├── clusters/
   │   └── my-cluster/
   │       ├── flux-system/
   │       └── apps/
   └── infrastructure/
       ├── longhorn/
       │   └── base/
       └── monitoring/
   ```

2. **Commit Practices**
   - Commit frequently with descriptive messages
   - Use feature branches and pull requests
   - Review changes before merging to main
   - Tag releases for important milestones

3. **Secrets Management**
   - Use Sealed Secrets or External Secrets Operator
   - Never commit plaintext secrets to Git
   - Rotate credentials regularly

### Recovery Procedures

1. **Flux Recovery**
   ```bash
   # If Flux is broken
   flux uninstall --silent
   
   # Re-bootstrap
   flux bootstrap github \
     --owner=$GITHUB_USER \
     --repository=<your-repo-name> \
     --branch=main \
     --path=./clusters/my-cluster \
     --personal
   ```

2. **Longhorn Recovery**
   - Back up Longhorn volumes regularly
   - Document volume backup/restore procedures
   - Test disaster recovery regularly

3. **Node Recovery**
   - Document node replacement procedures
   - Keep installation media and configuration handy
   - Test node recovery procedures periodically

## Conclusion

This guide provides a comprehensive approach to setting up a production-grade K3s cluster with FluxCD and Longhorn. By following these steps and adhering to GitOps principles, you can achieve a reliable, maintainable, and scalable Kubernetes infrastructure.
