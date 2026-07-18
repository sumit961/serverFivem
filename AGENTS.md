# CM FiveM Server — Agent Instructions

## Project scope

- This repository is a complete FiveM server, not a collection of isolated resources.
- Before changing a resource, identify its consumers, dependencies, events, exports, database tables, NUI callbacks and shared contracts.
- Inspect the complete repository when a change may affect multiple resources.
- Never assume an uploaded or mentioned resource operates independently.
- Prefer minimal, compatible changes over unnecessary rewrites.
- Preserve unrelated user modifications in a dirty working tree.

## Source of truth and ownership

Current architectural ownership:

- **cm-core** — framework lifecycle and shared core services.
- **cm-playerdata** — character identity, known/stranger relationships and player interaction data.
- **cm-items** — authoritative shared item definitions unless repository evidence establishes a narrower owner.
- **cm-inventory** — player and container inventory behaviour.
- **cm-weapons** — weapon and ammunition definitions.
- **cm-vehicles** — persistent vehicle identity, physical vehicle entities, condition and vehicle state.
- **cm-house** — house ownership, interiors, garage slots and house access assignments.
- **cm-family** — family membership, ranks, permissions and family-scoped access.
- **cm-admin** — privileged administration, permissions and high-risk activity visibility.
- **cm-ui** — shared UI primitives, interaction presentation, theme and design tokens.
- **cm-climatime** — shared weather and time.
- **oxmysql** — database access layer.
- `vehicle_id` is the authoritative persistent vehicle key. Do not substitute plate or network ID as the database identity.
- Character ID is the authoritative in-game player identity. FiveM server source is transport/session identity only.

Agents must verify these ownership assumptions against actual exports, events and schemas before making high-risk changes — this list is a starting map, not a substitute for reading the resource.

## Identity and privacy

- Never display FiveM server ID/source to normal players.
- Use database character ID in player-facing identity.
- Respect stranger/known-player visibility.
- Never leak account identifiers, tokens or internal permission data to NUI or clients.
- An account may have multiple characters; never confuse account ownership with character ownership.

## Server authority and security

- Treat every client event and NUI request as untrusted.
- Validate permissions, character identity, ownership, membership, rank, distance, routing bucket, entity existence, state, quantity, price and operation context on the server where applicable.
- Security checks must fail closed.
- Never trust client-provided prices, money results, inventory results, vehicle condition, ownership or admin status.
- Protect privileged and high-value operations with rate limiting or operation locks where appropriate.
- Avoid arbitrary client-directed entity spawning.
- Record high-risk actions through the appropriate logging/admin system without exposing secrets.
- Never weaken access control merely to make a feature appear functional.
- Never make cm-admin available to everyone unless the user explicitly requests that exact temporary behaviour and acknowledges the risk.
- Do not print secret values or include them in patches, reports, logs or commits.
- `server.local.cfg` and other ignored credential files must remain untracked.

## Database and persistence

- Prefer parameterised oxmysql queries.
- Database migrations must be safe, explicit and repeatable where practical.
- Use unique constraints for authoritative identities and assignments.
- Use transactions for multi-step ownership, money, inventory, house and vehicle operations.
- Prevent duplicate execution with locks, idempotency keys or operation journals where the risk warrants it.
- Define rollback and reconciliation behaviour for partial failures.
- Never silently convert genuine stored zero vehicle health into full health.
- Distinguish missing/uninitialised condition from genuine damage.
- Never delete a used house interior, garage template or other referenced template without dependency validation.
- Do not destructively alter production data without explicit user approval and a recovery plan.

## Events, exports and compatibility

- Search for all producers and consumers before renaming or changing an event, export, callback or database field.
- Keep existing public contracts compatible unless a coordinated migration is explicitly planned.
- Document newly added public exports, events and permission identifiers.
- Use namespaced event names.
- Network only events that must cross the client/server boundary.
- Do not make events network-safe unnecessarily.
- Validate resource start order and fxmanifest dependencies when adding integrations.
- Do not duplicate business logic already owned by another CM resource.

## UI and interaction rules

