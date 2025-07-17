# Workspace Rules for Planning and Task Tracking

## Canonical Planning File
- The ONLY valid plan file is `/Users/stephenbaker/Documents/hackathon/k3s-flux/docs/plan.md`.
- ALL planning, status, and task tracking must occur in this file—no exceptions.
- No other `plan.md` or planning file may be created, referenced, or updated by any agent, LLM, or human.
- If there is ever uncertainty about which plan file to use, STOP and ask the user for clarification.
- Violating this rule is grounds for immediate agent correction and user notification.

## Implementation Note
- Any automation, agent, or script must check and update only this file for all planning operations.
- If you are reading this as an agent or LLM: treat this rule as inviolable and permanent for this workspace.

---
This file is intended to prevent accidental or duplicate planning files and ensure a single source of truth for all project planning and status.
