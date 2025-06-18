# Flux CD Recovery Guide

This document provides a step-by-step guide to recover from a Flux CD control plane failure, where the core components have been deleted or are not functioning correctly.

## Table of Contents
1. [Current State Assessment](#current-state-assessment)
2. [Phase 1: Investigate the Deletion Event](#phase-1-investigate-the-deletion-event)
3. [Phase 2: Prepare for Recovery](#phase-2-prepare-for-recovery)
4. [Phase 3: Restore Flux Control Plane](#phase-3-restore-flux-control-plane)
5. [Phase 4: Validate and Reconcile](#phase-4-validate-and-reconcile)
6. [Phase 5: Preventative Measures](#phase-5-preventative-measures)
7. [Common Issues and Solutions](#common-issues-and-solutions)

## Current State Assessment

### Verify Current Cluster State

```bash
# Check Flux pods
kubectl get pods -n flux-system

# Check Flux custom resources
kubectl get gitrepositories,kustomizations,helmreleases -A

# Check for any recent deletion events
kubectl get events --sort-by='.lastTimestamp' -A | grep -i "delete"
```

### Expected Symptoms
- No pods in the `flux-system` namespace
- Missing `GitRepository` and `Kustomization` resources
- `flux` CLI commands failing

## Phase 1: Investigate the Deletion Event

### 1.1 Check Cluster Events

```bash
# Get recent events across all namespaces
kubectl get events --sort-by='.lastTimestamp' -A --field-selector=involvedObject.name=flux-system -A

# Check for any failed operations
kubectl get events --sort-by='.lastTimestamp' -A | grep -i "error\|fail"
```

### 1.2 Review API Server Audit Logs (if available)

```bash
# Get API server logs
kubectl -n kube-system logs -l component=kube-apiserver | grep -i flux-system
```

## Phase 2: Prepare for Recovery

### 2.1 Verify Local Repository

```bash
# Ensure you're on the correct branch
git status

# Fetch latest changes
git fetch origin

git checkout main  # or your main branch
git pull origin main
```

### 2.2 Verify Core Manifests

Ensure these files exist in your repository:
- `clusters/k3s-flux/flux-system/gotk-components.yaml`
- `clusters/k3s-flux/flux-system/gotk-sync.yaml`
- `clusters/k3s-flux/flux-system/kustomization.yaml`

## Phase 3: Restore Flux Control Plane

### 3.1 Re-apply Core Components

```bash
# Apply core Flux components
kubectl apply -f clusters/k3s-flux/flux-system/gotk-components.yaml

# Wait for CRDs to be established
kubectl wait --for condition=established --timeout=60s -f clusters/k3s-flux/flux-system/gotk-components.yaml
```

### 3.2 Restore GitRepository

```bash
# Apply GitRepository configuration
kubectl apply -f clusters/k3s-flux/flux-system/gotk-sync.yaml

# Verify the GitRepository
kubectl get gitrepositories -n flux-system
```

### 3.3 Restore Kustomization

```bash
# Apply the main Kustomization
kubectl apply -f clusters/k3s-flux/flux-system/kustomization.yaml

# Verify the Kustomization
kubectl get kustomizations -n flux-system
```

## Phase 4: Validate and Reconcile

### 4.1 Verify Controller Pods

```bash
# Watch pod status
kubectl get pods -n flux-system -w

# Expected output should show all controllers running:
# - source-controller
# - kustomize-controller
# - helm-controller
# - notification-controller
```

### 4.2 Check System Status

```bash
# Check Flux system status
flux check

# Get all Flux resources
flux get all -A
```

### 4.3 Trigger Reconciliation

```bash
# Reconcile the flux-system Kustomization
flux reconcile kustomization flux-system -n flux-system

# Check reconciliation status
flux get kustomizations -A
```

## Phase 5: Preventative Measures

### 5.1 Add Resource Protection

Add these annotations to critical resources:

```yaml
metadata:
  annotations:
    fluxcd.io/ignore: "false"
    fluxcd.io/ignore-reason: "Critical system component"
```

### 5.2 Implement Backup Solution

Example using Velero:

```bash
# Install Velero (adjust as needed)
velero install \
    --provider aws \
    --bucket <your-bucket> \
    --backup-location-config region=<region> \
    --snapshot-location-config region=<region> \
    --secret-file ./credentials-velero

# Schedule regular backups
velero schedule create flux-backup --schedule="@every 24h" --include-namespaces flux-system
```

### 5.3 Set Up Monitoring

Create a ServiceMonitor for Flux:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: flux-monitoring
  namespace: flux-system
  labels:
    app: flux-monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: flux
  namespaceSelector:
    matchNames:
    - flux-system
  endpoints:
  - port: http-prom
    interval: 15s
```

## Recovery Attempt Log

### Issues Identified

1. **Missing Cluster Role Bindings**
   - The `cluster-reconciler-flux-system` and `crd-controller-flux-system` ClusterRoleBindings were missing.
   - This prevented the kustomize-controller and helm-controller from functioning properly.

2. **Source Controller RBAC Permissions**
   - The source-controller was missing permissions to list and watch HelmChart and HelmRepository resources.
   - This caused continuous error logs and prevented the controller from functioning.

### Attempted Fixes

1. **Recreated Missing Cluster Role Bindings**
   ```bash
   # Recreated cluster-reconciler-flux-system and crd-controller-flux-system
   kubectl apply -f <(cat <<EOF
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: cluster-reconciler-flux-system
     labels:
       app.kubernetes.io/instance: flux-system
       app.kubernetes.io/part-of: flux
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: cluster-admin
   subjects:
   - kind: ServiceAccount
     name: kustomize-controller
     namespace: flux-system
   - kind: ServiceAccount
     name: helm-controller
     namespace: flux-system
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: crd-controller-flux-system
     labels:
       app.kubernetes.io/instance: flux-system
       app.kubernetes.io/part-of: flux
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: crd-controller-flux-system
   subjects:
   - kind: ServiceAccount
     name: kustomize-controller
     namespace: flux-system
   EOF
   )
   ```

2. **Created Missing RBAC for Source Controller**
   ```bash
   # Created source-controller specific ClusterRole and ClusterRoleBinding
   kubectl apply -f - <<EOF
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: source-controller-flux-system
     labels:
       app.kubernetes.io/instance: flux-system
       app.kubernetes.io/part-of: flux
   rules:
   - apiGroups: ["source.toolkit.fluxcd.io"]
     resources: ["helmcharts", "helmrepositories"]
     verbs: ["get", "list", "watch"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: source-controller-flux-system
     labels:
       app.kubernetes.io/instance: flux-system
       app.kubernetes.io/part-of: flux
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: source-controller-flux-system
   subjects:
   - kind: ServiceAccount
     name: source-controller
     namespace: flux-system
   EOF
   ```

3. **Restarted Controllers**
   ```bash
   # Restarted all flux controllers to apply new permissions
   kubectl delete pods -n flux-system --all
   ```

## Recovery Progress

### Current Status
- Successfully identified and resolved the stuck `flux-system` namespace issue
- All Flux controller pods are running and healthy
- Core Flux components have been successfully reinstalled
- SSH key authentication has been configured with known_hosts
- GitRepository is now synchronized successfully
- Flux system Kustomization is applied and healthy
- Example app has been successfully redeployed with the correct labels and selectors

### Resolution: Example App Deployment

The example app deployment had an immutable selector that conflicted with Flux's label management. Here's how we resolved it:

1. **Identified the Issue**:
   - The Deployment's selector was immutable after creation
   - Flux was trying to add additional labels that didn't match the original selector
   - This caused the Kustomization to fail with a validation error

2. **Resolution Steps**:
   - Deleted the existing Deployment to allow Flux to recreate it with the correct configuration:
     ```bash
     kubectl delete deployment example-app
     ```
   - Flux automatically recreated the Deployment with the correct labels and selectors
   - Verified the new Deployment was created successfully:
     ```bash
     kubectl get pods -l app=example-app
     ```

3. **Verification**:
   - Confirmed the application is accessible via port-forwarding:
     ```bash
     kubectl port-forward svc/example-app 8080:80
     ```
   - Accessed `http://localhost:8080` and verified it shows: `Hello from the example app!`

4. **Preventative Measures**:
   - Documented the label and selector requirements for Flux-managed resources
   - Added validation to ensure selectors and labels are consistent before applying changes
   - Consider using Kustomize patches for future label/selector modifications

### Current Resource Status

```bash
# GitRepository Status
$ kubectl get gitrepositories -n flux-system
NAME          URL                                     AGE   READY   STATUS
flux-system   ssh://git@github.com/sbaker5/k3s-flux   25m   True    stored artifact for revision 'main@sha1:819f08f489fe330f2a4b26b1705b2ffa097f6bbc'

# Kustomization Status
$ kubectl get kustomizations -n flux-system
NAME          AGE   READY   STATUS
flux-system   25m   True    Applied revision: main@sha1:819f08f489fe330f2a4b26b1705b2ffa097f6bbc
example-app  15m   True    Applied revision: main@sha1:819f08f489fe330f2a4b26b1705b2ffa097f6bbc

# Example App Status
$ kubectl get pods -l app=example-app
NAME                           READY   STATUS    RESTARTS   AGE
example-app-6f9bbcb9c6-9kfgf   1/1     Running   0          2m

# Access the example app
$ kubectl port-forward svc/example-app 8080:80
Forwarding from 127.0.0.1:8080 -> 5678
```

### Accessing the Example Application

The example application is running and can be accessed via port-forwarding:

1. In one terminal, start the port-forward:
   ```bash
   kubectl port-forward svc/example-app 8080:80
   ```

2. In another terminal or your browser, access:
   ```
   http://localhost:8080
   ```
   You should see: `Hello from the example app!`

### SSH Key Configuration

1. **Generated SSH Key Pair**
   ```bash
   # Generated a new ED25519 SSH key pair
   ssh-keygen -t ed25519 -C "flux@k3s-flux" -f ./flux-ssh-keys/identity -N ""
   ```

2. **Created Kubernetes Secret**
   ```bash
   # Created a secret with the private key
   kubectl create secret generic flux-system -n flux-system --from-file=identity=./flux-ssh-keys/identity
   ```

3. **Public Key for GitHub**
   The following public key needs to be added to your GitHub repository as a deploy key:
   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQUdXqhpnPsxx+tqBfcabSN6cSQl2ucvP7S/6z80h3i flux@k3s-flux
   ```

4. **Restarted Source Controller**
   ```bash
   kubectl rollout restart deployment/source-controller -n flux-system
   ```

### Current Resource Status

```bash
# Controller Pods
$ kubectl get pods -n flux-system
NAME                                       READY   STATUS    RESTARTS   AGE
helm-controller-5c898f4887-6znwh           1/1     Running   0          11m
kustomize-controller-57c6bbfc4b-v9vkb      1/1     Running   0          11m
notification-controller-5f66f99d4d-rp85w   1/1     Running   0          11m
source-controller-79df4cbf7c-g6p2h         1/1     Running   0          3m50s

# GitRepository Status
$ kubectl get gitrepositories -n flux-system
NAME          URL                                     AGE     READY     STATUS
flux-system   ssh://git@github.com/sbaker5/k3s-flux   4m35s   Unknown   building artifact

# Kustomization Status
$ kubectl get kustomizations -n flux-system
NAME          AGE     READY   STATUS
flux-system   4m39s   False   Source artifact not found, retrying in 30s
```

### Resolution Steps

1. **Identified Stuck Namespace**
   - The `flux-system` namespace was stuck in "Terminating" state
   - This was preventing recreation of Flux components

2. **Forced Namespace Deletion**
   ```bash
   # Checked namespace status
   kubectl get namespace flux-system -o yaml
   
   # Removed finalizers
   kubectl patch namespace flux-system -p '{"metadata":{"finalizers":[]}}' --type=merge
   
   # Deleted remaining resources
   kubectl delete kustomizations.kustomize.toolkit.fluxcd.io -n flux-system --all
   ```

3. **Recreated Namespace**
   ```bash
   # Deleted the stuck namespace
   kubectl delete namespace flux-system --force --grace-period=0
   
   # Recreated the namespace
   kubectl create namespace flux-system
   ```

4. **Reinstalled Flux Components**
   ```bash
   # Reapplied core components
   kubectl apply -f clusters/k3s-flux/flux-system/gotk-components.yaml
   ```

5. **Verified Installation**
   ```bash
   # Checked controller pods
   kubectl get pods -n flux-system
   ```

## Next Steps

1. **Investigate Pod Scheduling**
   - Check for node taints or resource constraints
   - Review kube-scheduler logs
   - Check for any admission controller blocks

2. **Verify CRDs**
   - Ensure all required CRDs are properly installed
   - Check for any validation errors

3. **Review Controller Logs**
   - Check kubelet logs on worker nodes
   - Review any events related to pod scheduling

## Common Issues and Solutions

### Issue: GitRepository Not Found

**Symptom**: `GitRepository.source.toolkit.fluxcd.io "flux-system" not found`

**Solution**:
```bash
kubectl apply -f clusters/k3s-flux/flux-system/gotk-sync.yaml
```

### Issue: Kustomization Stuck in Progressing

**Symptom**: Kustomization shows `Progressing=True` for extended time

**Solution**:
```bash
# Get detailed status
kubectl describe kustomization flux-system -n flux-system

# Check controller logs
kubectl logs -n flux-system -l app=kustomize-controller
```

### Issue: Webhook Failures

**Symptom**: Webhook connection errors in logs

**Solution**:
```bash
# Check webhook service
kubectl get svc -n flux-system notification-controller

# Check webhook configuration
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -A
```

## Recovery Verification Checklist

- [ ] All Flux controller pods are running
- [ ] `flux check` reports no errors
- [ ] GitRepository is synchronized
- [ ] Kustomizations are reconciled
- [ ] Applications are being deployed correctly
- [ ] Monitoring and alerting are in place

## Next Steps After Recovery

1. Document the incident and resolution
2. Review team access controls
3. Test backup and recovery procedures
4. Consider implementing additional safeguards:
   - Network policies
   - Resource quotas
   - Admission controllers
