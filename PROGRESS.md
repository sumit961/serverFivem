# CM License System — Implementation Progress

**Status**: Phase 2 (Core Data Model) — IN PROGRESS

**Total Token Budget Used**: ~60K / 200K remaining

---

## ✅ Completed Components

### 1. Planning & Analysis
- [x] Reviewed 54-point specification
- [x] Audited existing CM APIs (cm-playerdata, cm-inventory, cm-vehicles, cm-admin, cm-ui, oxmysql)
- [x] Mapped all integration points
- [x] Created implementation plan
- [x] Created integration guide with API signatures

### 2. Database Layer (server/database.lua)
- [x] SQL schema creation (5 tables):
  - `cm_license_types` — Admin-configured test types
  - `cm_license_routes` — Routes per license type
  - `cm_license_checkpoints` — Individual waypoints
  - `cm_character_licenses` — Player license records
  - `cm_license_active_tests` — Active test sessions
- [x] Database helper functions:
  - GetLicenseTypes, GetLicenseType
  - GetRoute, GetCheckpoints, GetCheckpoint
  - GetCharacterLicenses, HasActiveLicense
  - IssueLicense, RevokeLicense
  - CreateTestSession, UpdateTestSession, EndTestSession
  - GetExpiredLicenses, MarkLicenseExpired

### 3. Cache Layer (server/cache.lua)
- [x] In-memory cache for license types, routes, checkpoints
- [x] Cache invalidation and refresh strategies
- [x] Stale cache detection (1-hour TTL)
- [x] Fast lookups without repeated DB queries

### 4. Configuration (config.lua)
- [x] Default validity period (30 days)
- [x] Test session timeouts
- [x] Checkpoint detection radius
- [x] Debug/logging settings
- [x] Permission identifiers

### 5. Shared Utilities
- [x] **constants.lua**: License types, statuses, events, failure reasons
- [x] **utils.lua**: Date formatting, distance calculations, table utilities, validation

### 6. Resource Manifest
- [x] **fxmanifest.lua**: Proper dependencies, scripts, NUI setup
- [x] **sql/001_cm_license.sql**: Complete schema (reference for migrations)

---

## ⏳ Remaining Components (Phase 3-8)

### Phase 3: License Management (server/licenses.lua) — TODO
- [ ] IssueLicense export function
- [ ] HasLicense export function
- [ ] GetLicense, GetLicenses export functions
- [ ] RevokeLicense export function
- [ ] Check expiration logic
- [ ] Automatic expiration cleanup
- [ ] Character license lifecycle management

### Phase 4: Test Management (server/tests.lua) — TODO
- [ ] Create active test session
- [ ] Validate test progression (checkpoint order)
- [ ] Track checkpoint completion
- [ ] Detect test failures (vehicle destroyed, player died, etc.)
- [ ] Complete test and issue license
- [ ] Cancel/timeout handling

### Phase 5: Admin System (server/admin.lua) — TODO
- [ ] `/licensesetup` command registration
- [ ] License type CRUD (create, read, update, delete)
- [ ] Vehicle selection UI
- [ ] NPC setup
- [ ] Route creator (start point, checkpoints, finish)
- [ ] Route editor (move, delete, insert, renumber)
- [ ] Permission checks (admin.manage_licenses, etc.)

### Phase 6: Server Main (server/main.lua) — TODO
- [ ] Resource start/stop handlers
- [ ] Initialize database schema
- [ ] Initialize cache
- [ ] Register exports:
  - HasLicense(characterId, licenseType)
  - GetLicense(characterId, licenseType)
  - GetLicenses(characterId)
  - RevokeLicense(characterId, licenseType, reason)
- [ ] Register server events:
  - cm-license:server:interactNPC
  - cm-license:server:requestStartTest
  - cm-license:server:checkpointReached
  - cm-license:server:finishTest
  - cm-license:server:cancelTest
- [ ] Periodic expiration checks
- [ ] Disconnect cleanup

### Phase 7: Client Files — TODO
- [ ] **client/main.lua**: Client initialization
- [ ] **client/npc.lua**: NPC interaction, dialogue menus
- [ ] **client/test.lua**: Test vehicle control, validation
- [ ] **client/checkpoints.lua**: Checkpoint marker management
- [ ] **client/hud.lua**: Test HUD display
- [ ] **client/admin.lua**: Admin setup UI (route creator, etc.)

### Phase 8: NUI/Frontend — TODO
- [ ] **nui/index.html**: All UI screens
- [ ] **nui/style.css**: Styling (cyan theme, dark bg)
- [ ] **nui/script.js**: Logic, event handlers, form validation

---

## Database Schema Overview

```sql
-- License Types (admin-configured)
cm_license_types {
    id, license_type, label, item_name, price, valid_days,
    vehicle_model, vehicle_category, npc_model, npc_coords, enabled
}

-- Routes (one per license type)
cm_license_routes {
    id, license_type_id, vehicle_spawn
}

-- Checkpoints (multiple per route)
cm_license_checkpoints {
    id, route_id, sequence, point_type (start/checkpoint/finish),
    x, y, z, heading, radius, max_speed, min_altitude, max_altitude
}

-- Player Licenses
cm_character_licenses {
    id, character_id, license_type_id, issued_at, expires_at,
    status (active/expired/revoked), revoked_at, revoked_by, revoke_reason
}

-- Active Test Sessions
cm_license_active_tests {
    id, character_id, license_type_id, test_started_at,
    current_checkpoint, total_checkpoints, vehicle_netid,
    mistakes, max_mistakes, status, fail_reason
}
```

