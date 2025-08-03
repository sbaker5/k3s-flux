#!/bin/bash
# Remote Monitoring Access Validation Script
#
# This script validates remote access to monitoring services via Tailscale,
# including port forwarding setup, connectivity testing, and process management.
#
# Usage: ./scripts/validate-remote-monitoring-access.sh [--test-connectivity] [--cleanup]
#   --test-connectivity: Test actual HTTP connectivity to services
#   --cleanup: Clean up any existing port forwards

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAILSCALE_IP=""
TEST_CONNECTIVITY=false
CLEANUP_ONLY=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test-connectivity)
            TEST_CONNECTIVITY=true
            shift
            ;;
        --cleanup)
            CLEANUP_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--test-connectivity] [--cleanup]"
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

# Process management functions
cleanup_port_forwards() {
    log "Cleaning up existing port forwards..."
    
    # Find and kill kubectl port-forward processes
    local pids=$(pgrep -f "kubectl port-forward" 2>/dev/null || true)
    
    if [[ -n "$pids" ]]; then
        log "Found existing port forward processes: $pids"
        echo "$pids" | while read -r pid; do
            if kill "$pid" 2>/dev/null; then
                log "Killed port forward process: $pid"
            fi
        done
        
        # Wait for processes to terminate
        sleep 2
        
        # Check if any are still running
        local remaining=$(pgrep -f "kubectl port-forward" 2>/dev/null || true)
        if [[ -n "$remaining" ]]; then
            warn "Some port forward processes still running, force killing..."
            echo "$remaining" | while read -r pid; do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
        
        success "Port forward cleanup completed"
    else
        log "No existing port forwards found"
    fi
}

check_tailscale_connectivity() {
    log "Checking Tailscale connectivity..."
    
    if ! command -v tailscale >/dev/null 2>&1; then
        error "Tailscale CLI not found"
        error "Install with: brew install tailscale"
        return 1
    fi
    
    if ! tailscale status >/dev/null 2>&1; then
        error "Tailscale is not connected"
        error "Connect with: tailscale up"
        return 1
    fi
    
    # Get Tailscale IP
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    
    if [[ -n "$TAILSCALE_IP" ]]; then
        success "Tailscale connected with IP: $TAILSCALE_IP"
    else
        error "Could not determine Tailscale IP"
        return 1
    fi
    
    # Check if we can reach the cluster
    if kubectl cluster-info >/dev/null 2>&1; then
        success "Kubernetes cluster accessible via Tailscale"
    else
        error "Cannot access Kubernetes cluster"
        error "Check your kubeconfig and Tailscale subnet routing"
        return 1
    fi
    
    return 0
}

validate_service_references() {
    log "Validating monitoring service references..."
    
    # Check Prometheus service
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    
    if [[ -n "$prometheus_service" ]]; then
        success "Prometheus service found: $prometheus_service"
        
        # Get service details
        local prometheus_port=$(kubectl get service -n monitoring "$prometheus_service" -o jsonpath='{.spec.ports[0].port}')
        local prometheus_target_port=$(kubectl get service -n monitoring "$prometheus_service" -o jsonpath='{.spec.ports[0].targetPort}')
        
        log "  Port: $prometheus_port -> $prometheus_target_port"
        
        # Validate service has endpoints
        local endpoints=$(kubectl get endpoints -n monitoring "$prometheus_service" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null || echo "[]")
        if [[ "$endpoints" != "[]" && -n "$endpoints" ]]; then
            success "  Service has active endpoints"
        else
            error "  Service has no active endpoints"
            return 1
        fi
    else
        error "Prometheus service not found"
        return 1
    fi
    
    # Check Grafana service
    local grafana_service=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$grafana_service" ]]; then
        success "Grafana service found: $grafana_service"
        
        # Get service details
        local grafana_port=$(kubectl get service -n monitoring "$grafana_service" -o jsonpath='{.spec.ports[0].port}')
        local grafana_target_port=$(kubectl get service -n monitoring "$grafana_service" -o jsonpath='{.spec.ports[0].targetPort}')
        
        log "  Port: $grafana_port -> $grafana_target_port"
        
        # Validate service has endpoints
        local endpoints=$(kubectl get endpoints -n monitoring "$grafana_service" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null || echo "[]")
        if [[ "$endpoints" != "[]" && -n "$endpoints" ]]; then
            success "  Service has active endpoints"
        else
            error "  Service has no active endpoints"
            return 1
        fi
    else
        error "Grafana service not found"
        return 1
    fi
    
    return 0
}

