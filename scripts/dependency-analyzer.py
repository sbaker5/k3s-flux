#!/usr/bin/env python3
"""
Resource Dependency Mapping Tool

This tool analyzes Kubernetes resources to build dependency graphs and identify
cascade effects for change impact analysis.

Requirements addressed:
- 8.1: Impact analysis SHALL identify affected resources
- 8.3: Cascade effects SHALL be analyzed
"""

import json
import argparse
import sys
import subprocess
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field
from collections import defaultdict, deque
from pathlib import Path

# Try to import optional dependencies
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False
    print("Warning: PyYAML not available. Install with: brew install python3 (may include YAML)")

try:
    import networkx as nx
    HAS_NETWORKX = True
except ImportError:
    HAS_NETWORKX = False
    print("Warning: NetworkX not available. Install with: brew install python3 (may include NetworkX)")

try:
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("Warning: Matplotlib not available. Install with: brew install python-matplotlib")


@dataclass
class ResourceRef:
    """Represents a Kubernetes resource reference"""
    kind: str
    name: str
    namespace: Optional[str] = None
    api_version: str = "v1"
    
    def __str__(self):
        if self.namespace:
            return f"{self.kind}/{self.name} (ns: {self.namespace})"
        return f"{self.kind}/{self.name}"
    
    def __hash__(self):
        return hash((self.kind, self.name, self.namespace, self.api_version))


@dataclass
class DependencyRelation:
    """Represents a dependency relationship between resources"""
    source: ResourceRef
    target: ResourceRef
    relation_type: str  # "owns", "references", "depends_on", "selects"
    field_path: str = ""
    
    def __str__(self):
        return f"{self.source} --{self.relation_type}--> {self.target}"


@dataclass
class ResourceNode:
    """Represents a resource in the dependency graph"""
    resource: ResourceRef
    dependencies: Set[ResourceRef] = field(default_factory=set)
    dependents: Set[ResourceRef] = field(default_factory=set)
    metadata: Dict = field(default_factory=dict)


class SimpleDependencyGraph:
    """Simple dependency graph implementation when NetworkX is not available"""
    
    def __init__(self):
        self.nodes_set: Set[ResourceRef] = set()
        self.edges: Dict[ResourceRef, Set[ResourceRef]] = defaultdict(set)
        self.edge_data: Dict[Tuple[ResourceRef, ResourceRef], Dict] = {}
    
    def add_edge(self, source: ResourceRef, target: ResourceRef, **data):
        self.nodes_set.add(source)
        self.nodes_set.add(target)
        self.edges[source].add(target)
        self.edge_data[(source, target)] = data
    
    def nodes(self):
        return list(self.nodes_set)
    
    def successors(self, node: ResourceRef):
        return list(self.edges.get(node, set()))
    
    def predecessors(self, node: ResourceRef):
        predecessors = []
        for source, targets in self.edges.items():
            if node in targets:
                predecessors.append(source)
        return predecessors
    
    def edges_data(self, data=False):
        if data:
            return [(source, target, self.edge_data.get((source, target), {})) 
                   for source, targets in self.edges.items() 
                   for target in targets]
        else:
            return [(source, target) 
                   for source, targets in self.edges.items() 
                   for target in targets]


