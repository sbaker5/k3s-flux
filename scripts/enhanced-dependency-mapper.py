#!/usr/bin/env python3
"""
Enhanced Resource Dependency Mapping Tool

This tool provides advanced dependency analysis and visualization capabilities
specifically designed for GitOps resilience patterns.

Requirements addressed:
- 8.1: Impact analysis SHALL identify affected resources
- 8.3: Cascade effects SHALL be analyzed

Features:
- Advanced dependency detection including GitOps-specific patterns
- Interactive visualization with filtering and clustering
- Risk assessment for dependency changes
- Export capabilities for integration with other tools
"""

import json
import argparse
import sys
import subprocess
import logging
from typing import Dict, List, Set, Tuple, Optional, Any
from dataclasses import dataclass, field
from collections import defaultdict, deque
from pathlib import Path
from datetime import datetime
import re

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Try to import optional dependencies
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False
    logger.warning("PyYAML not available. Install with: brew install python3 (may include YAML)")

try:
    import networkx as nx
    HAS_NETWORKX = True
except ImportError:
    HAS_NETWORKX = False
    logger.warning("NetworkX not available. Install with: brew install python3 (may include NetworkX)")

try:
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
    from matplotlib.patches import FancyBboxPatch
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    logger.warning("Matplotlib not available. Install with: brew install python-matplotlib")


@dataclass
class ResourceRef:
    """Enhanced resource reference with GitOps metadata"""
    kind: str
    name: str
    namespace: Optional[str] = None
    api_version: str = "v1"
    labels: Dict[str, str] = field(default_factory=dict)
    annotations: Dict[str, str] = field(default_factory=dict)
    
    def __str__(self):
        if self.namespace:
            return f"{self.kind}/{self.name} (ns: {self.namespace})"
        return f"{self.kind}/{self.name}"
    
    def __hash__(self):
        return hash((self.kind, self.name, self.namespace, self.api_version))
    
    @property
    def is_flux_managed(self) -> bool:
        """Check if resource is managed by Flux"""
        flux_annotations = [
            'kustomize.toolkit.fluxcd.io/',
            'helm.toolkit.fluxcd.io/',
            'source.toolkit.fluxcd.io/'
        ]
        return any(key.startswith(prefix) for prefix in flux_annotations 
                  for key in self.annotations.keys())
    
    @property
    def is_critical_infrastructure(self) -> bool:
        """Check if resource is critical infrastructure"""
        critical_namespaces = {'flux-system', 'kube-system', 'longhorn-system', 'monitoring'}
        critical_kinds = {'Service', 'Ingress', 'PersistentVolume', 'StorageClass'}
        
        return (self.namespace in critical_namespaces or 
                self.kind in critical_kinds or
                self.labels.get('app.kubernetes.io/component') == 'infrastructure')


@dataclass
class DependencyRelation:
    """Enhanced dependency relationship with risk assessment"""
    source: ResourceRef
    target: ResourceRef
    relation_type: str
    field_path: str = ""
    strength: float = 1.0  # 0.0 to 1.0, higher = stronger dependency
    risk_level: str = "low"  # low, medium, high, critical
    description: str = ""
    
    def __str__(self):
        return f"{self.source} --{self.relation_type}({self.strength:.1f})--> {self.target}"

