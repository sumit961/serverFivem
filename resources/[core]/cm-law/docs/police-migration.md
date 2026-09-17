# Embedded Police migration — cm-law 2.0

`cm-law` now contains the complete LSPD implementation. Run only `cm-law`;
the standalone `cm-police` resource must not be started at the same time.

If both resources are started, both clients receive the same legacy
`cm-police:client:openDashboard` event. The standalone dashboard can cover the
embedded dashboard, and ESC may appear not to close because it only closes one
of the two active NUI layers. cm-law 2.4 prints a red server-console warning and
an in-game warning when this conflict is detected, but it cannot safely stop a
separate resource on the user's behalf.

## Install

1. Back up the current `cm-law` and `cm-police` folders and database.
2. Replace the existing `cm-law` folder with this release.
3. Remove `ensure cm-police` from `server.cfg` and keep `ensure cm-law`.
4. Do not delete or rename any `cm_police_*` tables. The embedded module reads
   them in place, preserving members, ranks, MDT records, evidence, outfits,
   fleet, facilities, ALPR, and activity history.
5. Restart the server. A live resource restart is not recommended because both
   resources register commands, interaction actions, and state bags at startup.

The legacy `cm-police:*` callbacks and network events are intentionally kept,
so existing event callers continue to work after the standalone folder is gone.

## Export callers in other resources

FiveM exports include the resource name, so an external call written as
`exports['cm-police']:Name(...)` cannot be intercepted after that resource is
deleted. Change its resource name to `cm-law`.

These Police-only names are unchanged and only need that resource replacement:

- `CreatePoliceCall`, `CanUseVehicle`, `AutoIssueWarrant`
- `GetCuffedSuspectInVehicle`, `GetDraggedSuspectForVehicle`
- `GetJailLocation`, `GetJailSpawns`
- `GetLicenseNumber`, `HasValidLicense`, `PurchaseLicense`, `SyncWantedStars`
- `GetPoliceDiagnostics`, `IsCapabilityEnabled`

Shared names collide with cm-law's generic API. Use these Police contracts:

| Old Police export | cm-law 2.0 export |
| --- | --- |
| `GetMember` | `GetMember(characterId, 'police')` |
| `HasPermission` | `HasPermission(characterId, permission, 'police')` |
| `IsOnDuty` | `IsOnDuty(characterId, 'police')` |
| `GetVehicleAccessDecision` | `GetVehicleAccessDecision` (automatic fallback) |
| `GetOrganizationSummary` | `PoliceLegacyGetOrganizationSummary` |
| `AdminAssignLeader` | `PoliceLegacyAdminAssignLeader` |
| `AdminRemoveLeader` | `PoliceLegacyAdminRemoveLeader` |
| `AdminGetFleet` | `PoliceLegacyAdminGetFleet` |
| `AdminConfigureFleetVehicle` | `PoliceLegacyAdminConfigureFleetVehicle` |
| `AdminBeginFleetPlacement` | `PoliceLegacyAdminBeginFleetPlacement` |
| `AdminResetFleetLocation` | `PoliceLegacyAdminResetFleetLocation` |
| `AdminGetArmory` | `PoliceLegacyAdminGetArmory` |
| `AdminConfigureArmory` | `PoliceLegacyAdminConfigureArmory` |
| `AdminGetCapabilities` | `PoliceLegacyAdminGetCapabilities` |
| `AdminConfigureCapability` | `PoliceLegacyAdminConfigureCapability` |
| `AdminGetNpcs` | `PoliceLegacyAdminGetNpcs` |
| `AdminConfigureNpc` | `PoliceLegacyAdminConfigureNpc` |
| `AdminSetFacility` | `PoliceLegacyAdminSetFacility` |

The dedicated `/policeadmin` workspace remains enabled. The central cm-admin
Police adapter is disabled because its generic export names would otherwise
target `cm_legal_*` rather than the authoritative `cm_police_*` tables.

## UI and controls

Both dashboards use one NUI shell and the same command-center stylesheet. The
Police dashboard, MDT, wardrobe, NPC dialogue, impound UI, cinematics, and quick
menu use namespaced NUI callbacks, avoiding duplicate close, refresh, dispatch,
fleet, and admin handlers.

`/police` now opens the full LSPD dashboard; `/policequickmenu` remains the field
action menu. `/policeadmin`, `/reportcrime`, legacy `cm-police:*` open events,
and existing Police key routes remain available. Generic organization contracts
stay under `cm-law:*`.
