#!/bin/bash
# Kustomization Build Validation Script
# Validates that all major kustomization.yaml files can build successfully
set -e

echo "🔍 Validating kustomization builds..."

# Main directories that contain kustomization.yaml files
DIRS=(
    "clusters/k3s-flux"
    "infrastructure"
    "infrastructure/monitoring"
    "infrastructure/longhorn/base"
    "infrastructure/nginx-ingress"
    "apps/example-app/base"
    "apps/example-app/overlays/dev"
    "apps/longhorn-test/base"
    "apps/longhorn-test/overlays/dev"
)

FAILED=0
TOTAL=0
SUCCESS=0

for dir in "${DIRS[@]}"; do
    if [ -f "$dir/kustomization.yaml" ]; then
        TOTAL=$((TOTAL + 1))
        echo -n "📦 $dir ... "
        
        if kubectl kustomize "$dir" > /dev/null 2>/tmp/kustomize-error.log; then
            echo "✅ OK"
            SUCCESS=$((SUCCESS + 1))
        else
            echo "❌ FAILED"
            echo "   Error details:"
            sed 's/^/   /' /tmp/kustomize-error.log
            FAILED=1
        fi
        rm -f /tmp/kustomize-error.log
    else
        echo "⚠️  $dir - no kustomization.yaml found"
    fi
done

echo ""
echo "📊 Summary:"
echo "   Total checked: $TOTAL"
echo "   Successful: $SUCCESS"
echo "   Failed: $((TOTAL - SUCCESS))"

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "❌ Some kustomization builds failed."
    echo "💡 Run 'kubectl kustomize <directory>' on failed directories for detailed error info."
    exit 1
fi

echo "✅ All kustomization builds successful!"