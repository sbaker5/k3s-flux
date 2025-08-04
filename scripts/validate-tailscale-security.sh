#!/bin/bash
# Validate Tailscale security configuration

set -euo pipefail

echo "🔍 Validating Tailscale security configuration..."

VALIDATION_ERRORS=0

validate_file_exists() {
    local file="$1"
    local description="$2"
    
    if [[ -f "$file" ]]; then
        echo "✅ $description: $file"
    else
        echo "❌ $description: $file (missing)"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
}

echo ""
echo "1. Checking for plaintext secrets..."
if grep -r "tskey-auth-" --include="*.yaml" --include="*.yml" infrastructure/tailscale/ 2>/dev/null | grep -v ".sops." | grep -v "PLACEHOLDER\|REDACTED"; then
    echo "❌ Plaintext Tailscale auth key found!"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    echo "✅ No plaintext auth keys found"
fi

echo ""
echo "2. Checking SOPS configuration..."
validate_file_exists ".sops.yaml" "SOPS configuration"

if [[ -f .sops.yaml ]]; then
    echo "✅ SOPS configuration exists"
else
    echo "❌ SOPS not configured - run ./scripts/setup-sops-for-tailscale.sh"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

echo ""
echo "3. Checking encrypted secret..."
validate_file_exists "infrastructure/tailscale/base/secret.sops.yaml" "Encrypted Tailscale secret"

if [[ -f infrastructure/tailscale/base/secret.sops.yaml ]]; then
    if sops --decrypt infrastructure/tailscale/base/secret.sops.yaml >/dev/null 2>&1; then
        echo "✅ SOPS decryption working"
        
        # Check if the decrypted secret contains a valid key
        DECRYPTED_KEY=$(sops --decrypt infrastructure/tailscale/base/secret.sops.yaml | grep "TS_AUTHKEY:" | cut -d'"' -f2)
        if [[ "$DECRYPTED_KEY" =~ ^tskey-auth- ]]; then
            echo "✅ Encrypted secret contains valid Tailscale auth key"
        else
            echo "❌ Encrypted secret does not contain valid auth key"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi
    else
        echo "❌ SOPS decryption failed"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
fi

echo ""
echo "4. Checking kustomization configuration..."
if [[ -f infrastructure/tailscale/base/kustomization.yaml ]]; then
    if grep -q "secret.sops.yaml" infrastructure/tailscale/base/kustomization.yaml; then
        echo "✅ Kustomization uses encrypted secret"
    else
        echo "❌ Kustomization not updated to use encrypted secret"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
else
    echo "❌ Kustomization file missing"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

echo ""
echo "5. Checking for old plaintext files..."
if [[ -f infrastructure/tailscale/base/secret.yaml ]]; then
    echo "⚠️  Old plaintext secret file still exists (should be removed)"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    echo "✅ Old plaintext secret file removed"
fi

echo ""
echo "6. Checking Kubernetes SOPS secret..."
if kubectl get secret sops-age -n flux-system >/dev/null 2>&1; then
    echo "✅ SOPS age secret exists in flux-system namespace"
else
    echo "❌ SOPS age secret missing from flux-system namespace"
    echo "   Run: ./scripts/setup-sops-for-tailscale.sh"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

echo ""
echo "========================================"

if [[ $VALIDATION_ERRORS -eq 0 ]]; then
    echo "🎉 All validations passed! Tailscale security is properly configured."
    echo ""
    echo "Your Tailscale configuration is now secure:"
    echo "  ✅ Auth key is encrypted with SOPS"
    echo "  ✅ No plaintext secrets in Git"
    echo "  ✅ Flux can decrypt secrets automatically"
    echo "  ✅ Old exposed key has been cleaned up"
    exit 0
else
    echo "❌ $VALIDATION_ERRORS validation error(s) found."
    echo ""
    echo "Please fix the issues above before proceeding."
    exit 1
fi