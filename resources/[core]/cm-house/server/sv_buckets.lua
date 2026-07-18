-- ============================================================
--  cm-house | sv_buckets.lua   |  PHASE 1
--
--  Spec 13: house and garage interiors must be isolated so players from
--  unrelated properties cannot see or interact with each other.
--
--  Without this, every player who enters the "motel" template stands in the
--  SAME physical room and sees each other. You have not hit that yet only
--  because you are testing alone.
--
--    house bucket   = 100000 + propertyId
--    garage bucket  = 200000 + propertyId
--
--  Bucket 0 is the normal world.
-- ============================================================

local HOUSE_BASE  = 100000
local GARAGE_BASE = 200000

Occupants = {}   -- [houseId] = { [src] = 'house' | 'garage' }

function HouseBucket(houseId)  return HOUSE_BASE  + houseId end
function GarageBucket(houseId) return GARAGE_BASE + houseId end

-- ------------------------------------------------------------
--  Move a player in or out
-- ------------------------------------------------------------
-- Persisted separately from the in-memory Occupants table above: Occupants
-- is rightly wiped on disconnect (it answers "who is online in here right
-- now"), but a player who drops while inside must be put BACK on rejoin, so
-- their last house/garage is written through to the database on every enter
-- and cleared on every explicit exit. See PersistLastInterior/ClearLastInterior.
function PersistLastInterior(src, houseId, kind)
    local cid = GetCid(src)
    if not cid then return end
    MySQL.insert('INSERT INTO cm_house_last_interior (cid, house_id, kind) VALUES (?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE house_id = VALUES(house_id), kind = VALUES(kind)',
        { cid, houseId, kind })
end

function ClearLastInteriorByCid(cid)
    if not cid then return end
    MySQL.query('DELETE FROM cm_house_last_interior WHERE cid = ?', { cid })
end

function ClearLastInterior(src)
    ClearLastInteriorByCid(GetCid(src))
end

function SendToHouse(src, houseId)
    SetPlayerRoutingBucket(src, HouseBucket(houseId))
    Occupants[houseId] = Occupants[houseId] or {}
    Occupants[houseId][src] = 'house'
    PersistLastInterior(src, houseId, 'house')
end

function SendToGarage(src, houseId)
    SetPlayerRoutingBucket(src, GarageBucket(houseId))
    Occupants[houseId] = Occupants[houseId] or {}
    Occupants[houseId][src] = 'garage'
    PersistLastInterior(src, houseId, 'garage')
end

function SendToWorld(src)
    SetPlayerRoutingBucket(src, 0)
    for houseId, set in pairs(Occupants) do
        if set[src] then
            set[src] = nil
            if not next(set) then
                Occupants[houseId] = nil
                OnGarageEmpty(houseId)
            end
        end
    end
    ClearLastInterior(src)
end

--- Which property is this player inside, if any?
function WhereIs(src)
    for houseId, set in pairs(Occupants) do
        if set[src] then return houseId, set[src] end
    end
    return nil
end

--- Everyone currently inside a given property, so a slot change can be
--- pushed to exactly the people who can see it.
function InsideProperty(houseId, kind)
    local out = {}
    for src, where in pairs(Occupants[houseId] or {}) do
        if not kind or where == kind then out[#out + 1] = src end
    end
    return out
end

--- Phase 3 will unload garage vehicle entities here. Declared now so the
--- bucket layer does not have to change when that lands.
function OnGarageEmpty(houseId)
    if Config.Debug then
        print(('[cm-house] property %d is empty'):format(houseId))
    end
end

-- ------------------------------------------------------------
--  Never strand a player.
--  A disconnect inside a house must not leave a phantom occupant, and a
--  player who drops while inside must not respawn in an empty bucket.
-- ------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    for houseId, set in pairs(Occupants) do
        if set[src] then
            set[src] = nil
            if not next(set) then
                Occupants[houseId] = nil
                OnGarageEmpty(houseId)
            end
        end
    end
end)

--- A resource restart while players are inside would leave them in a bucket
--- with no interior around them. Put everyone back in the world first.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, set in pairs(Occupants) do
        for src in pairs(set) do
            SetPlayerRoutingBucket(src, 0)
            TriggerClientEvent('cm-house:client:forceExit', src)
        end
    end
end)

exports('GetHouseBucket',  HouseBucket)
exports('GetGarageBucket', GarageBucket)
exports('WhereIsPlayer',   function(src) return WhereIs(src) end)
