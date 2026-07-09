# cm-admin v2.6.0 — Role-Based Map, Logs, GPS TP, Admin Tags

## Added
- Added `cm-ui` dependency and shared CM UI CSS/JS references.
- Added GTA live staff map using the same local GTA map asset style used by `cm-climatime`.
- Added live online player markers on admin map.
- Added optional vehicle markers on admin map, loaded only when the UI toggle is enabled and the rank can view vehicles.
- Added logged-in admin markers on admin map, permission-gated by `map.admins` or `admins.view`.
- Added GPS teleport button and `/cmtp` command.
- Added admin overhead tag while `/admin` is enabled:
  - shows `Administrator`
  - shows admin player name
  - shows database character ID only
  - never shows server ID in the overhead tag
- Added invisible noclip by default through `Config.MakeInvisible = true`.
- Added bigger role-based Developer launcher panel support using existing `RegisterDevTool` export.
- Added built-in developer launchers for:
  - `cm-climatime` via `climatime`
  - climatime zone debug via `climazone`
  - HUD admin via `hud admin`
  - clothing shop admin
  - vehicle admin
  - weapon admin placeholder
- Added drag/drop rank permission builder.
- Added `×` remove button for assigned rank permissions.
- Added role-based log categories:
  - `admin`
  - `players`
  - `economy`
  - `inventory`
  - `vehicles`
  - `dev`
  - `system`
- Added external audit log bridge for future resources:

```lua
exports['cm-admin']:AddLog(source, 'family_invite', {
    category = 'players',
    familyId = 1
}, targetIdentifier, targetName)
```

or:

```lua
TriggerEvent('cm-admin:server:addLog', source, 'org_created', {
    category = 'system',
    orgId = 5
})
```

## Changed
- Admin map now displays character ID labels instead of using server ID as the visible player ID.
- Production console logging is quieter through `Config.QuietConsoleLogs = true`.
- Developer tools now write to the central audit log bridge.
- Map data refresh is throttled server-side and client-side.
- Map canvas drawing is batched through `requestAnimationFrame`.
- Closing/opening developer tools now restores HUD focus state more safely.

## Permissions Added
- `map.view`
- `map.vehicles`
- `map.admins`
- `gps.teleport`
- `logs.all`
- `logs.admin`
- `logs.players`
- `logs.economy`
- `logs.inventory`
- `logs.vehicles`
- `logs.dev`
- `logs.system`
- `dev.hud`

## Notes
- Existing DB ranks are created with `INSERT IGNORE`, so if you already created ranks before v2.6.0, open the Ranks tab as owner and drag the new permissions into each rank.
- The admin overhead tag uses `cm_admin_tag` statebag set by `cm-admin` after `/admin` is enabled.
- Player visible IDs remain database character IDs.