test_port_forwarding_setup() {
    log "Testing port forwarding setup..."
    
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    local grafana_service=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$prometheus_service" || -z "$grafana_service" ]]; then
        error "Required services not found"
        return 1
    fi
    
    # Test Prometheus port forward
    log "Testing Prometheus port forward..."
    
    # Start port forward in background
    kubectl port-forward -n monitoring "service/$prometheus_service" 9090:9090 --address=0.0.0.0 >/dev/null 2>&1 &
    local prometheus_pid=$!
    
    # Wait for port forward to establish
    sleep 3
    
    # Check if port forward is working
    if kill -0 "$prometheus_pid" 2>/dev/null; then
        success "Prometheus port forward established (PID: $prometheus_pid)"
        
        # Test local connectivity if requested
        if [[ "$TEST_CONNECTIVITY" == "true" ]]; then
            if curl -s http://localhost:9090/api/v1/query?query=up >/dev/null 2>&1; then
                success "Prometheus HTTP endpoint accessible locally"
            else
                error "Prometheus HTTP endpoint not accessible locally"
            fi
        fi
        
        # Clean up
        kill "$prometheus_pid" 2>/dev/null || true
    else
        error "Prometheus port forward failed to establish"
        return 1
    fi
    
    # Test Grafana port forward
    log "Testing Grafana port forward..."
    
    # Start port forward in background
    kubectl port-forward -n monitoring "service/$grafana_service" 3000:80 --address=0.0.0.0 >/dev/null 2>&1 &
    local grafana_pid=$!
    
    # Wait for port forward to establish
    sleep 3
    
    # Check if port forward is working
    if kill -0 "$grafana_pid" 2>/dev/null; then
        success "Grafana port forward established (PID: $grafana_pid)"
        
        # Test local connectivity if requested
        if [[ "$TEST_CONNECTIVITY" == "true" ]]; then
            if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
                success "Grafana HTTP endpoint accessible locally"
            else
                # Grafana might not have /api/health, try root
                if curl -s http://localhost:3000/ >/dev/null 2>&1; then
                    success "Grafana HTTP endpoint accessible locally"
                else
                    error "Grafana HTTP endpoint not accessible locally"
                fi
            fi
        fi
        
        # Clean up
        kill "$grafana_pid" 2>/dev/null || true
    else
        error "Grafana port forward failed to establish"
        return 1
    fi
    
    return 0
}

