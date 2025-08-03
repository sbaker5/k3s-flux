# GitOps Resilience Patterns Testing Suite

This directory contains comprehensive testing tools for validating the GitOps resilience patterns implementation, specifically Tasks 3.1 (Error Pattern Detection) and 3.2 (Resource Recreation Automation).

## Quick Start

### Health Check After System Disruption
```bash
# Run after power outages, restarts, or other disruptions
./tests/validation/post-outage-health-check.sh
```

### Verify Tasks 3.1 & 3.2 Status
```bash
# Quick status check
./tests/validation/test-tasks-3.1-3.2.sh
```

### Verify k3s2 Node Onboarding
```bash
# Test k3s2 node readiness and integration
./tests/validation/test-k3s2-node-onboarding.sh
```

### Full System Validation
```bash
# Comprehensive testing with simulation
./tests/validation/test-pattern-simulation.sh
```

## Test Categories

### 1. Configuration Validation
- **File**: `validation/test-error-pattern-detection.sh`
- **Purpose**: Validates YAML syntax, Kustomization builds, and basic configuration
- **When to use**: After configuration changes, before deployment

### 2. Runtime Validation
- **Files**: 
  - `validation/test-error-pattern-runtime.sh` (detailed)
  - `validation/test-tasks-3.1-3.2.sh` (quick)
- **Purpose**: Verifies running systems and active monitoring
- **When to use**: Regular health checks, troubleshooting

### 3. Resource Recreation Testing
- **File**: `validation/test-resource-recreation.sh`
- **Purpose**: Validates Task 3.2 resource recreation capabilities
- **When to use**: After RBAC changes, recovery system updates

### 4. Integration Testing
- **File**: `validation/test-pattern-simulation.sh`
- **Purpose**: End-to-end testing with real resource creation and pattern detection
- **When to use**: Full system validation, before production deployment

### 5. Health Assessment
- **File**: `validation/post-outage-health-check.sh`
- **Purpose**: Comprehensive health check after system disruptions
- **When to use**: After power outages, cluster restarts, major incidents

### 6. Multi-Node Validation
- **File**: `validation/test-k3s2-node-onboarding.sh`
- **Purpose**: Validates k3s2 worker node integration and multi-node functionality
- **When to use**: Before/after k3s2 onboarding, multi-node cluster validation

## Test Results Interpretation

### Success Indicators
- ✅ All tests pass with green checkmarks
- ✅ Error pattern detector pod is Running
- ✅ Real-time event monitoring is active
- ✅ Recovery patterns are configured
- ✅ RBAC permissions are functional

### Warning Indicators
- ⚠️ Non-critical issues detected
- ⚠️ Some monitoring components have minor issues
- ⚠️ Pattern detection working but with warnings

### Failure Indicators
- ❌ Critical systems not operational
- ❌ Error pattern detector not running
- ❌ Configuration errors detected
- ❌ RBAC permissions missing

## Common Test Scenarios

### After Power Outage
```bash
# Comprehensive health assessment
./tests/validation/post-outage-health-check.sh

# If issues found, run detailed diagnostics
./tests/validation/test-pattern-simulation.sh
```

### After Configuration Changes
```bash
# Validate configuration first
./tests/validation/test-error-pattern-detection.sh

# Then test runtime functionality
./tests/validation/test-tasks-3.1-3.2.sh
```

### Before Production Deployment
```bash
# Full validation suite
./tests/validation/test-error-pattern-detection.sh
./tests/validation/test-resource-recreation.sh
./tests/validation/test-pattern-simulation.sh
```

### Regular Health Monitoring
```bash
# Quick daily check
./tests/validation/test-tasks-3.1-3.2.sh

# Multi-node cluster validation
./tests/validation/test-k3s2-node-onboarding.sh

# Weekly comprehensive check
./tests/validation/test-pattern-simulation.sh
```

## Troubleshooting Test Failures

### Pod Not Running
```bash
# Check pod status
kubectl get pods -n flux-recovery

# Check logs
kubectl logs -n flux-recovery -l app=error-pattern-detector

# Restart if needed
kubectl rollout restart deployment error-pattern-detector -n flux-recovery
```

### Configuration Issues
```bash
# Validate YAML syntax
kubectl get configmap recovery-patterns-config -n flux-recovery -o yaml

# Check Kustomization build
kubectl kustomize infrastructure/recovery/
```

### RBAC Issues
```bash
# Test permissions
kubectl auth can-i get events --as=system:serviceaccount:flux-recovery:error-pattern-detector

# Check role bindings
kubectl describe clusterrolebinding error-pattern-detector
```

## Integration with CI/CD

### Pre-commit Hooks
Add configuration validation to pre-commit hooks:
```bash
# In .pre-commit-config.yaml
- repo: local
  hooks:
    - id: test-error-pattern-config
      name: Test Error Pattern Configuration
      entry: ./tests/validation/test-error-pattern-detection.sh
      language: script
      pass_filenames: false
```

### Deployment Pipeline
Include runtime validation in deployment pipelines:
```bash
# After deployment
./tests/validation/test-tasks-3.1-3.2.sh

# Full validation for production
./tests/validation/test-pattern-simulation.sh
```

### Monitoring Integration
Use test results in monitoring dashboards:
```bash
# Export test results as metrics
./tests/validation/test-tasks-3.1-3.2.sh --export-metrics

# Include in Prometheus monitoring
./tests/validation/post-outage-health-check.sh --prometheus-format
```

## Test Development Guidelines

### Adding New Tests
1. Follow existing naming convention: `test-<component>-<purpose>.sh`
2. Include proper error handling and cleanup
3. Use consistent output formatting (✅ ❌ ⚠️)
4. Document test purpose and expected outcomes
5. Add to this README

### Test Script Structure
```bash
#!/bin/bash
set -euo pipefail

# Test description and purpose
echo "🧪 Testing [Component] [Purpose]"
echo "================================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test tracking
PASSED=0
FAILED=0

# Helper functions
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ $2${NC}"
        ((FAILED++))
    fi
}

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up test resources..."
    # Add cleanup commands
}
trap cleanup EXIT

# Test implementation
# ...

# Results summary
echo "📊 Test Results: $PASSED passed, $FAILED failed"
```

## Maintenance

### Regular Updates
- Review and update test patterns monthly
- Add new test cases for discovered issues
- Update documentation with new scenarios
- Validate tests against latest Kubernetes versions

### Performance Monitoring
- Monitor test execution time
- Optimize slow-running tests
- Add parallel execution where appropriate
- Cache test data when possible

## Related Documentation

- [Error Pattern Detection Testing Guide](../docs/testing/error-pattern-detection-testing.md)
- [Flux Recovery Guide](../docs/troubleshooting/flux-recovery-guide.md)
- [GitOps Resilience Patterns Design](../.kiro/specs/gitops-resilience-patterns/design.md)
- [Tasks Implementation Status](../.kiro/specs/gitops-resilience-patterns/tasks.md)

## Support

For issues with the testing suite:
1. Check the troubleshooting section above
2. Review test logs for specific error messages
3. Validate cluster health with health check script
4. Check related documentation for context

The testing suite is designed to be self-documenting and provide clear guidance on resolving issues.