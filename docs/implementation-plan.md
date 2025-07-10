# K3s Homelab Implementation Plan

## Table of Contents
1. [Current Issues](#current-issues)
2. [Immediate Actions](#immediate-actions)
3. [Network Troubleshooting](#network-troubleshooting)
4. [GitOps Implementation](#gitops-implementation)
5. [Security Enhancements](#security-enhancements)
6. [Monitoring & Observability](#monitoring--observability)
7. [Backup & Recovery](#backup--recovery)
8. [Documentation](#documentation)
9. [Long-term Improvements](#long-term-improvements)

## Current Issues

### 1. Longhorn UI Access
- **Issue**: Cannot access Longhorn UI via `http://192.168.86.71:30080/longhorn`
- **Workaround**: `kubectl port-forward -n longhorn-system svc/longhorn-ui 8080:80`
- **Root Causes**:
  - Network connectivity issues between kube-proxy and service endpoints
  - Potential CNI (Flannel) configuration issues
  - Service/Endpoint synchronization problems

### 2. Network Configuration
- NGINX Ingress Controller running on ports 30080/30443
- Longhorn UI service exposed on port 31863 (inaccessible)
- Documented Ports:
  - 30080: HTTP traffic
  - 30443: HTTPS traffic
  - 30090: Cloud-init server

## Immediate Actions

### 1. Port-Forwarding Workaround
```bash
# Access Longhorn UI via port-forwarding
kubectl port-forward -n longhorn-system svc/longhorn-ui 8080:80
```
Then access at: http://localhost:8080

### 2. Verify NGINX Ingress Accessibility
```bash
# Check NGINX Ingress service
kubectl get svc -n ingress-nginx

# Test direct access to NGINX
telnet 192.168.86.71 30080
curl -I http://192.168.86.71:30080
```

### 3. Check Host Firewall
```bash
# On k3s1 node
sudo ufw status
sudo iptables -L -n -v | grep 30080
```

## Network Troubleshooting

### 1. Verify kube-proxy
```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-proxy
```

### 2. Check Flannel CNI
```bash
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel -l app=flannel
```

### 3. Test Pod-to-Pod Connectivity
```bash
# Create test pods
kubectl run test-pod1 --image=busybox -- sleep 3600
kubectl run test-pod2 --image=busybox -- sleep 3600

# Test connectivity
kubectl exec -it test-pod1 -- ping test-pod2
```

## GitOps Implementation

### 1. Flux CD Health Check
```bash
flux check
flux get all -A
```

### 2. Resource Protection
```yaml
# Add to critical resources
metadata:
  annotations:
    fluxcd.io/ignore: "false"
    reconcile.fluxcd.io/ignore: "false"
```

### 3. Semantic Versioning
```yaml
# In HelmRelease
spec:
  chart:
    spec:
      version: "1.5.x"  # Use exact or patch version
```

## Security Enhancements

### 1. Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: longhorn-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 2. Enable Audit Logging
```yaml
# In k3s server config
apiServer:
  audit-policy-file: /etc/rancher/k3s/audit-policy.yaml
  audit-log-path: /var/lib/rancher/k3s/server/logs/audit.log
  audit-log-maxage: 30
  audit-log-maxbackup: 10
  audit-log-maxsize: 100
```

## Monitoring & Observability

### 1. Deploy Prometheus Operator
```bash
# Add Prometheus Community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

### 2. Configure Longhorn Metrics
```yaml
# In Longhorn values.yaml
defaultSettings:
  metricsServer: "http://prometheus-operated.monitoring:9090"
```

## Backup & Recovery

### 1. Install Velero
```bash
# Install Velero CLI
brew install velero

# Install Velero in cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.2.1 \
  --bucket my-velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio:9000
```

## Documentation

### 1. Network Architecture
- Update network diagram
- Document service dependencies
- Document access patterns

### 2. Runbooks
- Service recovery procedures
- Backup/restore procedures
- Troubleshooting guides

## Long-term Improvements

### 1. Progressive Delivery
- Implement Flagger for canary deployments
- Set up automated rollback on failure

### 2. Multi-cluster Management
- Set up Fleet for multi-cluster management
- Implement cluster API for provisioning

### 3. Policy as Code
- Implement OPA/Gatekeeper
- Define and enforce policies

## Next Steps
1. [ ] Implement port-forwarding workaround
2. [ ] Verify NGINX Ingress accessibility
3. [ ] Check network connectivity between components
4. [ ] Implement GitOps best practices
5. [ ] Set up monitoring and alerting
6. [ ] Document network architecture
7. [ ] Implement security enhancements
8. [ ] Set up backup solution
9. [ ] Document operational procedures
