#!/bin/bash
set -euo pipefail

# Enhanced Resource Dependency Analysis Script
# 
# This script provides advanced dependency analysis with GitOps-specific patterns,
# risk assessment, and enhanced visualization capabilities.
#
# Requirements addressed:
# - 8.1: Impact analysis SHALL identify affected resources  
# - 8.3: Cascade effects SHALL be analyzed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENHANCED_ANALYZER="$SCRIPT_DIR/enhanced-dependency-mapper.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Default values
OUTPUT_DIR="$SCRIPT_DIR/../reports/enhanced-dependency-analysis"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

usage() {
    cat << EOF
Enhanced Resource Dependency Analysis Tool

USAGE:
    $0 <command> [options]

COMMANDS:
    full-analysis       Complete analysis with report, visualization, and export
    cluster-analysis    Analyze all resources in the cluster with risk assessment
    manifest-analysis   Analyze resources from manifest files with GitOps patterns
    impact-analysis     Enhanced impact analysis with recovery time estimation
    risk-assessment     Generate risk assessment report for all resources
    visualize          Create enhanced dependency graph with risk-based coloring
    export             Export dependency data for integration with other tools
    help               Show this help message

OPTIONS:
    --namespaces NS1,NS2    Limit analysis to specific namespaces
    --manifests PATH1,PATH2 Analyze manifest files/directories
    --resource KIND/NAME    Specific resource to analyze (format: kind/name or kind/name/namespace)
    --filter PATTERN        Filter visualization to resources matching pattern
    --output-dir DIR        Output directory for reports (default: $OUTPUT_DIR)
    --cluster-by-namespace  Cluster visualization by namespace (default: true)
    --verbose              Enable verbose logging

EXAMPLES:
    # Complete analysis of entire cluster
    $0 full-analysis

    # Analyze specific namespaces with risk assessment
    $0 cluster-analysis --namespaces flux-system,monitoring

    # Analyze manifest files with GitOps patterns
    $0 manifest-analysis --manifests infrastructure/,apps/

    # Enhanced impact analysis with recovery estimation
    $0 impact-analysis --resource Deployment/nginx-ingress-controller/nginx-ingress

    # Risk assessment for all resources
    $0 risk-assessment --cluster

    # Create enhanced visualization with risk coloring
    $0 visualize --namespaces monitoring --filter prometheus

    # Export data for integration
    $0 export --cluster --output-dir ./integration-data
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

info() {
    echo -e "${BLUE}[INFO] $1${NC}" >&2
}

success() {
    echo -e "${PURPLE}[SUCCESS] $1${NC}" >&2
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
    
    # Check if enhanced analyzer exists
    if [[ ! -f "$ENHANCED_ANALYZER" ]]; then
        error "Enhanced dependency analyzer not found at $ENHANCED_ANALYZER"
        exit 1
    fi
    
    # Check Python packages (optional but recommended)
    if ! python3 -c "import yaml, networkx, matplotlib" &> /dev/null; then
        warn "Some Python packages may be missing for full functionality:"
        warn "  brew install python-matplotlib"
        warn "  For YAML and NetworkX, they may be included with brew python3"
        warn "Basic functionality will still work without these packages."
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

full_analysis() {
    local namespaces=""
    local manifests=""
    local output_dir="$OUTPUT_DIR/full-analysis-$TIMESTAMP"
    local verbose=""
    
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
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --verbose)
                verbose="--verbose"
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    setup_output_dir "$output_dir"
    
    log "Starting comprehensive dependency analysis..."
    
    # Build command
    local cmd_args=(
        "$ENHANCED_ANALYZER"
        --report "$output_dir/enhanced-dependency-report.md"
        --visualize "$output_dir/enhanced-dependency-graph.png"
        --export "$output_dir/dependency-data.json"
    )
    
    if [[ -n "$verbose" ]]; then
        cmd_args+=("$verbose")
    fi
    
    # Add data source
    if [[ -n "$manifests" ]]; then
        IFS=',' read -ra MANIFEST_ARRAY <<< "$manifests"
        cmd_args+=(--manifests "${MANIFEST_ARRAY[@]}")
        log "Analyzing manifests: $manifests"
    else
        cmd_args+=(--cluster)
        log "Analyzing cluster resources"
        
        if [[ -n "$namespaces" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespaces"
            cmd_args+=(--namespaces "${NS_ARRAY[@]}")
            log "Limited to namespaces: $namespaces"
        fi
    fi
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        success "Full analysis completed successfully!"
        echo ""
        info "Generated files:"
        info "  📊 Report: $output_dir/enhanced-dependency-report.md"
        info "  📈 Visualization: $output_dir/enhanced-dependency-graph.png"
        info "  📋 Export Data: $output_dir/dependency-data.json"
        echo ""
        info "Open the report to see risk assessments and recommendations."
    else
        error "Full analysis failed"
        exit 1
    fi
}

cluster_analysis() {
    local namespaces=""
    local output_dir="$OUTPUT_DIR/cluster-$TIMESTAMP"
    local verbose=""
    
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
            --verbose)
                verbose="--verbose"
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    setup_output_dir "$output_dir"
    
    log "Starting enhanced cluster dependency analysis..."
    
    # Build command
    local cmd_args=(
        "$ENHANCED_ANALYZER"
        --cluster
        --report "$output_dir/cluster-dependency-report.md"
        --visualize "$output_dir/cluster-dependency-graph.png"
    )
    
    if [[ -n "$verbose" ]]; then
        cmd_args+=("$verbose")
    fi
    
    if [[ -n "$namespaces" ]]; then
        IFS=',' read -ra NS_ARRAY <<< "$namespaces"
        cmd_args+=(--namespaces "${NS_ARRAY[@]}")
        log "Analyzing namespaces: $namespaces"
    else
        log "Analyzing all namespaces"
    fi
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        success "Cluster analysis completed successfully!"
        info "Report: $output_dir/cluster-dependency-report.md"
        info "Graph: $output_dir/cluster-dependency-graph.png"
    else
        error "Cluster analysis failed"
        exit 1
    fi
}

manifest_analysis() {
    local manifests=""
    local output_dir="$OUTPUT_DIR/manifests-$TIMESTAMP"
    local verbose=""
    
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
            --verbose)
                verbose="--verbose"
                shift
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
    
    log "Starting enhanced manifest dependency analysis..."
    log "Analyzing manifests: $manifests"
    
    # Build command
    IFS=',' read -ra MANIFEST_ARRAY <<< "$manifests"
    local cmd_args=(
        "$ENHANCED_ANALYZER"
        --manifests "${MANIFEST_ARRAY[@]}"
        --report "$output_dir/manifest-dependency-report.md"
        --visualize "$output_dir/manifest-dependency-graph.png"
    )
    
    if [[ -n "$verbose" ]]; then
        cmd_args+=("$verbose")
    fi
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        success "Manifest analysis completed successfully!"
        info "Report: $output_dir/manifest-dependency-report.md"
        info "Graph: $output_dir/manifest-dependency-graph.png"
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
    local verbose=""
    
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
            --verbose)
                verbose="--verbose"
                shift
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
    
    log "Starting enhanced impact analysis for resource: $resource"
    
    # Build command
    local cmd_args=(
        "$ENHANCED_ANALYZER"
        --analyze "$resource"
        --report "$output_dir/impact-report.md"
    )
    
    if [[ -n "$verbose" ]]; then
        cmd_args+=("$verbose")
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
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        success "Enhanced impact analysis completed successfully!"
        info "Report: $output_dir/impact-report.md"
        echo ""
        info "The analysis includes:"
        info "  • Risk level assessment"
        info "  • Recovery time estimation"
        info "  • Critical services impact"
        info "  • Cascade effect analysis"
    else
        error "Impact analysis failed"
        exit 1
    fi
}