class EnhancedDependencyAnalyzer:
    """Enhanced dependency analyzer with GitOps-specific features"""
    
    def __init__(self):
        self.resources: Dict[ResourceRef, Dict] = {}
        if HAS_NETWORKX:
            self.dependency_graph = nx.DiGraph()
        else:
            self.dependency_graph = self._create_simple_graph()
        self.relations: List[DependencyRelation] = []
        self.risk_assessments: Dict[ResourceRef, Dict] = {}
        
    def _create_simple_graph(self):
        """Create simple graph when NetworkX is not available"""
        class SimpleGraph:
            def __init__(self):
                self.nodes_dict = {}
                self.edges_dict = defaultdict(set)
                self.edge_data = {}
            
            def add_edge(self, source, target, **data):
                self.nodes_dict[source] = True
                self.nodes_dict[target] = True
                self.edges_dict[source].add(target)
                self.edge_data[(source, target)] = data
            
            def nodes(self):
                return list(self.nodes_dict.keys())
            
            def successors(self, node):
                return list(self.edges_dict.get(node, set()))
            
            def predecessors(self, node):
                return [s for s, targets in self.edges_dict.items() if node in targets]
            
            def edges(self, data=False):
                if data:
                    return [(s, t, self.edge_data.get((s, t), {})) 
                           for s, targets in self.edges_dict.items() for t in targets]
                return [(s, t) for s, targets in self.edges_dict.items() for t in targets]
        
        return SimpleGraph()
    
    def load_cluster_resources(self, namespaces: List[str] = None) -> None:
        """Load resources from cluster with enhanced metadata extraction"""
        logger.info("Loading cluster resources with enhanced metadata...")
        
        try:
            # Get all resource types
            result = subprocess.run([
                "kubectl", "api-resources", "--verbs=list", "-o", "name"
            ], capture_output=True, text=True, check=True)
            resource_types = [rt.strip() for rt in result.stdout.strip().split('\n') if rt.strip()]
        except subprocess.CalledProcessError as e:
            logger.error(f"Error getting API resources: {e}")
            return
        
        # Prioritize important resource types
        priority_types = [
            'deployments.apps', 'services', 'configmaps', 'secrets',
            'kustomizations.kustomize.toolkit.fluxcd.io',
            'helmreleases.helm.toolkit.fluxcd.io',
            'gitrepositories.source.toolkit.fluxcd.io',
            'persistentvolumeclaims', 'ingresses.networking.k8s.io'
        ]
        
        # Reorder resource types to process important ones first
        ordered_types = priority_types + [rt for rt in resource_types if rt not in priority_types]
        
        for resource_type in ordered_types:
            if not resource_type.strip():
                continue
            
            try:
                cmd = ["kubectl", "get", resource_type, "-o", "json"]
                if namespaces:
                    for ns in namespaces:
                        cmd.extend(["-n", ns])
                else:
                    cmd.append("--all-namespaces")
                
                result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                data = json.loads(result.stdout)
                
                if data.get("items"):
                    for item in data["items"]:
                        resource_ref = self._create_enhanced_resource_ref(item)
                        self.resources[resource_ref] = item
                        
            except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
                logger.debug(f"Skipping {resource_type}: {e}")
                continue
        
        logger.info(f"Loaded {len(self.resources)} resources")
    
    def load_manifest_files(self, paths: List[str]) -> None:
        """Load resources from manifest files with enhanced parsing"""
        logger.info(f"Loading manifest files from: {paths}")
        
        for path_str in paths:
            path = Path(path_str)
            if path.is_file():
                self._load_yaml_file(path)
            elif path.is_dir():
                # Look for YAML files recursively
                yaml_patterns = ["*.yaml", "*.yml"]
                for pattern in yaml_patterns:
                    for yaml_file in path.rglob(pattern):
                        if not any(skip in str(yaml_file) for skip in [".git", "node_modules", "__pycache__"]):
                            self._load_yaml_file(yaml_file)
        
        logger.info(f"Loaded {len(self.resources)} resources from manifests")
    
    def _create_enhanced_resource_ref(self, resource: Dict) -> ResourceRef:
        """Create enhanced ResourceRef with metadata"""
        metadata = resource.get("metadata", {})
        return ResourceRef(
            kind=resource.get("kind", "Unknown"),
            name=metadata.get("name", "unknown"),
            namespace=metadata.get("namespace"),
            api_version=resource.get("apiVersion", "v1"),
            labels=metadata.get("labels", {}),
            annotations=metadata.get("annotations", {})
        )
    
    def _load_yaml_file(self, file_path: Path) -> None:
        """Load resources from YAML file with enhanced error handling"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()
                
            if HAS_YAML:
                docs = yaml.safe_load_all(content)
                for doc in docs:
                    if doc and isinstance(doc, dict) and doc.get("kind"):
                        resource_ref = self._create_enhanced_resource_ref(doc)
                        self.resources[resource_ref] = doc
            else:
                # Simple parsing for basic YAML
                docs = content.split('---')
                for doc_str in docs:
                    doc_str = doc_str.strip()
                    if not doc_str:
                        continue
                    try:
                        doc = json.loads(doc_str)
                        if doc and isinstance(doc, dict) and doc.get("kind"):
                            resource_ref = self._create_enhanced_resource_ref(doc)
                            self.resources[resource_ref] = doc
                    except json.JSONDecodeError:
                        continue
                        
        except Exception as e:
            logger.warning(f"Could not load {file_path}: {e}")
    
    def analyze_dependencies(self) -> None:
        """Analyze dependencies with enhanced GitOps pattern detection"""
        logger.info("Analyzing dependencies with GitOps patterns...")
        
        for resource_ref, resource_data in self.resources.items():
            self._analyze_enhanced_dependencies(resource_ref, resource_data)
        
        # Build graph
        for relation in self.relations:
            self.dependency_graph.add_edge(
                relation.source, relation.target,
                relation_type=relation.relation_type,
                strength=relation.strength,
                risk_level=relation.risk_level,
                field_path=relation.field_path
            )
        
        # Perform risk assessment
        self._assess_dependency_risks()
        
        logger.info(f"Found {len(self.relations)} dependency relationships") 
   
    def _analyze_enhanced_dependencies(self, resource_ref: ResourceRef, resource_data: Dict) -> None:
        """Enhanced dependency analysis with GitOps patterns"""
        
        # Standard Kubernetes dependencies
        self._analyze_standard_dependencies(resource_ref, resource_data)
        
        # Flux-specific dependencies
        self._analyze_flux_dependencies(resource_ref, resource_data)
        
        # Infrastructure dependencies
        self._analyze_infrastructure_dependencies(resource_ref, resource_data)
    
    def _analyze_standard_dependencies(self, resource_ref: ResourceRef, resource_data: Dict) -> None:
        """Analyze standard Kubernetes dependencies"""
        
        # Owner references
        owner_refs = resource_data.get("metadata", {}).get("ownerReferences", [])
        for owner_ref in owner_refs:
            owner = ResourceRef(
                kind=owner_ref.get("kind"),
                name=owner_ref.get("name"),
                namespace=resource_ref.namespace,
                api_version=owner_ref.get("apiVersion", "v1")
            )
            self.relations.append(DependencyRelation(
                source=owner,
                target=resource_ref,
                relation_type="owns",
                field_path="metadata.ownerReferences",
                strength=1.0,
                risk_level="high",
                description="Owner reference creates strong dependency"
            ))
        
        # Analyze spec for references
        spec = resource_data.get("spec", {})
        self._analyze_spec_references(resource_ref, spec, "spec")
    
    def _analyze_flux_dependencies(self, resource_ref: ResourceRef, resource_data: Dict) -> None:
        """Analyze Flux-specific dependencies"""
        
        spec = resource_data.get("spec", {})
        
        # Kustomization dependencies
        if resource_ref.kind == "Kustomization":
            # Source references
            source_ref = spec.get("sourceRef", {})
            if source_ref:
                source_resource = ResourceRef(
                    kind=source_ref.get("kind", "GitRepository"),
                    name=source_ref.get("name"),
                    namespace=source_ref.get("namespace", resource_ref.namespace),
                    api_version=source_ref.get("apiVersion", "source.toolkit.fluxcd.io/v1")
                )
                self.relations.append(DependencyRelation(
                    source=resource_ref,
                    target=source_resource,
                    relation_type="sources_from",
                    field_path="spec.sourceRef",
                    strength=1.0,
                    risk_level="critical",
                    description="Kustomization depends on source for manifests"
                ))
            
            # dependsOn references
            depends_on = spec.get("dependsOn", [])
            for dep in depends_on:
                dep_resource = ResourceRef(
                    kind="Kustomization",
                    name=dep.get("name"),
                    namespace=dep.get("namespace", resource_ref.namespace),
                    api_version="kustomize.toolkit.fluxcd.io/v1"
                )
                self.relations.append(DependencyRelation(
                    source=resource_ref,
                    target=dep_resource,
                    relation_type="depends_on",
                    field_path="spec.dependsOn",
                    strength=0.9,
                    risk_level="high",
                    description="Explicit Flux dependency"
                ))
        
        # HelmRelease dependencies
        elif resource_ref.kind == "HelmRelease":
            # Chart reference
            chart_ref = spec.get("chart", {}).get("spec", {}).get("sourceRef", {})
            if chart_ref:
                chart_source = ResourceRef(
                    kind=chart_ref.get("kind", "HelmRepository"),
                    name=chart_ref.get("name"),
                    namespace=chart_ref.get("namespace", resource_ref.namespace),
                    api_version=chart_ref.get("apiVersion", "source.toolkit.fluxcd.io/v1")
                )
                self.relations.append(DependencyRelation(
                    source=resource_ref,
                    target=chart_source,
                    relation_type="chart_from",
                    field_path="spec.chart.spec.sourceRef",
                    strength=1.0,
                    risk_level="critical",
                    description="HelmRelease depends on chart source"
                ))
            
            # Values references
            values_from = spec.get("valuesFrom", [])
            for values_ref in values_from:
                values_resource = ResourceRef(
                    kind=values_ref.get("kind", "ConfigMap"),
                    name=values_ref.get("name"),
                    namespace=values_ref.get("namespace", resource_ref.namespace)
                )
                self.relations.append(DependencyRelation(
                    source=resource_ref,
                    target=values_resource,
                    relation_type="values_from",
                    field_path="spec.valuesFrom",
                    strength=0.7,
                    risk_level="medium",
                    description="HelmRelease uses values from resource"
                ))
    
    def _analyze_infrastructure_dependencies(self, resource_ref: ResourceRef, resource_data: Dict) -> None:
        """Analyze infrastructure-specific dependencies"""
        
        # Storage dependencies
        if resource_ref.kind == "PersistentVolumeClaim":
            spec = resource_data.get("spec", {})
            storage_class = spec.get("storageClassName")
            if storage_class:
                sc_resource = ResourceRef(
                    kind="StorageClass",
                    name=storage_class,
                    api_version="storage.k8s.io/v1"
                )
                self.relations.append(DependencyRelation(
                    source=resource_ref,
                    target=sc_resource,
                    relation_type="uses_storage_class",
                    field_path="spec.storageClassName",
                    strength=0.8,
                    risk_level="high",
                    description="PVC depends on StorageClass"
                ))
        
        # Ingress dependencies
        elif resource_ref.kind == "Ingress":
            spec = resource_data.get("spec", {})
            
            # TLS secret dependencies
            tls_configs = spec.get("tls", [])
            for tls_config in tls_configs:
                secret_name = tls_config.get("secretName")
                if secret_name:
                    secret_resource = ResourceRef(
                        kind="Secret",
                        name=secret_name,
                        namespace=resource_ref.namespace
                    )
                    self.relations.append(DependencyRelation(
                        source=resource_ref,
                        target=secret_resource,
                        relation_type="uses_tls_secret",
                        field_path="spec.tls",
                        strength=0.9,
                        risk_level="high",
                        description="Ingress depends on TLS secret"
                    ))
            
            # Service backend dependencies
            rules = spec.get("rules", [])
            for rule in rules:
                http = rule.get("http", {})
                paths = http.get("paths", [])
                for path in paths:
                    backend = path.get("backend", {})
                    service = backend.get("service", {})
                    service_name = service.get("name")
                    if service_name:
                        service_resource = ResourceRef(
                            kind="Service",
                            name=service_name,
                            namespace=resource_ref.namespace
                        )
                        self.relations.append(DependencyRelation(
                            source=resource_ref,
                            target=service_resource,
                            relation_type="routes_to",
                            field_path="spec.rules",
                            strength=0.9,
                            risk_level="high",
                            description="Ingress routes traffic to service"
                        ))   
 
    def _analyze_spec_references(self, resource_ref: ResourceRef, spec: Dict, path: str) -> None:
        """Enhanced spec analysis with risk assessment"""
        
        if not isinstance(spec, dict):
            return
        
        # ConfigMap and Secret references with risk assessment
        for ref_type in ["configMapRef", "secretRef"]:
            if ref_type in spec:
                ref_kind = "ConfigMap" if "configMap" in ref_type else "Secret"
                ref_name = spec[ref_type].get("name")
                if ref_name:
                    ref_resource = ResourceRef(
                        kind=ref_kind,
                        name=ref_name,
                        namespace=resource_ref.namespace
                    )
                    risk_level = "high" if ref_kind == "Secret" else "medium"
                    self.relations.append(DependencyRelation(
                        source=resource_ref,
                        target=ref_resource,
                        relation_type="references",
                        field_path=f"{path}.{ref_type}",
                        strength=0.8,
                        risk_level=risk_level,
                        description=f"Resource references {ref_kind}"
                    ))
        
        # Volume references with enhanced analysis
        volumes = spec.get("volumes", [])
        for i, volume in enumerate(volumes):
            for vol_type in ["configMap", "secret", "persistentVolumeClaim"]:
                if vol_type in volume:
                    ref_kind = {
                        "configMap": "ConfigMap",
                        "secret": "Secret", 
                        "persistentVolumeClaim": "PersistentVolumeClaim"
                    }[vol_type]
                    ref_name = volume[vol_type].get("name")
                    if ref_name:
                        ref_resource = ResourceRef(
                            kind=ref_kind,
                            name=ref_name,
                            namespace=resource_ref.namespace
                        )
                        strength = 0.9 if vol_type == "persistentVolumeClaim" else 0.7
                        risk_level = "high" if vol_type in ["secret", "persistentVolumeClaim"] else "medium"
                        self.relations.append(DependencyRelation(
                            source=resource_ref,
                            target=ref_resource,
                            relation_type="mounts_volume",
                            field_path=f"{path}.volumes[{i}].{vol_type}",
                            strength=strength,
                            risk_level=risk_level,
                            description=f"Resource mounts {ref_kind} as volume"
                        ))
        
        # Recursively analyze nested objects
        for key, value in spec.items():
            if isinstance(value, dict):
                self._analyze_spec_references(resource_ref, value, f"{path}.{key}")
            elif isinstance(value, list):
                for i, item in enumerate(value):
                    if isinstance(item, dict):
                        self._analyze_spec_references(resource_ref, item, f"{path}.{key}[{i}]")
    
    def _assess_dependency_risks(self) -> None:
        """Assess risks for each resource based on its dependencies"""
        logger.info("Assessing dependency risks...")
        
        for resource_ref in self.resources.keys():
            risk_assessment = {
                "total_dependencies": 0,
                "critical_dependencies": 0,
                "high_risk_dependencies": 0,
                "circular_dependencies": [],
                "single_points_of_failure": [],
                "overall_risk": "low"
            }
            
            # Count dependencies by risk level
            for relation in self.relations:
                if relation.source == resource_ref:
                    risk_assessment["total_dependencies"] += 1
                    if relation.risk_level == "critical":
                        risk_assessment["critical_dependencies"] += 1
                    elif relation.risk_level == "high":
                        risk_assessment["high_risk_dependencies"] += 1
            
            # Assess overall risk
            if risk_assessment["critical_dependencies"] > 0:
                risk_assessment["overall_risk"] = "critical"
            elif risk_assessment["high_risk_dependencies"] > 2:
                risk_assessment["overall_risk"] = "high"
            elif risk_assessment["total_dependencies"] > 5:
                risk_assessment["overall_risk"] = "medium"
            
            # Check for single points of failure
            if resource_ref.is_critical_infrastructure:
                dependents_count = len([r for r in self.relations if r.target == resource_ref])
                if dependents_count > 3:
                    risk_assessment["single_points_of_failure"].append(
                        f"Critical resource with {dependents_count} dependents"
                    )
            
            self.risk_assessments[resource_ref] = risk_assessment
    
    def find_enhanced_impact_chain(self, resource_ref: ResourceRef) -> Dict[str, Any]:
        """Enhanced impact analysis with risk assessment"""
        
        if resource_ref not in self.dependency_graph.nodes():
            return {
                "direct_impact": set(),
                "indirect_impact": set(),
                "risk_assessment": "unknown",
                "affected_namespaces": set(),
                "critical_services_affected": [],
                "estimated_recovery_time": "unknown"
            }
        
        # Find impact chains
        direct_impact = set(self.dependency_graph.successors(resource_ref))
        indirect_impact = set()
        affected_namespaces = set()
        critical_services_affected = []
        
        # BFS to find indirect impacts
        visited = set()
        queue = deque(direct_impact)
        
        while queue:
            current = queue.popleft()
            if current in visited:
                continue
            visited.add(current)
            
            if current.namespace:
                affected_namespaces.add(current.namespace)
            
            if current.is_critical_infrastructure:
                critical_services_affected.append(str(current))
            
            successors = set(self.dependency_graph.successors(current))
            for successor in successors:
                if successor not in direct_impact and successor != resource_ref:
                    indirect_impact.add(successor)
                    queue.append(successor)
        
        # Assess overall impact risk
        total_affected = len(direct_impact) + len(indirect_impact)
        if total_affected > 20 or len(critical_services_affected) > 2:
            risk_level = "critical"
            recovery_time = "30-60 minutes"
        elif total_affected > 10 or len(critical_services_affected) > 0:
            risk_level = "high"
            recovery_time = "15-30 minutes"
        elif total_affected > 5:
            risk_level = "medium"
            recovery_time = "5-15 minutes"
        else:
            risk_level = "low"
            recovery_time = "1-5 minutes"
        
        return {
            "direct_impact": direct_impact,
            "indirect_impact": indirect_impact,
            "risk_assessment": risk_level,
            "affected_namespaces": affected_namespaces,
            "critical_services_affected": critical_services_affected,
            "estimated_recovery_time": recovery_time,
            "total_affected": total_affected
        } 
   
    def generate_enhanced_report(self, output_file: str = None) -> str:
        """Generate comprehensive dependency analysis report"""
        
        report_lines = [
            "# Enhanced Resource Dependency Analysis Report",
            f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "",
            f"**Total Resources Analyzed:** {len(self.resources)}",
            f"**Total Dependencies Found:** {len(self.relations)}",
            "",
            "## Executive Summary",
            ""
        ]
        
        # Risk summary
        risk_counts = {"low": 0, "medium": 0, "high": 0, "critical": 0}
        for assessment in self.risk_assessments.values():
            risk_counts[assessment["overall_risk"]] += 1
        
        report_lines.extend([
            f"- **Critical Risk Resources:** {risk_counts['critical']}",
            f"- **High Risk Resources:** {risk_counts['high']}",
            f"- **Medium Risk Resources:** {risk_counts['medium']}",
            f"- **Low Risk Resources:** {risk_counts['low']}",
            ""
        ])
        
        # Flux-managed resources
        flux_managed = [r for r in self.resources.keys() if r.is_flux_managed]
        critical_infra = [r for r in self.resources.keys() if r.is_critical_infrastructure]
        
        report_lines.extend([
            f"- **Flux-Managed Resources:** {len(flux_managed)}",
            f"- **Critical Infrastructure Resources:** {len(critical_infra)}",
            "",
            "## Dependency Analysis by Type",
            ""
        ])
        
        # Group relations by type
        relations_by_type = defaultdict(list)
        for relation in self.relations:
            relations_by_type[relation.relation_type].append(relation)
        
        for rel_type, relations in sorted(relations_by_type.items()):
            report_lines.extend([
                f"### {rel_type.replace('_', ' ').title()} Relations ({len(relations)})",
                ""
            ])
            
            # Show risk distribution for this relation type
            risk_dist = defaultdict(int)
            for rel in relations:
                risk_dist[rel.risk_level] += 1
            
            report_lines.append(f"**Risk Distribution:** Critical: {risk_dist['critical']}, "
                              f"High: {risk_dist['high']}, Medium: {risk_dist['medium']}, "
                              f"Low: {risk_dist['low']}")
            report_lines.append("")
            
            # Show examples
            for relation in sorted(relations, key=lambda r: r.strength, reverse=True)[:5]:
                report_lines.append(f"- {relation} (Risk: {relation.risk_level})")
            if len(relations) > 5:
                report_lines.append(f"- ... and {len(relations) - 5} more")
            report_lines.append("")
        
        # High-risk resources section
        high_risk_resources = [
            (r, a) for r, a in self.risk_assessments.items() 
            if a["overall_risk"] in ["high", "critical"]
        ]
        
        if high_risk_resources:
            report_lines.extend([
                "## ⚠️ High-Risk Resources Requiring Attention",
                ""
            ])
            
            for resource, assessment in sorted(high_risk_resources, 
                                             key=lambda x: x[1]["critical_dependencies"], 
                                             reverse=True)[:10]:
                report_lines.extend([
                    f"### {resource} (Risk: {assessment['overall_risk'].upper()})",
                    f"- **Total Dependencies:** {assessment['total_dependencies']}",
                    f"- **Critical Dependencies:** {assessment['critical_dependencies']}",
                    f"- **High Risk Dependencies:** {assessment['high_risk_dependencies']}",
                ])
                
                if assessment["single_points_of_failure"]:
                    report_lines.append(f"- **SPOF Concerns:** {', '.join(assessment['single_points_of_failure'])}")
                
                report_lines.append("")
        
        # Circular dependencies
        try:
            if HAS_NETWORKX:
                cycles = list(nx.simple_cycles(self.dependency_graph))
            else:
                cycles = self._find_simple_cycles()
            
            if cycles:
                report_lines.extend([
                    "## 🔄 Circular Dependencies Detected",
                    "",
                    "**⚠️ WARNING:** Circular dependencies can cause deployment deadlocks!",
                    ""
                ])
                for i, cycle in enumerate(cycles[:5]):
                    cycle_str = " → ".join(str(r) for r in cycle) + f" → {cycle[0]}"
                    report_lines.append(f"{i+1}. {cycle_str}")
                if len(cycles) > 5:
                    report_lines.append(f"... and {len(cycles) - 5} more cycles")
                report_lines.append("")
        except Exception as e:
            logger.warning(f"Could not detect circular dependencies: {e}")
        
        # Recommendations
        report_lines.extend([
            "## 🎯 Recommendations",
            "",
            "### Immediate Actions",
            "- Review and address circular dependencies",
            "- Implement monitoring for critical infrastructure resources",
            "- Consider backup strategies for single points of failure",
            "",
            "### Long-term Improvements", 
            "- Implement dependency health checks",
            "- Add automated recovery procedures for high-risk dependencies",
            "- Consider resource redundancy for critical services",
            ""
        ])
        
        report = "\n".join(report_lines)
        
        if output_file:
            with open(output_file, 'w') as f:
                f.write(report)
            logger.info(f"Enhanced report saved to {output_file}")
        
        return report    

    def create_enhanced_visualization(self, output_file: str = "enhanced_dependency_graph.png", 
                                    resource_filter: str = None, 
                                    cluster_by_namespace: bool = True) -> None:
        """Create enhanced visualization with risk-based coloring and clustering"""
        
        if not HAS_MATPLOTLIB or not HAS_NETWORKX:
            logger.warning("Enhanced visualization requires matplotlib and networkx")
            self._create_enhanced_text_visualization(output_file.replace('.png', '.txt'), resource_filter)
            return
        
        # Filter graph if requested
        if resource_filter:
            filtered_nodes = [
                node for node in self.dependency_graph.nodes()
                if resource_filter.lower() in str(node).lower()
            ]
            
            # Add connected nodes
            connected_nodes = set(filtered_nodes)
            for node in filtered_nodes:
                connected_nodes.update(self.dependency_graph.predecessors(node))
                connected_nodes.update(self.dependency_graph.successors(node))
            
            graph = self.dependency_graph.subgraph(connected_nodes)
        else:
            graph = self.dependency_graph
        
        if len(graph.nodes()) == 0:
            logger.warning("No nodes to visualize")
            return
        
        # Create figure with subplots for legend
        fig, (ax_main, ax_legend) = plt.subplots(1, 2, figsize=(20, 12), 
                                                gridspec_kw={'width_ratios': [4, 1]})
        
        # Layout with clustering
        if cluster_by_namespace and len(graph.nodes()) > 10:
            # Group nodes by namespace for better layout
            pos = self._create_clustered_layout(graph)
        else:
            pos = nx.spring_layout(graph, k=3, iterations=50)
        
        # Color nodes by risk level and type
        node_colors = []
        node_sizes = []
        risk_color_map = {
            "critical": "#FF4444",  # Red
            "high": "#FF8800",      # Orange  
            "medium": "#FFDD00",    # Yellow
            "low": "#44FF44",       # Green
            "unknown": "#CCCCCC"    # Gray
        }
        
        for node in graph.nodes():
            # Get risk level
            risk_level = self.risk_assessments.get(node, {}).get("overall_risk", "unknown")
            node_colors.append(risk_color_map[risk_level])
            
            # Size based on number of dependencies
            dep_count = len([r for r in self.relations if r.source == node])
            node_sizes.append(max(500, min(2000, 500 + dep_count * 100)))
        
        # Draw nodes
        nx.draw_networkx_nodes(graph, pos, 
                              node_color=node_colors,
                              node_size=node_sizes,
                              alpha=0.8,
                              ax=ax_main)
        
        # Draw edges with different styles based on relationship type
        edge_styles = {
            "owns": {"style": "-", "width": 3, "color": "red"},
            "depends_on": {"style": "-", "width": 2, "color": "blue"},
            "references": {"style": "--", "width": 1, "color": "gray"},
            "sources_from": {"style": "-", "width": 2, "color": "purple"},
            "chart_from": {"style": "-", "width": 2, "color": "orange"},
            "selects": {"style": ":", "width": 1, "color": "green"}
        }
        
        # Group edges by type and draw separately
        edges_by_type = defaultdict(list)
        for source, target, data in graph.edges(data=True):
            rel_type = data.get("relation_type", "references")
            edges_by_type[rel_type].append((source, target))
        
        for rel_type, edges in edges_by_type.items():
            style_info = edge_styles.get(rel_type, {"style": "-", "width": 1, "color": "gray"})
            nx.draw_networkx_edges(graph, pos, edgelist=edges,
                                 style=style_info["style"],
                                 width=style_info["width"],
                                 edge_color=style_info["color"],
                                 alpha=0.6,
                                 arrows=True,
                                 arrowsize=20,
                                 ax=ax_main)
        
        # Add labels
        labels = {}
        for node in graph.nodes():
            # Truncate long names
            name = node.name[:15] + "..." if len(node.name) > 15 else node.name
            labels[node] = f"{node.kind}\n{name}"
        
        nx.draw_networkx_labels(graph, pos, labels, font_size=8, font_weight="bold", ax=ax_main)
        
        # Create legend
        ax_legend.axis('off')
        
        # Risk level legend
        risk_patches = []
        for risk, color in risk_color_map.items():
            if risk != "unknown":
                patch = mpatches.Patch(color=color, label=f"{risk.title()} Risk")
                risk_patches.append(patch)
        
        ax_legend.legend(handles=risk_patches, loc='upper left', title="Risk Levels")
        
        # Relationship type legend
        rel_patches = []
        for rel_type, style_info in edge_styles.items():
            if rel_type in edges_by_type:
                patch = mpatches.Patch(color=style_info["color"], label=rel_type.replace("_", " ").title())
                rel_patches.append(patch)
        
        ax_legend.legend(handles=rel_patches, loc='center left', title="Relationship Types")
        
        # Add statistics
        stats_text = f"""
