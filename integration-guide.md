# CM License Resource — Integration Guide

This document covers the concrete API signatures discovered during audit, ready for implementation.

---

## Character/Player APIs

### Get Character ID
```lua
local charId = exports['cm-playerdata']:GetCharacterId(src)
-- Returns: number (character ID) or nil
```

### Check Character Loaded
```lua
if exports['cm-playerdata']:IsLoaded(src) then
    -- Character ready for operations
end
```

### Get Full Character Data
```lua
local charData = exports['cm-playerdata']:GetCharacterData(src)
-- Returns: {CharacterId, Character, ...}
```

---

## Money System

### Check Affordability
```lua
if exports['cm-playerdata']:CanAfford(src, 'cash', 5000) then
    -- Player has $5000+ in cash
end
```

### Deduct Money (Use this for license fees)
```lua
local ok, newAmount = exports['cm-playerdata']:RemoveMoney(src, 'cash', 5000, 'license_purchase')
if ok then
    -- Money deducted successfully, newAmount is new balance
    -- Transaction logged to money_ledger table automatically
else
    -- Insufficient funds or error
    -- newAmount contains error reason
end
```

### Add Money (for refunds if needed)
```lua
local ok, newAmount = exports['cm-playerdata']:AddMoney(src, 'cash', 5000, 'license_refund')
```

### Get Current Balance
```lua
local amount = exports['cm-playerdata']:GetMoney(src, 'cash')
-- Returns: number (0 if not found)
```

---

## Inventory System

### Add License Item
```lua
local ok, slot = exports['cm-inventory']:AddItem(
    src,
    'driver_license',  -- item name
    1,                 -- quantity
    {
        licenseType = 'driver',
        characterId = charId,
        firstName = 'John',
        lastName = 'Doe',
        issuedAt = os.time(),
        expiresAt = os.time() + (30 * 86400),  -- 30 days
        validDays = 30
    },  -- metadata
    'license_issued'   -- reason
)

if ok then
    -- Item added successfully at slot position
else
    -- slot contains error reason
    -- Possible errors: 'inventory_full', 'item_not_found', etc.
end
```

### Remove Item
```lua
local ok, qty = exports['cm-inventory']:RemoveItem(src, 'driver_license', 1)
-- Returns: ok, newQuantity
```

### Check Inventory Can Carry
```lua
local can, reason = exports['cm-inventory']:CanCarryItem(src, 'driver_license', 1)
if not can then
    -- reason = error message
end
```

### Get Inventory State
```lua
local inv = exports['cm-inventory']:GetInventory(src)
-- Returns: { slots: {...}, info: {...}, accounts: {...} }
```

---

## Vehicle Spawning (for test vehicles)

### Create Test Vehicle (temporary, not permanent)
```lua
-- cm-vehicles API
local ok, err, vehicleInfo = exports['cm-vehicles']:SpawnVehicleFromParking(
    vehicleId,
    vec4(x, y, z, heading),
    { temporary = true }
)
-- For temp test vehicles, use entity state instead of DB

-- OR manually spawn:
local model = GetHashKey('blista')
RequestModel(model)
while not HasModelLoaded(model) do Wait(0) end

local entity = CreateVehicle(model, x, y, z, heading, true, false)
SetEntityAsMissionEntity(entity, true, true)

-- Mark as test vehicle via state
Entity(entity).state:set('cmLicenseTest', true, true)
Entity(entity).state:set('cmLicenseOwner', charId, true)
Entity(entity).state:set('cmLocked', true, true)
```

### Grant Vehicle Access
```lua
-- Create temp vehicle key
local netId = NetworkGetNetworkIdFromEntity(entity)
-- Track locally: ActiveTestVehicles[charId] = { netId, vehicleModel, ... }
```

### Delete Test Vehicle Safely
```lua
if DoesEntityExist(entity) then
    DeleteEntity(entity)
end
```

---

## Admin Permissions

### Check Admin Permission
```lua
local hasPermission = exports['cm-admin']:HasPermission(src, 'admin.manage_licenses')
if hasPermission then
    -- Allow action
else
    -- Deny, optionally notify player
    TriggerClientEvent('chat:addMessage', src, {
        args = { 'License System', 'No permission' }
    })
end
```

### Permission Strings to Create
- `admin.manage_licenses` — Create/edit/delete tests
- `admin.issue_licenses` — Issue licenses to players
- `admin.revoke_licenses` — Revoke licenses

### Admin Rank Storage
- Table: `cm_admin_ranks`
  - `rank_name` (PK)
  - `label`
  - `level`
  - `permissions_json` (JSON array of permission strings)

---

## Database & Queries

