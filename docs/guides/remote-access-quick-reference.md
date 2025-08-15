# Remote Access Quick Reference

## 🚀 Quick Setup (5 minutes)

1. **Get Tailscale auth key**: https://login.tailscale.com/admin/settings/keys
2. **Configure secret**: Replace key in `infrastructure/tailscale/base/secret.yaml`
3. **Deploy**: `./scripts/setup-tailscale-remote-access.sh`
4. **Approve routes**: https://login.tailscale.com/admin/machines
5. **Install on MacBook**: `brew install --cask tailscale`

## 📱 Remote Access Commands

### ✅ Verified Working Method (August 2025)

**Key Discovery**: kubectl port-forward works locally through k3s-remote context!

```bash
# 1. Switch to remote context
kubectl config use-context k3s-remote

# 2. Run port-forward locally (on MacBook)
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# 3. Access via localhost
open http://localhost:9090  # Prometheus
open http://localhost:3000  # Grafana

# 4. Clean up when done
pkill -f "kubectl port-forward"
kubectl config use-context default  # Switch back to local
```

**How it works**: The k3s-remote context routes kubectl commands through Tailscale, so port-forward runs on your MacBook but connects to the remote cluster seamlessly.

**For detailed setup and troubleshooting**: See [Tailscale Remote Access Setup Guide](tailscale-remote-access-setup.md)

### Check Status
```bash
# On MacBook
tailscale status

# Get k3s node IP (100.x.x.x)
tailscale status | grep k3s-cluster
```

### kubectl Access
```bash
# RECOMMENDED: Use k3s-remote context (configured via Tailscale)
kubectl config use-context k3s-remote
kubectl get nodes

# Switch back to local when home
kubectl config use-context default
```

### Service Access
```bash
# IMPORTANT: Use k3s-remote context first
kubectl config use-context k3s-remote

# Forward services locally (runs on MacBook, forwards through Tailscale)
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 &

# Access via localhost (port-forward handles Tailscale routing)
# http://localhost:9090 (Prometheus)
# http://localhost:3000 (Grafana) 
# http://localhost:8080 (Longhorn)

# Kill port forwards when done
pkill -f "kubectl port-forward"
```

### Emergency Access
```bash
# SSH to k3s node via Tailscale
ssh k3s1-tailscale

# Basic cluster status
kubectl get nodes,pods --all-namespaces

# Check monitoring system
kubectl get pods -n monitoring
kubectl get pods -n flux-system
```

## 🔧 Troubleshooting

### Common Issues
```bash
# Check Tailscale pod
kubectl get pods -n tailscale
kubectl logs -n tailscale deployment/tailscale-subnet-router

# Restart Tailscale
kubectl rollout restart deployment/tailscale-subnet-router -n tailscale

# Test connectivity
ping 100.x.x.x  # k3s node Tailscale IP
```

### Network Issues
- **Routes not working**: Approve them in Tailscale admin console
- **Can't reach services**: Check if ports are forwarded with `--address=0.0.0.0`
- **kubectl fails**: Verify server IP in kubeconfig or use proxy method

### Monitoring Issues
```bash
# Check monitoring system health (use k3s-remote context)
kubectl config use-context k3s-remote
kubectl get pods -n monitoring

# Test Prometheus access (after port-forward)
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/query?query=up

# Test Grafana access (after port-forward)
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &
curl -s http://localhost:3000/api/health
```

## 📋 Pre-Travel Checklist

- [ ] Tailscale deployed and routes approved
- [ ] Tailscale installed on MacBook and connected
- [ ] Test kubectl access remotely
- [ ] Test service access (Grafana, Longhorn)
- [ ] Test emergency tooling remotely
- [ ] Save Tailscale IPs and access methods
- [ ] Backup kubeconfig with Tailscale IPs

## 🆘 Emergency Contacts

- **Tailscale Admin**: https://login.tailscale.com/admin/machines
- **Emergency CLI**: `./scripts/emergency-cli.sh`
- **Cluster Status**: `kubectl get nodes,pods --all-namespaces`

## 🔐 Security Notes

- Tailscale provides zero-trust encrypted access
- No ports exposed to internet
- Device-level authentication required
- All traffic encrypted end-to-end
- Access logs available in Tailscale admin console

---

**Full Documentation**: `docs/setup/tailscale-remote-access-setup.md`