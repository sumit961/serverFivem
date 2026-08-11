-- ============================================================
--  cm-house | sv_compat.lua
--  The single seam between cm-house and cm-playerdata.
--  If playerdata's API ever changes, this is the only file to edit.
--
--  Verified against cm-playerdata's actual exports:
--    GetCharId(src)                            -> integer charId, nil if unloaded
--    GetSourceByCharId(charId)                 -> src, nil when offline
--    GetCharacterFullName(src)                 -> "First Last"  [ONLINE ONLY]
--    AddMoney(src, account, amount, reason)    -> boolean
--    RemoveMoney(src, account, amount, reason) -> false if unaffordable
--    CanAfford(src, account, amount)           -> boolean
--    event cm-playerdata:server:characterLoaded(src, data)
--
--  Loads BEFORE sv_core.lua.
-- ============================================================

-- ------------------------------------------------------------
--  Lazy resolution.
--  `local PD = exports['cm-playerdata']` at file scope runs the moment this
--  file loads. If cm-playerdata has not started yet, that THROWS -- the file
--  aborts, and every function below it (GetCid, TakeMoney, ...) is never
--  declared. The symptom is a confusing "attempt to call a nil value (global
--  'GetCid')" from a completely different file.
--
--  fxmanifest `dependencies` does not reliably guarantee start order, so we
--  never touch the export until it is actually called.
-- ------------------------------------------------------------
local function PD()
    return exports['cm-playerdata']
end

-- ------------------------------------------------------------
--  SQL NULL -- and why there is no sentinel here
--
--  Two traps, and we hit both:
--
--  1. A `nil` in a Lua table literal TRUNCATES the array. { a, nil, c } has
--     length 1, so an optional parameter silently shortens the list and the
--     placeholder count stops matching.
--
--  2. `false` is NOT a safe stand-in for NULL. On an INT column MySQL coerces
--     false to 0, and on a FOREIGN KEY that means "row 0", which does not
--     exist:
--       Cannot add or update a child row: a foreign key constraint fails
--
--  Rather than hunt for a sentinel that survives both, build the statement
--  WITHOUT the column. A column that is not in the INSERT takes its DEFAULT
--  NULL -- no coercion, no sentinel, nothing to get wrong.
-- ------------------------------------------------------------

