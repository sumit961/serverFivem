# Police migration: Phase 1

Phase 1 makes `cm-law` the owner of generic law contracts without moving
Police-specific gameplay or database tables.

## Generic Law API

Server resources should use these `cm-law` exports:

- `GetLawMember(source)`
- `GetLawMemberByCharacterId(characterId, organizationId)`
- `GetLawOrganization(organizationId)`
- `HasLawPermission(source, permission, organizationId)`
- `IsLawMember(source)`
- `IsLawMemberOf(source, organizationId)`
- `GetOrganizationArmoryStock(organizationId)`
- `GetOrganizationArmoryItem(organizationId, itemId)`
- `AddOrganizationArmoryStock(organizationId, itemId, amount, context)`
- `RemoveOrganizationArmoryStock(organizationId, itemId, amount, context)`
- `CanAccessOrganizationArmory(source, organizationId)`
- `CheckoutOrganizationArmoryItem(source, organizationId, itemId)`
- `CanUseOrganizationVehicle(source, vehicleId, action)`
- `GetOrganizationMembers(organizationId)`
- `CanManageOrganizationMembers(source, organizationId, targetCharacterId)`
- `SetOrganizationRank(source, targetCharacterId, rankId, organizationId)`
- `RemoveOrganizationMember(source, targetCharacterId, organizationId)`

The source-based APIs resolve the active character on the server. Callers
must not pass or display FiveM source IDs as player identity.

British-spelling `Organisation` aliases are also provided for the shared
armory, fleet, and membership APIs. Armory mutations require a unique
`context.operationId`, a positive integer amount, and a reason. Reusing an
operation ID is idempotent and cannot apply the stock mutation twice.

## Phase 2 ownership mapping

| System | Authority | Compatibility status |
| --- | --- | --- |
| Organisation membership, ranks, duty, permissions | `cm-law` | Police legacy exports retained |
| Organisation armory catalog, stock, and issue records | `cm-law` / `cm_legal_*` | Police UI/callbacks retained |
| Organisation fleet access | `cm-law` / `cm_legal_fleet_vehicles` | `cm-police` Police-only info/track fallback retained |
| Shared dispatch lifecycle and recipients | `cm-law` | `CreatePoliceCall` delegates to Law |
| Organisation activity/history | `cm-law` / `cm_legal_activity_logs` | Existing Police-specific incident logs retained |

`cm-police` remains responsible for MDT, ALPR, K9, radar, evidence,
citations, impound, NPC interactions, wardrobe, and Police-specific station
gameplay. No Police SQL table is renamed, copied, or deleted in Phase 2.

## Compatibility boundary

`cm-police` remains the owner of Police-specific membership fields and
legacy exports during this phase. `GetMember`, `HasPermission`, `IsOnDuty`,
licensing, MDT, ALPR, K9, radar, impound, evidence, citations, wardrobe,
and Police SQL tables are intentionally unchanged.

New Law events and scene-equipment callbacks are namespaced under
`cm-law:*`. The old Police client handoff events remain as compatibility
listeners where existing Police UI contracts require them.

## Not included

This phase does not migrate Police SQL data, rename tables, remove legacy
exports, move Police modules, or change `server.cfg` start order. Those
changes require a separate compatibility and data-migration plan.
