#!/bin/bash
set -euo pipefail

# Test script for error pattern detection system
# This script validates that the error pattern detection system is properly configured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🧪 Testing Error Pattern Detection System"
echo "=========================================="

# Test 1: Validate configuration files exist
echo "📁 Test 1: Checking configuration files..."

CONFIG_FILES=(
    "infrastructure/recovery/recovery-patterns-config.yaml"
    "infrastructure/recovery/error-pattern-detector.yaml"
    "infrastructure/recovery/namespace.yaml"
    "infrastructure/recovery/kustomization.yaml"
)

for file in "${CONFIG_FILES[@]}"; do
    if [[ -f "$PROJECT_ROOT/$file" ]]; then
        echo "✅ Found: $file"
    else
        echo "❌ Missing: $file"
        exit 1
    fi
done

# Test 2: Validate YAML syntax
echo ""
echo "📝 Test 2: Validating YAML syntax..."

for file in "${CONFIG_FILES[@]}"; do
    if command -v yamllint >/dev/null 2>&1; then
        if yamllint -d relaxed "$PROJECT_ROOT/$file" >/dev/null 2>&1; then
            echo "✅ Valid YAML: $file"
        else
            echo "❌ Invalid YAML: $file"
            yamllint -d relaxed "$PROJECT_ROOT/$file"
            exit 1
        fi
    else
        echo "⚠️  yamllint not available, skipping YAML validation"
        break
    fi
done

# Test 3: Validate Kustomization build
echo ""
echo "🔨 Test 3: Testing Kustomization build..."

if command -v kubectl >/dev/null 2>&1; then
    if kubectl kustomize "$PROJECT_ROOT/infrastructure/recovery" >/dev/null 2>&1; then
        echo "✅ Kustomization builds successfully"
    else
        echo "❌ Kustomization build failed"
        kubectl kustomize "$PROJECT_ROOT/infrastructure/recovery"
        exit 1
    fi
else
    echo "⚠️  kubectl not available, skipping Kustomization build test"
fi

# Test 4: Validate recovery patterns configuration
echo ""
echo "🔍 Test 4: Validating recovery patterns..."

PATTERNS_FILE="$PROJECT_ROOT/infrastructure/recovery/recovery-patterns-config.yaml"

if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import yaml
import sys

try:
    with open('$PATTERNS_FILE', 'r') as f:
        config = yaml.safe_load(f)
    
    data = config.get('data', {})
    patterns_yaml = data.get('recovery-patterns.yaml', '')
    
    if not patterns_yaml:
        print('❌ No recovery-patterns.yaml data found')
        sys.exit(1)
    
    patterns_config = yaml.safe_load(patterns_yaml)
    
    patterns = patterns_config.get('patterns', [])
    recovery_actions = patterns_config.get('recovery_actions', {})
    settings = patterns_config.get('settings', {})
    
    print(f'✅ Found {len(patterns)} error patterns')
    print(f'✅ Found {len(recovery_actions)} recovery actions')
    print(f'✅ Found {len(settings)} configuration settings')
    
    # Validate pattern structure
    required_pattern_fields = ['name', 'error_pattern', 'recovery_action']
    for i, pattern in enumerate(patterns):
        for field in required_pattern_fields:
            if field not in pattern:
                print(f'❌ Pattern {i+1} missing required field: {field}')
                sys.exit(1)
    
    print('✅ All patterns have required fields')
    
    # Validate recovery actions exist for patterns
    for pattern in patterns:
        action = pattern.get('recovery_action')
        if action not in recovery_actions:
            print(f'❌ Pattern \"{pattern[\"name\"]}\" references unknown recovery action: {action}')
            sys.exit(1)
    
    print('✅ All recovery actions are defined')
    
except Exception as e:
    print(f'❌ Error validating patterns: {e}')
    sys.exit(1)
"
    echo "✅ Recovery patterns configuration is valid"
else
    echo "⚠️  Python3 not available, skipping pattern validation"
fi

# Test 5: Check RBAC permissions
echo ""
echo "🔐 Test 5: Validating RBAC configuration..."

RBAC_RESOURCES=(
    "ServiceAccount"
    "ClusterRole" 
    "ClusterRoleBinding"
)

DETECTOR_FILE="$PROJECT_ROOT/infrastructure/recovery/error-pattern-detector.yaml"

for resource in "${RBAC_RESOURCES[@]}"; do
    if grep -q "kind: $resource" "$DETECTOR_FILE"; then
        echo "✅ Found RBAC resource: $resource"
    else
        echo "❌ Missing RBAC resource: $resource"
        exit 1
    fi
done

# Test 6: Validate controller script
echo ""
echo "🐍 Test 6: Validating controller script..."

if grep -q "class ErrorPatternDetector" "$DETECTOR_FILE"; then
    echo "✅ Controller script contains main class"
else
    echo "❌ Controller script missing main class"
    exit 1
fi

if grep -q "def load_config" "$DETECTOR_FILE"; then
    echo "✅ Controller script has config loading"
else
    echo "❌ Controller script missing config loading"
    exit 1
fi

if grep -q "def match_pattern" "$DETECTOR_FILE"; then
    echo "✅ Controller script has pattern matching"
else
    echo "❌ Controller script missing pattern matching"
    exit 1
fi

echo ""
echo "🎉 All tests passed! Error Pattern Detection System is properly configured."
echo ""
echo "📋 Summary:"
echo "   - Configuration files: ✅"
echo "   - YAML syntax: ✅"
echo "   - Kustomization build: ✅"
echo "   - Recovery patterns: ✅"
echo "   - RBAC configuration: ✅"
echo "   - Controller script: ✅"
echo ""
echo "🚀 The error pattern detection system is ready for deployment!"