risk_assessment() {
    local namespaces=""
    local manifests=""
    local output_dir="$OUTPUT_DIR/risk-assessment-$TIMESTAMP"
    local verbose=""
    
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
            --cluster)
                # Flag to use cluster data
                shift
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --verbose)
                verbose="--verbose"
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    setup_output_dir "$output_dir"
    
    log "Starting comprehensive risk assessment..."
    
    # Build command
    local cmd_args=(
        "$ENHANCED_ANALYZER"
        --report "$output_dir/risk-assessment-report.md"
    )
    
    if [[ -n "$verbose" ]]; then
        cmd_args+=("$verbose")
    fi
    
    # Add data source
    if [[ -n "$manifests" ]]; then
        IFS=',' read -ra MANIFEST_ARRAY <<< "$manifests"
        cmd_args+=(--manifests "${MANIFEST_ARRAY[@]}")
        log "Analyzing manifests: $manifests"
    else
        cmd_args+=(--cluster)
        log "Analyzing cluster resources"
        
        if [[ -n "$namespaces" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespaces"
            cmd_args+=(--namespaces "${NS_ARRAY[@]}")
            log "Limited to namespaces: $namespaces"
        fi
    fi
    
    # Run analysis
    if python3 "${cmd_args[@]}"; then
        success "Risk assessment completed successfully!"
        info "Report: $output_dir/risk-assessment-report.md"
        echo ""
        info "The assessment includes:"
        info "  • Resource risk levels (critical, high, medium, low)"
        info "  • Single points of failure identification"
        info "  • Circular dependency detection"
        info "  • Actionable recommendations"
    else
        error "Risk assessment failed"
        exit 1
    fi
}

visualize() {
    local namespaces=""
    local manifests=""
    local filter=""
    local output_dir="$OUTPUT_DIR/visualization-$TIMESTAMP"
    local cluster_by_namespace="--cluster-by-namespace"
    local verbose=""
    
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
            --no-cluster-by-namespace)
                cluster_by_namespace=""
                shift
                ;;
            --verbose)
                verbose="--verbose"
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    setup_output_dir "$output_dir"
    
    log "Creating enhanced dependency visualization..."
    
    # Build command
    local cmd_args=(
        "$ENHANCED_ANALYZER"
        --visualize "$output_dir/enhanced-dependency-graph.png"
    )
    
    if [[ -n "$filter" ]]; then
        cmd_args+=(--filter "$filter")
        log "Filtering to resources matching: $filter"
    fi
    
    if [[ -n "$cluster_by_namespace" ]]; then
        cmd_args+=("$cluster_by_namespace")
    fi
    
    if [[ -n "$verbose" ]]; then
        cmd_args+=("$verbose")
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
        success "Enhanced visualization completed successfully!"
        info "Graph: $output_dir/enhanced-dependency-graph.png"
        echo ""
        info "Visualization features:"
        info "  • Risk-based node coloring (red=critical, orange=high, yellow=medium, green=low)"
        info "  • Node size based on dependency count"
        info "  • Namespace-based clustering"
        info "  • Relationship type differentiation"
    else
        error "Visualization failed"
        exit 1
    fi
}

