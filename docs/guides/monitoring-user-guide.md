# Monitoring User Guide - From Setup to Daily Use

This guide walks you through everything you need to know to actually **use** your monitoring system, from first access to understanding what you're looking at.

## 🚀 Quick Start - Get to Your Dashboards

### Option 1: Local Access (when at home)
```bash
# Forward the services to your local machine
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# Open in browser
open http://localhost:9090  # Prometheus (raw metrics)
open http://localhost:3000  # Grafana (pretty dashboards)
```

### Option 2: Remote Access (when away from home)
```bash
# Switch to remote context (via Tailscale)
kubectl config use-context k3s-remote

# Forward services (runs locally but connects remotely)
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# Access same URLs
open http://localhost:9090  # Prometheus
open http://localhost:3000  # Grafana

# Clean up when done
pkill -f "kubectl port-forward"
```

## 📊 What You'll See - Dashboard Overview

### Grafana Login
- **URL**: http://localhost:3000
- **Username**: `admin`
- **Password**: Check with `kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d`

### Key Dashboards You Have

#### 1. **GitOps Health Monitoring** (Your Custom Dashboard)
**What it shows**: Health of your GitOps system (Flux)
- **Health Score Gauge**: Overall system health (aim for >95%)
- **Resource Status**: Pie chart of what's working vs broken
- **Reconciliation Performance**: How fast Flux is processing changes
- **Error Rates**: What's failing and how often
- **Stuck Resources**: Things that need attention

**When to check**: 
- After making changes to your cluster
- When something seems broken
- Weekly health check

#### 2. **Flux Cluster Dashboard** (ID: 16714)
**What it shows**: Detailed Flux controller metrics
- Controller status and performance
- Git repository sync status
- Kustomization and Helm release health

#### 3. **Flux Control Plane Dashboard** (ID: 16713)  
**What it shows**: Flux infrastructure health
- Controller resource usage
- API request rates
- Workqueue status

#### 4. **Kubernetes Cluster Dashboard** (ID: 7249)
**What it shows**: Overall cluster health
- Node status and resource usage
- Pod distribution and health
- Network and storage metrics

#### 5. **Node Exporter Dashboard** (ID: 1860)
**What it shows**: Your k3s node hardware metrics
- CPU, memory, disk usage
- Network traffic
- System load

## 🔍 How to Read Your Dashboards

### GitOps Health Dashboard - What Each Panel Means

#### Health Score Gauge
- **Green (>95%)**: Everything's working great
- **Yellow (80-95%)**: Some minor issues, keep an eye on it
- **Red (<80%)**: Problems that need attention

#### Resource Status Distribution (Pie Chart)
- **True (Green)**: Resources are healthy and ready
- **False (Red)**: Resources are broken or stuck
- **Unknown (Yellow)**: Resources in transition or unclear state

#### Reconciliation Duration
- **Normal**: Most operations under 10 seconds
- **Concerning**: Regular spikes over 30 seconds
- **Problem**: Consistent high duration (>60 seconds)

#### Error Rate by Controller
- **Normal**: <5% error rate
- **Concerning**: 5-15% error rate  
- **Problem**: >15% error rate

#### Resource Status Details Table
- Shows every Flux-managed resource and its current status
- Look for ❌ (failed) or ⚠️ (unknown) entries
- Click on resource names to investigate further

### What Normal Looks Like
- Health score: 95-100%
- Most resources showing "True" status
- Reconciliation times under 10 seconds
- Error rates under 5%
- No stuck resources

### What Problems Look Like
- Health score dropping below 90%
- Multiple resources showing "False" status
- Reconciliation times consistently high
- Error rates above 10%
- Resources stuck for >5 minutes

## 🚨 Common Issues and What They Mean

### "Kustomization Not Ready"
**What it means**: Flux can't apply your configuration
**Common causes**:
- YAML syntax error in your files
- Missing dependencies
- Resource conflicts

**How to investigate**:
```bash
# Check Flux status
kubectl get kustomizations -A
kubectl describe kustomization <name> -n flux-system
```

### "High Reconciliation Error Rate"
**What it means**: Flux is failing to process changes
**Common causes**:
- Network issues
- Resource constraints
- Configuration errors