--- Build an INSERT from a { column = value } map, skipping any nil.
--- @return string sql, table params
function BuildInsert(tbl, fields)
    local cols, marks, params = {}, {}, {}

    for _, f in ipairs(fields) do
        local col, val = f[1], f[2]
        if val ~= nil then
            cols[#cols + 1]   = ('`%s`'):format(col)
            marks[#marks + 1] = '?'
            params[#params + 1] = val
        end
        -- nil -> the column is omitted entirely, and takes its DEFAULT NULL.
    end

    local sql = ('INSERT INTO `%s` (%s) VALUES (%s)')
        :format(tbl, table.concat(cols, ', '), table.concat(marks, ', '))

    return sql, params
end

--- Optional JSON column. Returns nil (not false) when there is nothing to
--- encode, so BuildInsert drops the column.
function SqlJson(v)
    if v == nil then return nil end
    return json.encode(v)
end

--- Kept for the UPDATE paths, which have no FK columns and where oxmysql's
--- false -> NULL mapping is safe.
function SqlNull(v)
    if v == nil then return false end
    return v
end

-- ------------------------------------------------------------
--  Database booleans
--  oxmysql returns TINYINT(1) as `true`, `1`, or `'1'` depending on its
--  type-casting settings. Comparing with `== 1` therefore fails silently on
--  some servers -- garage options vanish, a stored car looks un-stored.
--  Never compare a database boolean directly. Always go through this.
-- ------------------------------------------------------------
function DbBool(v)
    if v == true or v == 1 then return true end
    if type(v) == 'string' then
        v = v:lower()
        return v == '1' or v == 'true' or v == 'yes' or v == 'on'
    end
    return false
end

-- oxmysql normally returns INT columns as Lua numbers, but older schemas,
-- views and some driver modes may return numeric database values as strings.
-- Keep all comparisons type-safe at the database boundary.
function DbNumber(v, fallback)
    if type(v) == 'number' then return v end
    if type(v) == 'string' then
        local trimmed = v:match('^%s*(.-)%s*$')
        local n = tonumber(trimmed)
        if n ~= nil then return n end
    end
    return fallback
end

function DbInteger(v, fallback)
    local n = DbNumber(v, nil)
    if n == nil then return fallback end
    return n >= 0 and math.floor(n) or math.ceil(n)
end

function DbPositiveInteger(v)
    local n = DbInteger(v, nil)
    return n and n > 0 and n or nil
end

-- ------------------------------------------------------------
--  Identity.  charId is an INTEGER -- houses key off it.
-- ------------------------------------------------------------

--- src -> charId. nil when no character is loaded, which is the correct
--- "you can't do this yet" signal at every call site.
function GetCid(src)
    if not src or src == 0 then return nil end
    local ok, id = pcall(function() return PD():GetCharId(src) end)
    if not ok then return nil end
    return tonumber(id)
end

--- charId -> src, or nil when that character is offline.
function GetSrcByCid(charId)
    charId = tonumber(charId)
    if not charId then return nil end
    local ok, src = pcall(function() return PD():GetSourceByCharId(charId) end)
    if not ok then return nil end
    return src
end

-- ------------------------------------------------------------
--  Offline names.
--  GetCharacterFullName needs a live src, but a house owner is usually
--  offline -- which is the entire point of a name on a door. So read the
--  characters table directly and cache it. Names change rarely, so a
--  process-lifetime cache is safe and keeps the door menu instant.
-- ------------------------------------------------------------
local NameCache = {}

function GetCharName(charId)
    charId = tonumber(charId)
    if not charId then return 'Nobody' end
    if NameCache[charId] then return NameCache[charId] end

    -- Online: use playerdata's own formatter so the name matches everywhere.
    local src = GetSrcByCid(charId)
    if src then
        local ok, name = pcall(function() return PD():GetCharacterFullName(src) end)
        if ok and name and name ~= '' and name ~= 'Unknown' then
            NameCache[charId] = name
            return name
        end
    end

    -- Offline: read the same table playerdata reads.
    local row = MySQL.single.await(
        'SELECT first_name, last_name FROM characters WHERE id = ? LIMIT 1', { charId })
    if not row then return ('Character #%d'):format(charId) end

    local name = ((row.first_name or '') .. ' ' .. (row.last_name or ''))
        :gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if name == '' then name = ('Character #%d'):format(charId) end

    NameCache[charId] = name
    return name
end

--- Prime every owner name in ONE query at boot, so opening a door never
--- blocks on a lookup.
function WarmNameCache(charIds)
    local ids = {}
    for _, id in ipairs(charIds) do
        id = tonumber(id)
        if id and not NameCache[id] then ids[#ids + 1] = id end
    end
    if #ids == 0 then return 0 end

    local rows = MySQL.query.await(
        ('SELECT id, first_name, last_name FROM characters WHERE id IN (%s)')
            :format(string.rep('?', #ids, ',')),
        ids
    ) or {}

    for _, r in ipairs(rows) do
        local name = ((r.first_name or '') .. ' ' .. (r.last_name or ''))
            :gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
        NameCache[tonumber(r.id)] = name ~= '' and name or ('Character #%d'):format(r.id)
    end
    return #rows
end

function InvalidateName(charId)
    NameCache[tonumber(charId) or 0] = nil
end

-- ------------------------------------------------------------
--  Money. cm-playerdata is the ONLY authority: cm-house never writes
--  a balance, it asks and believes the answer.
-- ------------------------------------------------------------

--- True only if the money genuinely left the account. RemoveMoney returns
--- false on insufficient funds, and that is what gates a purchase.
function TakeMoney(src, account, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end
    local ok, res = pcall(function()
        return PD():RemoveMoney(src, account, amount, reason)
    end)
    return ok and res == true
end

function GiveMoney(src, account, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end
    local ok, res = pcall(function()
        return PD():AddMoney(src, account, amount, reason)
    end)
    return ok and res ~= false
end

--- What they actually hold. Used so "you need more money" can say how much
--- they have, rather than leaving them to guess which account is short.
function GetMoney(src, account)
    local ok, res = pcall(function()
        return PD():GetMoney(src, account)
    end)
    return ok and tonumber(res) or 0
end

--- 1130000 -> "1,130,000". A seven-figure price is unreadable without this.
function Comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

function CanAfford(src, account, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end
    local ok, res = pcall(function()
        return PD():CanAfford(src, account, amount)
    end)
    return ok and res == true
end

-- ------------------------------------------------------------
function CheckPlayerData()
    if GetResourceState('cm-playerdata') ~= 'started' then
        print('[cm-house] ^1cm-playerdata is not started. Ownership and money are disabled.^7')
        return false
    end

    local ok, err = pcall(function()
        for _, name in ipairs({ 'GetCharId', 'GetSourceByCharId', 'GetCharacterFullName',
                                'AddMoney', 'RemoveMoney', 'CanAfford' }) do
            if type(PD()[name]) ~= 'function' then
                error(('missing export: %s'):format(name), 0)
            end
        end
    end)

    if not ok then
        print(('[cm-house] ^1cm-playerdata %s^7'):format(err))
        return false
    end

    print('[cm-house] cm-playerdata linked')
    return true
end

-- ============================================================
--  cm-inventory / cm-vehicles
--  These export names are NOT yet verified against your resources.
--  Wrapping them means a wrong name prints one clear line and the house
--  system keeps working, instead of the whole resource erroring out.
--  Fix a name here and everywhere else is already correct.
-- ============================================================

local INV = 'cm-inventory'
local VEH = 'cm-vehicles'

local warned = {}
local function warnOnce(res, fn)
    local k = res .. ':' .. fn
    if warned[k] then return end
    warned[k] = true
    print(('[cm-house] ^3%s has no export "%s". That feature degrades until it is mapped.^7')
        :format(res, fn))
end

-- ------------------------------------------------------------
--  Legacy wardrobes / general storage
--  cm-inventory has NO stash registry. Storage is opened on demand
--  with an ownerType/ownerId/slotPrefix triplet, and the rows live in
--  inventory_items. So a wardrobe is not an object we create -- it is
--  just an address we open. Nothing to pre-register.
--
--    owner_type = 'house_wardrobe'
--    owner_id   = '<houseId>:<slotIndex>'      e.g. "12:2"
--    slot       = 'wardrobe-1' ... 'wardrobe-30'
-- ------------------------------------------------------------

function WardrobeOwnerId(houseId, slotIndex)
    return ('%d:%d'):format(houseId, slotIndex)
end

--- Spec 4.2: "Storage IDs should be derived from the property ID and storage
--- type, not the template ID." Two houses sharing a layout must NOT share a
--- fridge -- so the address is the property, and the template only says where
--- the fridge physically stands.
function OpenPropertyStash(src, houseId, index, def)
    if GetResourceState(INV) ~= 'started' then
        Notify(src, 'Inventory is not running.', 'error')
        return false
    end

    local ownerId = ('%d:%d'):format(houseId, index)
    local house = Houses and Houses[tonumber(houseId)] or nil
    local family = house and house.family_id and GetFamilyDisplay(house.family_id) or nil
    local familyName = family and tostring(family.name or family.label or '') or nil
    local storageLabel = familyName and familyName ~= ''
        and ('%s Family Storage'):format(familyName)
        or (def.label or 'Storage')
    local storageSubtitle = familyName and familyName ~= ''
        and tostring(house.label or ('Family House #' .. tostring(houseId)))
        or ('Property #%d'):format(houseId)

    local ok, res, err = pcall(function()
        return exports[INV]:OpenExternalInventory(src, {
            ownerType    = 'house_storage',
            ownerId      = ownerId,
            slotPrefix   = 'store-',
            slots        = def.slots or 30,
            displaySlots = 30,
            kind         = familyName and 'family_house_storage' or 'house_storage',
            label        = storageLabel,
            subtitle     = storageSubtitle,
            noWeightLimit = true,
            canDeposit   = true,
            canWithdraw  = true,
            data         = {
                houseId = houseId,
                familyId = house and house.family_id or nil,
                point = index,
            },
        })
    end)

    if not ok then
        warnOnce(INV, 'OpenExternalInventory')
        Notify(src, 'Storage is not wired up yet.', 'error')
        return false
    end
    if res == false then
        Notify(src, err or 'The storage would not open.', 'error')
        return false
    end
    return true
end

function OpenWardrobe(src, houseId, slotIndex, label)
    if GetResourceState(INV) ~= 'started' then
        TriggerClientEvent('cm-house:client:notify', src, 'Inventory is not running.', 'error')
        return false
    end

    local ok, res, err = pcall(function()
        return exports[INV]:OpenExternalInventory(src, {
            ownerType    = 'house_wardrobe',
            ownerId      = WardrobeOwnerId(houseId, slotIndex),
            slotPrefix   = 'wardrobe-',
            slots        = Config.WardrobeSlots,   -- 30 usable
            displaySlots = 30,                     -- the standard 6x5 board
            kind         = 'house_wardrobe',
            label        = label or 'Wardrobe',
            subtitle     = ('Wardrobe %d'):format(slotIndex),
            noWeightLimit = true,
            canDeposit   = true,
            canWithdraw  = true,
            data         = { houseId = houseId, slot = slotIndex },
        })
    end)

    if not ok then
        warnOnce(INV, 'OpenExternalInventory')
        TriggerClientEvent('cm-house:client:notify', src, 'Wardrobes are not wired up yet.', 'error')
        return false
    end
    if res == false then
        TriggerClientEvent('cm-house:client:notify', src, err or 'The wardrobe would not open.', 'error')
        return false
    end
    return true
end

--- Selling a house empties its wardrobes. The rows live in cm-inventory's
--- own table, so delete them there by address.
function ClearWardrobe(houseId, slotIndex)
    MySQL.query('DELETE FROM inventory_items WHERE owner_type = ? AND owner_id = ?', {
        'house_wardrobe', WardrobeOwnerId(houseId, slotIndex),
    })
end

-- ============================================================
--  cm-vehicles
--  Verified against the real resource:
--    SpawnVehicleFromParking(src, vehicleId, lotId, spawn, options) -> ok, err
--    DeleteSpawnedVehicle(plate)
--    GetVehicleByPlate(plate) -> row
--    PlayerOwnsVehicle(src, plate) -> bool
--    HasVehicleAccess(src, plate) -> bool   (owner OR temp key)
--
--  CRITICAL: cm_owned_vehicles.is_stored / .garage is the ONLY authority on
--  where a vehicle is. cm-house never keeps a second opinion -- the moment two
--  systems disagree about a car's location, the car exists twice.
--
--  cm-vehicles can take a car OUT of parking but has no way to put one back,
--  so storing is implemented here.
-- ============================================================

--- Every vehicle ASSIGNED to a physical space at this property.
---
--- Slot assignment and physical location are intentionally separate:
---   * cm_house_vehicle_slots.vehicle_id = the vehicle owns/reserves this space
---   * is_stored=1 + garage='house:<id>' = the vehicle is physically inside
---   * is_stored=0 = the assigned vehicle is currently outside in the city
---
--- This lets a player drive a vehicle out without losing its home space, then
--- recall the same vehicle back into that exact space later.
function GarageVehicles(houseId)
    houseId = tonumber(houseId)
    if not houseId then return {} end

    -- Older stored house vehicles may predate slot assignments. Seat those
    -- first, but never clear valid reservations merely because a car is outside.
    ReseatHomelessVehicles(houseId)

    return MySQL.query.await([[
        SELECT v.id, v.plate, v.model, v.label, v.owner_character_id,
               v.fuel, v.engine_health, v.body_health, v.tank_health, v.dirt_level,
               v.condition_state, v.is_locked, v.is_stored, v.garage,
               v.location_state, v.location_ref, v.location_slot,
               s.slot_index, s.owner_class
        FROM cm_house_vehicle_slots s
        INNER JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
        WHERE s.house_id = ?
        ORDER BY s.slot_index
    ]], { houseId }) or {}
end

--- Give a seat to every car that claims to live here but holds none.
--- Without this such a car is invisible forever: it cannot spawn (no slot) and
--- cannot be retrieved (the garage does not know it is there).
function ReseatHomelessVehicles(houseId)
    houseId = tonumber(houseId)
    if not houseId then return 0 end

    local homeless = MySQL.query.await([[
        SELECT v.id, v.plate, v.model
        FROM cm_owned_vehicles v
        WHERE v.is_stored = 1 AND v.garage = ?
          AND NOT EXISTS (
              SELECT 1 FROM cm_house_vehicle_slots s WHERE s.vehicle_id = v.id
          )
        ORDER BY v.id
    ]], { ('house:%d'):format(houseId) }) or {}

    if #homeless == 0 then return 0 end

    local seated = 0
    for _, v in ipairs(homeless) do
        local free = MySQL.scalar.await([[
            SELECT MIN(slot_index) FROM cm_house_vehicle_slots
            WHERE house_id = ? AND vehicle_id IS NULL
        ]], { houseId })

        if free then
            -- The `AND vehicle_id IS NULL` guard makes this safe to run from
            -- several places at once: only one caller can take the space.
            local rows = MySQL.update.await([[
                UPDATE cm_house_vehicle_slots
                SET vehicle_id = ?, owner_class = 'personal', assigned_at = NOW()
                WHERE house_id = ? AND slot_index = ? AND vehicle_id IS NULL
            ]], { v.id, houseId, free })

            if rows and rows > 0 then
                seated = seated + 1
                print(('[cm-house] ^3reseated %s (%s) into house %d space %d^7')
                    :format(tostring(v.model), tostring(v.plate), houseId, free))
            end
        else
            -- Full. Release rather than strand: the owner keeps the car.
            MySQL.update.await(
                'UPDATE cm_owned_vehicles SET is_stored = 0, garage = NULL, parking_id = NULL, parked_at = NULL WHERE id = ?',
                { v.id })
            print(('[cm-house] ^1house %d is full -- %s (%s) released from the garage^7')
                :format(houseId, tostring(v.model), tostring(v.plate)))
        end
    end

    return seated
end

--- Cars this character owns that are NOT stored anywhere -- i.e. candidates to
--- be driven in and parked.
function LooseVehicles(charId)
    return MySQL.query.await([[
        SELECT id, plate, model, label, is_stored, garage
        FROM cm_owned_vehicles
        WHERE owner_character_id = ? AND is_stored = 0
        ORDER BY id DESC
    ]], { tostring(charId) }) or {}
end

function VehicleById(id)
    return MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1',
        { tonumber(id) })
end

function VehicleByPlate(plate)
    return MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE plate = ? LIMIT 1',
        { tostring(plate) })
end

--- Take a car OUT of a house garage and put it in the world.
--- cm-vehicles owns this: it clears is_stored, repairs, and spawns the entity.
function SpawnFromHouse(src, vehicleId, houseId, spawn)
    if GetResourceState(VEH) ~= 'started' then
        return false, 'The vehicle system is not running.'
    end

    local ok, res, err = pcall(function()
        return exports[VEH]:SpawnVehicleFromParking(
            src, vehicleId, ('house:%d'):format(houseId), spawn,
            { warp = false, engineOn = false, unlockOnRetrieve = true }
        )
    end)

    if not ok then
        warnOnce(VEH, 'SpawnVehicleFromParking')
        return false, 'The vehicle system rejected the request.'
    end
    if res == false then
        return false, err or 'The vehicle could not be taken out.'
    end
    return true
end

--- Despawn the physical entity. Used after a car is stored, so the world copy
--- disappears the instant the database says it is parked.
function DespawnVehicle(vehicleId, plate)
    if GetResourceState(VEH) ~= 'started' then
        return false, 'The vehicle system is not running.'
    end
    local ok, deleted, why = pcall(function()
        return exports[VEH]:DeleteSpawnedVehicle(tonumber(vehicleId) or plate)
    end)
    if not ok then
        warnOnce(VEH, 'DeleteSpawnedVehicle')
        return false, tostring(deleted or 'The vehicle deletion export failed.')
    end
    if deleted == false then
        if Config.Debug then
            print(('[cm-house] DeleteSpawnedVehicle rejected %s: %s')
                :format(tostring(vehicleId or plate), tostring(why)))
        end
        return false, tostring(why or 'The vehicle entity could not be deleted.')
    end
    return true
end

--- Does this player have any claim on this car at all?
function CanUseVehicle(src, plate)
    if GetResourceState(VEH) ~= 'started' then return false end
    local ok, res = pcall(function() return exports[VEH]:HasVehicleAccess(src, plate) end)
    return ok and res == true
end

function OwnsVehicle(src, plate)
    if GetResourceState(VEH) ~= 'started' then return false end
    local ok, res = pcall(function() return exports[VEH]:PlayerOwnsVehicle(src, plate) end)
    return ok and res == true
end

--- Release every vehicle connected to a property before ownership is cleared
--- or the property row is deleted. A released car stays owned, keeps its saved
--- condition, loses the dead house assignment, and becomes an OUTSIDE/missing
--- entity that can be called into another valid house garage.
local function captureVehicleBeforeHouseRelease(row)
    if GetResourceState(VEH) ~= 'started' then return end
    local ok, captured, condition = pcall(function()
        return exports[VEH]:GetSpawnedVehicleCondition(tonumber(row.id), row)
    end)
    if not ok or captured ~= true or type(condition) ~= 'table' then return end

    local state = condition.conditionState
    local encodedState = type(state) == 'table' and json.encode(state)
        or tostring(row.condition_state or '{}')
    MySQL.update.await([[
        UPDATE cm_owned_vehicles
        SET fuel = ?, engine_health = ?, body_health = ?, tank_health = ?,
            dirt_level = ?, condition_state = ?
        WHERE id = ?
    ]], {
        tonumber(condition.fuel) or tonumber(row.fuel) or 100.0,
        tonumber(condition.engine) or tonumber(row.engine_health) or 1000.0,
        tonumber(condition.body) or tonumber(row.body_health) or 1000.0,
        tonumber(condition.tank) or tonumber(row.tank_health) or 1000.0,
        tonumber(condition.dirt) or tonumber(row.dirt_level) or 0.0,
        encodedState, tonumber(row.id),
    })
end

local function releaseHouseVehicleRow(row, reason, actorCid)
    local vehicleId = tonumber(row and row.id)
    if not vehicleId then return false, 'invalid_vehicle_id' end

    if GetResourceState(VEH) == 'started' then
        local okBusy, busy = pcall(function()
            return exports[VEH]:IsVehicleOperationActive(vehicleId)
        end)
        if okBusy and busy == true then
            return false, ('Vehicle %s is already being moved.'):format(tostring(row.plate or vehicleId))
        end

        captureVehicleBeforeHouseRelease(row)

        -- A vehicle already outside may remain in the world. Only the private
        -- garage display entity must be deleted. Never make an occupied car
        -- disappear because its linked property was sold or removed.
        local spawnedInfo
        local okInfo, infoResult, infoData = pcall(function()
            return exports[VEH]:GetSpawnedVehicleInfo(vehicleId)
        end)
        if okInfo and infoResult == true and type(infoData) == 'table' then
            spawnedInfo = infoData
        end

        local spawnedContext = spawnedInfo and tostring(spawnedInfo.context or '') or ''
        local databaseHouseStored = (row.is_stored == true or tonumber(row.is_stored) == 1)
            and tostring(row.garage or ''):match('^house:%d+$') ~= nil
        local mustDeleteGarageEntity = spawnedContext == 'house_garage'
            or (spawnedInfo == nil and (databaseHouseStored
                or tostring(row.location_state or ''):upper() == 'HOUSE_GARAGE'))

        if mustDeleteGarageEntity then
            local entity = tonumber(spawnedInfo and spawnedInfo.entity) or 0
            if entity ~= 0 and DoesEntityExist(entity) then
                local maxPassengers = 6
                pcall(function() maxPassengers = math.max(0, GetVehicleMaxNumberOfPassengers(entity)) end)
                for seat = -1, maxPassengers do
                    local ped = 0
                    pcall(function() ped = GetPedInVehicleSeat(entity, seat) end)
                    if ped and ped ~= 0 then
                        return false, ('Vehicle %s is occupied inside the garage.'):format(
                            tostring(row.plate or vehicleId))
                    end
                end
            end

            local okDelete, deleted, deleteWhy = pcall(function()
                return exports[VEH]:DeleteSpawnedVehicle(vehicleId)
            end)
            if not okDelete or deleted ~= true then
                return false, tostring(deleteWhy or deleted or 'The garage vehicle could not be released.')
            end
        end

        local keepWorldEntity = spawnedInfo ~= nil and spawnedContext ~= 'house_garage'
        local okTransition, transitioned, transitionWhy = pcall(function()
            return exports[VEH]:TransitionVehicleLocation(vehicleId, 'OUTSIDE', {
                reason = tostring(reason or 'house_release'),
                actorCharacterId = actorCid and tostring(actorCid) or nil,
                previousHouseId = tonumber(row.house_id),
            })
        end)
        if okTransition and transitioned == true then
            if not keepWorldEntity then
                MySQL.update.await('UPDATE cm_owned_vehicles SET last_position = NULL WHERE id = ?', { vehicleId })
            end
            return true
        end
        if Config.Debug then
            print(('[cm-house] location export fallback for vehicle %s: %s')
                :format(tostring(vehicleId), tostring(transitionWhy or transitioned)))
        end
    end

    local affected = MySQL.update.await([[
        UPDATE cm_owned_vehicles
        SET is_stored = 0,
            garage = NULL,
            parking_id = NULL,
            parked_at = NULL,
            last_position = NULL,
            location_state = 'OUTSIDE',
            location_ref = NULL,
            location_slot = NULL,
            location_updated_at = NOW()
        WHERE id = ?
    ]], { vehicleId })
    return affected and tonumber(affected) > 0, affected and nil or 'vehicle_release_failed'
end

function EvictVehicles(houseId, reason, actorCid)
    houseId = tonumber(houseId)
    if not houseId then return false, 'invalid_house_id' end
    local houseKey = ('house:%d'):format(houseId)
    local rows = MySQL.query.await([[
        SELECT DISTINCT v.*, ? AS house_id
        FROM cm_owned_vehicles v
        LEFT JOIN cm_house_vehicle_slots s ON s.vehicle_id = v.id
        WHERE s.house_id = ?
           OR v.garage = ?
           OR (v.location_state = 'HOUSE_GARAGE'
               AND CAST(SUBSTRING_INDEX(COALESCE(v.location_ref, ''), ':', -1) AS UNSIGNED) = ?)
    ]], { houseId, houseId, houseKey, houseId }) or {}

    local released = 0
    for _, row in ipairs(rows) do
        local ok, why = releaseHouseVehicleRow(row, reason or 'house_eviction', actorCid)
        if not ok then
            return false, why or ('Vehicle %s could not be released.'):format(tostring(row.plate or row.id))
        end
        MySQL.query.await('DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?', { tonumber(row.id) })
        MySQL.update.await([[
            UPDATE cm_house_vehicle_slots
            SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
            WHERE vehicle_id = ?
        ]], { tonumber(row.id) })
        released = released + 1
    end

    -- Clear any empty/legacy rows that were not joined to an existing vehicle.
    MySQL.update.await([[
        UPDATE cm_house_vehicle_slots
        SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
        WHERE house_id = ?
    ]], { houseId })
    MySQL.query.await('DELETE FROM cm_house_shared_vehicles WHERE house_id = ?', { houseId })
    return true, { released = released }
end

--- Repair vehicles left pointing at a house that no longer exists. This runs at
--- startup and fixes properties deleted by older cm-house builds.
function RecoverOrphanedHouseVehicles()
    -- house_id must be read from the SAME reference the WHERE clause matched on.
    -- The garage branch takes precedence only when it is the one that orphaned
    -- the vehicle; otherwise the location_ref branch supplies the id. Using a
    -- blanket COALESCE(garage, location_ref) previously reported the wrong
    -- previousHouseId whenever a stale garage string coexisted with the
    -- location_ref match.
    local rows = MySQL.query.await([[
        SELECT DISTINCT v.*,
            CASE
                WHEN v.garage REGEXP '^house:[0-9]+$' AND hg.id IS NULL
                    THEN CAST(SUBSTRING_INDEX(v.garage, ':', -1) AS UNSIGNED)
                WHEN v.location_state = 'HOUSE_GARAGE' AND hl.id IS NULL
                    THEN CAST(SUBSTRING_INDEX(COALESCE(v.location_ref, ''), ':', -1) AS UNSIGNED)
                ELSE NULL
            END AS house_id
        FROM cm_owned_vehicles v
        LEFT JOIN cm_houses hg
          ON hg.id = CAST(SUBSTRING_INDEX(COALESCE(v.garage, ''), ':', -1) AS UNSIGNED)
        LEFT JOIN cm_houses hl
          ON hl.id = CAST(SUBSTRING_INDEX(COALESCE(v.location_ref, ''), ':', -1) AS UNSIGNED)
        WHERE (v.garage REGEXP '^house:[0-9]+$' AND hg.id IS NULL)
           OR (v.location_state = 'HOUSE_GARAGE' AND hl.id IS NULL)
    ]]) or {}

    local recovered, failed = 0, 0
    for _, row in ipairs(rows) do
        local ok, why = releaseHouseVehicleRow(row, 'deleted_house_startup_recovery', nil)
        if ok then
            MySQL.query.await('DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?', { tonumber(row.id) })
            MySQL.update.await([[
                UPDATE cm_house_vehicle_slots
                SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
                WHERE vehicle_id = ?
            ]], { tonumber(row.id) })
            recovered = recovered + 1
        else
            failed = failed + 1
            print(('[cm-house] ^1orphan vehicle %s could not be recovered: %s^7')
                :format(tostring(row.plate or row.id), tostring(why)))
        end
    end
    if recovered > 0 or failed > 0 then
        print(('[cm-house] deleted-house vehicle recovery | recovered=%d failed=%d')
            :format(recovered, failed))
    end
    return recovered, failed
end

-- ------------------------------------------------------------
--  Load sentinel.
--  If this file ever aborts partway through again, the symptom shows up in a
--  DIFFERENT file as "attempt to call a nil value (global 'GetCid')", which
--  sends you hunting in the wrong place. sv_core checks this flag and says so
--  plainly instead.
-- ------------------------------------------------------------
-- ============================================================
--  cm-core
--  The framework spine: ACL, notifications, audit. Optional -- cm-house
--  degrades to its own behaviour if cm-core is absent.
-- ============================================================

local function CORE()
    return exports['cm-core']
end

local function hasCore()
    return GetResourceState('cm-core') == 'started'
end

--- Admin gate. cm-core:ACLCheck delegates to cm-admin:HasPermission. Building
--- and sensitive staff overrides remain separate granular permission checks.
local function adminPermissionKey(scope)
    scope = tostring(scope or 'panel')
    return tostring((Config.AdminPermissions and Config.AdminPermissions[scope])
        or Config.AdminPermission or 'house.create')
end

local function adminAceKey(scope)
    scope = tostring(scope or 'panel')
    return tostring((Config.AdminAces and Config.AdminAces[scope])
        or Config.AdminAce or 'cm-house.create')
end

local function aclAllows(src, permission)
    if hasCore() then
        local ok, allowed = pcall(function() return CORE():ACLCheck(src, permission) end)
        if ok and allowed == true then return true end
    end
    if GetResourceState('cm-admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports['cm-admin']:HasPermission(src, permission)
        end)
        if ok and allowed == true then return true end
    end
    return false
end

--- Granular cm-admin rank/ACE staff permission gate.
function HasHouseStaffPermission(src, scope)
    if not src or src == 0 then return true end

    local permission = adminPermissionKey(scope)
    if aclAllows(src, permission) or IsPlayerAceAllowed(src, adminAceKey(scope)) then
        return true
    end
    if Config.AdminUseLegacyFallback == true then
        local legacyPermission = tostring(Config.AdminPermission or 'house.create')
        local legacyAce = tostring(Config.AdminAce or 'cm-house.create')
        if permission ~= legacyPermission and aclAllows(src, legacyPermission) then return true end
        if adminAceKey(scope) ~= legacyAce and IsPlayerAceAllowed(src, legacyAce) then return true end
    end
    return false
end

function GetHouseAdminPermissionKey(scope)
    return adminPermissionKey(scope)
end

function IsRealStaff(src)
    if not src or src == 0 then return true end

    -- Do not use the public-development bypass here. Real-staff checks are
    -- used by optional gameplay overrides and sensitive read paths.
    local permission = adminPermissionKey('panel')
    if aclAllows(src, permission) or IsPlayerAceAllowed(src, adminAceKey('panel')) then
        return true
    end

    if Config.AdminUseLegacyFallback == true then
        local legacyPermission = tostring(Config.AdminPermission or 'house.create')
        local legacyAce = tostring(Config.AdminAce or 'cm-house.create')
        if permission ~= legacyPermission and aclAllows(src, legacyPermission) then return true end
        if adminAceKey('panel') ~= legacyAce and IsPlayerAceAllowed(src, legacyAce) then return true end
    end

    return false
end

--- May this player use the building tools? Always requires the create scope.
function IsHouseAdmin(src)
    return HasHouseStaffPermission(src, 'create')
end

--- Notify through cm-core when present so house messages look like every
--- other message on the server, rather than a second notification style.
function Notify(src, message, kind)
    if hasCore() then
        local ok = pcall(function()
            return CORE():Notify(src, message, kind or 'inform')
        end)
        if ok then return end
    end
    TriggerClientEvent('cm-house:client:notify', src, message, kind or 'inform')
end

--- Mirror significant events into cm-core's audit trail. cm_house_logs stays
--- the in-game record the family menu reads; this is the operator's record.
function Audit(src, action, detail)
    if not hasCore() then return end
    pcall(function()
        CORE():Log('cm-house', 'info', action, detail)
    end)
end

-- ------------------------------------------------------------
--  Property photo references
--  New captures are generated server-side and stored under html/img/houses.
--  Legacy Discord CDN rows remain readable during migration, but no client
--  can submit an arbitrary path or URL.
-- ------------------------------------------------------------
local PHOTO_HOSTS = {
    ['cdn.discordapp.com'] = true,
    ['media.discordapp.net'] = true,
}

function ValidPhotoUrl(url)
    if type(url) ~= 'string' or url == '' then return false end
    if url:match('^img/houses/house_%d+%.jpg%?v=%d+$')
        or url:match('^img/houses/house_%d+%.jpg$') then
        return true
    end
    local host = url:match('^https://([^/]+)/')
    return host ~= nil and PHOTO_HOSTS[host] == true
end

CompatLoaded = true