export_data() {
    local namespaces=""
    local manifests=""
    local output_dir="$OUTPUT_DIR/export-$TIMESTAMP"
    local verbose=""
    
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
            --cluster)
                # Flag to use cluster data
                shift
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --verbose)
                verbose="--verbose"
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    setup_output_dir "$output_dir"
    
    log "Exporting dependency data for integration..."
    
    # Build command
    local cmd_args=(
        "$ENHANCED_ANALYZER"
        --export "$output_dir/dependency-data.json"
    )
    
    if [[ -n "$verbose" ]]; then
        cmd_args+=("$verbose")
    fi
    
    # Add data source
    if [[ -n "$manifests" ]]; then
        IFS=',' read -ra MANIFEST_ARRAY <<< "$manifests"
        cmd_args+=(--manifests "${MANIFEST_ARRAY[@]}")
        log "Exporting from manifests: $manifests"
    else
        cmd_args+=(--cluster)
        log "Exporting from cluster resources"
        
        if [[ -n "$namespaces" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespaces"
            cmd_args+=(--namespaces "${NS_ARRAY[@]}")
            log "Limited to namespaces: $namespaces"
        fi
    fi
    
    # Run export
    if python3 "${cmd_args[@]}"; then
        success "Data export completed successfully!"
        info "Export file: $output_dir/dependency-data.json"
        echo ""
        info "Export includes:"
        info "  • Resource metadata with GitOps flags"
        info "  • Dependency relationships with risk levels"
        info "  • Risk assessments for all resources"
        info "  • JSON format for easy integration"
    else
        error "Data export failed"
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
    full-analysis)
        full_analysis "$@"
        ;;
    cluster-analysis)
        cluster_analysis "$@"
        ;;
    manifest-analysis)
        manifest_analysis "$@"
        ;;
    impact-analysis)
        impact_analysis "$@"
        ;;
    risk-assessment)
        risk_assessment "$@"
        ;;
    visualize)
        visualize "$@"
        ;;
    export)
        export_data "$@"
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