**How to investigate**:
```bash
# Check controller logs
kubectl logs -n flux-system -l app=kustomize-controller --tail=50
```

### "Resources Stuck Terminating"
**What it means**: Something is preventing resources from being deleted
**Common causes**:
- Finalizers not being cleared
- Storage issues
- Network policies

**How to investigate**:
```bash
# Check stuck resources
kubectl get pods --all-namespaces --field-selector=status.phase=Terminating
```

## 🛠️ Daily Monitoring Workflow

### Morning Check (2 minutes)
1. Open Grafana: http://localhost:3000
2. Check GitOps Health dashboard
3. Verify health score is >95%
4. Scan for any red alerts

### After Making Changes (5 minutes)
1. Make your Git changes and push
2. Wait 2-3 minutes for Flux to sync
3. Check GitOps Health dashboard
4. Verify your changes applied successfully
5. Check for any new errors

### Weekly Deep Dive (15 minutes)
1. Review all dashboards
2. Check resource usage trends
3. Look for performance degradation
4. Review error patterns
5. Plan any needed optimizations

## 🔧 Troubleshooting Your Monitoring

### Can't Access Dashboards
```bash
# Check if monitoring is running
kubectl get pods -n monitoring

# Check if services exist
kubectl get svc -n monitoring

# Restart port forwards
pkill -f "kubectl port-forward"
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &
```

### No Data in Dashboards
```bash
# Check if Prometheus is collecting metrics
kubectl port-forward -n monitoring svc/monitoring-core-prometheus-prometheus 9090:9090 &
# Visit http://localhost:9090/targets - should show targets as "UP"

# Check Flux controllers are running
kubectl get pods -n flux-system
```

### Dashboards Show Errors
```bash
# Run the health check script
./scripts/monitoring-health-check.sh

# Check for stuck resources
./scripts/cleanup-stuck-monitoring.sh assess
```

## 📱 Remote Monitoring Setup

### One-Time Setup
1. **Get Tailscale auth key**: https://login.tailscale.com/admin/settings/keys
2. **Update secret**: Edit `infrastructure/tailscale/base/secret.yaml`
3. **Deploy**: `./scripts/setup-tailscale-remote-access.sh`
4. **Approve routes**: https://login.tailscale.com/admin/machines
5. **Install on laptop**: `brew install --cask tailscale`

### Using Remote Access
```bash
# Switch to remote context
kubectl config use-context k3s-remote

# Use same port-forward commands as local
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# Access same URLs (port-forward handles the routing)
open http://localhost:3000
```

## 🎯 What Success Looks Like

### Healthy System Indicators
- ✅ Health score consistently >95%
- ✅ All resources showing "Ready" status
- ✅ Reconciliation times under 10 seconds
- ✅ Error rates under 5%
- ✅ No stuck resources
- ✅ Dashboards load quickly and show data

### When to Investigate
- ⚠️ Health score drops below 90%
- ⚠️ Multiple resources showing "False" status
- ⚠️ Reconciliation times consistently >30 seconds
- ⚠️ Error rates above 10%
- ⚠️ Resources stuck for >5 minutes

### When to Take Action
- 🚨 Health score below 80%
- 🚨 Critical resources failing
- 🚨 System unresponsive
- 🚨 Can't deploy new changes

## 📚 Quick Reference

### Essential URLs
- **Grafana**: http://localhost:3000
- **Prometheus**: http://localhost:9090
- **Longhorn**: http://localhost:8080 (when forwarded)

### Essential Commands
```bash
# Start monitoring access
kubectl port-forward -n monitoring svc/monitoring-core-grafana 3000:80 &

# Check system health
./scripts/monitoring-health-check.sh

# Clean up issues
./scripts/cleanup-stuck-monitoring.sh

# Stop port forwards
pkill -f "kubectl port-forward"
```

### Getting Help
- **Health check script**: `./scripts/monitoring-health-check.sh --report`
- **Remote access validation**: `./scripts/validate-remote-monitoring-access.sh`
- **Emergency access**: `ssh k3s1-tailscale` then `./scripts/emergency-cli.sh`

---

**Remember**: Your monitoring system is designed to be bulletproof. If something breaks, the monitoring itself should keep working to help you diagnose the issue!