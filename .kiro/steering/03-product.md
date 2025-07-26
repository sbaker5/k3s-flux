# Product Overview

This is a production-grade k3s Kubernetes cluster implementing GitOps patterns with Flux CD for continuous deployment, Longhorn for distributed storage, and NGINX Ingress for service exposure.

## Core Purpose
- **GitOps Infrastructure**: Declarative cluster management using Flux CD
- **Distributed Storage**: Longhorn provides resilient block storage across nodes
- **Application Platform**: Multi-environment deployment pipeline (dev/staging/prod)
- **Homelab Foundation**: Self-hosted Kubernetes platform for learning and experimentation

## Key Features
- **Bulletproof Architecture**: Core services remain operational even during storage failures
- **Multi-Node Ready**: Designed for k3s1 (primary) and k3s2 (expansion) nodes
- **Security-First**: SOPS integration for secrets management
- **Automated Recovery**: Dynamic disk discovery and self-healing infrastructure
- **Environment Isolation**: Separate overlays for development, staging, and production workloads

## Target Use Cases
- Learning Kubernetes and GitOps patterns
- Hosting containerized applications
- Testing distributed storage scenarios
- Developing cloud-native applications
- Infrastructure automation and monitoring