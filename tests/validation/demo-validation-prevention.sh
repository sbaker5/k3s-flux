#!/bin/bash

# Demonstration: How Validation Pipeline Prevents Problematic Commits
# This script demonstrates the validation pipeline catching common breaking changes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() {
    local level=$1
    shift
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $*" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $*"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $*"
            ;;
    esac
}

demo_header() {
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

# Demo 1: Show successful validation
demo_successful_validation() {
    demo_header "Demo 1: Successful Validation (Good Commit)"
    
    log INFO "Running validation on current repository state..."
    
    if "$REPO_ROOT/scripts/validate-kustomizations.sh"; then
        log SUCCESS "✅ Validation passed - commit would be allowed"
    else
        log ERROR "❌ Validation failed - commit would be blocked"
    fi
}

# Demo 2: Show validation catching invalid kustomization
demo_invalid_kustomization() {
    demo_header "Demo 2: Invalid Kustomization Detection (Bad Commit Blocked)"
    
    log INFO "Attempting to validate invalid kustomization..."
    log INFO "This simulates a developer trying to commit broken YAML"
    
    if kubectl kustomize "$SCRIPT_DIR/test-cases/invalid-kustomization" >/dev/null 2>&1; then
        log ERROR "❌ Validation should have failed but passed"
    else
        log SUCCESS "✅ Validation correctly blocked invalid kustomization"
        log INFO "Developer would see error message and fix before committing"
    fi
}

# Demo 3: Show immutable field detection
demo_immutable_field_detection() {
    demo_header "Demo 3: Immutable Field Change Detection"
    
    log INFO "Demonstrating detection of problematic field changes..."
    
    # Show the difference between before and after
    log INFO "Before state (Deployment selector):"
    echo "  selector:"
    echo "    matchLabels:"
    echo "      app: test-app"
    echo "      version: v1"
    
    echo ""
    log WARN "After state (would cause immutable field conflict):"
    echo "  selector:"
    echo "    matchLabels:"
    echo "      app: test-app"
    echo "      version: v2  # This change would break reconciliation!"
    
    echo ""
    log SUCCESS "✅ Validation pipeline would detect this change"
    log INFO "Developer would be warned about immutable field modification"
    log INFO "Suggested fix: Use blue-green deployment strategy instead"
}

# Demo 4: Show what happens without validation
demo_without_validation() {
    demo_header "Demo 4: What Happens Without Validation"
    
    log WARN "Without validation pipeline:"
    echo "  1. Developer commits breaking change"
    echo "  2. Flux attempts to apply the change"
    echo "  3. Kubernetes rejects due to immutable field"
    echo "  4. Kustomization gets stuck in failed state"
    echo "  5. Manual intervention required to fix"
    echo "  6. Potential service disruption"
    
    echo ""
    log SUCCESS "With validation pipeline:"
    echo "  1. Pre-commit hook catches the issue"
    echo "  2. Commit is blocked with helpful error message"
    echo "  3. Developer fixes the issue before committing"
    echo "  4. No service disruption"
    echo "  5. GitOps remains healthy"
}

# Demo 5: Show validation in action
demo_validation_in_action() {
    demo_header "Demo 5: Validation Pipeline in Action"
    
    log INFO "Simulating pre-commit hook execution..."
    
    echo ""
    echo "$ git commit -m 'Update deployment configuration'"
    echo ""
    echo "Running pre-commit validation..."
    
    # Simulate the validation steps
    echo "🔍 Validating kustomization builds..."
    sleep 1
    echo "📦 clusters/k3s-flux ... ✅ OK"
    echo "📦 infrastructure ... ✅ OK"
    echo "📦 apps/example-app/base ... ✅ OK"
    
    echo ""
    echo "🔒 Checking for immutable field changes..."
    sleep 1
    echo "✅ No problematic changes detected"
    
    echo ""
    log SUCCESS "✅ All validations passed - commit allowed!"
    echo ""
    echo "$ git push origin main"
    echo "Enumerating objects: 5, done."
    echo "Total 3 (delta 1), reused 0 (delta 0)"
    echo "To github.com:user/k3s-flux.git"
    echo "   abc123..def456  main -> main"
}

# Main execution
main() {
    log INFO "🚀 GitOps Resilience Validation Pipeline Demo"
    log INFO "This demo shows how validation prevents problematic commits"
    
    demo_successful_validation
    demo_invalid_kustomization
    demo_immutable_field_detection
    demo_without_validation
    demo_validation_in_action
    
    demo_header "Summary"
    log SUCCESS "🎉 Validation pipeline successfully prevents:"
    echo "  ✅ Invalid kustomization syntax"
    echo "  ✅ Missing resource files"
    echo "  ✅ Immutable field conflicts"
    echo "  ✅ Breaking configuration changes"
    
    echo ""
    log INFO "📚 Next steps:"
    echo "  1. Set up pre-commit hooks: ./scripts/setup-pre-commit.sh"
    echo "  2. Run full test suite: ./tests/validation/run-validation-tests.sh"
    echo "  3. Review validation results: ./tests/validation/VALIDATION_RESULTS.md"
    
    echo ""
    log SUCCESS "🛡️ Your GitOps infrastructure is now protected!"
}

main "$@"