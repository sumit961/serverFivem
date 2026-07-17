-- ============================================================
--  cm-family | sv_bridge.lua
--  Thin, defensive wrappers around the CM resources cm-family depends on.
--  Wired to the real cm-playerdata / cm-house export surface. Every call is
--  pcall-guarded so a missing/updated dependency degrades instead of throwing.
--
--  cm-playerdata facts this bridge relies on:
--    GetCharacterId(src) -> numeric charId
--    GetSourceByCharId(charId) -> src (charId is tonumber'd internally)
--    GetCharacterFullName(src) -> "First Last" (online only)
--    AddMoney(src, account, amount, reason)    -> boolean
--    RemoveMoney(src, account, amount, reason)  -> boolean (false if short)
--    GetMoney(src, account) -> number
--    SetFamily(src, familyId, familyName) -> boolean
--    notify: TriggerClientEvent('cm-playerdata:client:interactionNotify', src, msg, type)
--    characters table: id, first_name, last_name
-- ============================================================

CMFamilyBridge = CMFamilyBridge or {}
local B = CMFamilyBridge

local HOUSE = Config.HouseResource
local PD    = Config.PlayerDataResource

local function started(res) return GetResourceState(res) == 'started' end

-- Simple in-memory name cache so we don't hit the DB repeatedly for offline
-- members when rendering the menu.
local nameCache = {}

-- ---------- character id ----------
function B.GetCid(src)
    src = tonumber(src)
    if not src then return nil end
    if started(PD) then
        local ok, cid = pcall(function() return exports[PD]:GetCharacterId(src) end)
        if ok and cid then return tonumber(cid) or cid end
    end
    return nil
end

function B.GetSrcByCid(cid)
    if cid == nil then return nil end
    if started(PD) then
        local ok, src = pcall(function() return exports[PD]:GetSourceByCharId(cid) end)
        if ok and tonumber(src) then return tonumber(src) end
    end
    return nil
end

-- Name for a character id. Uses the online full-name export when the player is
-- connected, otherwise reads the characters table directly (cached).
function B.GetCharName(cid)
    local key = tostring(cid)
    if nameCache[key] then return nameCache[key] end

    local src = B.GetSrcByCid(cid)
    if src and started(PD) then
        local ok, name = pcall(function() return exports[PD]:GetCharacterFullName(src) end)
        if ok and name and name ~= '' then
            nameCache[key] = name
            return name
        end
    end

    local numeric = tonumber(cid)
    if numeric then
        local row = MySQL.single.await(
            'SELECT first_name, last_name FROM characters WHERE id = ? LIMIT 1', { numeric })
        if row then
            local full = (tostring(row.first_name or '') .. ' ' .. tostring(row.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
            if full ~= '' then
                nameCache[key] = full
                return full
            end
        end
    end
    return ('Character #%s'):format(tostring(cid))
end

function B.ClearNameCache(cid)
    if cid == nil then nameCache = {} else nameCache[tostring(cid)] = nil end
end

-- ---------- money ----------
function B.AddMoney(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    if not started(PD) then return false, 'playerdata_not_running' end
    local ok, res = pcall(function()
        return exports[PD]:AddMoney(src, Config.Bank.account, amount, reason or 'family_bank')
    end)
    return ok and res == true
end

-- RemoveMoney returns false when the player can't afford it, so this is atomic:
-- a true result guarantees the funds were taken.
function B.RemoveMoney(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    if not started(PD) then return false, 'playerdata_not_running' end
    local ok, res = pcall(function()
        return exports[PD]:RemoveMoney(src, Config.Bank.account, amount, reason or 'family_bank')
    end)
    return ok and res == true
end

function B.GetMoney(src)
    if not started(PD) then return 0 end
    local ok, bal = pcall(function() return exports[PD]:GetMoney(src, Config.Bank.account) end)
    if ok and tonumber(bal) then return tonumber(bal) end
    return 0
end

-- Reflect family membership into the player's own data (used for HUD/tags).
function B.SetPlayerFamily(src, familyId, familyName, identity)
    if not started(PD) then return end
    pcall(function() exports[PD]:SetFamily(src, familyId, familyName, identity) end)
end

-- ---------- notifications ----------
function B.Notify(src, message, kind)
    src = tonumber(src)
    if not src then return end
    TriggerClientEvent('cm-playerdata:client:interactionNotify', src, message, kind or 'inform')
end

-- ---------- cm-house ----------
function B.GetHousesForCharacter(cid)
    if not started(HOUSE) then return {} end
    local ok, houses = pcall(function() return exports[HOUSE]:GetHousesForCharacter(cid) end)
    if ok and type(houses) == 'table' then return houses end
    return {}
end

function B.SetFamilyHouseLink(houseId, familyId, actorCid)
    if not started(HOUSE) then return false, 'house_not_running' end
    local ok, res, why = pcall(function()
        return exports[HOUSE]:SetFamilyHouseLink(houseId, familyId, actorCid)
    end)
    if not ok then
        print(('[cm-family] cm-house SetFamilyHouseLink export failed: %s'):format(tostring(res)))
        return false, 'house_link_error'
    end
    return res == true, why
end

function B.GetFamilyVehicles(familyId)
    if not started(HOUSE) then return {} end
    local ok, v = pcall(function() return exports[HOUSE]:GetFamilyVehicles(familyId) end)
    if ok and type(v) == 'table' then return v end
    return {}
end


function B.GetFamilyVehicleManagementList(familyId, ownerCid)
    if not started(HOUSE) then return {} end
    local ok, vehicles = pcall(function()
        return exports[HOUSE]:GetFamilyVehicleManagementList(familyId, ownerCid)
    end)
    if ok and type(vehicles) == 'table' then return vehicles end
    return {}
end

function B.SetVehicleFamilyShared(vehicleId, shared, actorCid)
    if not started(HOUSE) then return false, 'house_not_running' end
    local ok, result, reason = pcall(function()
        return exports[HOUSE]:SetVehicleFamilyShared(vehicleId, shared == true, actorCid)
    end)
    if not ok then return false, 'house_vehicle_share_error' end
    return result == true, reason
end

function B.RecallAllFamilyGarageVehicles(familyId, actorCid)
    if not started(HOUSE) then return false, 'house_not_running' end
    local ok, result, detail = pcall(function()
        return exports[HOUSE]:RecallAllFamilyGarageVehicles(familyId, actorCid)
    end)
    if not ok then
        print(('[cm-family] family garage recall-all export failed: %s'):format(tostring(result)))
        return false, 'house_recall_all_error'
    end
    return result == true, detail
end

function B.RefreshFamilyMembers(familyId)
    if not started(HOUSE) then return false, 'house_not_running' end
    local ok, result, detail = pcall(function()
        return exports[HOUSE]:RefreshFamilyMembers(familyId)
    end)
    if not ok then
        print(('[cm-family] house member refresh failed for family %s: %s')
            :format(tostring(familyId), tostring(result)))
        return false, 'house_refresh_error'
    end
    if result ~= true then
        print(('[cm-family] house member refresh rejected for family %s: %s')
            :format(tostring(familyId), tostring(detail)))
        return false, detail or 'house_refresh_rejected'
    end
    return true, detail
end

function B.RefreshCharacterAccess(characterId)
    if not started(HOUSE) then return false end
    local ok, result = pcall(function() return exports[HOUSE]:RefreshFamilyAccess(characterId) end)
    return ok and result == true
end

-- Every existing caller supplies a family id. The old bridge accidentally sent
-- that number to cm-house's single-character refresh export, so a new member's
-- client house map was never refreshed. Refresh the whole family instead.
function B.RefreshFamilyAccess(familyId)
    return B.RefreshFamilyMembers(familyId)
end

function B.GetHouse(houseId)
    if not started(HOUSE) then return nil end
    local ok, h = pcall(function() return exports[HOUSE]:GetHouse(houseId) end)
    if ok then return h end
    return nil
end

return B
