-- cm-hub/server/main.lua
-- Server authority for CM Hub (M-Menu) data aggregation and actions.

local function getCharacterId(src)
    if GetResourceState('cm-playerdata') == 'started' then
        local ok, cid = pcall(function() return exports['cm-playerdata']:GetCharacterId(src) end)
        if ok and tonumber(cid) then return tonumber(cid) end
    end
    local ply = Player(src)
    if ply and ply.state and ply.state.charId then
        return tonumber(ply.state.charId)
    end
    return nil
end

lib.callback.register('cm-hub:server:getPlayerData', function(source)
    local src = source
    local charId = getCharacterId(src)
    if not charId then
        return {
            ok = false,
            message = 'No active character loaded.'
        }
    end

    local fullName = 'Citizen'
    local cash = 0
    local bank = 0

    if GetResourceState('cm-playerdata') == 'started' then
        pcall(function()
            fullName = exports['cm-playerdata']:GetCharacterFullName(src) or 'Citizen'
            cash = tonumber(exports['cm-playerdata']:GetCash(src)) or 0
            bank = tonumber(exports['cm-playerdata']:GetBank(src)) or 0
        end)
    end

    -- Family membership check
    local familyName = 'None'
    local familyRank = nil
    if GetResourceState('cm-family') == 'started' then
        pcall(function()
            local fam = exports['cm-family']:GetFamilyForCharacter(charId)
            if fam and fam.id then
                familyName = fam.name or ('Family #' .. tostring(fam.id))
                familyRank = fam.rankName or ('Rank ' .. tostring(fam.rank or ''))
            end
        end)
    end

    -- Organization / Gang membership check
    local orgName = 'Civilian'
    local plyState = Player(src).state
    if plyState then
        if type(plyState.cmPolice) == 'table' and tonumber(plyState.cmPolice.organizationId) == 1 then
            orgName = 'San Andreas Police'
        elseif type(plyState.cmLegalOrg) == 'table' and type(plyState.cmLegalOrg.id) == 'string' and plyState.cmLegalOrg.id ~= '' then
            orgName = plyState.cmLegalOrg.name or 'Department of Justice'
        elseif type(plyState.cmEms) == 'table' and tonumber(plyState.cmEms.organizationId) == 1 then
            orgName = 'Emergency Medical Services'
        elseif GetResourceState('cm-gang') == 'started' then
            pcall(function()
                local gang = exports['cm-gang']:GetGangForCharacter(charId)
                if gang and gang.gangId then
                    orgName = gang.name or gang.displayName or gang.gangId:upper()
                end
            end)
        end
    end

    -- Character table details (gender, phone, created_at)
    local gender = 'male'
    local phone = 'Not Available'
    local createdAt = nil
    pcall(function()
        local rows = MySQL.query.await('SELECT gender, phone_number, created_at FROM characters WHERE id = ? LIMIT 1', { charId })
        if rows and rows[1] then
            if rows[1].gender then gender = tostring(rows[1].gender):lower() end
            if rows[1].phone_number and rows[1].phone_number ~= '' then phone = tostring(rows[1].phone_number) end
            createdAt = rows[1].created_at
        end
    end)

    -- Fines sum from police / legal citations
    local fines = 0
    pcall(function()
        local cRows = MySQL.query.await('SELECT COALESCE(SUM(fine), 0) AS total FROM cm_police_citations WHERE target_cid = ?', { tostring(charId) })
        if cRows and cRows[1] and cRows[1].total then
            fines = tonumber(cRows[1].total) or 0
        end
    end)

    -- Criminal record check
    local hasCriminalRecord = false
    if plyState and plyState.cmGang and type(plyState.cmGang) == 'table' and plyState.cmGang.gangId then
        hasCriminalRecord = true
    end

    -- Licenses check
    local licenses = {
        driver = false,
        water = false,
        air = false,
        weapon = false,
        military = false,
        lawyer = false,
        insurance = false,
    }
    if GetResourceState('cm-license') == 'started' then
        pcall(function()
            local summary = exports['cm-license']:GetLicenseSummary(charId)
            if type(summary) == 'table' then
                if summary.driver and summary.driver.status == 'active' then licenses.driver = true end
                if summary.boat and summary.boat.status == 'active' then licenses.water = true end
                if summary.air and summary.air.status == 'active' then licenses.air = true end
            end
        end)
    end
    if GetResourceState('cm-weapons') == 'started' then
        pcall(function()
            if exports['cm-weapons']:HasWeaponLicense(src) then
                licenses.weapon = true
            end
        end)
    end

    -- Vehicles list (Autopark)
    local vehicles = {}
    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function()
            local vRows = exports['cm-vehicles']:GetVehiclesByOwner(charId, { limit = 10 })
            if type(vRows) == 'table' then
                for i, v in ipairs(vRows) do
                    table.insert(vehicles, {
                        slot = i,
                        id = v.id,
                        model = v.model or v.name or 'Vehicle',
                        plate = v.plate or 'N/A'
                    })
                end
            end
        end)
    end

    -- Houses list
    local houses = {}
    if GetResourceState('cm-house') == 'started' then
        pcall(function()
            local hRows = exports['cm-house']:GetHousesForCharacter(charId)
            if type(hRows) == 'table' then
                for i, h in ipairs(hRows) do
                    local door = h.door_coords or h.door or h.coords
                    table.insert(houses, {
                        slot = i,
                        id = h.id,
                        label = h.label or h.name or ('House #' .. tostring(h.id)),
                        paid = '14 / 14',
                        coords = door and { x = door.x, y = door.y, z = door.z } or nil
                    })
                end
            end
        end)
    end

    -- Family house
    local familyHouse = nil
    if GetResourceState('cm-family') == 'started' and GetResourceState('cm-house') == 'started' then
        pcall(function()
            local fam = exports['cm-family']:GetFamilyForCharacter(charId)
            if fam and fam.id then
                local famHouses = exports['cm-house']:GetFamilyHouses(fam.id)
                if type(famHouses) == 'table' and #famHouses > 0 then
                    local fh = famHouses[1]
                    local fDoor = fh.door_coords or fh.door or fh.coords
                    familyHouse = {
                        id = fh.id,
                        label = ('FAMILY HOUSE %s'):format(fh.label or fh.name or tostring(fh.id)),
                        paid = '14 / 14',
                        coords = fDoor and { x = fDoor.x, y = fDoor.y, z = fDoor.z } or nil
                    }
                end
            end
        end)
    end

    return {
        ok = true,
        charId = charId,
        fullName = fullName,
        gender = gender,
        phone = phone,
        cash = cash,
        bank = bank,
        family = familyName,
        familyRank = familyRank or 'Member',
        organization = orgName,
        fines = fines,
        criminalRecord = hasCriminalRecord,
        warnings = 0,
        licenses = licenses,
        vehicles = vehicles,
        houses = houses,
        familyHouse = familyHouse,
        level = 39,
        currentXp = 8,
        maxXp = 156,
        vip = false,
        figurines = 2,
    }
