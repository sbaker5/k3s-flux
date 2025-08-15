#!/bin/bash
set -euo pipefail

# Resource Dependency Analysis Script
# 
# This script provides easy-to-use commands for analyzing Kubernetes resource
# dependencies and understanding change impact.
#
# Requirements addressed:
# - 8.1: Impact analysis SHALL identify affected resources  
# - 8.3: Cascade effects SHALL be analyzed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZER_SCRIPT="$SCRIPT_DIR/dependency-analyzer.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
OUTPUT_DIR="$SCRIPT_DIR/../reports/dependency-analysis"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

usage() {
    cat << EOF
Resource Dependency Analysis Tool

USAGE:
    $0 <command> [options]

COMMANDS:
    cluster-analysis    Analyze all resources in the cluster
    manifest-analysis   Analyze resources from manifest files
    impact-analysis     Analyze impact of changes to a specific resource
    visualize          Create dependency graph visualization
    help               Show this help message

OPTIONS:
    --namespaces NS1,NS2    Limit analysis to specific namespaces
    --manifests PATH1,PATH2 Analyze manifest files/directories
    --resource KIND/NAME    Specific resource to analyze (format: kind/name or kind/name/namespace)
    --filter PATTERN        Filter visualization to resources matching pattern
    --output-dir DIR        Output directory for reports (default: $OUTPUT_DIR)

EXAMPLES:
    # Analyze entire cluster
    $0 cluster-analysis

    # Analyze specific namespaces
    $0 cluster-analysis --namespaces flux-system,monitoring

    # Analyze manifest files
    $0 manifest-analysis --manifests infrastructure/,apps/

    # Analyze impact of changing a deployment
    $0 impact-analysis --resource Deployment/nginx-ingress-controller/nginx-ingress

    # Create visualization of monitoring namespace
    $0 visualize --namespaces monitoring --filter monitoring

    # Analyze manifests and create full report
    $0 manifest-analysis --manifests . --output-dir ./reports
EOF
}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" >&2
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

check_dependencies() {
    local missing_deps=()
    
    # Check for Python
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi
    
    # Check Python packages
    if ! python3 -c "import yaml, networkx, matplotlib" &> /dev/null; then
        warn "Some Python packages may be missing. Install with:"
        warn "  brew install python-matplotlib"
        warn "  For YAML and NetworkX, they may be included with brew python3"
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please install missing dependencies and try again"
        exit 1
    fi
}

setup_output_dir() {
    local output_dir="$1"
    mkdir -p "$output_dir"
    log "Output directory: $output_dir"
}

cluster_analysis() {
    local namespaces=""
    local output_dir="$OUTPUT_DIR/cluster-$TIMESTAMP"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespaces)
                namespaces="$2"
                shift 2
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    setup_output_dir "$output_dir"
    
    log "Starting cluster dependency analysis..."
    
    # Build command
    local cmd_args=(
        "$ANALYZER_SCRIPT"
        --cluster
        --report "$output_dir/dependency-report.md"
        --visualize "$output_dir/dependency-graph.png"
    )
    
    if [[ -n "$namespaces" ]]; then
        IFS=',' read -ra NS_ARRAY <<< "$namespaces"
        cmd_args+=(--namespaces "${NS_ARRAY[@]}")
        log "Analyzing namespaces: $namespaces"
    else
        log "Analyzing all namespaces"
    fi
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        log "Cluster analysis completed successfully"
        log "Report: $output_dir/dependency-report.md"
        log "Graph: $output_dir/dependency-graph.png"
    else
        error "Cluster analysis failed"
        exit 1
    fi
}