class DependencyAnalyzer:
    """Analyzes Kubernetes resources to build dependency graphs"""
    
    def __init__(self):
        self.resources: Dict[ResourceRef, Dict] = {}
        if HAS_NETWORKX:
            self.dependency_graph = nx.DiGraph()
        else:
            self.dependency_graph = SimpleDependencyGraph()
        self.relations: List[DependencyRelation] = []
        
    def load_cluster_resources(self, namespaces: List[str] = None) -> None:
        """Load resources from the cluster"""
        print("Loading cluster resources...")
        
        # Get all resource types
        try:
            result = subprocess.run([
                "kubectl", "api-resources", "--verbs=list", "-o", "name"
            ], capture_output=True, text=True, check=True)
            resource_types = result.stdout.strip().split('\n')
        except subprocess.CalledProcessError as e:
            print(f"Error getting API resources: {e}")
            return
            
        # Load resources for each type
        for resource_type in resource_types:
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
                        resource_ref = self._create_resource_ref(item)
                        self.resources[resource_ref] = item
                        
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                # Skip resources we can't access or parse
                continue
                
        print(f"Loaded {len(self.resources)} resources")
    
    def load_manifest_files(self, paths: List[str]) -> None:
        """Load resources from YAML manifest files"""
        print(f"Loading manifest files from: {paths}")
        
        for path_str in paths:
            path = Path(path_str)
            if path.is_file():
                self._load_yaml_file(path)
            elif path.is_dir():
                for yaml_file in path.rglob("*.yaml"):
                    if not any(skip in str(yaml_file) for skip in [".git", "node_modules"]):
                        self._load_yaml_file(yaml_file)
                        
        print(f"Loaded {len(self.resources)} resources from manifests")
    
    def _load_yaml_file(self, file_path: Path) -> None:
        """Load resources from a single YAML file"""
        try:
            with open(file_path, 'r') as f:
                if HAS_YAML:
                    docs = yaml.safe_load_all(f)
                    for doc in docs:
                        if doc and isinstance(doc, dict) and doc.get("kind"):
                            resource_ref = self._create_resource_ref(doc)
                            self.resources[resource_ref] = doc
                else:
                    # Simple YAML parsing for basic cases
                    content = f.read()
                    # Split on document separators
                    docs = content.split('---')
                    for doc_str in docs:
                        doc_str = doc_str.strip()
                        if not doc_str:
                            continue
                        try:
                            # Try to parse as JSON (which is valid YAML)
                            doc = json.loads(doc_str)
                            if doc and isinstance(doc, dict) and doc.get("kind"):
                                resource_ref = self._create_resource_ref(doc)
                                self.resources[resource_ref] = doc
                        except json.JSONDecodeError:
                            # Skip documents we can't parse
                            continue
        except Exception as e:
            print(f"Warning: Could not load {file_path}: {e}")
    
    def _create_resource_ref(self, resource: Dict) -> ResourceRef:
        """Create a ResourceRef from a Kubernetes resource"""
        return ResourceRef(
            kind=resource.get("kind", "Unknown"),
            name=resource.get("metadata", {}).get("name", "unknown"),
            namespace=resource.get("metadata", {}).get("namespace"),
            api_version=resource.get("apiVersion", "v1")
        )
    
    def analyze_dependencies(self) -> None:
        """Analyze all resources to build dependency relationships"""
        print("Analyzing dependencies...")
        
        for resource_ref, resource_data in self.resources.items():
            self._analyze_resource_dependencies(resource_ref, resource_data)
            
        # Build NetworkX graph
        for relation in self.relations:
            self.dependency_graph.add_edge(
                relation.source, relation.target,
                relation_type=relation.relation_type,
                field_path=relation.field_path
            )
            
        print(f"Found {len(self.relations)} dependency relationships")
    
    def _analyze_resource_dependencies(self, resource_ref: ResourceRef, resource_data: Dict) -> None:
        """Analyze a single resource for dependencies"""
        
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
                field_path="metadata.ownerReferences"
            ))
        
        # Analyze spec for references
        spec = resource_data.get("spec", {})
        self._analyze_spec_references(resource_ref, spec, "spec")
    
    def _analyze_spec_references(self, resource_ref: ResourceRef, spec: Dict, path: str) -> None:
        """Analyze spec section for resource references"""
        
        if not isinstance(spec, dict):
            return
            
        # Service references
        if "serviceName" in spec:
            service_ref = ResourceRef(
                kind="Service",
                name=spec["serviceName"],
                namespace=resource_ref.namespace
            )
            self.relations.append(DependencyRelation(
                source=resource_ref,
                target=service_ref,
                relation_type="references",
                field_path=f"{path}.serviceName"
            ))
        
        # ConfigMap and Secret references
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
                    self.relations.append(DependencyRelation(
                        source=resource_ref,
                        target=ref_resource,
                        relation_type="references",
                        field_path=f"{path}.{ref_type}"
                    ))
        
        # Volume references
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
                        self.relations.append(DependencyRelation(
                            source=resource_ref,
                            target=ref_resource,
                            relation_type="references",
                            field_path=f"{path}.volumes[{i}].{vol_type}"
                        ))
        
        # Selector dependencies
        selector = spec.get("selector", {})
        if selector and resource_ref.kind in ["Service", "Deployment", "ReplicaSet"]:
            # This creates implicit dependencies on pods with matching labels
            # We'll mark this as a special "selects" relationship
            match_labels = selector.get("matchLabels", {})
            if match_labels:
                # Find resources that would match this selector
                for other_ref, other_data in self.resources.items():
                    if other_ref.kind == "Pod" and other_ref.namespace == resource_ref.namespace:
                        pod_labels = other_data.get("metadata", {}).get("labels", {})
                        if all(pod_labels.get(k) == v for k, v in match_labels.items()):
                            self.relations.append(DependencyRelation(
                                source=resource_ref,
                                target=other_ref,
                                relation_type="selects",
                                field_path=f"{path}.selector"
                            ))
        
        # Recursively analyze nested objects
        for key, value in spec.items():
            if isinstance(value, dict):
                self._analyze_spec_references(resource_ref, value, f"{path}.{key}")
            elif isinstance(value, list):
                for i, item in enumerate(value):
                    if isinstance(item, dict):
                        self._analyze_spec_references(resource_ref, item, f"{path}.{key}[{i}]")
    
    def find_impact_chain(self, resource_ref: ResourceRef) -> Dict[str, Set[ResourceRef]]:
        """Find all resources that would be impacted by changes to the given resource"""
        
        if resource_ref not in self.dependency_graph:
            return {"direct": set(), "indirect": set()}
        
        # Direct dependents (resources that directly depend on this one)
        direct_dependents = set(self.dependency_graph.successors(resource_ref))
        
        # Indirect dependents (cascade effects)
        indirect_dependents = set()
        visited = set()
        queue = deque(direct_dependents)
        
        while queue:
            current = queue.popleft()
            if current in visited:
                continue
            visited.add(current)
            
            successors = set(self.dependency_graph.successors(current))
            for successor in successors:
                if successor not in direct_dependents and successor != resource_ref:
                    indirect_dependents.add(successor)
                    queue.append(successor)
        
        return {
            "direct": direct_dependents,
            "indirect": indirect_dependents
        }
    
    def find_dependency_chain(self, resource_ref: ResourceRef) -> Dict[str, Set[ResourceRef]]:
        """Find all resources that the given resource depends on"""
        
        if resource_ref not in self.dependency_graph:
            return {"direct": set(), "indirect": set()}
        
        # Direct dependencies
        direct_deps = set(self.dependency_graph.predecessors(resource_ref))
        
        # Indirect dependencies
        indirect_deps = set()
        visited = set()
        queue = deque(direct_deps)
        
        while queue:
            current = queue.popleft()
            if current in visited:
                continue
            visited.add(current)
            
            predecessors = set(self.dependency_graph.predecessors(current))
            for predecessor in predecessors:
                if predecessor not in direct_deps and predecessor != resource_ref:
                    indirect_deps.add(predecessor)
                    queue.append(predecessor)
        
        return {
            "direct": direct_deps,
            "indirect": indirect_deps
        }
    
    def generate_report(self, output_file: str = None) -> str:
        """Generate a dependency analysis report"""
        
        report_lines = [
            "# Resource Dependency Analysis Report",
            "",
            f"**Total Resources Analyzed:** {len(self.resources)}",
            f"**Total Dependencies Found:** {len(self.relations)}",
            "",
            "## Dependency Summary by Type",
            ""
        ]
        
        # Group relations by type
        relations_by_type = defaultdict(list)
        for relation in self.relations:
            relations_by_type[relation.relation_type].append(relation)
        
        for rel_type, relations in relations_by_type.items():
            report_lines.extend([
                f"### {rel_type.title()} Relations ({len(relations)})",
                ""
            ])
            for relation in relations[:10]:  # Show first 10
                report_lines.append(f"- {relation}")
            if len(relations) > 10:
                report_lines.append(f"- ... and {len(relations) - 10} more")
            report_lines.append("")
        
        # Find resources with most dependencies
        dependency_counts = defaultdict(int)
        for relation in self.relations:
            dependency_counts[relation.source] += 1
        
        if dependency_counts:
            report_lines.extend([
                "## Resources with Most Dependencies",
                ""
            ])
            sorted_deps = sorted(dependency_counts.items(), key=lambda x: x[1], reverse=True)
            for resource, count in sorted_deps[:10]:
                report_lines.append(f"- {resource}: {count} dependencies")
            report_lines.append("")
        
        # Find potential circular dependencies
        try:
            if HAS_NETWORKX:
                cycles = list(nx.simple_cycles(self.dependency_graph))
            else:
                cycles = self._find_simple_cycles()
                
            if cycles:
                report_lines.extend([
                    "## ⚠️ Potential Circular Dependencies",
                    ""
                ])
                for cycle in cycles[:5]:  # Show first 5 cycles
                    cycle_str = " -> ".join(str(r) for r in cycle)
                    report_lines.append(f"- {cycle_str}")
                if len(cycles) > 5:
                    report_lines.append(f"- ... and {len(cycles) - 5} more cycles")
                report_lines.append("")
        except:
            # Cycle detection might fail on very large graphs
            pass
        
        report = "\n".join(report_lines)
        
        if output_file:
            with open(output_file, 'w') as f:
                f.write(report)
            print(f"Report saved to {output_file}")
        
        return report
    
    def visualize_dependencies(self, resource_filter: str = None, output_file: str = "dependency_graph.png") -> None:
        """Create a visual representation of the dependency graph"""
        
        if not HAS_MATPLOTLIB or not HAS_NETWORKX:
            print("Visualization requires matplotlib and networkx packages")
            print("Install with: pip3 install matplotlib networkx")
            self._create_text_visualization(resource_filter, output_file.replace('.png', '.txt'))
            return
        
        # Filter graph if requested
        if resource_filter:
            # Create subgraph with resources matching the filter
            filtered_nodes = [
                node for node in self.dependency_graph.nodes()
                if resource_filter.lower() in str(node).lower()
            ]
            
            # Add connected nodes
            connected_nodes = set(filtered_nodes)
            for node in filtered_nodes:
                connected_nodes.update(self.dependency_graph.predecessors(node))
                connected_nodes.update(self.dependency_graph.successors(node))
            
            if HAS_NETWORKX:
                graph = self.dependency_graph.subgraph(connected_nodes)
            else:
                # For simple graph, just use the filtered nodes
                graph = self.dependency_graph
        else:
            graph = self.dependency_graph
        
        if len(graph.nodes()) == 0:
            print("No nodes to visualize")
            return
        
        # Create visualization
        plt.figure(figsize=(16, 12))
        
        # Use spring layout for better visualization
        pos = nx.spring_layout(graph, k=3, iterations=50)
        
        # Color nodes by resource type
        node_colors = []
        color_map = {
            "Deployment": "lightblue",
            "Service": "lightgreen", 
            "ConfigMap": "lightyellow",
            "Secret": "lightcoral",
            "PersistentVolumeClaim": "lightpink",
            "Pod": "lightgray"
        }
        
        for node in graph.nodes():
            node_colors.append(color_map.get(node.kind, "white"))
        
        # Draw the graph
        nx.draw(graph, pos, 
                node_color=node_colors,
                node_size=1000,
                font_size=8,
                font_weight="bold",
                arrows=True,
                arrowsize=20,
                edge_color="gray",
                with_labels=True,
                labels={node: f"{node.kind}\n{node.name}" for node in graph.nodes()})
        
        # Add edge labels for relation types
        edge_labels = {}
        for source, target, data in graph.edges(data=True):
            edge_labels[(source, target)] = data.get("relation_type", "")
        
        nx.draw_networkx_edge_labels(graph, pos, edge_labels, font_size=6)
        
        plt.title("Resource Dependency Graph")
        plt.axis('off')
        plt.tight_layout()
        plt.savefig(output_file, dpi=300, bbox_inches='tight')
        print(f"Dependency graph saved to {output_file}")
        plt.close()
    
    def _create_text_visualization(self, resource_filter: str = None, output_file: str = "dependency_graph.txt") -> None:
        """Create a text-based visualization when matplotlib is not available"""
        
        nodes = self.dependency_graph.nodes()
        if resource_filter:
            nodes = [node for node in nodes if resource_filter.lower() in str(node).lower()]
        
        lines = [
            "# Resource Dependency Graph (Text Format)",
            "",
            f"Total Resources: {len(nodes)}",
            f"Total Relations: {len(self.relations)}",
            "",
            "## Dependencies",
            ""
        ]
        
        for node in sorted(nodes, key=str):
            lines.append(f"### {node}")
            
            # Dependencies (what this resource depends on)
            deps = self.dependency_graph.predecessors(node)
            if deps:
                lines.append("**Dependencies:**")
                for dep in sorted(deps, key=str):
                    lines.append(f"  - {dep}")
            
            # Dependents (what depends on this resource)
            dependents = self.dependency_graph.successors(node)
            if dependents:
                lines.append("**Dependents:**")
                for dependent in sorted(dependents, key=str):
                    lines.append(f"  - {dependent}")
            
            lines.append("")
        
        content = "\n".join(lines)
        with open(output_file, 'w') as f:
            f.write(content)
        
        print(f"Text dependency graph saved to {output_file}")
    
    def _find_simple_cycles(self) -> List[List[ResourceRef]]:
        """Simple cycle detection when NetworkX is not available"""
        cycles = []
        visited = set()
        rec_stack = set()
        
        def dfs(node, path):
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
            
            for successor in self.dependency_graph.successors(node):
                dfs(successor, path.copy())
            
            rec_stack.remove(node)
        
        for node in self.dependency_graph.nodes():
            if node not in visited:
                dfs(node, [])
        
        return cycles


