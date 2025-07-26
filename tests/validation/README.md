# Validation Pipeline Tests

This directory contains test cases for validating the GitOps resilience validation pipeline, specifically testing:

1. **Kustomization Build Validation** - Tests that ensure kustomization.yaml files build correctly
2. **Immutable Field Change Detection** - Tests that detect problematic changes to immutable Kubernetes fields

## Test Structure

- `test-cases/` - Sample configurations that should trigger validation failures
- `valid-cases/` - Sample configurations that should pass validation
- `run-validation-tests.sh` - Main test runner script
- `test-scenarios/` - Specific test scenarios with before/after states

## Running Tests

```bash
# Run all validation tests
./tests/validation/run-validation-tests.sh

# Run specific test category
./tests/validation/run-validation-tests.sh --category kustomization
./tests/validation/run-validation-tests.sh --category immutable-fields

# Run with verbose output
./tests/validation/run-validation-tests.sh --verbose
```

## Test Categories

### Kustomization Build Tests
- Invalid YAML syntax
- Missing resource references
- Circular dependencies
- Invalid patch targets

### Immutable Field Tests
- Deployment selector changes
- Service clusterIP modifications
- StatefulSet selector changes
- PVC storage class changes