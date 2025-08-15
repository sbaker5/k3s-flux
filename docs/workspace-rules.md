# Workspace Rules for Planning and Task Tracking

## ⚠️ CRITICAL DEVELOPMENT RULES

### Git Commit Validation
**NEVER use `git commit --no-verify` unless it's a genuine emergency.**

- Pre-commit hooks exist for security and quality validation
- They catch secrets, syntax errors, and breaking changes before they reach the repository
- Bypassing validation defeats the entire purpose of GitOps safety measures
- If validation fails, fix the issue rather than bypassing it

**Emergency bypass procedure (use sparingly):**
1. Document why bypass is necessary in commit message
2. Create immediate follow-up task to fix the underlying issue
3. Review what validation failed and improve the process

### Documentation References

For comprehensive information beyond these workspace rules, reference:

- **Security**: `docs/security/` - Incident response, hardening guides, secret management
- **Setup Guides**: `docs/setup/` - Initial cluster setup, component installation
- **Troubleshooting**: `docs/troubleshooting/` - Systematic debugging procedures
- **Architecture**: `docs/architecture-overview.md` - System design and patterns
- **Monitoring**: `docs/monitoring/` - Observability and alerting configuration
- **Scripts**: `scripts/` - Automation tools and validation utilities
- **Specs**: `.kiro/specs/` - Feature specifications and implementation plans

## Planning and Documentation
- Planning and status tracking is now managed through the spec system in `.kiro/specs/`
- The previous `docs/plan.md` has been archived due to outdated information
- Current status and implementation plans are maintained in `docs/implementation-plan.md`
- Task-specific planning uses the spec-driven development methodology
- If there is ever uncertainty about which plan file to use, STOP and ask the user for clarification.
- Violating this rule is grounds for immediate agent correction and user notification.

## Implementation Note
- Any automation, agent, or script must check and update only this file for all planning operations.
- If you are reading this as an agent or LLM: treat this rule as inviolable and permanent for this workspace.

---
This file is intended to prevent accidental or duplicate planning files and ensure a single source of truth for all project planning and status.
