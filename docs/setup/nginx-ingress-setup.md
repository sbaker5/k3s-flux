# NGINX Ingress Controller Setup

This document outlines the configuration and deployment of the NGINX Ingress Controller in the K3s homelab environment.

## Table of Contents
- [Overview](#overview)
- [Current Configuration](#current-configuration)
- [Accessing Services](#accessing-services)
- [Deployment](#deployment)
- [Configuration](#configuration)
- [Default Backend](#default-backend)
- [Service Examples](#service-examples)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [References](#references)

## Overview
The NGINX Ingress Controller manages external access to services in the cluster using HTTP/HTTPS. It's configured with NodePort for simplicity in the homelab environment.

## Current Configuration

### Access Points
- **HTTP**: `http://<node-ip>:30080`
- **HTTPS**: `https://<node-ip>:30443` (not configured by default)

### Managed Services
1. **Longhorn UI**
   - Path: `/longhorn`
   - Service: `longhorn-frontend` in `longhorn-system` namespace
   - Access: `http://<node-ip>:30080/longhorn`

2. **Default Backend**
   - Handles 404 responses
   - Service: `default-backend` in `infrastructure` namespace

## Accessing Services

### Longhorn UI
```bash
# Access via web browser:
http://<node-ip>:30080/longhorn

# Verify with curl:
curl -I http://<node-ip>:30080/longhorn
```

### Adding New Services
To expose a new service:

1. Create an Ingress resource:
   ```yaml
   # myapp-ingress.yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: myapp
     namespace: myapp-namespace
     annotations:
       nginx.ingress.kubernetes.io/rewrite-target: /
   spec:
     ingressClassName: nginx
     rules:
     - http:
         paths:
         - path: /myapp
           pathType: Prefix
           backend:
             service:
               name: myapp-service
               port:
                 number: 80
   ```

2. Apply the configuration:
   ```bash
   kubectl apply -f myapp-ingress.yaml
   ```

3. Access at: `http://<node-ip>:30080/myapp`

## Deployment

The NGINX Ingress Controller is deployed using Flux with the following configuration:

- **Helm Chart**: `ingress-nginx`
- **Service Type**: NodePort
- **NodePorts**:
  - HTTP: 30080
  - HTTPS: 30443
- **Namespace**: `infrastructure`

### Key Files

1. **HelmRelease**: `infrastructure/nginx-ingress/release.yaml`
2. **Default Backend**: `infrastructure/nginx-ingress/default-backend.yaml`
3. **Kustomization**: `infrastructure/nginx-ingress/kustomization.yaml`
4. **Ingress Examples**: `infrastructure/monitoring/longhorn-ingress.yaml`

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

## Service Examples

### Longhorn UI Ingress
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

### Basic Ingress Example
```yaml
# example-ingress.yaml
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

1. **Service Not Accessible**
   - Check if the Ingress resource exists:
     ```bash
     kubectl get ingress --all-namespaces
     ```
   - Verify the service is running:
     ```bash
     kubectl get svc -n <namespace> <service-name>
     ```
   - Check Ingress controller logs:
     ```bash
     kubectl logs -n infrastructure -l app.kubernetes.io/name=ingress-nginx
     ```

2. **404 Errors**
   - Verify the path in the Ingress matches the service path
   - Check if the backend service has endpoints:
     ```bash
     kubectl get endpoints -n <namespace> <service-name>
     ```
   - Check service selectors match pod labels:
     ```bash
     kubectl describe svc -n <namespace> <service-name>
     kubectl get pods -n <namespace> --show-labels
     ```

3. **Port Access Issues**
   - Ensure NodePorts (30080/30443) are open in your firewall
   - Verify the service is properly exposed:
     ```bash
     kubectl get svc -n infrastructure nginx-ingress-ingress-nginx-controller
     ```
   - Check if kube-proxy is running:
     ```bash
     kubectl -n kube-system get pods -l k8s-app=kube-proxy
     ```

## Security Considerations

1. **Authentication**
   - Consider adding authentication using OAuth2-Proxy or basic auth
   - Example basic auth annotation:
     ```yaml
     nginx.ingress.kubernetes.io/auth-type: basic
     nginx.ingress.kubernetes.io/auth-secret: basic-auth
     nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
     ```

2. **TLS/HTTPS**
   - For production, enable TLS with a valid certificate
   - Consider using cert-manager with Let's Encrypt

3. **Network Policies**
   - Restrict access to the Ingress controller using NetworkPolicies
   - Limit access to backend services from the Ingress controller only

## References

- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [K3s Networking](https://rancher.com/docs/k3s/latest/en/networking/)
- [Flux NGINX Ingress Example](https://github.com/fluxcd/flux2-kustomize-helm-example/tree/main/infrastructure/nginx-ingress)
- [Helm Chart Documentation](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx)
