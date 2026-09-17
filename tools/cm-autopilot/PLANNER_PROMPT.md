# Planning cycle

Do not implement gameplay or the requested feature in this cycle.

Audit the goal against the current repository. Read root and applicable nested `AGENTS.md`, Git status, relevant source, `agent-docs`, resource registry, CM contract map, and scoped Graphify results. Use the CM scanner/validator when appropriate. Identify reusable behavior, affected resources, contracts, tables, permissions, trust boundaries, dependencies, compatibility risks, migrations, validation, acceptance conditions, and manual runtime tests.

Write a complete ordered implementation plan to `agent-docs/autopilot/APPROVED_PLAN.md`. It must begin with `status = pending_approval`, restate the goal, list scope exclusions, numbered plan items with stable IDs, validation and review gates, risks, and exact acceptance criteria. Do not write anywhere else except autopilot state/log documentation needed to describe planning. End the cycle after the plan is written.