### Connection Setup
```lua
-- oxmysql is already loaded via:
-- @oxmysql/lib/MySQL.lua in fxmanifest

-- Usage pattern:
local rows = MySQL.query.await('SELECT * FROM table WHERE id = ?', { id })
local row = MySQL.single.await('SELECT * FROM table WHERE id = ?', { id })
local count = MySQL.scalar.await('SELECT COUNT(*) FROM table')
local result = MySQL.insert.await('INSERT INTO table (...) VALUES (...)', params)
```

### Transaction Pattern (for atomic license issue)
```lua
local success = MySQL.transaction.await({
    {
        query = 'UPDATE cm_character_licenses SET status = ? WHERE character_id = ? AND license_type_id = ?',
        values = { 'expired', charId, typeId }
    },
    {
        query = 'INSERT INTO cm_character_licenses (character_id, license_type_id, issued_at, expires_at, status) VALUES (?, ?, ?, ?, ?)',
        values = { charId, typeId, os.time(), expiresAt, 'active' }
    }
})
```

### Parameter Binding
- Always use `?` placeholders
- Pass params as array: `{ param1, param2, param3 }`
- Never concatenate user input

---

## UI Theme & Design

### Get Theme
```lua
local theme = exports['cm-ui']:GetTheme()
-- Returns theme object with colors, fonts, etc.
```

### Theme Colors (Cyan/Ice-Blue)
```lua
{
    bg = '#07111f',              -- Dark background
    panel = '#081222',           -- Panel background
    panelSoft = '#0c1a2e',       -- Softer panels
    primary = '#00e5ff',         -- Cyan (primary action)
    primaryDark = '#0891b2',     -- Dark cyan
    blue = '#2563eb',            -- Blue
    success = '#22c55e',         -- Green
    warning = '#f59e0b',         -- Orange
    danger = '#ef4444',          -- Red
    text = '#eaf7ff',            -- Light text
    muted = '#8aa4b8'            -- Muted gray
}

-- Fonts: Inter, Segoe UI, Roboto, Arial, sans-serif
-- Border radius: 16px
```

### Interaction System
```lua
-- Register NPC interaction (via cm-playerdata)
exports['cm-playerdata']:RegisterInteractionAction({
    id = 'license_instructor',
    event = 'cm-license:server:interactNPC',
    allowDeadTarget = false,
    allowVehicleTarget = false,
    resource = 'cm-license'
})
```

---

## Events & Namespacing

### Event Namespace Pattern
- Server events: `cm-license:server:eventName`
- Client events: `cm-license:client:eventName`

### Events to Emit
```lua
-- When license is successfully issued
TriggerEvent('cm-license:server:licenseIssued', charId, licenseType, expiresAt)

-- When test starts
TriggerEvent('cm-license:server:testStarted', charId, testId, licenseType)

-- When test fails
TriggerEvent('cm-license:server:testFailed', charId, testId, reason)

-- To notify client
TriggerClientEvent('cm-license:client:testStarted', src, {
    testId = testId,
    licenseType = licenseType,
    startCoords = startCoords,
    -- ...
})
```

### Server Event Listeners
```lua
RegisterNetEvent('cm-license:server:requestStartTest', function(licenseTypeId)
    local src = source
    -- Validate and start test
end)

RegisterNetEvent('cm-license:server:checkpointReached', function(testId, checkpointNumber)
    local src = source
    -- Validate checkpoint progression
end)
```

---

## Money Ledger Schema

The `money_ledger` table automatically tracks all money changes:
- `character_id` — Who the money belongs to
- `account_type` — 'cash', 'bank', 'dirty'
- `action` — 'add', 'remove', 'set', 'transfer'
- `amount` — Absolute value changed
- `balance_after` — New balance
- `reason` — Why (e.g., 'license_purchase')
- `created_at` — Timestamp

No need to manually log money changes via RemoveMoney/AddMoney.

---

## Character ID vs. Server ID

**IMPORTANT**: Use `character_id` (database integer) everywhere, NOT server ID.

- `src` = server ID (session-based, changes on reconnect)
- `charId` = character ID (persistent database ID, same across reconnects)

Always convert: `local charId = exports['cm-playerdata']:GetCharacterId(src)`

---

## Dependencies in fxmanifest.lua

```lua
dependencies {
    'cm-core',
    'cm-playerdata',
    'cm-inventory',
    'cm-ui',
    'cm-admin',  -- optional, for permissions
    'oxmysql'
}
```

---

## Next Steps

1. Create fxmanifest.lua with dependencies
2. Create SQL migration (001_cm_license.sql)
3. Create config.lua with defaults
4. Implement server/main.lua with database init + cache
5. Implement server/licenses.lua with license CRUD
6. Implement server/tests.lua with test session management
7. Implement admin setup system
8. Implement player test flow
9. Implement NUI for all UIs
10. Test and validate all integrations