generate_access_commands() {
    log "Generating remote access commands..."
    
    local prometheus_service=$(kubectl get service -n monitoring -o name | grep "prometheus-prometheus" | head -1 | sed 's|service/||' 2>/dev/null || echo "")
    local grafana_service=$(kubectl get service -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$prometheus_service" && -n "$grafana_service" ]]; then
        success "Remote access commands:"
        echo
        echo "# Prometheus (metrics and queries)"
        echo "kubectl port-forward -n monitoring service/$prometheus_service 9090:9090 --address=0.0.0.0 &"
        echo "# Access at: http://$TAILSCALE_IP:9090"
        echo
        echo "# Grafana (dashboards and visualization)"
        echo "kubectl port-forward -n monitoring service/$grafana_service 3000:80 --address=0.0.0.0 &"
        echo "# Access at: http://$TAILSCALE_IP:3000"
        echo
        echo "# Clean up port forwards when done:"
        echo "pkill -f 'kubectl port-forward'"
        echo
        
        # Save commands to file for easy access
        local commands_file="/tmp/monitoring-remote-access-commands.sh"
        cat > "$commands_file" << EOF
#!/bin/bash
# Remote Monitoring Access Commands
# Generated: $(date)

echo "Starting remote monitoring access..."

# Clean up any existing port forwards
pkill -f 'kubectl port-forward' 2>/dev/null || true
sleep 2

# Start Prometheus port forward
echo "Starting Prometheus port forward..."
kubectl port-forward -n monitoring service/$prometheus_service 9090:9090 --address=0.0.0.0 &
PROMETHEUS_PID=\$!

# Start Grafana port forward
echo "Starting Grafana port forward..."
kubectl port-forward -n monitoring service/$grafana_service 3000:80 --address=0.0.0.0 &
GRAFANA_PID=\$!

# Wait for port forwards to establish
sleep 3

echo "Remote monitoring access established:"
echo "  Prometheus: http://$TAILSCALE_IP:9090"
echo "  Grafana:    http://$TAILSCALE_IP:3000"
echo
echo "Port forward PIDs: Prometheus=\$PROMETHEUS_PID, Grafana=\$GRAFANA_PID"
echo
echo "To stop port forwards:"
echo "  kill \$PROMETHEUS_PID \$GRAFANA_PID"
echo "  # or"
echo "  pkill -f 'kubectl port-forward'"
EOF
        
        chmod +x "$commands_file"
        success "Commands saved to: $commands_file"
    else
        error "Cannot generate commands - services not found"
        return 1
    fi
    
    return 0
}

validate_port_availability() {
    log "Checking port availability..."
    
    # Check if ports 9090 and 3000 are available
    local ports_in_use=""
    
    if lsof -i :9090 >/dev/null 2>&1; then
        ports_in_use="$ports_in_use 9090"
    fi
    
    if lsof -i :3000 >/dev/null 2>&1; then
        ports_in_use="$ports_in_use 3000"
    fi
    
    if [[ -n "$ports_in_use" ]]; then
        warn "Ports in use:$ports_in_use"
        warn "You may need to stop existing services or use different ports"
        
        # Show what's using the ports
        for port in $ports_in_use; do
            log "Port $port is used by:"
            lsof -i ":$port" | head -5
        done
        
        return 1
    else
        success "Ports 9090 and 3000 are available"
        return 0
    fi
}

# Main validation function
run_remote_access_validation() {
    log "Starting remote monitoring access validation..."
    
    local issues=0
    
    # Clean up first if requested
    if [[ "$CLEANUP_ONLY" == "true" ]]; then
        cleanup_port_forwards
        success "Cleanup completed"
        return 0
    fi
    
    # Check Tailscale connectivity
    if ! check_tailscale_connectivity; then
        issues=$((issues + 1))
    fi
    
    # Validate service references
    if ! validate_service_references; then
        issues=$((issues + 1))
    fi
    
    # Check port availability
    if ! validate_port_availability; then
        issues=$((issues + 1))
    fi
    
    # Test port forwarding setup
    if ! test_port_forwarding_setup; then
        issues=$((issues + 1))
    fi
    
    # Generate access commands
    if ! generate_access_commands; then
        issues=$((issues + 1))
    fi
    
    # Summary
    if [[ $issues -eq 0 ]]; then
        success "Remote monitoring access validation completed successfully"
        success "All systems ready for remote access via Tailscale"
    else
        error "Remote monitoring access validation found $issues issue(s)"
        error "Please resolve the issues above before attempting remote access"
    fi
    
    return $issues
}

# Dependency checks
check_dependencies() {
    local missing_deps=0
    
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found - please install kubectl"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v lsof >/dev/null 2>&1; then
        error "lsof not found - please install lsof"
        missing_deps=$((missing_deps + 1))
    fi
    
    if [[ "$TEST_CONNECTIVITY" == "true" ]] && ! command -v curl >/dev/null 2>&1; then
        error "curl not found - please install curl (required for connectivity testing)"
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
    log "Remote Monitoring Access Validation v1.0"
    log "========================================"
    
    check_dependencies
    
    # Run the validation
    run_remote_access_validation
    exit_code=$?
    
    log "========================================"
    if [[ $exit_code -eq 0 ]]; then
        success "Remote monitoring access is ready!"
    else
        error "Remote monitoring access has $exit_code issue(s) - see details above"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"