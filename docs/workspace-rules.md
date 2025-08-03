# Workspace Rules for Planning and Task Tracking

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