Statistics:
• Total Resources: {len(graph.nodes())}
• Total Dependencies: {len(graph.edges())}
• Critical Risk: {len([n for n in graph.nodes() if self.risk_assessments.get(n, {}).get('overall_risk') == 'critical'])}
• High Risk: {len([n for n in graph.nodes() if self.risk_assessments.get(n, {}).get('overall_risk') == 'high'])}
• Flux Managed: {len([n for n in graph.nodes() if n.is_flux_managed])}
        """
        ax_legend.text(0.1, 0.3, stats_text, transform=ax_legend.transAxes, 
                      fontsize=10, verticalalignment='top',
                      bbox=dict(boxstyle="round,pad=0.3", facecolor="lightgray", alpha=0.5))
        
        ax_main.set_title("Enhanced Resource Dependency Graph\n(Node size = dependency count, Color = risk level)", 
                         fontsize=16, fontweight='bold')
        ax_main.axis('off')
        
        plt.tight_layout()
        plt.savefig(output_file, dpi=300, bbox_inches='tight')
        logger.info(f"Enhanced dependency graph saved to {output_file}")
        plt.close()
    
    def _create_clustered_layout(self, graph):
        """Create layout with namespace-based clustering"""
        # Group nodes by namespace
        namespace_groups = defaultdict(list)
        for node in graph.nodes():
            ns = node.namespace or "cluster-wide"
            namespace_groups[ns].append(node)
        
        pos = {}
        angle_step = 2 * 3.14159 / len(namespace_groups)
        
        for i, (namespace, nodes) in enumerate(namespace_groups.items()):
            # Position namespace clusters in a circle
            center_x = 5 * self._cos(i * angle_step)
            center_y = 5 * self._sin(i * angle_step)
            
            # Layout nodes within the namespace cluster
            if len(nodes) == 1:
                pos[nodes[0]] = (center_x, center_y)
            else:
                subgraph = graph.subgraph(nodes)
                sub_pos = nx.spring_layout(subgraph, k=1, iterations=30)
                
                # Offset to cluster center
                for node, (x, y) in sub_pos.items():
                    pos[node] = (center_x + x, center_y + y)
        
        return pos
    
    def _cos(self, x):
        """Cosine function fallback"""
        import math
        return math.cos(x)
    
    def _sin(self, x):
        """Sine function fallback"""
        import math
        return math.sin(x)   
 
    def _create_enhanced_text_visualization(self, output_file: str, resource_filter: str = None) -> None:
        """Create enhanced text visualization with risk information"""
        
        nodes = list(self.dependency_graph.nodes())
        if resource_filter:
            nodes = [node for node in nodes if resource_filter.lower() in str(node).lower()]
        
        lines = [
            "# Enhanced Resource Dependency Graph (Text Format)",
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "",
            f"Total Resources: {len(nodes)}",
            f"Total Relations: {len(self.relations)}",
            "",
            "## Risk Summary",
            ""
        ]
        
        # Risk summary
        risk_counts = defaultdict(int)
        for node in nodes:
            risk_level = self.risk_assessments.get(node, {}).get("overall_risk", "unknown")
            risk_counts[risk_level] += 1
        
        for risk_level, count in sorted(risk_counts.items()):
            lines.append(f"- {risk_level.title()}: {count}")
        
        lines.extend(["", "## Resource Dependencies", ""])
        
        # Sort nodes by risk level and dependency count
        def sort_key(node):
            risk_order = {"critical": 0, "high": 1, "medium": 2, "low": 3, "unknown": 4}
            risk_level = self.risk_assessments.get(node, {}).get("overall_risk", "unknown")
            dep_count = len([r for r in self.relations if r.source == node])
            return (risk_order[risk_level], -dep_count)
        
        for node in sorted(nodes, key=sort_key):
            risk_info = self.risk_assessments.get(node, {})
            risk_level = risk_info.get("overall_risk", "unknown")
            
            lines.append(f"### {node} [{risk_level.upper()} RISK]")
            
            if node.is_flux_managed:
                lines.append("**🔄 Flux Managed**")
            if node.is_critical_infrastructure:
                lines.append("**⚡ Critical Infrastructure**")
            
            # Dependencies
            deps = [r for r in self.relations if r.source == node]
            if deps:
                lines.append("**Dependencies:**")
                for dep in sorted(deps, key=lambda r: r.strength, reverse=True):
                    lines.append(f"  - {dep.target} ({dep.relation_type}, "
                               f"strength: {dep.strength:.1f}, risk: {dep.risk_level})")
            
            # Dependents
            dependents = [r for r in self.relations if r.target == node]
            if dependents:
                lines.append("**Dependents:**")
                for dep in sorted(dependents, key=lambda r: r.strength, reverse=True)[:5]:
                    lines.append(f"  - {dep.source} ({dep.relation_type})")
                if len(dependents) > 5:
                    lines.append(f"  - ... and {len(dependents) - 5} more")
            
            lines.append("")
        
        content = "\n".join(lines)
        with open(output_file, 'w') as f:
            f.write(content)
        
        logger.info(f"Enhanced text dependency graph saved to {output_file}")
    
    def _find_simple_cycles(self) -> List[List[ResourceRef]]:
        """Simple cycle detection for basic graph implementation"""
        cycles = []
        visited = set()
        rec_stack = set()
        
        def dfs(node, path):
            if node in rec_stack:
                cycle_start = path.index(node)
                cycle = path[cycle_start:] + [node]
                cycles.append(cycle)
                return
            
            if node in visited:
                return
            
            visited.add(node)
            rec_stack.add(node)
            path.append(node)
            
            for successor in self.dependency_graph.successors(node):
                dfs(successor, path.copy())
            
            rec_stack.remove(node)
        
        for node in self.dependency_graph.nodes():
            if node not in visited:
                dfs(node, [])
        
        return cycles
    
    def export_for_integration(self, output_file: str) -> None:
        """Export dependency data in JSON format for integration with other tools"""
        
        export_data = {
            "metadata": {
                "generated_at": datetime.now().isoformat(),
                "total_resources": len(self.resources),
                "total_relations": len(self.relations)
            },
            "resources": [],
            "relations": [],
            "risk_assessments": {}
        }
        
        # Export resources
        for resource_ref in self.resources.keys():
            export_data["resources"].append({
                "kind": resource_ref.kind,
                "name": resource_ref.name,
                "namespace": resource_ref.namespace,
                "api_version": resource_ref.api_version,
                "is_flux_managed": resource_ref.is_flux_managed,
                "is_critical_infrastructure": resource_ref.is_critical_infrastructure,
                "labels": resource_ref.labels,
                "annotations": dict(list(resource_ref.annotations.items())[:5])  # Limit annotations
            })
        
        # Export relations
        for relation in self.relations:
            export_data["relations"].append({
                "source": {
                    "kind": relation.source.kind,
                    "name": relation.source.name,
                    "namespace": relation.source.namespace
                },
                "target": {
                    "kind": relation.target.kind,
                    "name": relation.target.name,
                    "namespace": relation.target.namespace
                },
                "relation_type": relation.relation_type,
                "strength": relation.strength,
                "risk_level": relation.risk_level,
                "field_path": relation.field_path,
                "description": relation.description
            })
        
        # Export risk assessments
        for resource_ref, assessment in self.risk_assessments.items():
            key = f"{resource_ref.kind}/{resource_ref.name}"
            if resource_ref.namespace:
                key += f"/{resource_ref.namespace}"
            export_data["risk_assessments"][key] = assessment
        
        with open(output_file, 'w') as f:
            json.dump(export_data, f, indent=2, default=str)
        
        logger.info(f"Dependency data exported to {output_file}")


def main():
    parser = argparse.ArgumentParser(description="Enhanced Kubernetes resource dependency analysis")
    parser.add_argument("--cluster", action="store_true", help="Load resources from cluster")
    parser.add_argument("--manifests", nargs="+", help="Load resources from manifest files/directories")
    parser.add_argument("--namespaces", nargs="+", help="Limit analysis to specific namespaces")
    parser.add_argument("--analyze", help="Analyze impact of changes to specific resource (format: kind/name or kind/name/namespace)")
    parser.add_argument("--report", help="Generate enhanced report file")
    parser.add_argument("--visualize", help="Create enhanced dependency graph visualization (PNG file)")
    parser.add_argument("--filter", help="Filter visualization to resources matching this string")
    parser.add_argument("--cluster-by-namespace", action="store_true", default=True, help="Cluster visualization by namespace")
    parser.add_argument("--export", help="Export dependency data as JSON for integration")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    if not args.cluster and not args.manifests:
        print("Error: Must specify either --cluster or --manifests")
        sys.exit(1)
    
    analyzer = EnhancedDependencyAnalyzer()
    
    # Load resources
    if args.cluster:
        analyzer.load_cluster_resources(args.namespaces)
    
    if args.manifests:
        analyzer.load_manifest_files(args.manifests)
    
    # Analyze dependencies
    analyzer.analyze_dependencies()
    
    # Specific resource analysis
    if args.analyze:
        parts = args.analyze.split("/")
        if len(parts) < 2:
            print("Error: Resource format should be kind/name or kind/name/namespace")
            sys.exit(1)
        
        resource_ref = ResourceRef(
            kind=parts[0],
            name=parts[1],
            namespace=parts[2] if len(parts) > 2 else None
        )
        
        print(f"\n=== Enhanced Impact Analysis for {resource_ref} ===")
        
        impact_analysis = analyzer.find_enhanced_impact_chain(resource_ref)
        
        print(f"\n📊 Impact Summary:")
        print(f"  • Risk Level: {impact_analysis['risk_assessment'].upper()}")
        print(f"  • Total Affected Resources: {impact_analysis['total_affected']}")
        print(f"  • Estimated Recovery Time: {impact_analysis['estimated_recovery_time']}")
        print(f"  • Affected Namespaces: {len(impact_analysis['affected_namespaces'])}")
        
        if impact_analysis['critical_services_affected']:
            print(f"\n⚠️  Critical Services Affected:")
            for service in impact_analysis['critical_services_affected']:
                print(f"    - {service}")
        
        print(f"\n🔗 Direct Impact ({len(impact_analysis['direct_impact'])}):")
        for resource in sorted(impact_analysis['direct_impact'], key=str):
            risk = analyzer.risk_assessments.get(resource, {}).get('overall_risk', 'unknown')
            print(f"  - {resource} (Risk: {risk})")
        
        print(f"\n🔗 Indirect Impact ({len(impact_analysis['indirect_impact'])}):")
        for resource in sorted(list(impact_analysis['indirect_impact'])[:10], key=str):
            risk = analyzer.risk_assessments.get(resource, {}).get('overall_risk', 'unknown')
            print(f"  - {resource} (Risk: {risk})")
        
        if len(impact_analysis['indirect_impact']) > 10:
            print(f"  - ... and {len(impact_analysis['indirect_impact']) - 10} more")
    
    # Generate enhanced report
    if args.report:
        analyzer.generate_enhanced_report(args.report)
    
    # Create enhanced visualization
    if args.visualize:
        try:
            analyzer.create_enhanced_visualization(
                args.visualize, 
                args.filter, 
                args.cluster_by_namespace
            )
        except Exception as e:
            logger.error(f"Could not create visualization: {e}")
    
    # Export data
    if args.export:
        analyzer.export_for_integration(args.export)


if __name__ == "__main__":
    main()