- Use cm-ui for shared UI components and design tokens where integration exists.
- Maintain the CM cyan/ice-blue visual identity.
- Do not use purple as the main accent.
- Do not use CSS `backdrop-filter`.
- Prioritise readable typography, clean spacing and production-quality responsive layouts.
- Avoid full-screen UI unless the feature genuinely requires it.
- Shared E interactions should be simple, centred or appropriately positioned, readable and cyan.
- Hide world interaction prompts while an associated NUI interface is open.
- Avoid default FiveM menus when a CM UI interaction exists.
- Do not create noisy normal-player debug notifications.
- Put diagnostic detail in controlled logs or admin/development modes.

## Vehicles, houses and families

- cm-vehicles owns the physical and persistent vehicle state even when a vehicle appears inside a house garage.
- cm-house owns garage slot assignments and access to house garage locations.
- Vehicle recall must preserve the same persistent vehicle identity and prevent duplicates.
- Entity network ID is transient and must not replace persistent vehicle identity.
- Preserve genuine engine, body and tank condition.
- Validate owner or authorised family-rank access server-side.
- Family capabilities must use explicit permission identifiers rather than hard-coded rank names.
- Family house, vehicle, storage, weapon storage, banking and high-risk membership actions require activity logs.
- Prepare integrations through documented exports/events instead of command-only access where future cm-admin or family use is expected.

## Performance and logging

- Avoid tight zero-delay loops unless required for currently visible gameplay.
- Use adaptive waits, caching and event-driven updates where practical.
- Avoid large repeated network payloads.
- Do not broadcast private or irrelevant state server-wide.
- Avoid repeated database queries inside frame loops.
- Remove or gate verbose debug logging before production.
- Investigate hitch warnings, oversized events, uncontrolled entity creation and repeated retry loops.
- Do not hide real errors merely to make logs appear clean.

## Working procedure

For non-trivial changes:

1. Inspect applicable AGENTS.md files.
2. Check git status and preserve unrelated work.
3. Identify affected resources and contracts.
4. Explain a concise implementation plan.
5. Implement the smallest coherent change.
6. Run proportionate validation.
7. Review security and backward compatibility.
8. Report changed files, checks performed, remaining risks and manual gameplay tests.

For a diagnosis-only request, do not implement unless asked.
For a review request, report findings before changing code.
Do not deploy to a live server without explicit approval.

## Validation expectations

Where applicable, verify:

- Lua syntax.
- fxmanifest files and referenced paths.
- NUI dependency installation/build/lint.
- Event/export/callback consumers.
- SQL migrations and constraints.
- Client/server trust boundaries.
- Permission enforcement.
- Resource dependencies and start order.
- Debug output and secret exposure.
- Relevant regression paths.

State clearly when a behaviour requires manual FiveM gameplay testing. Never claim a runtime fix is fully verified using syntax checks alone.

## Response expectations

- Lead with the result.
- Use exact file paths when reporting changes.
- Separate verified facts from assumptions.
- Do not claim tests passed unless they were run.
- Include concise manual test steps for gameplay behaviour.
- Mention blockers and remaining risks directly.
- Never expose credential values.

## Project intelligence tools

- Portable workflow skill: `.agents/skills/cm-server-agent/SKILL.md`.
- FiveM contract scanner: `tools/cm-fivem-map/scan.py`.
- Generated contract map: `cm-agent-out/` (events, exports, NUI, ox_lib
  callbacks, MySQL/oxmysql, commands, permissions).
- Generic call graph: `graphify-out/`.
- Manifest registry: `agent-docs/resource-registry.yaml`.
- Use the CM scanner for FiveM events/exports/NUI/callbacks/MySQL — it has
  FiveM-specific knowledge Graphify does not.
- Use Graphify only as a supplemental generic call graph.
- Refresh or `--check` both maps before and after non-trivial
  cross-resource work.
- Generated output directories remain ignored and must not be committed by
  default.
- AI tools that do not automatically discover `.agents/skills/` must be
  explicitly told to read `.agents/skills/cm-server-agent/SKILL.md`.
