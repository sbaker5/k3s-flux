# Common Breaking Changes Test Scenarios

This directory contains test scenarios for common breaking changes that occur in GitOps environments:

## Scenarios Covered

1. **Label Selector Changes** - Changes to Deployment selectors that would cause immutable field conflicts
2. **Service Type Changes** - Changing Service type from ClusterIP to NodePort/LoadBalancer
3. **StatefulSet Changes** - Changes to StatefulSet selectors and volume claim templates
4. **PVC Storage Changes** - Attempts to modify PVC storage class or size
5. **Namespace Resource Conflicts** - Resources that would conflict with existing namespace resources

## Test Structure

Each scenario has:
- `before/` - Initial state that would be committed first
- `after/` - Modified state that should trigger validation failures
- `description.md` - Explanation of what the test validates

## Expected Behavior

The validation pipeline should:
1. Detect these changes during pre-commit validation
2. Prevent commits that would cause reconciliation failures
3. Suggest appropriate remediation strategies