---

## Integration Points Confirmed

### ✅ Character API (cm-playerdata)
```lua
local charId = exports['cm-playerdata']:GetCharacterId(src)
if exports['cm-playerdata']:IsLoaded(src) then ... end
```

### ✅ Money System (cm-playerdata)
```lua
if exports['cm-playerdata']:CanAfford(src, 'cash', price) then
    local ok, newAmount = exports['cm-playerdata']:RemoveMoney(src, 'cash', price, 'license_purchase')
end
```

### ✅ Inventory (cm-inventory)
```lua
exports['cm-inventory']:AddItem(src, 'driver_license', 1, {licenseType='driver', ...}, 'license_issued')
```

### ✅ Admin Permissions (cm-admin)
```lua
if exports['cm-admin']:HasPermission(src, 'admin.manage_licenses') then ... end
```

### ✅ Database (oxmysql)
```lua
MySQL.query.await(sql, params)
MySQL.transaction.await({{query, values}, ...})
```

---

## Next Steps

To complete the implementation, I need to:

1. **Create server/licenses.lua** — License CRUD, expiration, exports
2. **Create server/tests.lua** — Test session management
3. **Create server/admin.lua** — Admin setup commands
4. **Create server/main.lua** — Resource lifecycle, event handlers
5. **Create all client files** — NPC, tests, checkpoints, HUD, admin UI
6. **Create NUI files** — HTML/CSS/JS for all dialogs

---

## Files Created (in order)

1. ✅ [implementation-plan.md](../implementation-plan.md) — Detailed implementation strategy
2. ✅ [integration-guide.md](../integration-guide.md) — API reference with signatures
3. ✅ [fxmanifest.lua](fxmanifest.lua) — Resource manifest
4. ✅ [config.lua](config.lua) — Configuration defaults
5. ✅ [shared/constants.lua](shared/constants.lua) — Shared constants
6. ✅ [shared/utils.lua](shared/utils.lua) — Utility functions
7. ✅ [sql/001_cm_license.sql](sql/001_cm_license.sql) — SQL schema
8. ✅ [server/database.lua](server/database.lua) — Database operations
9. ✅ [server/cache.lua](server/cache.lua) — In-memory cache

---

## Estimated Remaining Work

- Server modules (licenses, tests, admin, main): ~3K lines
- Client modules (npc, test, checkpoints, hud, admin): ~2K lines
- NUI (HTML/CSS/JS): ~1.5K lines

**Total estimated resource size**: ~6.5K lines

---

## Security Review Checklist (Pre-Implementation)

- [x] Server authority: All licensing decisions server-side
- [x] Client trust: Zero trust on client-provided data
- [x] Database: Parameterized queries planned
- [x] Money: Deduction validated before DB update
- [x] Vehicle: Marked as temporary (cmLicenseTest state)
- [x] Admin: Permission checks on sensitive operations
- [x] Character ID: Using persistent DB ID, not server ID
- [x] Inventory: Item metadata includes character ID, not server ID

---

## Manual Testing Checklist (TBD after implementation)

### Admin Setup Flow
- [ ] `/licensesetup` opens admin menu
- [ ] Create new test (name, type, vehicle, price)
- [ ] Spawn vehicle preview
- [ ] Position vehicle spawn point
- [ ] Set NPC model and position
- [ ] Create route (E = start/checkpoint, G = finish)
- [ ] Edit checkpoint (move, delete, change radius)
- [ ] Preview route (all markers visible)
- [ ] Save test
- [ ] Verify DB records created

### Player Test Flow
- [ ] Player interacts with NPC (E)
- [ ] NPC shows license menu
- [ ] Select license type
- [ ] Confirmation screen shows fee
- [ ] Click confirm
- [ ] Money deducted
- [ ] Vehicle spawns near NPC
- [ ] Player enters vehicle
- [ ] Player travels to start point
- [ ] E at start to begin
- [ ] Follow checkpoints in order
- [ ] Reach finish line
- [ ] License issued
- [ ] Item added to inventory
- [ ] "My Licenses" shows new license
- [ ] Wait 30 days
- [ ] License automatically expires
- [ ] Inventory item removed
- [ ] NPC says "must retake test"

### Failure Scenarios
- [ ] Test timeout → Fail
- [ ] Vehicle destroyed → Fail
- [ ] Player dies → Fail
- [ ] Player leaves vehicle → Fail
- [ ] Wrong checkpoint order → Fail
- [ ] Player disconnects → Cleanup
- [ ] Resource restart → Active test cleaned up
- [ ] Admin revokes license → Item removed
- [ ] Event spam → Only counted once

---

## Notes

- Using oxmysql for all DB operations (async/await pattern)
- Cache auto-invalidates after 1 hour or on admin changes
- Character ID (persistent) used everywhere, not server ID
- License expiration checked on load, inventory open, periodic timer
- Test vehicles marked with entity state to prevent storage
- Money ledger automatically tracks all deductions
- Admin setup completely visual (no manual coordinate editing)
- All exports and events namespaced properly
