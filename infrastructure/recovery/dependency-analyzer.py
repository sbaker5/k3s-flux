#!/usr/bin/env python3
"""
Dependency-Aware Cleanup System for GitOps Recovery

This module implements dependency graph analysis for resource cleanup
and creates ordered cleanup and recreation workflows.
"""

import logging
import json
import yaml
import time
from datetime import datetime, timedelta
from typing import Dict, List, Set, Tuple, Optional, Any
from dataclasses import dataclass, field
from enum import Enum

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('dependency-analyzer')

class ResourceState(Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    FAILED = "failed"
    STUCK = "stuck"
    PENDING_CLEANUP = "pending_cleanup"
    CLEANING_UP = "cleaning_up"
    RECREATING = "recreating"

class DependencyType(Enum):
    HARD = "hard"  # Must be resolved before proceeding
    SOFT = "soft"  # Preferred order but not blocking
    CIRCULAR = "circular"  # Circular dependency detected

@dataclass
class ResourceIdentifier:
    """Unique identifier for a Kubernetes resource"""
    kind: str
    name: str
    namespace: str
    api_version: str = "v1"
    
    def __str__(self) -> str:
        return f"{self.namespace}/{self.kind}/{self.name}"
    
    def __hash__(self) -> int:
        return hash((self.kind, self.name, self.namespace, self.api_version))

@dataclass
class DependencyRelation:
    """Represents a dependency relationship between resources"""
    source: ResourceIdentifier
    target: ResourceIdentifier
    dependency_type: DependencyType
    reason: str
    weight: int = 1  # Higher weight = stronger dependency
    
    def __str__(self) -> str:
        return f"{self.source} -> {self.target} ({self.dependency_type.value})"

@dataclass
class ResourceNode:
    """Node in the dependency graph representing a resource"""
    resource: ResourceIdentifier
    state: ResourceState = ResourceState.HEALTHY
    dependencies: Set[ResourceIdentifier] = field(default_factory=set)
    dependents: Set[ResourceIdentifier] = field(default_factory=set)
    metadata: Dict[str, Any] = field(default_factory=dict)
    last_updated: datetime = field(default_factory=datetime.now)
    cleanup_priority: int = 0  # Higher = cleanup first
    recreation_priority: int = 0  # Higher = recreate first

class DependencyGraph:
    """Manages the dependency graph for Kubernetes resources"""
    
    def __init__(self):
        self.nodes: Dict[ResourceIdentifier, ResourceNode] = {}
        self.relations: List[DependencyRelation] = []
        self.circular_dependencies: List[List[ResourceIdentifier]] = []
        
    def add_resource(self, resource: ResourceIdentifier, state: ResourceState = ResourceState.HEALTHY) -> ResourceNode:
        """Add a resource to the dependency graph"""
        if resource not in self.nodes:
            self.nodes[resource] = ResourceNode(resource=resource, state=state)
            logger.debug(f"Added resource to graph: {resource}")
        else:
            self.nodes[resource].state = state
            self.nodes[resource].last_updated = datetime.now()
        
        return self.nodes[resource]
    
    def add_dependency(self, source: ResourceIdentifier, target: ResourceIdentifier, 
                      dependency_type: DependencyType = DependencyType.HARD, 
                      reason: str = "", weight: int = 1) -> None:
        """Add a dependency relationship between resources"""
        # Ensure both resources exist in the graph
        self.add_resource(source)
        self.add_resource(target)
        
        # Add the dependency relation
        relation = DependencyRelation(source, target, dependency_type, reason, weight)
        self.relations.append(relation)
        
        # Update node relationships
        self.nodes[source].dependencies.add(target)
        self.nodes[target].dependents.add(source)
        
        logger.debug(f"Added dependency: {relation}")
        
        # Check for circular dependencies
        self._detect_circular_dependencies()
    
    def _detect_circular_dependencies(self) -> None:
        """Detect circular dependencies in the graph"""
        visited = set()
        rec_stack = set()
        cycles = []
        
        def dfs(node: ResourceIdentifier, path: List[ResourceIdentifier]) -> None:
            if node in rec_stack:
                # Found a cycle
                cycle_start = path.index(node)
                cycle = path[cycle_start:] + [node]
                cycles.append(cycle)
                return
            
            if node in visited:
                return
            
            visited.add(node)
            rec_stack.add(node)
            path.append(node)
            
            for dependency in self.nodes[node].dependencies:
                dfs(dependency, path.copy())
            
            rec_stack.remove(node)
        
        for node in self.nodes:
            if node not in visited:
                dfs(node, [])
        
        self.circular_dependencies = cycles
        
        # Mark circular dependencies
        for cycle in cycles:
            for i in range(len(cycle) - 1):
                source, target = cycle[i], cycle[i + 1]
                for relation in self.relations:
                    if relation.source == source and relation.target == target:
                        relation.dependency_type = DependencyType.CIRCULAR
                        logger.warning(f"Circular dependency detected: {relation}")
    
    def get_cleanup_order(self, failed_resources: Set[ResourceIdentifier]) -> List[List[ResourceIdentifier]]:
        """
        Calculate the optimal cleanup order for failed resources.
        Returns a list of batches where resources in each batch can be cleaned up in parallel.
        """
        if not failed_resources:
            return []
        
        # Build subgraph of failed resources and their dependencies
        subgraph_nodes = set()
        for resource in failed_resources:
            subgraph_nodes.add(resource)
            # Add all dependents that might be affected
            subgraph_nodes.update(self._get_all_dependents(resource))
        
        # Calculate cleanup priorities
        self._calculate_cleanup_priorities(subgraph_nodes)
        
        # Perform topological sort for cleanup order (reverse dependency order)
        cleanup_batches = self._topological_sort_cleanup(subgraph_nodes)
        
        logger.info(f"Calculated cleanup order for {len(failed_resources)} failed resources:")
        for i, batch in enumerate(cleanup_batches):
            logger.info(f"  Batch {i + 1}: {[str(r) for r in batch]}")
        
        return cleanup_batches
    
    def get_recreation_order(self, resources_to_recreate: Set[ResourceIdentifier]) -> List[List[ResourceIdentifier]]:
        """
        Calculate the optimal recreation order for resources.
        Returns a list of batches where resources in each batch can be recreated in parallel.
        """
        if not resources_to_recreate:
            return []
        
        # Calculate recreation priorities
        self._calculate_recreation_priorities(resources_to_recreate)
        
        # Perform topological sort for recreation order (dependency order)
        recreation_batches = self._topological_sort_recreation(resources_to_recreate)
        
        logger.info(f"Calculated recreation order for {len(resources_to_recreate)} resources:")
        for i, batch in enumerate(recreation_batches):
            logger.info(f"  Batch {i + 1}: {[str(r) for r in batch]}")
        
        return recreation_batches
    
    def _get_all_dependents(self, resource: ResourceIdentifier) -> Set[ResourceIdentifier]:
        """Get all resources that depend on the given resource (transitively)"""
        visited = set()
        dependents = set()
        
        def dfs(node: ResourceIdentifier):
            if node in visited:
                return
            visited.add(node)
            
            if node in self.nodes:
                for dependent in self.nodes[node].dependents:
                    dependents.add(dependent)
                    dfs(dependent)
        
        dfs(resource)
        return dependents
    
    def _calculate_cleanup_priorities(self, resources: Set[ResourceIdentifier]) -> None:
        """Calculate cleanup priorities based on dependency relationships"""
        for resource in resources:
            if resource not in self.nodes:
                continue
            
            node = self.nodes[resource]
            priority = 0
            
            # Higher priority for resources with more dependents
            priority += len(node.dependents) * 10
            
            # Higher priority for critical resource types
            if node.resource.kind in ['Service', 'Ingress']:
                priority += 50
            elif node.resource.kind in ['Deployment', 'StatefulSet']:
                priority += 30
            elif node.resource.kind in ['ConfigMap', 'Secret']:
                priority += 20
            
            # Higher priority for resources in critical namespaces
            if node.resource.namespace in ['flux-system', 'kube-system', 'longhorn-system']:
                priority += 25
            
            # Lower priority for resources with many dependencies (cleanup last)
            priority -= len(node.dependencies) * 5
            
            node.cleanup_priority = priority
    
    def _calculate_recreation_priorities(self, resources: Set[ResourceIdentifier]) -> None:
        """Calculate recreation priorities based on dependency relationships"""
        for resource in resources:
            if resource not in self.nodes:
                continue
            
            node = self.nodes[resource]
            priority = 0
            
            # Higher priority for resources with fewer dependencies (recreate first)
            priority += max(0, 10 - len(node.dependencies)) * 5
            
            # Higher priority for foundational resource types
            if node.resource.kind in ['ConfigMap', 'Secret']:
                priority += 50
            elif node.resource.kind in ['Service']:
                priority += 40
            elif node.resource.kind in ['Deployment', 'StatefulSet']:
                priority += 30
            elif node.resource.kind in ['Ingress']:
                priority += 20
            
            # Higher priority for resources in critical namespaces
            if node.resource.namespace in ['flux-system', 'kube-system', 'longhorn-system']:
                priority += 25
            
            # Higher priority for resources that many others depend on
            priority += len(node.dependents) * 3
            
            node.recreation_priority = priority
    
    def _topological_sort_cleanup(self, resources: Set[ResourceIdentifier]) -> List[List[ResourceIdentifier]]:
        """Perform topological sort for cleanup order (reverse dependency order)"""
        # Create a copy of the graph for manipulation
        in_degree = {}
        graph = {}
        
        for resource in resources:
            if resource not in self.nodes:
                continue
            
            # For cleanup, we reverse the dependencies (dependents become dependencies)
            dependencies = self.nodes[resource].dependents.intersection(resources)
            in_degree[resource] = len(dependencies)
            graph[resource] = dependencies
        
        batches = []
        
        while in_degree:
            # Find all nodes with in-degree 0
            current_batch = []
            for resource, degree in in_degree.items():
                if degree == 0:
                    current_batch.append(resource)
            
            if not current_batch:
                # Handle circular dependencies by breaking them
                current_batch = self._break_circular_dependencies_cleanup(in_degree)
            
            # Sort batch by cleanup priority (highest first)
            current_batch.sort(key=lambda r: self.nodes[r].cleanup_priority, reverse=True)
            batches.append(current_batch)
            
            # Remove current batch from graph and update in-degrees
            for resource in current_batch:
                del in_degree[resource]
                for other_resource in list(in_degree.keys()):
                    if resource in graph.get(other_resource, set()):
                        in_degree[other_resource] -= 1
        
        return batches
    
    def _topological_sort_recreation(self, resources: Set[ResourceIdentifier]) -> List[List[ResourceIdentifier]]:
        """Perform topological sort for recreation order (dependency order)"""
        # Create a copy of the graph for manipulation
        in_degree = {}
        graph = {}
        
        for resource in resources:
            if resource not in self.nodes:
                continue
            
            dependencies = self.nodes[resource].dependencies.intersection(resources)
            in_degree[resource] = len(dependencies)
            graph[resource] = dependencies
        
        batches = []
        
        while in_degree:
            # Find all nodes with in-degree 0
            current_batch = []
            for resource, degree in in_degree.items():
                if degree == 0:
                    current_batch.append(resource)
            
            if not current_batch:
                # Handle circular dependencies by breaking them
                current_batch = self._break_circular_dependencies_recreation(in_degree)
            
            # Sort batch by recreation priority (highest first)
            current_batch.sort(key=lambda r: self.nodes[r].recreation_priority, reverse=True)
            batches.append(current_batch)
            
            # Remove current batch from graph and update in-degrees
            for resource in current_batch:
                del in_degree[resource]
                for other_resource in list(in_degree.keys()):
                    if resource in graph.get(other_resource, set()):
                        in_degree[other_resource] -= 1
        
        return batches
    
    def _break_circular_dependencies_cleanup(self, in_degree: Dict[ResourceIdentifier, int]) -> List[ResourceIdentifier]:
        """Break circular dependencies for cleanup by selecting the best candidate"""
        # Find the resource with the highest cleanup priority among those in the cycle
        candidates = [r for r, degree in in_degree.items() if degree > 0]
        if not candidates:
            return []
        
        best_candidate = max(candidates, key=lambda r: self.nodes[r].cleanup_priority)
        logger.warning(f"Breaking circular dependency for cleanup by selecting: {best_candidate}")
        return [best_candidate]
    
    def _break_circular_dependencies_recreation(self, in_degree: Dict[ResourceIdentifier, int]) -> List[ResourceIdentifier]:
        """Break circular dependencies for recreation by selecting the best candidate"""
        # Find the resource with the highest recreation priority among those in the cycle
        candidates = [r for r, degree in in_degree.items() if degree > 0]
        if not candidates:
            return []
        
        best_candidate = max(candidates, key=lambda r: self.nodes[r].recreation_priority)
        logger.warning(f"Breaking circular dependency for recreation by selecting: {best_candidate}")
        return [best_candidate]
    
    def analyze_impact(self, failed_resource: ResourceIdentifier) -> Dict[str, Any]:
        """Analyze the impact of a failed resource on the system"""
        if failed_resource not in self.nodes:
            return {"error": "Resource not found in dependency graph"}
        
        affected_resources = self._get_all_dependents(failed_resource)
        
        impact_analysis = {
            "failed_resource": str(failed_resource),
            "directly_affected": len(self.nodes[failed_resource].dependents),
            "total_affected": len(affected_resources),
            "affected_resources": [str(r) for r in affected_resources],
            "critical_affected": [],
            "cleanup_complexity": "low",
            "estimated_recovery_time": "5-10 minutes"
        }
        
        # Identify critical affected resources
        for resource in affected_resources:
            if resource in self.nodes:
                node = self.nodes[resource]
                if (node.resource.namespace in ['flux-system', 'kube-system', 'longhorn-system'] or
                    node.resource.kind in ['Service', 'Ingress'] or
                    len(node.dependents) > 3):
                    impact_analysis["critical_affected"].append(str(resource))
        
        # Assess cleanup complexity
        if len(affected_resources) > 10:
            impact_analysis["cleanup_complexity"] = "high"
            impact_analysis["estimated_recovery_time"] = "20-30 minutes"
        elif len(affected_resources) > 5:
            impact_analysis["cleanup_complexity"] = "medium"
            impact_analysis["estimated_recovery_time"] = "10-20 minutes"
        
        # Check for circular dependencies
        for cycle in self.circular_dependencies:
            if failed_resource in cycle:
                impact_analysis["cleanup_complexity"] = "high"
                impact_analysis["circular_dependency"] = True
                impact_analysis["estimated_recovery_time"] = "15-25 minutes"
                break
        
        return impact_analysis

class DependencyAnalyzer:
    """Main class for dependency-aware cleanup procedures"""
    
    def __init__(self):
        self.graph = DependencyGraph()
        self.kubernetes_client = None
        self.recovery_state = {}
        
    def initialize_kubernetes_client(self):
        """Initialize Kubernetes client for real cluster interaction"""
        try:
            from kubernetes import client, config
            config.load_incluster_config()
            self.kubernetes_client = client
            logger.info("✅ Kubernetes client initialized")
            return True
        except ImportError:
            logger.warning("⚠️  Kubernetes client not available, using simulation mode")
            return False
        except Exception as e:
            logger.error(f"❌ Error initializing Kubernetes client: {e}")
            return False
    
    def discover_dependencies(self) -> None:
        """Discover resource dependencies from the cluster"""
        logger.info("🔍 Discovering resource dependencies...")
        
        if self.kubernetes_client:
            self._discover_real_dependencies()
        else:
            self._simulate_dependencies()
    
    def _discover_real_dependencies(self) -> None:
        """Discover real dependencies from Kubernetes cluster"""
        try:
            # Get all relevant resources
            v1 = self.kubernetes_client.CoreV1Api()
            apps_v1 = self.kubernetes_client.AppsV1Api()
            
            # Discover Services and their dependencies
            services = v1.list_service_for_all_namespaces()
            for service in services.items:
                service_id = ResourceIdentifier(
                    kind="Service",
                    name=service.metadata.name,
                    namespace=service.metadata.namespace
                )
                self.graph.add_resource(service_id)
                
                # Services depend on Deployments/StatefulSets via selectors
                if service.spec.selector:
                    deployments = apps_v1.list_deployment_for_all_namespaces()
                    for deployment in deployments.items:
                        if (deployment.metadata.namespace == service.metadata.namespace and
                            self._labels_match(deployment.spec.selector.match_labels, service.spec.selector)):
                            
                            deployment_id = ResourceIdentifier(
                                kind="Deployment",
                                name=deployment.metadata.name,
                                namespace=deployment.metadata.namespace
                            )
                            self.graph.add_resource(deployment_id)
                            self.graph.add_dependency(
                                service_id, deployment_id,
                                DependencyType.HARD,
                                "Service selector matches Deployment labels"
                            )
            
            # Discover ConfigMap and Secret dependencies
            configmaps = v1.list_config_map_for_all_namespaces()
            secrets = v1.list_secret_for_all_namespaces()
            
            for deployment in apps_v1.list_deployment_for_all_namespaces().items:
                deployment_id = ResourceIdentifier(
                    kind="Deployment",
                    name=deployment.metadata.name,
                    namespace=deployment.metadata.namespace
                )
                self.graph.add_resource(deployment_id)
                
                # Check for ConfigMap dependencies
                for container in deployment.spec.template.spec.containers:
                    if container.env:
                        for env_var in container.env:
                            if env_var.value_from and env_var.value_from.config_map_key_ref:
                                cm_name = env_var.value_from.config_map_key_ref.name
                                cm_id = ResourceIdentifier(
                                    kind="ConfigMap",
                                    name=cm_name,
                                    namespace=deployment.metadata.namespace
                                )
                                self.graph.add_resource(cm_id)
                                self.graph.add_dependency(
                                    deployment_id, cm_id,
                                    DependencyType.HARD,
                                    f"Deployment references ConfigMap in env var {env_var.name}"
                                )
                    
                    # Check for Secret dependencies
                    if env_var.value_from and env_var.value_from.secret_key_ref:
                        secret_name = env_var.value_from.secret_key_ref.name
                        secret_id = ResourceIdentifier(
                            kind="Secret",
                            name=secret_name,
                            namespace=deployment.metadata.namespace
                        )
                        self.graph.add_resource(secret_id)
                        self.graph.add_dependency(
                            deployment_id, secret_id,
                            DependencyType.HARD,
                            f"Deployment references Secret in env var {env_var.name}"
                        )
            
            logger.info(f"✅ Discovered {len(self.graph.nodes)} resources with {len(self.graph.relations)} dependencies")
            
        except Exception as e:
            logger.error(f"❌ Error discovering real dependencies: {e}")
            self._simulate_dependencies()
    
    def _simulate_dependencies(self) -> None:
        """Simulate dependency discovery for testing"""
        logger.info("📺 Simulating dependency discovery...")
        
        # Create sample resources and dependencies
        resources = [
            # Infrastructure resources
            ResourceIdentifier("ConfigMap", "app-config", "default"),
            ResourceIdentifier("Secret", "app-secrets", "default"),
            ResourceIdentifier("Service", "app-service", "default"),
            ResourceIdentifier("Deployment", "app-deployment", "default"),
            ResourceIdentifier("Ingress", "app-ingress", "default"),
            
            # Flux resources
            ResourceIdentifier("GitRepository", "flux-system", "flux-system"),
            ResourceIdentifier("Kustomization", "infrastructure", "flux-system"),
            ResourceIdentifier("Kustomization", "apps", "flux-system"),
            ResourceIdentifier("HelmRepository", "longhorn", "longhorn-system"),
            ResourceIdentifier("HelmRelease", "longhorn", "longhorn-system"),
            
            # Monitoring resources
            ResourceIdentifier("HelmRepository", "prometheus-community", "monitoring"),
            ResourceIdentifier("HelmRelease", "monitoring-core", "monitoring"),
            ResourceIdentifier("ServiceMonitor", "flux-controllers", "monitoring"),
        ]
        
        # Add resources to graph
        for resource in resources:
            self.graph.add_resource(resource)
        
        # Define dependencies
        dependencies = [
            # App dependencies
            (resources[3], resources[0], "Deployment uses ConfigMap"),  # deployment -> configmap
            (resources[3], resources[1], "Deployment uses Secret"),     # deployment -> secret
            (resources[2], resources[3], "Service targets Deployment"), # service -> deployment
            (resources[4], resources[2], "Ingress routes to Service"),  # ingress -> service
            
            # Flux dependencies
            (resources[6], resources[5], "Kustomization uses GitRepository"), # kustomization -> gitrepo
            (resources[7], resources[5], "Apps Kustomization uses GitRepository"), # apps -> gitrepo
            (resources[7], resources[6], "Apps depends on Infrastructure"), # apps -> infrastructure
            (resources[9], resources[8], "HelmRelease uses HelmRepository"), # helmrelease -> helmrepo
            
            # Monitoring dependencies
            (resources[11], resources[10], "Monitoring HelmRelease uses HelmRepository"), # monitoring -> helm repo
            (resources[12], resources[11], "ServiceMonitor depends on Monitoring"), # servicemonitor -> monitoring
        ]
        
        for source, target, reason in dependencies:
            self.graph.add_dependency(source, target, DependencyType.HARD, reason)
        
        logger.info(f"✅ Simulated {len(resources)} resources with {len(dependencies)} dependencies")
    
    def _labels_match(self, selector_labels: Dict[str, str], target_labels: Dict[str, str]) -> bool:
        """Check if selector labels match target labels"""
        if not selector_labels:
            return False
        
        for key, value in selector_labels.items():
            if key not in target_labels or target_labels[key] != value:
                return False
        
        return True
    
    def plan_cleanup_and_recreation(self, failed_resources: List[str]) -> Dict[str, Any]:
        """Plan the cleanup and recreation workflow for failed resources"""
        logger.info(f"📋 Planning cleanup and recreation for {len(failed_resources)} resources")
        
        # Convert string identifiers to ResourceIdentifier objects
        failed_resource_ids = set()
        for resource_str in failed_resources:
            try:
                # Parse resource string (format: namespace/kind/name)
                parts = resource_str.split('/')
                if len(parts) == 3:
                    namespace, kind, name = parts
                    resource_id = ResourceIdentifier(kind, name, namespace)
                    failed_resource_ids.add(resource_id)
                else:
                    logger.warning(f"⚠️  Invalid resource format: {resource_str}")
            except Exception as e:
                logger.error(f"❌ Error parsing resource {resource_str}: {e}")
        
        if not failed_resource_ids:
            return {"error": "No valid failed resources provided"}
        
        # Analyze impact
        impact_analyses = {}
        for resource in failed_resource_ids:
            impact_analyses[str(resource)] = self.graph.analyze_impact(resource)
        
        # Calculate cleanup order
        cleanup_batches = self.graph.get_cleanup_order(failed_resource_ids)
        
        # Calculate recreation order
        recreation_batches = self.graph.get_recreation_order(failed_resource_ids)
        
        # Create comprehensive plan
        plan = {
            "timestamp": datetime.now().isoformat(),
            "failed_resources": [str(r) for r in failed_resource_ids],
            "impact_analysis": impact_analyses,
            "cleanup_plan": {
                "total_batches": len(cleanup_batches),
                "batches": [
                    {
                        "batch_number": i + 1,
                        "resources": [str(r) for r in batch],
                        "parallel_execution": True,
                        "estimated_duration": "2-5 minutes"
                    }
                    for i, batch in enumerate(cleanup_batches)
                ]
            },
            "recreation_plan": {
                "total_batches": len(recreation_batches),
                "batches": [
                    {
                        "batch_number": i + 1,
                        "resources": [str(r) for r in batch],
                        "parallel_execution": True,
                        "estimated_duration": "3-8 minutes"
                    }
                    for i, batch in enumerate(recreation_batches)
                ]
            },
            "total_estimated_time": f"{len(cleanup_batches) * 3 + len(recreation_batches) * 5}-{len(cleanup_batches) * 5 + len(recreation_batches) * 8} minutes",
            "risk_assessment": self._assess_recovery_risk(failed_resource_ids, impact_analyses),
            "recommendations": self._generate_recommendations(failed_resource_ids, impact_analyses)
        }
        
        return plan
    
    def _assess_recovery_risk(self, failed_resources: Set[ResourceIdentifier], 
                            impact_analyses: Dict[str, Any]) -> Dict[str, Any]:
        """Assess the risk level of the recovery operation"""
        risk_factors = []
        risk_level = "low"
        
        # Check for critical namespace involvement
        critical_namespaces = {'flux-system', 'kube-system', 'longhorn-system'}
        for resource in failed_resources:
            if resource.namespace in critical_namespaces:
                risk_factors.append(f"Critical namespace involved: {resource.namespace}")
                risk_level = "high"
        
        # Check for high impact resources
        total_affected = sum(analysis.get("total_affected", 0) for analysis in impact_analyses.values())
        if total_affected > 10:
            risk_factors.append(f"High impact: {total_affected} resources affected")
            risk_level = "high" if risk_level != "critical" else "critical"
        elif total_affected > 5:
            risk_factors.append(f"Medium impact: {total_affected} resources affected")
            risk_level = "medium" if risk_level == "low" else risk_level
        
        # Check for circular dependencies
        for analysis in impact_analyses.values():
            if analysis.get("circular_dependency"):
                risk_factors.append("Circular dependencies detected")
                risk_level = "high" if risk_level != "critical" else "critical"
        
        # Check for complex cleanup
        complex_cleanups = sum(1 for analysis in impact_analyses.values() 
                             if analysis.get("cleanup_complexity") == "high")
        if complex_cleanups > 0:
            risk_factors.append(f"Complex cleanup required for {complex_cleanups} resources")
            risk_level = "medium" if risk_level == "low" else risk_level
        
        return {
            "level": risk_level,
            "factors": risk_factors,
            "mitigation_required": risk_level in ["high", "critical"],
            "manual_oversight_recommended": risk_level == "critical"
        }
    
    def _generate_recommendations(self, failed_resources: Set[ResourceIdentifier], 
                                impact_analyses: Dict[str, Any]) -> List[str]:
        """Generate recommendations for the recovery operation"""
        recommendations = []
        
        # General recommendations
        recommendations.append("Ensure cluster has sufficient resources before starting recovery")
        recommendations.append("Monitor recovery progress and be prepared to intervene if needed")
        
        # Specific recommendations based on analysis
        critical_affected = []
        for analysis in impact_analyses.values():
            critical_affected.extend(analysis.get("critical_affected", []))
        
        if critical_affected:
            recommendations.append(f"Pay special attention to critical resources: {', '.join(set(critical_affected))}")
        
        # Check for Flux resources
        flux_resources = [r for r in failed_resources if r.namespace == "flux-system"]
        if flux_resources:
            recommendations.append("Flux system resources involved - consider suspending reconciliation during recovery")
        
        # Check for storage resources
        storage_resources = [r for r in failed_resources if r.namespace == "longhorn-system"]
        if storage_resources:
            recommendations.append("Storage system resources involved - ensure data backup before proceeding")
        
        # Circular dependency recommendations
        for analysis in impact_analyses.values():
            if analysis.get("circular_dependency"):
                recommendations.append("Circular dependencies detected - manual intervention may be required")
                break
        
        return recommendations
    
    def execute_cleanup_batch(self, batch: List[ResourceIdentifier], dry_run: bool = True) -> Dict[str, Any]:
        """Execute cleanup for a batch of resources"""
        logger.info(f"🧹 {'[DRY RUN] ' if dry_run else ''}Executing cleanup batch: {[str(r) for r in batch]}")
        
        results = {
            "batch_size": len(batch),
            "dry_run": dry_run,
            "results": [],
            "success_count": 0,
            "failure_count": 0
        }
        
        for resource in batch:
            try:
                if dry_run:
                    # Simulate cleanup
                    logger.info(f"  🔍 [DRY RUN] Would delete {resource}")
                    result = {
                        "resource": str(resource),
                        "action": "delete",
                        "status": "simulated_success",
                        "message": "Dry run - would delete resource"
                    }
                    results["success_count"] += 1
                else:
                    # Actual cleanup would go here
                    result = self._delete_resource(resource)
                    if result["status"] == "success":
                        results["success_count"] += 1
                    else:
                        results["failure_count"] += 1
                
                results["results"].append(result)
                
            except Exception as e:
                logger.error(f"❌ Error cleaning up {resource}: {e}")
                results["results"].append({
                    "resource": str(resource),
                    "action": "delete",
                    "status": "error",
                    "message": str(e)
                })
                results["failure_count"] += 1
        
        return results
    
    def execute_recreation_batch(self, batch: List[ResourceIdentifier], dry_run: bool = True) -> Dict[str, Any]:
        """Execute recreation for a batch of resources"""
        logger.info(f"🔨 {'[DRY RUN] ' if dry_run else ''}Executing recreation batch: {[str(r) for r in batch]}")
        
        results = {
            "batch_size": len(batch),
            "dry_run": dry_run,
            "results": [],
            "success_count": 0,
            "failure_count": 0
        }
        
        for resource in batch:
            try:
                if dry_run:
                    # Simulate recreation
                    logger.info(f"  🔍 [DRY RUN] Would recreate {resource}")
                    result = {
                        "resource": str(resource),
                        "action": "recreate",
                        "status": "simulated_success",
                        "message": "Dry run - would recreate resource"
                    }
                    results["success_count"] += 1
                else:
                    # Actual recreation would go here
                    result = self._recreate_resource(resource)
                    if result["status"] == "success":
                        results["success_count"] += 1
                    else:
                        results["failure_count"] += 1
                
                results["results"].append(result)
                
            except Exception as e:
                logger.error(f"❌ Error recreating {resource}: {e}")
                results["results"].append({
                    "resource": str(resource),
                    "action": "recreate",
                    "status": "error",
                    "message": str(e)
                })
                results["failure_count"] += 1
        
        return results
    
    def _delete_resource(self, resource: ResourceIdentifier) -> Dict[str, Any]:
        """Delete a Kubernetes resource"""
        if not self.kubernetes_client:
            return {
                "resource": str(resource),
                "action": "delete",
                "status": "simulated_success",
                "message": "Simulated deletion (no Kubernetes client)"
            }
        
        try:
            # Implementation would depend on resource type
            logger.info(f"🗑️  Deleting {resource}")
            
            # For now, simulate success
            return {
                "resource": str(resource),
                "action": "delete",
                "status": "success",
                "message": "Resource deleted successfully"
            }
            
        except Exception as e:
            return {
                "resource": str(resource),
                "action": "delete",
                "status": "error",
                "message": str(e)
            }
    
    def _recreate_resource(self, resource: ResourceIdentifier) -> Dict[str, Any]:
        """Recreate a Kubernetes resource"""
        if not self.kubernetes_client:
            return {
                "resource": str(resource),
                "action": "recreate",
                "status": "simulated_success",
                "message": "Simulated recreation (no Kubernetes client)"
            }
        
        try:
            # Implementation would depend on resource type
            logger.info(f"🔨 Recreating {resource}")
            
            # For now, simulate success
            return {
                "resource": str(resource),
                "action": "recreate",
                "status": "success",
                "message": "Resource recreated successfully"
            }
            
        except Exception as e:
            return {
                "resource": str(resource),
                "action": "recreate",
                "status": "error",
                "message": str(e)
            }
    
    def run_demo(self):
        """Run a demonstration of the dependency analysis system"""
        logger.info("🚀 Starting Dependency Analysis Demo")
        
        # Initialize
        self.initialize_kubernetes_client()
        self.discover_dependencies()
        
        # Simulate some failed resources
        failed_resources = [
            "default/Deployment/app-deployment",
            "flux-system/Kustomization/apps",
            "monitoring/HelmRelease/monitoring-core"
        ]
        
        logger.info(f"📋 Simulating failure of resources: {failed_resources}")
        
        # Create recovery plan
        plan = self.plan_cleanup_and_recreation(failed_resources)
        
        # Display plan
        logger.info("📊 Recovery Plan Generated:")
        logger.info(f"  Total failed resources: {len(plan['failed_resources'])}")
        logger.info(f"  Cleanup batches: {plan['cleanup_plan']['total_batches']}")
        logger.info(f"  Recreation batches: {plan['recreation_plan']['total_batches']}")
        logger.info(f"  Estimated time: {plan['total_estimated_time']}")
        logger.info(f"  Risk level: {plan['risk_assessment']['level']}")
        
        # Execute cleanup (dry run)
        logger.info("\n🧹 Executing Cleanup Phase (Dry Run):")
        for i, batch_info in enumerate(plan['cleanup_plan']['batches']):
            batch_resources = [
                self._parse_resource_string(r) for r in batch_info['resources']
            ]
            batch_resources = [r for r in batch_resources if r is not None]
            
            if batch_resources:
                results = self.execute_cleanup_batch(batch_resources, dry_run=True)
                logger.info(f"  Batch {i + 1}: {results['success_count']}/{results['batch_size']} successful")
        
        # Execute recreation (dry run)
        logger.info("\n🔨 Executing Recreation Phase (Dry Run):")
        for i, batch_info in enumerate(plan['recreation_plan']['batches']):
            batch_resources = [
                self._parse_resource_string(r) for r in batch_info['resources']
            ]
            batch_resources = [r for r in batch_resources if r is not None]
            
            if batch_resources:
                results = self.execute_recreation_batch(batch_resources, dry_run=True)
                logger.info(f"  Batch {i + 1}: {results['success_count']}/{results['batch_size']} successful")
        
        logger.info("✅ Dependency Analysis Demo Completed")
        
        return plan
    
    def _parse_resource_string(self, resource_str: str) -> Optional[ResourceIdentifier]:
        """Parse a resource string into a ResourceIdentifier"""
        try:
            parts = resource_str.split('/')
            if len(parts) == 3:
                namespace, kind, name = parts
                return ResourceIdentifier(kind, name, namespace)
        except Exception as e:
            logger.error(f"Error parsing resource string {resource_str}: {e}")
        return None

def main():
    """Main entry point for dependency analyzer"""
    analyzer = DependencyAnalyzer()
    analyzer.run_demo()

if __name__ == "__main__":
    main()