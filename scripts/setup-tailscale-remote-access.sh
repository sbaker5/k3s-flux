#!/bin/bash
# Tailscale Remote Access Setup Script
# Helps set up secure remote access to k3s cluster

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${message}"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is required but not installed"
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to Kubernetes cluster"
    fi
    
    log "Prerequisites check passed"
}

# Get network information
get_network_info() {
    log "Gathering network information..."
    
    echo -e "${BLUE}=== Network Information ===${NC}"
    
    # k3s cluster networks
    echo -e "${CYAN}k3s Cluster Networks:${NC}"
    kubectl cluster-info dump 2>/dev/null | grep -E "cluster-cidr|service-cidr" | head -2 || {
        echo "  Pod CIDR: 10.42.0.0/16 (default)"
        echo "  Service CIDR: 10.43.0.0/16 (default)"
    }
    
    # Local network
    echo -e "${CYAN}Local Network:${NC}"
    if command -v ip &> /dev/null; then
        ip route | grep -E "192.168|10\." | head -3 || echo "  Could not detect local network"
    else
        echo "  Please check your local network range (usually 192.168.1.0/24)"
    fi
    
    echo
}

# Check if Tailscale auth key is configured
check_auth_key() {
    local secret_file="$PROJECT_ROOT/infrastructure/tailscale/base/secret.yaml"
    
    if [[ ! -f "$secret_file" ]] || grep -q "REPLACE_WITH_YOUR_TAILSCALE_AUTH_KEY" "$secret_file" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Tailscale auth key not configured${NC}"
        echo
        echo "Please follow these steps:"
        echo "1. Go to: https://login.tailscale.com/admin/settings/keys"
        echo "2. Click 'Generate auth key'"
        echo "3. Configure:"
        echo "   - Reusable: Yes"
        echo "   - Ephemeral: No"
        echo "   - Pre-authorized: Yes"
        echo "   - Tags: tag:k8s"
        echo "4. Copy the key and run:"
        echo "   sed -i 's/REPLACE_WITH_YOUR_TAILSCALE_AUTH_KEY/your-actual-key/' $secret_file"
        echo
        return 1
    else
        log "Auth key appears to be configured"
        return 0
    fi
}

# Deploy Tailscale
deploy_tailscale() {
    log "Deploying Tailscale to cluster..."
    
    # Apply the configuration
    kubectl apply -k "$PROJECT_ROOT/infrastructure/tailscale/base/" || {
        error_exit "Failed to deploy Tailscale"
    }
    
    log "Waiting for Tailscale pod to be ready..."
    kubectl wait --for=condition=Ready pod -l app=tailscale-subnet-router -n tailscale --timeout=120s || {
        echo -e "${YELLOW}Pod not ready yet, checking logs...${NC}"
        kubectl logs -n tailscale deployment/tailscale-subnet-router --tail=20
        return 1
    }
    
    log "Tailscale deployed successfully!"
}

# Show status
show_status() {
    echo -e "${BLUE}=== Tailscale Status ===${NC}"
    
    # Pod status
    echo -e "${CYAN}Pod Status:${NC}"
    kubectl get pods -n tailscale -o wide
    echo
    
    # Recent logs
    echo -e "${CYAN}Recent Logs:${NC}"
    kubectl logs -n tailscale deployment/tailscale-subnet-router --tail=10
    echo
}

# Show next steps
show_next_steps() {
    echo -e "${BLUE}=== Next Steps ===${NC}"
    echo
    echo "1. ${CYAN}Approve subnet routes:${NC}"
    echo "   - Go to: https://login.tailscale.com/admin/machines"
    echo "   - Find your 'k3s-cluster' device"
    echo "   - Click '...' → 'Edit route settings'"
    echo "   - Approve all advertised routes"
    echo
    echo "2. ${CYAN}Install Tailscale on your MacBook:${NC}"
    echo "   brew install --cask tailscale"
    echo
    echo "3. ${CYAN}Test connectivity:${NC}"
    echo "   tailscale status"
    echo "   ping <k3s-tailscale-ip>"
    echo
    echo "4. ${CYAN}Set up kubectl access:${NC}"
    echo "   See: docs/tailscale-remote-access-setup.md"
    echo
    echo -e "${GREEN}✅ Tailscale setup complete!${NC}"
    echo "Full documentation: docs/tailscale-remote-access-setup.md"
}

# Main function
main() {
    echo -e "${BLUE}=== Tailscale Remote Access Setup ===${NC}"
    echo "This script will help you set up secure remote access to your k3s cluster"
    echo
    
    check_prerequisites
    get_network_info
    
    if ! check_auth_key; then
        echo -e "${YELLOW}Please configure your Tailscale auth key first, then run this script again.${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}This will deploy Tailscale to your cluster. Continue? (y/N)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled"
        exit 0
    fi
    
    deploy_tailscale
    show_status
    show_next_steps
}

# Handle command line arguments
case "${1:-}" in
    "status")
        check_prerequisites
        show_status
        ;;
    "logs")
        check_prerequisites
        kubectl logs -n tailscale deployment/tailscale-subnet-router -f
        ;;
    "restart")
        check_prerequisites
        kubectl rollout restart deployment/tailscale-subnet-router -n tailscale
        kubectl rollout status deployment/tailscale-subnet-router -n tailscale
        ;;
    "remove")
        check_prerequisites
        echo -e "${RED}This will remove Tailscale from your cluster. Continue? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            kubectl delete -k "$PROJECT_ROOT/infrastructure/tailscale/base/" || true
            log "Tailscale removed from cluster"
        fi
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [COMMAND]"
        echo
        echo "Commands:"
        echo "  (no args)  Run interactive setup"
        echo "  status     Show Tailscale status"
        echo "  logs       Show Tailscale logs (follow)"
        echo "  restart    Restart Tailscale deployment"
        echo "  remove     Remove Tailscale from cluster"
        echo "  help       Show this help"
        ;;
    "")
        main
        ;;
    *)
        error_exit "Unknown command: $1. Use 'help' for usage."
        ;;
esac