end)

-- Receive admin reports/feedback from Hub
RegisterNetEvent('cm-hub:server:submitAdminReport', function(message)
    local src = source
    local charId = getCharacterId(src)
    local text = tostring(message or ''):sub(1, 255)
    if text == '' then return end

    local name = 'Citizen'
    if GetResourceState('cm-playerdata') == 'started' then
        pcall(function()
            name = exports['cm-playerdata']:GetCharacterFullName(src) or 'Citizen'
        end)
    end

    print(('[CM-HUB] Admin report from %s (CharID: %s, Source: %s): %s'):format(name, tostring(charId or 'N/A'), tostring(src), text))

    -- Notify admins
    for _, player in ipairs(GetPlayers()) do
        local pSrc = tonumber(player)
        if IsPlayerAceAllowed(player, 'command') or IsPlayerAceAllowed(player, 'group.admin') then
            if GetResourceState('cm-hud') == 'started' then
                TriggerClientEvent('cm-hud:client:notify', pSrc, ('[REPORT] #%s %s: %s'):format(tostring(charId or src), name, text), 'warning')
            end
        end
    end

    if GetResourceState('cm-hud') == 'started' then
        TriggerClientEvent('cm-hud:client:notify', src, 'Your message has been dispatched to available administrators.', 'success')
    end
end)

