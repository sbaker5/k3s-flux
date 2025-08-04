---
inclusion: manual
title: Flux Troubleshooting Workflows
description: Specialized troubleshooting procedures for Flux resources
---

# Flux Troubleshooting Workflows

## When to Use This Guide

Include this steering rule (`#flux-troubleshooting`) when:
- Debugging failed Flux reconciliations
- Analyzing HelmRelease or Kustomization issues
- Comparing Flux resources between clusters
- Investigating GitOps pipeline failures

## Flux HelmRelease Troubleshooting

When troubleshooting a HelmRelease, follow these systematic steps:

### 1. Check Controller Status
- Use the `get_flux_instance` tool to check the helm-controller deployment status and the apiVersion of the HelmRelease kind.

### 2. Analyze HelmRelease Resource
- Use the `get_kubernetes_resources` tool to get the HelmRelease, then analyze the spec, the status, inventory and events.
- Determine which Flux object is managing the HelmRelease by looking at the annotations; it can be a Kustomization or a ResourceSet.

### 3. Validate Configuration Sources
- If `valuesFrom` is present, get all the referenced ConfigMap and Secret resources.
- Identify the HelmRelease source by looking at the `chartRef` or the `sourceRef` field.
- Use the `get_kubernetes_resources` tool to get the HelmRelease source then analyze the source status and events.

### 4. Check Managed Resources
- If the HelmRelease is in a failed state or in progress, it may be due to failures in one of the managed resources found in the inventory.
- Use the `get_kubernetes_resources` tool to get the managed resources and analyze their status.
- If the managed resources are in a failed state, analyze their logs using the `get_kubernetes_logs` tool.

### 5. Generate Report
- If any issues were found, create a root cause analysis report for the user.
- If no issues were found, create a report with the current status of the HelmRelease and its managed resources and container images.

## Flux Kustomization Troubleshooting

When troubleshooting a Kustomization, follow these systematic steps:

### 1. Check Controller Status
- Use the `get_flux_instance` tool to check the kustomize-controller deployment status and the apiVersion of the Kustomization kind.

### 2. Analyze Kustomization Resource
- Use the `get_kubernetes_resources` tool to get the Kustomization, then analyze the spec, the status, inventory and events.
- Determine which Flux object is managing the Kustomization by looking at the annotations; it can be another Kustomization or a ResourceSet.

### 3. Validate Configuration Sources
- If `substituteFrom` is present, get all the referenced ConfigMap and Secret resources.
- Identify the Kustomization source by looking at the `sourceRef` field.
- Use the `get_kubernetes_resources` tool to get the Kustomization source then analyze the source status and events.

### 4. Check Managed Resources
- If the Kustomization is in a failed state or in progress, it may be due to failures in one of the managed resources found in the inventory.
- Use the `get_kubernetes_resources` tool to get the managed resources and analyze their status.
- If the managed resources are in a failed state, analyze their logs using the `get_kubernetes_logs` tool.

### 5. Generate Report
- If any issues were found, create a root cause analysis report for the user.
- If no issues were found, create a report with the current status of the Kustomization and its managed resources.

## Multi-Cluster Flux Comparison

When comparing a Flux resource between clusters, follow these steps:

### 1. Prepare Cluster Contexts
- Use the `get_kubernetes_contexts` tool to get the cluster contexts.
- Use the `set_kubernetes_context` tool to switch to a specific cluster.

### 2. Gather Resource Data
- Use the `get_flux_instance` tool to check the Flux Operator status and settings.
- Use the `get_kubernetes_resources` tool to get the resource you want to compare.
- If the Flux resource contains `valuesFrom` or `substituteFrom`, get all the referenced ConfigMap and Secret resources.

### 3. Compare Across Clusters
- Repeat the above steps for each cluster.
- Look for differences in the `spec`, `status` and `events`, including the referenced ConfigMaps and Secrets.
- The Flux resource `spec` represents the desired state and should be the main focus of the comparison, while the status and events represent the current state in the cluster.

## Common Troubleshooting Patterns

### Log Analysis Workflow
When looking at logs, first you need to determine the pod name:

1. Get the Kubernetes deployment that manages the pods using the `get_kubernetes_resources` tool.
2. Look for the `matchLabels` and the container name in the deployment spec.
3. List the pods with the `get_kubernetes_resources` tool using the found `matchLabels` from the deployment spec.
4. Get the logs by calling the `get_kubernetes_logs` tool using the pod name and container name.

### Resource Identification
To determine if a Kubernetes resource is Flux-managed, search the metadata field for `fluxcd` labels.

### Documentation Lookup
When asked about Flux CRDs call the `search_flux_docs` tool to get the latest API docs.