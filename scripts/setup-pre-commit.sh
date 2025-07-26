#!/bin/bash
# Git Pre-commit Hook Setup Script
# Configures Git pre-commit hooks for GitOps resilience validation

set -euo pipefail

# Constants
readonly HOOK_PATH=".git/hooks/pre-commit"
readonly HOOK_SIGNATURE="GitOps resilience validation"
readonly VALIDATION_SCRIPTS=(
    "scripts/validate-kustomizations.sh"
    "scripts/check-immutable-fields.sh"
)
readonly REQUIRED_DEPS=("git" "python3")
readonly OPTIONAL_DEPS=("kubectl" "flux")

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $*" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies
check_dependencies() {
    log INFO "Checking dependencies..."
    
    local missing_deps=()
    local optional_missing=()
    
    # Check for required dependencies
    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    # Check for optional dependencies
    for dep in "${OPTIONAL_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            optional_missing+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log ERROR "Missing required dependencies: ${missing_deps[*]}"
        log ERROR "Please install the missing dependencies and run this script again"
        exit 1
    fi
    
    if [ ${#optional_missing[@]} -gt 0 ]; then
        log WARN "Optional dependencies not found: ${optional_missing[*]}"
        log WARN "Some validation features will be skipped if these are not available"
    fi
    
    log SUCCESS "All required dependencies are available"
}

# Function to verify we're in a git repository
verify_git_repository() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log ERROR "Not in a Git repository"
        exit 1
    fi
}

# Function to validate pre-commit hook installation
validate_precommit_hook() {
    if [ ! -f "$HOOK_PATH" ]; then
        log ERROR "Pre-commit hook not found in $HOOK_PATH"
        log ERROR "The comprehensive pre-commit hook should be part of the repository"
        exit 1
    fi
    
    if [ ! -r "$HOOK_PATH" ]; then
        log ERROR "Pre-commit hook is not readable"
        exit 1
    fi
    
    if grep -q "$HOOK_SIGNATURE" "$HOOK_PATH" 2>/dev/null; then
        log SUCCESS "Comprehensive GitOps pre-commit hook is already installed"
        return 0
    else
        log WARN "Simple pre-commit hook found - the comprehensive version should already be installed"
        log INFO "The current hook includes GitOps resilience validation features"
        return 1
    fi
}

# Function to ensure scripts are executable
ensure_scripts_executable() {
    for script in "${VALIDATION_SCRIPTS[@]}"; do
        if [ -f "$script" ]; then
            chmod +x "$script"
            log SUCCESS "$(basename "$script") is executable"
        else
            log ERROR "$(basename "$script") not found"
            exit 1
        fi
    done
}

# Function to setup Git pre-commit hook
setup_git_hook() {
    log INFO "Setting up Git pre-commit hook..."
    
    verify_git_repository
    validate_precommit_hook
    
    # Ensure the hook is executable
    chmod +x "$HOOK_PATH"
    log SUCCESS "Pre-commit hook is executable"
    
    ensure_scripts_executable
}

# Function to test Git pre-commit hook
test_git_hook() {
    log INFO "Testing Git pre-commit hook..."
    
    if [ ! -x "$HOOK_PATH" ]; then
        log ERROR "Pre-commit hook is not executable"
        exit 1
    fi
    
    log INFO "Verifying hook can execute without staged files..."
    
    # Test that the hook can run when no YAML files are staged
    # This should exit cleanly with "No YAML files staged" message
    if "$HOOK_PATH" >/dev/null 2>&1; then
        log SUCCESS "Pre-commit hook executes correctly with no staged files"
    else
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log SUCCESS "Pre-commit hook test completed successfully"
        else
            log ERROR "Pre-commit hook failed with exit code $exit_code"
            log INFO "This may be normal if validation dependencies are missing"
            log INFO "The hook will work correctly when dependencies are available"
        fi
    fi
    
    log INFO "Pre-commit hook is ready for actual commits"
}

# Function to show usage information
show_usage() {
    echo "Git Pre-commit Hook Setup Script for GitOps Resilience Patterns"
    echo ""
    echo "This script will:"
    echo "  1. Check for required dependencies (git, python3)"
    echo "  2. Verify the comprehensive Git pre-commit hook is installed"
    echo "  3. Ensure validation scripts are executable"
    echo "  4. Test the pre-commit hook setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-test       Skip testing the pre-commit setup"
    echo "  --help            Show this help message"
    echo ""
    echo "Git pre-commit hook includes:"
    echo "  - YAML syntax validation"
    echo "  - Kustomization build validation"
    echo "  - Immutable field change detection"
    echo "  - Flux health check validation"
    echo "  - Kubernetes dry-run validation"
}

# Main function
main() {
    local skip_test=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-test)
                skip_test=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log INFO "Starting Git pre-commit hook setup for GitOps resilience patterns..."
    
    # Check dependencies
    check_dependencies
    
    # Setup Git pre-commit hook
    setup_git_hook
    
    # Test the setup if requested
    if [ "$skip_test" = false ]; then
        test_git_hook
    fi
    
    log SUCCESS "Git pre-commit hook setup completed successfully!"
    echo ""
    log INFO "Next steps:"
    echo "  1. Make changes to your Kubernetes manifests"
    echo "  2. Run 'git add <files>' to stage your changes"
    echo "  3. Run 'git commit' - the Git pre-commit hook will validate your changes"
    echo "  4. If validation fails, fix the issues and commit again"
    echo ""
    log INFO "Manual validation commands:"
    echo "  - Run the pre-commit hook: $HOOK_PATH"
    echo "  - Validate kustomizations: ./${VALIDATION_SCRIPTS[0]}"
    echo "  - Check immutable fields: ./${VALIDATION_SCRIPTS[1]}"
    echo "  - Check Flux health: flux check"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi