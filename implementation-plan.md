# CM License Test System — Implementation Plan

## Phase 1: Audit & Planning (Current)

### Status
- ✅ Reviewed specification (54 points, comprehensive requirements)
- ⏳ Audit of existing CM APIs in progress
- ⏳ Identifying integration points and dependencies

### Known Resources
From resource-registry.yaml:
- **cm-admin** (14) — Admin UI and permissions
- **cm-core** (6) — Framework lifecycle
- **cm-ui** — Shared UI components
- **cm-playerdata** — Character identity
- **cm-inventory** — Inventory system
- **cm-vehicles** — Vehicle spawning and persistence
- **cm-items** — Item definitions
- **oxmysql** — Database wrapper

### Key Requirements from Specification
1. **Core System**: Driver, Boat, Air license exams via interactive NPC
2. **Admin Setup**: Visual in-game route creation (no manual coordinates)
3. **Player Flow**: NPC → Test selection → Payment → Vehicle spawn → Checkpoints → Finish → License item
4. **Database**: Authoritative license records with expiration
5. **Security**: Server-side validation, no client trust
6. **Integration**: Police can check licenses via export; inventory items as physical representation

---

## Phase 2: Core Data Model

### Database Schema (SQL Migration)

```sql
-- cm_license_types: Admin-configured test types
CREATE TABLE cm_license_types (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_type VARCHAR(50) UNIQUE NOT NULL,  -- 'driver', 'boat', 'air'
    label VARCHAR(100) NOT NULL,               -- 'Driver License'
    item_name VARCHAR(50) NOT NULL,            -- 'driver_license'
    price INT NOT NULL,
    valid_days INT DEFAULT 30,
    vehicle_model VARCHAR(50),
    vehicle_category VARCHAR(20),              -- 'ground', 'boat', 'air'
    npc_model VARCHAR(50),
    npc_coords JSON,                           -- {x, y, z, heading}
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- cm_license_routes: Test routes
CREATE TABLE cm_license_routes (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_type_id INT NOT NULL,
    vehicle_spawn JSON NOT NULL,               -- {x, y, z, heading}
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id)
);

-- cm_license_checkpoints: Route checkpoints
CREATE TABLE cm_license_checkpoints (
    id INT PRIMARY KEY AUTO_INCREMENT,
    route_id INT NOT NULL,
    sequence INT NOT NULL,
    point_type ENUM('start', 'checkpoint', 'finish') NOT NULL,
    x FLOAT NOT NULL,
    y FLOAT NOT NULL,
    z FLOAT NOT NULL,
    heading FLOAT,
    radius FLOAT DEFAULT 20.0,
    max_speed INT,
    min_altitude INT,
    max_altitude INT,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (route_id) REFERENCES cm_license_routes(id),
    UNIQUE KEY unique_route_sequence (route_id, sequence),
    INDEX idx_route_sequence (route_id, sequence)
);

-- cm_character_licenses: Player licenses
CREATE TABLE cm_character_licenses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    character_id INT NOT NULL,
    license_type_id INT NOT NULL,
    issued_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    status ENUM('active', 'expired', 'revoked') DEFAULT 'active',
    revoked_at BIGINT,
    revoked_by INT,
    revoke_reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id),
    UNIQUE KEY unique_character_license (character_id, license_type_id, status),
    INDEX idx_character_id (character_id),
    INDEX idx_expires_at (expires_at)
);
```

### In-Memory Cache Strategy
- Cache all cm_license_types on resource start
- Cache routes/checkpoints per license_type on demand
- Invalidate on admin updates
- Never cache active test sessions or character licenses (always DB check)

---

## Phase 3: Admin Setup System

### Admin Commands/Menu Integration
- `/licensesetup` or CM-Admin integration
- List existing tests → Create/Edit/Delete/Preview/Test

### Admin Workflows

1. **Create Test**
   - Step 1: License details (name, type, item, price, validity days)
   - Step 2: Select vehicle model (search, spawn preview near admin)
   - Step 3: Confirm vehicle and spawn position (positioning mode with E to save)
   - Step 4: Set NPC (model, coords, heading)
   - Step 5: Create route (start point → checkpoints → finish)
   - Step 6: Route preview and confirm

2. **Route Creator**
   - Admin gets in vehicle, drives/flies/sails
   - E = Set Start Point (first time only)
   - E = Add Checkpoint (repeatable, auto-increments)
   - G = Set Finish (marks final point, exits creator)
   - Menu buttons: Undo Last, Finish Route, Cancel

3. **Route Editor** (after creation)
   - Select checkpoint by number
   - Move, Delete, Insert Before/After
   - Change Radius, Max Speed, Altitude limits
   - Auto-renumber after edits

---

## Phase 4: Player Testing Flow

### NPC Interaction
1. Player presses E on NPC
2. Shows dialogue with options:
   - 🚗 Driver License ($500)
   - 🚤 Boat License ($1,000)
   - ✈️ Air License ($5,000)
   - 📄 My Licenses
   - ❌ Leave

### License Selection → Payment → Vehicle Spawn
1. Player selects license type
2. Server validates:
   - Character loaded
   - No active test
   - No valid license of that type already
   - Player has enough money
3. Confirmation screen shows fee and requirements
4. On confirm: Deduct money (atomic), spawn vehicle, mark test active
5. Vehicle marked with state: `cmLicenseTest=true`, `cmLicenseOwner=characterId`

### Test Execution
1. Player enters vehicle
2. Travels to START POINT
3. E to start test (marks test as "in_progress")
4. Follow checkpoints in order (server validates progression)
5. Reach FINISH checkpoint
6. Server validates completion, issues license item, marks test complete

### License Item
- Item name: `driver_license`, `boat_license`, `air_license`
- Metadata: `{licenseType, characterId, firstName, lastName, issuedAt, expiresAt, validDays}`
- NPC can show "My Licenses" screen displaying all 3 types with expiry

### Failure Conditions
- Vehicle destroyed
- Player dies
- Player abandons vehicle
- Player goes far from route
- Test timeout
- Too many mistakes
- Player disconnects
- Admin cancels test

All delete vehicle, end session, show failure message (no refund default).

---

## Phase 5: License Expiration & Renewal

### Expiration Logic
- Check on character load
- Check periodically (configurable interval, e.g., every 5 min)
- Check on inventory open
- Check when police/systems query via export

### Automatic Cleanup
- If `current_time >= expires_at`:
  1. Mark DB record `status='expired'`
  2. Remove matching inventory item (filter by license_type + characterId)
  3. If item removal fails, log and retry on next interval

### Renewal
- Expired license → NPC says "You must complete the exam again"
- Player takes test again (pays full fee, no auto-renewal)

---

## Phase 6: Security & Recovery

### Transaction Safety
- Use DB transactions for multi-step operations:
  1. Verify test session exists and is active
  2. Verify checkpoint completion in correct order
  3. Mark test as "completing" (operation lock)
  4. Issue/update license in DB
  5. Add inventory item
  6. Mark test as "complete"
- Fail-closed: If any step fails, log error, notify player, do not give license or money back

### Duplicate Prevention
- One active test per character at a time
- Unique constraint: `(character_id, license_type_id, status)` on cm_character_licenses
- Server-side session tracking prevents double-payment
- Inventory item issuance is idempotent (upsert pattern if item already exists)

### Disconnect/Crash Handling
- On player disconnect:
  1. End active test session
  2. Delete spawned vehicle
  3. Clear temp vehicle keys
  4. Do NOT grant license
  5. Do NOT refund money (default)

### Vehicle Security
- Spawned test vehicles marked with entity state
- Cannot be stored/sold/transferred (check in cm-inventory/cm-vehicles hooks)
- Deleted on test end or resource restart
- No permanent ownership created

---

## Phase 7: Exports & Events

### Server Exports
```lua
-- Check if player has valid license
exports('HasLicense', function(characterId, licenseType)
    -- Returns: true, licenseData OR false, reason
end)

-- Get all licenses for character
exports('GetLicenses', function(characterId)
    -- Returns table of license records
end)

-- Get specific license
exports('GetLicense', function(characterId, licenseType)
    -- Returns license record or nil
end)

-- Revoke license (admin)
exports('RevokeLicense', function(characterId, licenseType, reason)
    -- Returns: true or false
end)
```

### Events
```lua
-- Client events
'cm-license:client:testStarted'       -- {testId, licenseType, ...}
'cm-license:client:setCheckpoint'     -- {checkpointNumber, totalCheckpoints, ...}
'cm-license:client:testCompleted'     -- {licenseType, validDays}
'cm-license:client:testFailed'        -- {reason}

-- Server events (validation only)
'cm-license:server:requestStartTest'
'cm-license:server:checkpointReached'
'cm-license:server:finishTest'
'cm-license:server:cancelTest'
```

---

## Phase 8: UI/NUI

### Components Needed
1. **NPC Dialogue Menu** — License selection, My Licenses view
2. **Test Confirmation Screen** — Price, requirements, start/cancel buttons
3. **Test HUD Panel** — Small side display (checkpoint, distance, mistakes, altitude)
4. **Test Result Screen** — Pass/Fail with details
5. **License Item Display** — When player uses item from inventory
6. **Admin Setup UI** — License type list, test editor, route visualizer
7. **Checkpoint Markers** — Cyan checkpoints visible only to player in test

### Design Principles
- Use cm-ui components where available
- Cyan/ice-blue theme, clean spacing, dark background
- No purple, no backdrop-filter
- Small panels (not full-screen unless necessary)
- Clean E interaction prompts
- Minimal clutter

---

## Implementation Checklist

### Phase 1 ✅
- [x] Review specification
- [x] Understand existing CM architecture
- [x] Identify integration points

### Phase 2
- [ ] Create SQL migration
- [ ] Implement cache system
- [ ] Create config.lua with defaults

### Phase 3
- [ ] Admin command/menu registration
- [ ] License type CRUD
- [ ] Vehicle selection UI
- [ ] NPC setup UI
- [ ] Route creator (E to add checkpoints, G to finish)
- [ ] Route editor/preview
- [ ] Admin test mode (spawn vehicle, no payment, no license)

### Phase 4
- [ ] NPC interaction and dialogue
- [ ] License selection menu
- [ ] Confirmation screen
- [ ] Test payment and vehicle spawn
- [ ] Checkpoint detection and validation
- [ ] Test completion logic
- [ ] License item issuance

### Phase 5
- [ ] Expiration checking on character load
- [ ] Periodic expiration check
- [ ] Expired item removal from inventory
- [ ] Renewal flow in NPC dialogue

### Phase 6
- [ ] Event validation and error handling
- [ ] Duplicate prevention mechanisms
- [ ] Disconnect/crash handling
- [ ] Vehicle security (state/statebags)

### Phase 7
- [ ] Export implementations
- [ ] Event registrations
- [ ] Police integration documentation

### Phase 8
- [ ] NUI for all dialogues and menus
- [ ] Checkpoint markers
- [ ] Test HUD
- [ ] Result screens
- [ ] Admin setup UI

### Phase 9: Validation
- [ ] Lua syntax check
- [ ] fxmanifest.lua validation
- [ ] SQL migration safety
- [ ] Event/export consumer check
- [ ] Security review (server authority, client trust)
- [ ] Manual gameplay tests

---

## Resource Structure

```
cm-license/
├── fxmanifest.lua
├── config.lua
├── README.md
│
├── client/
│   ├── main.lua
│   ├── npc.lua
│   ├── test.lua
│   ├── checkpoints.lua
│   ├── hud.lua
│   └── admin.lua
│
├── server/
│   ├── main.lua
│   ├── licenses.lua
│   ├── tests.lua
│   ├── admin.lua
│   ├── database.lua
│   └── cache.lua
│
├── shared/
│   ├── constants.lua
│   └── utils.lua
│
├── sql/
│   └── 001_cm_license.sql
│
└── nui/
    ├── index.html
    ├── style.css
    └── script.js
```

---

## Dependencies

- **oxmysql** — Database
- **cm-core** — Character/player lifecycle
- **cm-playerdata** — Character ID, identity
- **cm-inventory** — License item storage
- **cm-vehicles** — Vehicle spawning (optional but preferred)
- **cm-ui** — Shared components (optional, fallback to custom)
- **cm-admin** — Admin permissions (optional, fallback to admin check)

---

## Remaining Unknowns (Waiting for Audit)
1. Character lifecycle events (when loaded, when unloaded)
2. Money deduction API and validation pattern
3. Inventory item addition/removal API and failure handling
4. Vehicle spawn API (model, position, temporary ownership)
5. Admin permission checking API
6. Existing NPC dialogue/interaction UI pattern
7. Database migration pattern
8. Entity state/statebag usage examples

---

## Next Steps
1. ✅ Audit returns → Update plan with actual API signatures
2. Create resource skeleton
3. Implement SQL migration
4. Implement server-side cache and license logic
5. Implement admin setup system (NPC, vehicle, route)
6. Implement player test flow
7. Implement expiration and renewal
8. Implement NUI/UI components
9. Comprehensive testing and validation
