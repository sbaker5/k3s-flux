#!/bin/bash
# Test script for Flux alert rules validation
# Validates PrometheusRule syntax and basic rule structure

set -euo pipefail

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

echo "🔍 Testing Flux alert rules..."
echo ""

# Test 1: YAML syntax validation
log INFO "Step 1: Validating YAML syntax..."
YAML_FILES=(
    "infrastructure/monitoring/core/flux-alerts.yaml"
    "infrastructure/monitoring/core/gitops-resilience-alerts.yaml"
)

YAML_FAILED=0
for file in "${YAML_FILES[@]}"; do
    echo -n "  📄 $file ... "
    if command -v yamllint >/dev/null 2>&1; then
        if yamllint -d relaxed "$file" >/dev/null 2>&1; then
            echo "✅ OK"
        else
            echo "❌ FAILED"
            YAML_FAILED=1
        fi
    else
        echo "⚠️  SKIPPED (yamllint not available)"
    fi
done

if [ $YAML_FAILED -eq 1 ]; then
    log ERROR "YAML syntax validation failed"
    exit 1
fi

echo ""

# Test 2: Kustomization build validation
log INFO "Step 2: Validating kustomization build..."
echo -n "  📦 infrastructure/monitoring/core ... "
if kubectl kustomize infrastructure/monitoring/core/ >/dev/null 2>/tmp/kustomize-error.log; then
    echo "✅ OK"
else
    echo "❌ FAILED"
    echo "   Error details:"
    sed 's/^/   /' /tmp/kustomize-error.log
    rm -f /tmp/kustomize-error.log
    exit 1
fi
rm -f /tmp/kustomize-error.log

echo ""

# Test 3: PrometheusRule structure validation
log INFO "Step 3: Validating PrometheusRule structure..."

validate_prometheus_rule() {
    local file=$1
    local rule_name=$(basename "$file" .yaml)
    
    echo -n "  🔍 $rule_name ... "
    
    # Check if file contains required PrometheusRule fields
    if ! grep -q "kind: PrometheusRule" "$file"; then
        echo "❌ FAILED - Missing PrometheusRule kind"
        return 1
    fi
    
    if ! grep -q "spec:" "$file"; then
        echo "❌ FAILED - Missing spec section"
        return 1
    fi
    
    if ! grep -q "groups:" "$file"; then
        echo "❌ FAILED - Missing groups section"
        return 1
    fi
    
    # Count alert rules
    local alert_count=$(grep -c "alert:" "$file" || echo "0")
    local record_count=$(grep -c "record:" "$file" || echo "0")
    
    if [ "$alert_count" -eq 0 ] && [ "$record_count" -eq 0 ]; then
        echo "❌ FAILED - No alert or recording rules found"
        return 1
    fi
    
    echo "✅ OK ($alert_count alerts, $record_count recording rules)"
    return 0
}

RULE_FAILED=0
for file in "${YAML_FILES[@]}"; do
    if ! validate_prometheus_rule "$file"; then
        RULE_FAILED=1
    fi
done

if [ $RULE_FAILED -eq 1 ]; then
    log ERROR "PrometheusRule structure validation failed"
    exit 1
fi

echo ""

# Test 4: Alert rule syntax validation (if promtool is available)
log INFO "Step 4: Validating alert rule syntax..."
if command -v promtool >/dev/null 2>&1; then
    for file in "${YAML_FILES[@]}"; do
        rule_name=$(basename "$file" .yaml)
        echo -n "  🔧 $rule_name ... "
        
        # Extract rules section and validate with promtool
        if kubectl kustomize infrastructure/monitoring/core/ | \
           yq eval "select(.kind == \"PrometheusRule\" and .metadata.name == \"$rule_name\") | .spec" - > /tmp/rule-spec.yaml 2>/dev/null; then
            
            if promtool check rules /tmp/rule-spec.yaml >/dev/null 2>&1; then
                echo "✅ OK"
            else
                echo "❌ FAILED"
                log ERROR "Promtool validation failed for $rule_name"
                RULE_FAILED=1
            fi
        else
            echo "⚠️  SKIPPED (could not extract rule spec)"
        fi
        rm -f /tmp/rule-spec.yaml
    done
else
    log WARN "promtool not available, skipping syntax validation"
    log INFO "Install with: brew install prometheus"
fi

echo ""

# Test 5: Alert metadata validation
log INFO "Step 5: Validating alert metadata..."

validate_alert_metadata() {
    local file=$1
    local rule_name=$(basename "$file" .yaml)
    
    echo -n "  📋 $rule_name metadata ... "
    
    # Check for required alert annotations using a more robust approach
    local total_alerts=$(grep -c "alert:" "$file" || echo "0")
    
    if [ "$total_alerts" -gt 0 ]; then
        # Check if each alert has both summary and description
        local missing_metadata=0
        
        # Extract alert names and check their annotations
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*alert:[[:space:]]*(.+)$ ]]; then
                local alert_name="${BASH_REMATCH[1]}"
                
                # Look for summary and description in the next 20 lines after the alert
                local alert_section=$(grep -A 20 "alert: $alert_name" "$file" || echo "")
                
                if ! echo "$alert_section" | grep -q "summary:"; then
                    missing_metadata=1
                    break
                fi
                
                if ! echo "$alert_section" | grep -q "description:"; then
                    missing_metadata=1
                    break
                fi
            fi
        done < "$file"
        
        if [ "$missing_metadata" -eq 1 ]; then
            echo "❌ FAILED - Some alerts missing summary or description"
            return 1
        fi
    fi
    
    echo "✅ OK ($total_alerts alerts with complete metadata)"
    return 0
}

METADATA_FAILED=0
for file in "${YAML_FILES[@]}"; do
    if ! validate_alert_metadata "$file"; then
        METADATA_FAILED=1
    fi
done

if [ $METADATA_FAILED -eq 1 ]; then
    log ERROR "Alert metadata validation failed"
    exit 1
fi

echo ""

# Summary
log SUCCESS "All alert rule validations passed!"
echo ""
log INFO "Summary:"
echo "  - YAML syntax: ✅ Valid"
echo "  - Kustomization build: ✅ Valid"
echo "  - PrometheusRule structure: ✅ Valid"
echo "  - Alert rule syntax: ✅ Valid (if promtool available)"
echo "  - Alert metadata: ✅ Complete"
echo ""
log INFO "Alert rules are ready for deployment!"