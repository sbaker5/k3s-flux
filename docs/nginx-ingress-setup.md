# Nginx Ingress Controller Setup

This document outlines the configuration and deployment of the Nginx Ingress Controller in the K3s homelab environment.

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Deployment](#deployment)
- [Configuration](#configuration)
- [Default Backend](#default-backend)
- [Example Application](#example-application)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Overview
The Nginx Ingress Controller is deployed as a Kubernetes Ingress Controller to manage external access to services in the cluster, typically via HTTP/HTTPS.

## Architecture

```
┌─────────────────┐     ┌─────────────────────────────┐
│  External User  │────▶│  Nginx Ingress Controller  │
└─────────────────┘     │  - Service Type: NodePort  │
                        │  - HTTP: 30080            │
                        │  - HTTPS: 30443           │
                        └─────────────┬─────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────┐
│                Kubernetes Cluster                  │
│  ┌─────────────────┐        ┌─────────────────┐  │
│  │  Example App    │        | Default Backend  |  │
│  │  - Port: 80     │        | - Handles 404    |  │
│  │  - Path: /      │        |   responses      |  │
│  └─────────────────┘        └─────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Deployment

The Nginx Ingress Controller is deployed using the official Helm chart with the following key configurations:

- **Helm Chart**: `ingress-nginx` (version 4.10.0)
- **Service Type**: NodePort
- **NodePorts**:
  - HTTP: 30080
  - HTTPS: 30443
- **Namespace**: `infrastructure`

### Key Files

1. **HelmRelease**: `infrastructure/nginx-ingress/release.yaml`
2. **Default Backend**: `infrastructure/nginx-ingress/default-backend.yaml`
3. **Kustomization**: `infrastructure/nginx-ingress/kustomization.yaml`

## Configuration

### Helm Values

Key configuration values for the Nginx Ingress Controller:

```yaml
controller:
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
    externalTrafficPolicy: Local
  metrics:
    enabled: false  # Will be enabled with Prometheus in Phase 6
  defaultBackend:
    enabled: true
    name: default-backend
    port:
      number: 80
  kubeletPath: /var/lib/rancher/agent/kubelet/standalone/kubelet.sock
```

## Default Backend

A custom default backend is deployed to handle requests that don't match any Ingress rules. It returns a 404 response.

**Components**:
- Deployment: `default-backend`
- Service: `default-backend`
- Port: 80

## Example Application

An example application is deployed to demonstrate Ingress routing:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: example-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-app
            port:
              number: 80
```

### Testing the Example Application

1. **Using curl**:
   ```bash
   curl -H "Host: example-app.local" http://<NODE_IP>:30080
   ```
   
   Example output:
   ```
   Hello from the example app!
   ```

2. **Using /etc/hosts**:
   Add the following line to your `/etc/hosts` file:
   ```
   <NODE_IP> example-app.local
   ```
   
   Then access: `http://example-app.local:30080`

## Troubleshooting

### Common Issues

1. **Ingress not working**:
   - Check if the Nginx Ingress Controller pods are running:
     ```bash
     kubectl get pods -n infrastructure
     ```
   - Check the Ingress Controller logs:
     ```bash
     kubectl logs -n infrastructure -l app.kubernetes.io/name=ingress-nginx
     ```

2. **Default backend not responding**:
   - Check if the default backend pods are running:
     ```bash
     kubectl get pods -n infrastructure -l app=default-backend
     ```
   - Check the logs:
     ```bash
     kubectl logs -n infrastructure -l app=default-backend
     ```

3. **Ports not accessible**:
   - Ensure the NodePorts (30080/30443) are open in your firewall
   - Verify the service is properly exposed:
     ```bash
     kubectl get svc -n infrastructure nginx-ingress-ingress-nginx-controller
     ```

## References

- [Nginx Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Helm Chart Documentation](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx)