manifest_analysis() {
    local manifests=""
    local output_dir="$OUTPUT_DIR/manifests-$TIMESTAMP"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --manifests)
                manifests="$2"
                shift 2
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$manifests" ]]; then
        error "Must specify --manifests for manifest analysis"
        exit 1
    fi
    
    setup_output_dir "$output_dir"
    
    log "Starting manifest dependency analysis..."
    log "Analyzing manifests: $manifests"
    
    # Build command
    IFS=',' read -ra MANIFEST_ARRAY <<< "$manifests"
    local cmd_args=(
        "$ANALYZER_SCRIPT"
        --manifests "${MANIFEST_ARRAY[@]}"
        --report "$output_dir/dependency-report.md"
        --visualize "$output_dir/dependency-graph.png"
    )
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        log "Manifest analysis completed successfully"
        log "Report: $output_dir/dependency-report.md"
        log "Graph: $output_dir/dependency-graph.png"
    else
        error "Manifest analysis failed"
        exit 1
    fi
}

impact_analysis() {
    local resource=""
    local namespaces=""
    local manifests=""
    local output_dir="$OUTPUT_DIR/impact-$TIMESTAMP"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource)
                resource="$2"
                shift 2
                ;;
            --namespaces)
                namespaces="$2"
                shift 2
                ;;
            --manifests)
                manifests="$2"
                shift 2
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$resource" ]]; then
        error "Must specify --resource for impact analysis"
        exit 1
    fi
    
    setup_output_dir "$output_dir"
    
    log "Starting impact analysis for resource: $resource"
    
    # Build command
    local cmd_args=(
        "$ANALYZER_SCRIPT"
        --analyze "$resource"
        --report "$output_dir/impact-report.md"
    )
    
    # Add data source
    if [[ -n "$manifests" ]]; then
        IFS=',' read -ra MANIFEST_ARRAY <<< "$manifests"
        cmd_args+=(--manifests "${MANIFEST_ARRAY[@]}")
        log "Using manifest files: $manifests"
    else
        cmd_args+=(--cluster)
        log "Using cluster data"
        
        if [[ -n "$namespaces" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespaces"
            cmd_args+=(--namespaces "${NS_ARRAY[@]}")
            log "Limited to namespaces: $namespaces"
        fi
    fi
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        log "Impact analysis completed successfully"
        log "Report: $output_dir/impact-report.md"
    else
        error "Impact analysis failed"
        exit 1
    fi
}

visualize() {
    local namespaces=""
    local manifests=""
    local filter=""
    local output_dir="$OUTPUT_DIR/visualization-$TIMESTAMP"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespaces)
                namespaces="$2"
                shift 2
                ;;
            --manifests)
                manifests="$2"
                shift 2
                ;;
            --filter)
                filter="$2"
                shift 2
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    setup_output_dir "$output_dir"
    
    log "Creating dependency visualization..."
    
    # Build command
    local cmd_args=(
        "$ANALYZER_SCRIPT"
        --visualize "$output_dir/dependency-graph.png"
    )
    
    if [[ -n "$filter" ]]; then
        cmd_args+=(--filter "$filter")
        log "Filtering to resources matching: $filter"
    fi
    
    # Add data source
    if [[ -n "$manifests" ]]; then
        IFS=',' read -ra MANIFEST_ARRAY <<< "$manifests"
        cmd_args+=(--manifests "${MANIFEST_ARRAY[@]}")
        log "Using manifest files: $manifests"
    else
        cmd_args+=(--cluster)
        log "Using cluster data"
        
        if [[ -n "$namespaces" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespaces"
            cmd_args+=(--namespaces "${NS_ARRAY[@]}")
            log "Limited to namespaces: $namespaces"
        fi
    fi
    
    # Run visualization
    if python3 "${cmd_args[@]}"; then
        log "Visualization completed successfully"
        log "Graph: $output_dir/dependency-graph.png"
    else
        error "Visualization failed"
        exit 1
    fi
}

# Main command processing
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

# Check dependencies first
check_dependencies

command="$1"
shift

case "$command" in
    cluster-analysis)
        cluster_analysis "$@"
        ;;
    manifest-analysis)
        manifest_analysis "$@"
        ;;
    impact-analysis)
        impact_analysis "$@"
        ;;
    visualize)
        visualize "$@"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $command"
        usage
        exit 1
        ;;
esac