#!/bin/bash
# Monitoring Service Reference Validation Script
#
# This script validates that service references in documentation match actual
# deployed services, preventing configuration mismatches and outdated documentation.
#
# Usage: ./scripts/validate-monitoring-service-references.sh [--update-docs] [--report]
#   --update-docs: Update documentation with current service names
#   --report: Generate detailed validation report

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="/tmp/service-validation-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/service-validation-$TIMESTAMP.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
UPDATE_DOCS=false
GENERATE_REPORT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --update-docs)
            UPDATE_DOCS=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--update-docs] [--report]"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
}

# Initialize report
init_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        mkdir -p "$REPORT_DIR"
        cat > "$REPORT_FILE" << EOF
# Monitoring Service Reference Validation Report

**Date**: $(date)
**Cluster**: $(kubectl config current-context)
**Validation Script**: $0

## Executive Summary

This report validates that service references in documentation match actual deployed services.

## Validation Results

EOF
    fi
}

# Add to report
add_to_report() {
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo "$*" >> "$REPORT_FILE"
    fi
}

# Get actual service information
get_actual_services() {
    log "Discovering actual monitoring services..."
    
    # Get Prometheus services
    ACTUAL_PROMETHEUS_SERVICES=$(kubectl get services -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    # Get Grafana services
    ACTUAL_GRAFANA_SERVICES=$(kubectl get services -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    # Get all monitoring services for reference
    ALL_MONITORING_SERVICES=$(kubectl get services -n monitoring --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || echo "")
    
    log "Found services:"
    if [[ -n "$ACTUAL_PROMETHEUS_SERVICES" ]]; then
        log "  Prometheus: $ACTUAL_PROMETHEUS_SERVICES"
    else
        warn "  Prometheus: None found"
    fi
    
    if [[ -n "$ACTUAL_GRAFANA_SERVICES" ]]; then
        log "  Grafana: $ACTUAL_GRAFANA_SERVICES"
    else
        warn "  Grafana: None found"
    fi
    
    add_to_report "### Discovered Services"
    add_to_report ""
    add_to_report "**Prometheus Services**: $ACTUAL_PROMETHEUS_SERVICES"
    add_to_report "**Grafana Services**: $ACTUAL_GRAFANA_SERVICES"
    add_to_report ""
    add_to_report "**All Monitoring Services**:"
    if [[ -n "$ALL_MONITORING_SERVICES" ]]; then
        echo "$ALL_MONITORING_SERVICES" | while read -r service; do
            add_to_report "- $service"
        done
    else
        add_to_report "- None found"
    fi
    add_to_report ""
}

# Validate documentation files
validate_documentation_references() {
    log "Validating service references in documentation..."
    local issues=0
    
    add_to_report "### Documentation Validation"
    add_to_report ""
    
    # List of documentation files to check
    local doc_files=(
        "docs/setup/tailscale-remote-access-setup.md"
        "docs/operations/monitoring-system-cleanup.md"
        "docs/architecture-overview.md"
        "README.md"
    )
    
    for doc_file in "${doc_files[@]}"; do
        local full_path="$REPO_ROOT/$doc_file"
        
        if [[ -f "$full_path" ]]; then
            log "Checking $doc_file..."
            add_to_report "#### $doc_file"
            add_to_report ""
            
            # Look for service references
            local found_references=false
            
            # Check for Prometheus service references
            if grep -q "prometheus" "$full_path" 2>/dev/null; then
                found_references=true
                
                # Extract specific service names mentioned
                local mentioned_prometheus=$(grep -o "service/[a-zA-Z0-9-]*prometheus[a-zA-Z0-9-]*" "$full_path" 2>/dev/null | sed 's/service\///' | sort -u || echo "")
                
                if [[ -n "$mentioned_prometheus" ]]; then
                    log "  Found Prometheus service references:"
                    echo "$mentioned_prometheus" | while read -r service; do
                        log "    - $service"
                        add_to_report "- Prometheus service mentioned: \`$service\`"
                        
                        # Check if this service actually exists
                        if echo "$ACTUAL_PROMETHEUS_SERVICES" | grep -q "$service"; then
                            success "      ✅ Service exists"
                            add_to_report "  - ✅ Service exists"
                        else
                            error "      ❌ Service not found"
                            add_to_report "  - ❌ Service not found"
                            issues=$((issues + 1))
                        fi
                    done
                fi
            fi
            
            # Check for Grafana service references
            if grep -q "grafana" "$full_path" 2>/dev/null; then
                found_references=true
                
                # Extract specific service names mentioned
                local mentioned_grafana=$(grep -o "service/[a-zA-Z0-9-]*grafana[a-zA-Z0-9-]*" "$full_path" 2>/dev/null | sed 's/service\///' | sort -u || echo "")
                
                if [[ -n "$mentioned_grafana" ]]; then
                    log "  Found Grafana service references:"
                    echo "$mentioned_grafana" | while read -r service; do
                        log "    - $service"
                        add_to_report "- Grafana service mentioned: \`$service\`"
                        
                        # Check if this service actually exists
                        if echo "$ACTUAL_GRAFANA_SERVICES" | grep -q "$service"; then
                            success "      ✅ Service exists"
                            add_to_report "  - ✅ Service exists"
                        else
                            error "      ❌ Service not found"
                            add_to_report "  - ❌ Service not found"
                            issues=$((issues + 1))
                        fi
                    done
                fi
            fi
            
            # Check for generic port-forward commands
            local port_forward_commands=$(grep -n "kubectl port-forward" "$full_path" 2>/dev/null || echo "")
            if [[ -n "$port_forward_commands" ]]; then
                found_references=true
                log "  Found port-forward commands:"
                echo "$port_forward_commands" | while IFS=':' read -r line_num command; do
                    log "    Line $line_num: $(echo "$command" | xargs)"
                    add_to_report "- Port-forward command (line $line_num): \`$(echo "$command" | xargs)\`"
                done
            fi
            
            if [[ "$found_references" == "false" ]]; then
                log "  No monitoring service references found"
                add_to_report "- No monitoring service references found"
            fi
            
            add_to_report ""
        else
            warn "$doc_file not found"
            add_to_report "#### $doc_file"
            add_to_report "⚠️ File not found"
            add_to_report ""
        fi
    done
    
    return $issues
}

# Validate script references
validate_script_references() {
    log "Validating service references in scripts..."
    local issues=0
    
    add_to_report "### Script Validation"
    add_to_report ""
    
    # List of script files to check
    local script_files=(
        "scripts/monitoring-health-check.sh"
        "scripts/validate-remote-monitoring-access.sh"
        "scripts/monitoring-health-assessment.sh"
    )
    
    for script_file in "${script_files[@]}"; do
        local full_path="$REPO_ROOT/$script_file"
        
        if [[ -f "$full_path" ]]; then
            log "Checking $script_file..."
            add_to_report "#### $script_file"
            add_to_report ""
            
            # Look for hardcoded service names
            local hardcoded_services=$(grep -o "service/[a-zA-Z0-9-]*" "$full_path" 2>/dev/null | sed 's/service\///' | sort -u || echo "")
            
            if [[ -n "$hardcoded_services" ]]; then
                log "  Found hardcoded service references:"
                echo "$hardcoded_services" | while read -r service; do
                    log "    - $service"
                    add_to_report "- Hardcoded service: \`$service\`"
                    
                    # Check if this service exists
                    if echo "$ALL_MONITORING_SERVICES" | grep -q "^$service$"; then
                        success "      ✅ Service exists"
                        add_to_report "  - ✅ Service exists"
                    else
                        error "      ❌ Service not found"
                        add_to_report "  - ❌ Service not found"
                        issues=$((issues + 1))
                    fi
                done
            else
                success "  Uses dynamic service discovery (good practice)"
                add_to_report "✅ Uses dynamic service discovery"
            fi
            
            add_to_report ""
        else
            warn "$script_file not found"
            add_to_report "#### $script_file"
            add_to_report "⚠️ File not found"
            add_to_report ""
        fi
    done
    
    return $issues
}

# Generate service reference template
generate_service_template() {
    log "Generating current service reference template..."
    
    local template_file="/tmp/monitoring-service-references.md"
    
    cat > "$template_file" << EOF
# Current Monitoring Service References

Generated: $(date)
Cluster: $(kubectl config current-context)

## Prometheus Services

EOF
    
    if [[ -n "$ACTUAL_PROMETHEUS_SERVICES" ]]; then
        echo "$ACTUAL_PROMETHEUS_SERVICES" | tr ' ' '\n' | while read -r service; do
            if [[ -n "$service" ]]; then
                local port=$(kubectl get service -n monitoring "$service" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "unknown")
                echo "- **$service**: Port $port" >> "$template_file"
                echo "  \`kubectl port-forward -n monitoring service/$service $port:$port --address=0.0.0.0\`" >> "$template_file"
            fi
        done
    else
        echo "- None found" >> "$template_file"
    fi
    
    cat >> "$template_file" << EOF

## Grafana Services

EOF
    
    if [[ -n "$ACTUAL_GRAFANA_SERVICES" ]]; then
        echo "$ACTUAL_GRAFANA_SERVICES" | tr ' ' '\n' | while read -r service; do
            if [[ -n "$service" ]]; then
                local port=$(kubectl get service -n monitoring "$service" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "unknown")
                echo "- **$service**: Port $port" >> "$template_file"
                echo "  \`kubectl port-forward -n monitoring service/$service 3000:$port --address=0.0.0.0\`" >> "$template_file"
            fi
        done
    else
        echo "- None found" >> "$template_file"
    fi
    
    cat >> "$template_file" << EOF

## All Monitoring Services

EOF
    
    if [[ -n "$ALL_MONITORING_SERVICES" ]]; then
        echo "$ALL_MONITORING_SERVICES" | while read -r service; do
            if [[ -n "$service" ]]; then
                local port=$(kubectl get service -n monitoring "$service" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "unknown")
                local type=$(kubectl get service -n monitoring "$service" -o jsonpath='{.spec.type}' 2>/dev/null || echo "unknown")
                echo "- **$service**: Port $port (Type: $type)" >> "$template_file"
            fi
        done
    else
        echo "- None found" >> "$template_file"
    fi
    
    cat >> "$template_file" << EOF

## Recommended Port Forward Commands

\`\`\`bash
# Clean up existing port forwards
pkill -f 'kubectl port-forward' 2>/dev/null || true

EOF
    
    # Add Prometheus commands
    if [[ -n "$ACTUAL_PROMETHEUS_SERVICES" ]]; then
        local first_prometheus=$(echo "$ACTUAL_PROMETHEUS_SERVICES" | awk '{print $1}')
        local prometheus_port=$(kubectl get service -n monitoring "$first_prometheus" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "9090")
        echo "# Prometheus" >> "$template_file"
        echo "kubectl port-forward -n monitoring service/$first_prometheus $prometheus_port:$prometheus_port --address=0.0.0.0 &" >> "$template_file"
        echo "" >> "$template_file"
    fi
    
    # Add Grafana commands
    if [[ -n "$ACTUAL_GRAFANA_SERVICES" ]]; then
        local first_grafana=$(echo "$ACTUAL_GRAFANA_SERVICES" | awk '{print $1}')
        local grafana_port=$(kubectl get service -n monitoring "$first_grafana" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
        echo "# Grafana" >> "$template_file"
        echo "kubectl port-forward -n monitoring service/$first_grafana 3000:$grafana_port --address=0.0.0.0 &" >> "$template_file"
        echo "" >> "$template_file"
    fi
    
    echo "\`\`\`" >> "$template_file"
    
    success "Service reference template generated: $template_file"
    add_to_report "### Generated Service Template"
    add_to_report ""
    add_to_report "Service reference template available at: \`$template_file\`"
    add_to_report ""
    
    return 0
}

# Update documentation if requested
update_documentation() {
    if [[ "$UPDATE_DOCS" != "true" ]]; then
        return 0
    fi
    
    log "Updating documentation with current service references..."
    
    # This is a placeholder for documentation updates
    # In a real implementation, you would update specific files
    warn "Documentation update feature not yet implemented"
    warn "Use the generated template to manually update documentation"
    
    add_to_report "### Documentation Update"
    add_to_report ""
    add_to_report "⚠️ Automatic documentation update not yet implemented"
    add_to_report "Use the generated service template to manually update documentation"
    add_to_report ""
    
    return 0
}

# Main validation function
run_service_reference_validation() {
    log "Starting monitoring service reference validation..."
    
    init_report
    add_to_report "## Service Reference Validation Started"
    add_to_report "**Timestamp**: $(date)"
    add_to_report ""
    
    local total_issues=0
    
    # Get actual service information
    get_actual_services
    
    # Validate documentation references
    validate_documentation_references
    total_issues=$((total_issues + $?))
    
    # Validate script references
    validate_script_references
    total_issues=$((total_issues + $?))
    
    # Generate service template
    generate_service_template
    
    # Update documentation if requested
    update_documentation
    
    # Summary
    add_to_report "## Validation Summary"
    add_to_report ""
    add_to_report "**Total Issues Found**: $total_issues"
    add_to_report "**Validation Completed**: $(date)"
    
    if [[ $total_issues -eq 0 ]]; then
        success "Service reference validation completed successfully - no issues found"
        add_to_report "**Overall Status**: ✅ ALL REFERENCES VALID"
    elif [[ $total_issues -le 3 ]]; then
        warn "Service reference validation completed with $total_issues minor issues"
        add_to_report "**Overall Status**: ⚠️ MINOR ISSUES FOUND"
    else
        error "Service reference validation found $total_issues issues requiring attention"
        add_to_report "**Overall Status**: ❌ ATTENTION REQUIRED"
    fi
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        log "Validation report generated: $REPORT_FILE"
        add_to_report ""
        add_to_report "---"
        add_to_report "*Report generated by validate-monitoring-service-references.sh*"
    fi
    
    return $total_issues
}

# Dependency checks
check_dependencies() {
    local missing_deps=0
    
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v grep >/dev/null 2>&1; then
        error "grep not found - please install grep"
        missing_deps=$((missing_deps + 1))
    fi
    
    if [[ $missing_deps -gt 0 ]]; then
        error "Missing $missing_deps required dependencies"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        error "Please check your kubeconfig and cluster connectivity"
        exit 1
    fi
}

# Main execution
main() {
    log "Monitoring Service Reference Validation v1.0"
    log "============================================="
    
    check_dependencies
    
    # Run the validation
    run_service_reference_validation
    exit_code=$?
    
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo
        log "Service reference validation report available at: $REPORT_FILE"
        
        # If running in CI/CD, also output to stdout
        if [[ -n "${CI:-}" ]]; then
            echo "## Service Reference Validation Report"
            cat "$REPORT_FILE"
        fi
    fi
    
    log "============================================="
    if [[ $exit_code -eq 0 ]]; then
        success "All service references are valid!"
    else
        error "Service reference validation found $exit_code issue(s) - see details above"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"