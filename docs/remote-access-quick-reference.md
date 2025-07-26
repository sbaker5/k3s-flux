# Remote Access Quick Reference

## 🚀 Quick Setup (5 minutes)

1. **Get Tailscale auth key**: https://login.tailscale.com/admin/settings/keys
2. **Configure secret**: Replace key in `infrastructure/tailscale/base/secret.yaml`
3. **Deploy**: `./scripts/setup-tailscale-remote-access.sh`
4. **Approve routes**: https://login.tailscale.com/admin/machines
5. **Install on MacBook**: `brew install --cask tailscale`

## 📱 Remote Access Commands

### Check Status
```bash
# On MacBook
tailscale status

# Get k3s node IP (100.x.x.x)
tailscale status | grep k3s-cluster
```

### kubectl Access
```bash
# Option 1: Proxy (easiest)
# On k3s node:
kubectl proxy --address='0.0.0.0' --port=8080 --accept-hosts='.*'

# On MacBook:
kubectl --server=http://100.x.x.x:8080 get nodes

# Option 2: Direct API access
# Copy kubeconfig and change server to: https://100.x.x.x:6443
```

### Service Access
```bash
# Forward services to access from MacBook
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 --address=0.0.0.0
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 --address=0.0.0.0

# Access via: http://100.x.x.x:3000 (Grafana), http://100.x.x.x:8080 (Longhorn)
```

### Emergency Access
```bash
# SSH to k3s node
ssh user@100.x.x.x

# Run emergency tools remotely
./scripts/emergency-cli.sh status
./scripts/emergency-cli.sh interactive
```

## 🔧 Troubleshooting

### Common Issues
```bash
# Check Tailscale pod
kubectl get pods -n tailscale
kubectl logs -n tailscale deployment/tailscale-subnet-router

# Restart Tailscale
./scripts/setup-tailscale-remote-access.sh restart

# Test connectivity
ping 100.x.x.x  # k3s node Tailscale IP
```

### Network Issues
- **Routes not working**: Approve them in Tailscale admin console
- **Can't reach services**: Check if ports are forwarded with `--address=0.0.0.0`
- **kubectl fails**: Verify server IP in kubeconfig or use proxy method

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

**Full Documentation**: `docs/tailscale-remote-access-setup.md`