def main():
    parser = argparse.ArgumentParser(description="Analyze Kubernetes resource dependencies")
    parser.add_argument("--cluster", action="store_true", 
                       help="Load resources from cluster")
    parser.add_argument("--manifests", nargs="+", 
                       help="Load resources from manifest files/directories")
    parser.add_argument("--namespaces", nargs="+", 
                       help="Limit analysis to specific namespaces")
    parser.add_argument("--analyze", 
                       help="Analyze impact of changes to specific resource (format: kind/name or kind/name/namespace)")
    parser.add_argument("--report", 
                       help="Generate report file")
    parser.add_argument("--visualize", 
                       help="Create dependency graph visualization (PNG file)")
    parser.add_argument("--filter", 
                       help="Filter visualization to resources matching this string")
    
    args = parser.parse_args()
    
    if not args.cluster and not args.manifests:
        print("Error: Must specify either --cluster or --manifests")
        sys.exit(1)
    
    analyzer = DependencyAnalyzer()
    
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
        
        print(f"\n=== Impact Analysis for {resource_ref} ===")
        
        impact_chain = analyzer.find_impact_chain(resource_ref)
        dependency_chain = analyzer.find_dependency_chain(resource_ref)
        
        print(f"\nDirect Dependencies ({len(dependency_chain['direct'])}):")
        for dep in sorted(dependency_chain['direct'], key=str):
            print(f"  - {dep}")
        
        print(f"\nIndirect Dependencies ({len(dependency_chain['indirect'])}):")
        for dep in sorted(dependency_chain['indirect'], key=str):
            print(f"  - {dep}")
        
        print(f"\nDirect Impact ({len(impact_chain['direct'])}):")
        for imp in sorted(impact_chain['direct'], key=str):
            print(f"  - {imp}")
        
        print(f"\nIndirect Impact ({len(impact_chain['indirect'])}):")
        for imp in sorted(impact_chain['indirect'], key=str):
            print(f"  - {imp}")
        
        total_impact = len(impact_chain['direct']) + len(impact_chain['indirect'])
        print(f"\n⚠️  Total resources that could be affected: {total_impact}")
    
    # Generate report
    if args.report:
        analyzer.generate_report(args.report)
    
    # Create visualization
    if args.visualize:
        try:
            analyzer.visualize_dependencies(args.filter, args.visualize)
        except ImportError:
            print("Warning: matplotlib not available, skipping visualization")
        except Exception as e:
            print(f"Warning: Could not create visualization: {e}")


if __name__ == "__main__":
    main()