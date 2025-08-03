# Tailscale Remote Access Setup Guide

This guide will help you set up secure remote access to your k3s cluster using Tailscale, a zero-trust mesh VPN.

## Overview

Tailscale provides:
- **Zero-trust networking**: Each device authenticates individually
- **Mesh VPN**: Direct encrypted connections between devices
- **Subnet routing**: Access to your entire k3s cluster network
- **Easy setup**: No complex firewall rules or port forwarding
- **Cross-platform**: Works on macOS, Linux, Windows, iOS, Android

## Prerequisites

1. **Tailscale Account**: Sign up at [https://tailscale.com](https://tailscale.com)
2. **k3s Cluster**: Your existing k3s cluster
3. **Network Information**: Know your local network ranges

## Step 1: Create Tailscale Auth Key

1. Go to [https://login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)
2. Click "Generate auth key"
3. Configure the key:
   - **Description**: "k3s-cluster-subnet-router"
   - **Reusable**: ✅ Yes (allows multiple deployments)
   - **Ephemeral**: ❌ No (persists across restarts)
   - **Pre-authorized**: ✅ Yes (auto-approves the device)
   - **Tags**: Add `tag:k8s` (for ACL management)
4. Copy the generated key (starts with `tskey-auth-`)

## Step 2: Configure the Secret

Edit the Tailscale secret with your auth key:

```bash
# Edit the secret file
vim infrastructure/tailscale/base/secret.yaml

# Replace REPLACE_WITH_YOUR_TAILSCALE_AUTH_KEY with your actual key
```

## Step 3: Verify Network Configuration

Check your network ranges and update if needed:

```bash
# Check your k3s cluster networks
kubectl cluster-info dump | grep -E "cluster-cidr|service-cidr"

# Check your local network (usually 192.168.1.0/24 or 192.168.0.0/24)
ip route | grep -E "192.168|10\."
```

Update the `TS_ROUTES` in `infrastructure/tailscale/base/subnet-router.yaml` if your networks are different:

```yaml
- name: TS_ROUTES
  value: "10.42.0.0/16,10.43.0.0/16,192.168.1.0/24"  # Adjust these ranges
```

Common network ranges:
- **k3s pods**: `10.42.0.0/16`
- **k3s services**: `10.43.0.0/16`
- **Home network**: `192.168.1.0/24` or `192.168.0.0/24`

## Step 4: Deploy Tailscale to Cluster

```bash
# Apply the Tailscale configuration
kubectl apply -k infrastructure/tailscale/base/

# Check deployment status
kubectl get pods -n tailscale
kubectl logs -n tailscale deployment/tailscale-subnet-router

# The logs should show successful connection to Tailscale
```

## Step 5: Approve Subnet Routes

1. Go to [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2. Find your "k3s-cluster" device
3. Click the "..." menu → "Edit route settings"
4. **Approve** all the subnet routes that were advertised
5. The routes should show as "Approved" with green checkmarks

## Step 6: Install Tailscale on Your MacBook

```bash
# Install Tailscale on macOS
brew install --cask tailscale

# Or download from: https://tailscale.com/download/mac
```

1. Launch Tailscale from Applications
2. Sign in with your Tailscale account
3. Your MacBook will appear in the admin console

## Step 7: Test Remote Access

Once both devices are connected:

```bash
# Check Tailscale status on your MacBook
tailscale status

# Test connectivity to your k3s node (replace with your node's Tailscale IP)
ping 100.x.x.x  # This will be shown in tailscale status

# Test kubectl access (you'll need to copy your kubeconfig)
kubectl get nodes

# Test accessing services directly
curl http://100.x.x.x:30080  # If you have nginx-ingress on NodePort
```

## Step 8: Configure kubectl for Remote Access

### Option A: Copy kubeconfig and modify

```bash
# On your k3s node, copy the kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/k3s-remote.yaml
sudo chown $USER:$USER ~/k3s-remote.yaml

# Edit the server address to use Tailscale IP
vim ~/k3s-remote.yaml
# Change: server: https://127.0.0.1:6443
# To:     server: https://100.x.x.x:6443  # Your k3s node's Tailscale IP
```

### Option B: Use kubectl proxy (easier)

```bash
# On your k3s node, run kubectl proxy accessible via Tailscale
kubectl proxy --address='0.0.0.0' --port=8080 --accept-hosts='.*'

# On your MacBook, access the cluster
export KUBECONFIG=/dev/null  # Use proxy instead of kubeconfig
kubectl --server=http://100.x.x.x:8080 get nodes
```

## Step 9: Set Up Port Forwarding for Services

### Recommended Method: Local Port Forwarding

**Key Discovery**: kubectl port-forward works locally through the k3s-remote context! You don't need to SSH to the k3s node and run port-forward there.

```bash
# Switch to remote context
kubectl config use-context k3s-remote

# Forward services (runs on MacBook, connects through Tailscale)
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 &

# Access via localhost (NOT Tailscale IP)
open http://localhost:9090   # Prometheus
open http://localhost:3000   # Grafana
open http://localhost:8080   # Longhorn

# Cleanup when done
pkill -f "kubectl port-forward"
kubectl config use-context default  # Switch back to local
```

### How It Works

1. **k3s-remote context**: Configured to connect to k3s cluster via Tailscale
2. **kubectl port-forward**: Runs locally but connects through the remote context
3. **Tailscale routing**: Handles the network routing transparently
4. **Local access**: Services accessible via localhost, not Tailscale IPs

### Alternative Method: Remote Port Forwarding

If the local method doesn't work, you can use remote port forwarding:

```bash
# SSH to k3s node and forward with external access
ssh k3s1-tailscale "kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0"

# Access from your MacBook using Tailscale IP
# http://100.x.x.x:3000  (Grafana)
# http://100.x.x.x:8080  (Longhorn)
```

### Common Service Names

```bash
# Monitoring services
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# Longhorn service
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 &

# Check available services
kubectl get svc -n monitoring
kubectl get svc -n longhorn-system
```

## Security Best Practices

### 1. Use Tailscale ACLs

Create ACL rules in the Tailscale admin console:

```json
{
  "tagOwners": {
    "tag:k8s": ["your-email@example.com"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["your-email@example.com"],
      "dst": ["tag:k8s:*"]
    }
  ]
}
```

### 2. Enable MagicDNS

1. Go to [DNS settings](https://login.tailscale.com/admin/dns)
2. Enable "MagicDNS"
3. Access your cluster as: `k3s-cluster.your-tailnet.ts.net`

### 3. Use Exit Nodes (Optional)

If you want to route all traffic through your home network:

1. Enable exit node on your k3s cluster
2. Use it from your MacBook when traveling

## Troubleshooting

### Common Issues

1. **Subnet routes not working**:
   - Ensure routes are approved in admin console
   - Check `TS_ROUTES` environment variable
   - Verify network ranges are correct

2. **Pod not starting**:
   - Check auth key is valid and not expired
   - Verify `/dev/net/tun` exists on the node
   - Check pod logs: `kubectl logs -n tailscale deployment/tailscale-subnet-router`

3. **Can't access services**:
   - Verify Tailscale IPs with `tailscale status`
   - Check k3s firewall rules
   - Test with `ping` first, then specific ports

### Useful Commands

```bash
# Check Tailscale status
tailscale status

# Show Tailscale routes
tailscale status --json | jq '.Peer[].PrimaryRoutes'

# Debug connectivity
tailscale ping k3s-cluster

# Check k3s node Tailscale logs
kubectl logs -n tailscale deployment/tailscale-subnet-router -f
```

### Port Forwarding Troubleshooting

#### Port Forward Not Working
```bash
# Check if port forward is running
ps aux | grep "kubectl port-forward"

# Check logs with verbose output
kubectl port-forward -n monitoring svc/service 9090:9090 -v=6

# Kill existing port forwards
pkill -f "kubectl port-forward"
```

#### Context Issues
```bash
# Check current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Switch contexts
kubectl config use-context k3s-remote  # For remote
kubectl config use-context default     # For local
```

#### Common Mistakes to Avoid

**❌ Wrong: SSH + Remote Port Forward**
```bash
# This is more complex and unnecessary
ssh k3s1-tailscale "kubectl port-forward -n monitoring svc/service 9090:9090 --address=0.0.0.0"
curl http://100.84.71.112:9090  # Access via Tailscale IP
```

**✅ Right: Local Port Forward + Localhost Access**
```bash
kubectl config use-context k3s-remote
kubectl port-forward -n monitoring svc/service 9090:9090
curl http://localhost:9090  # This works!
```

## Alternative: Direct Node Access

If you prefer direct SSH access to your k3s node:

```bash
# SSH to your k3s node via Tailscale
ssh user@100.x.x.x

# Then use kubectl locally on the node
kubectl get nodes
```

## Backup Access Method

Keep a backup access method in case Tailscale has issues:

1. **SSH tunnel**: Set up SSH key-based access
2. **VPN**: Traditional VPN as backup
3. **Cloud proxy**: Use a cloud VM as jump host

## Next Steps

Once remote access is working:

1. **Test your emergency tooling remotely**
2. **Set up monitoring alerts** to your phone
3. **Create runbooks** for common remote operations
4. **Test backup and restore procedures** remotely

## Security Notes

- **Never expose k3s API directly to internet**
- **Use strong authentication** (Tailscale handles this)
- **Monitor access logs** in Tailscale admin console
- **Rotate auth keys** periodically
- **Use device approval** for additional security

This setup gives you secure, encrypted access to your entire k3s cluster from anywhere in the world, without exposing any ports to the internet.