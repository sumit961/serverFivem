-- nv_cloth/server/sv_store_session.lua
-- Server-authoritative "who is shopping where". Use IsPlayerShopping(src)
-- in sv_cloth.lua instead of the old distance-to-any-shop check.

local Sessions  = {}
local ShopsById = {}

local function indexShops()
    ShopsById = {}
    if type(Config.Shops) == 'table' then
        for _, s in ipairs(Config.Shops) do
            if s and s.id then ShopsById[s.id] = s end
        end
    end
end

CreateThread(function()
    indexShops()
end)

local ENTER_RANGE = 4.0   -- distance to the counter when opening
local SHOP_RANGE  = 8.0   -- distance to the dressing spot when buying

local function reply(src, ok, reason)
    TriggerClientEvent('nv_cloth:client:enterStoreResult', src, ok, reason)
end

RegisterNetEvent('nv_cloth:server:enterStore', function(shopId)
    local src = source
    if not next(ShopsById) then indexShops() end

    local shop = type(shopId) == 'string' and ShopsById[shopId]
    if not shop or not shop.interact or not shop.dressing then
        return reply(src, false, 'invalid')
    end
    if Sessions[src] then
        return reply(src, false, 'busy')
    end

    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - shop.interact) > ENTER_RANGE then
        return reply(src, false, 'too_far')
    end

    -- State validations (dead, vehicle, cuffed)
    if GetEntityHealth(ped) <= 100 then
        return reply(src, false, 'dead')
    end

    if GetVehiclePedIsIn(ped, false) ~= 0 then
        return reply(src, false, 'vehicle')
    end

    local state = Player(src) and Player(src).state
    if state then
        if state.isDead == true or state.dead == true or state.downed == true then
            return reply(src, false, 'dead')
        end
        if state.cmCuffed == true or state.cuffed == true or state.isCuffed == true or state.handcuffed == true then
            return reply(src, false, 'cuffed')
        end
        if state.isEscorted == true or state.escorted == true or state.isDragged == true then
            return reply(src, false, 'escorted')
        end
        if state.inCombat == true or state.combatTag == true then
            return reply(src, false, 'combat')
        end
    end

    local origBucket = GetPlayerRoutingBucket(src)
    Sessions[src] = { shopId = shopId, bucket = origBucket }

    if Config.IsolateDressing then
        SetPlayerRoutingBucket(src, 50000 + tonumber(src))
    end

    if state then
        state:set('inClothingStore', true, true)
        state:set('cmClothingPreview', true, true)
        state:set('skipPositionSave', true, true)
        state:set('cmSkipPositionSave', true, true)
        state:set('ignorePositionSave', true, true)
    end

    reply(src, true)
end)

local function endSession(src, restoreBucket)
    local s = Sessions[src]
    if not s then return end
    Sessions[src] = nil

    if restoreBucket and Config.IsolateDressing then
        SetPlayerRoutingBucket(src, s.bucket)
    end

    local state = Player(src) and Player(src).state
    if state then
        state:set('inClothingStore', false, true)
        state:set('cmClothingPreview', false, true)
        state:set('skipPositionSave', false, true)
        state:set('cmSkipPositionSave', false, true)
        state:set('ignorePositionSave', false, true)
    end
end

RegisterNetEvent('nv_cloth:server:leaveStore', function()
    endSession(source, true)
end)

AddEventHandler('playerDropped', function()
    endSession(source, false)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Sessions) do endSession(src, true) end
end)

-- returns ok, shopId
function IsPlayerShopping(src)
    local s = Sessions[src]
    if not s then return false end
    if not next(ShopsById) then indexShops() end
    local shop = ShopsById[s.shopId]
    if not shop or not shop.dressing then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - shop.dressing.xyz) <= SHOP_RANGE, s.shopId
end

exports('IsPlayerShopping', IsPlayerShopping)

-- force-close (e.g. when a player is cuffed or killed by someone else)
function ForceCloseStore(src)
    if Sessions[src] then TriggerClientEvent('nv_cloth:client:closeStore', src) end
end
exports('ForceCloseStore', ForceCloseStore)

