# Tailscale Port Forwarding Guide

## Overview

This guide documents the working method for accessing cluster services remotely using Tailscale and kubectl port-forwarding. This was validated on January 25, 2025.

## Key Discovery

**kubectl port-forward works locally through the k3s-remote context!**

You don't need to SSH to the k3s node and run port-forward there. Instead, you can run port-forward on your MacBook, and it will route through Tailscale automatically.

## Prerequisites

1. Tailscale deployed in cluster (`tailscale` namespace)
2. Tailscale routes approved in admin console
3. Tailscale installed on MacBook (`brew install --cask tailscale`)
4. k3s-remote kubectl context configured

## Verified Working Method

### Step 1: Verify Tailscale Connection
```bash
# Check Tailscale status
tailscale status

# Should show something like:
# 100.117.198.6   stephens-macbook-pro sbaker5@     macOS   -
# 100.84.71.112   k3s1                 sbaker5@     linux   active
```

### Step 2: Switch to Remote Context
```bash
# Switch to remote context
kubectl config use-context k3s-remote

# Verify connection
kubectl get nodes
# Should show: k3s1   Ready   control-plane,master
```

### Step 3: Start Port Forwarding (Local)
```bash
# Forward Prometheus (runs on MacBook, connects to remote cluster)
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &

# Forward Grafana
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# Forward Longhorn (if needed)
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 &
```

### Step 4: Access Services
```bash
# Access via localhost (NOT Tailscale IP)
open http://localhost:9090   # Prometheus
open http://localhost:3000   # Grafana
open http://localhost:8080   # Longhorn

# Or test with curl
curl -s http://localhost:9090/api/v1/query?query=up
curl -s http://localhost:3000/api/health
```

### Step 5: Cleanup
```bash
# Kill port forwards
pkill -f "kubectl port-forward"

# Switch back to local context
kubectl config use-context default
```

## How It Works

1. **k3s-remote context**: Configured to connect to k3s cluster via Tailscale
2. **kubectl port-forward**: Runs locally but connects through the remote context
3. **Tailscale routing**: Handles the network routing transparently
4. **Local access**: Services accessible via localhost, not Tailscale IPs

## Common Mistakes (Don't Do This)

### ❌ Wrong: SSH + Remote Port Forward
```bash
# This is more complex and unnecessary
ssh k3s1-tailscale "kubectl port-forward -n monitoring svc/service 9090:9090 --address=0.0.0.0"
curl http://100.84.71.112:9090  # Access via Tailscale IP
```

### ❌ Wrong: Local Port Forward + Tailscale IP Access
```bash
kubectl port-forward -n monitoring svc/service 9090:9090 --address=0.0.0.0
curl http://100.84.71.112:9090  # This won't work
```

### ✅ Right: Local Port Forward + Localhost Access
```bash
kubectl config use-context k3s-remote
kubectl port-forward -n monitoring svc/service 9090:9090
curl http://localhost:9090  # This works!
```

## Troubleshooting

### Port Forward Not Working
```bash
# Check if port forward is running
ps aux | grep "kubectl port-forward"

# Check logs
kubectl port-forward -n monitoring svc/service 9090:9090 -v=6

# Kill existing port forwards
pkill -f "kubectl port-forward"
```

### Context Issues
```bash
# Check current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Switch contexts
kubectl config use-context k3s-remote  # For remote
kubectl config use-context default     # For local
```

### Tailscale Connection Issues
```bash
# Check Tailscale status
tailscale status

# Check cluster connectivity
kubectl --context=k3s-remote get nodes

# Test basic connectivity
ping 100.84.71.112  # k3s node Tailscale IP
```

## Service Names Reference

Common services you might want to forward:

```bash
# Monitoring
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# Longhorn
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 &

# Check available services
kubectl get svc -n monitoring
kubectl get svc -n longhorn-system
```

## Security Notes

- All traffic encrypted through Tailscale
- No ports exposed to internet
- Device authentication required
- Port forwards only accessible from your MacBook
- Can be killed instantly with `pkill -f "kubectl port-forward"`

## Performance Notes

- Port forwarding through Tailscale adds some latency
- Fine for monitoring dashboards and admin tasks
- Not recommended for high-throughput applications
- Connection is stable for long-running forwards

---

**Last Updated**: January 25, 2025  
**Tested With**: k3s v1.32.5+k3s1, Tailscale latest, macOS