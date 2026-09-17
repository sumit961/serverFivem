-- cm-hub/client/main.lua
-- Client controller for CM Hub (M-Menu)

local isMenuOpen = false
local HUD_REASON = 'cm-hub'

local function notify(message, kind)
    local notifyKind = kind or 'info'
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', tostring(message or ''), notifyKind)
        return
    end
    if lib and lib.notify then
        lib.notify({ description = message, type = notifyKind })
    end
end

local function closeHub()
    if not isMenuOpen then return end
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerEvent('cm-hud:client:showAfterUi')
    TriggerEvent('cm-chat:client:showAfterUi')
end

local function openHub()
    if isMenuOpen then
        closeHub()
        return
    end

    if LocalPlayer.state.isDead == true then
        notify('You cannot open the hub while incapacitated.', 'error')
        return
    end

    -- Pull live player profile
    local playerData = {}
    local ok, res = pcall(function()
        return lib.callback.await('cm-hub:server:getPlayerData', false)
    end)
    if ok and type(res) == 'table' and res.ok then
        playerData = res
    else
        playerData = {
            fullName = 'Citizen',
            charId = LocalPlayer.state.charId or LocalPlayer.state.characterId or 'N/A',
            cash = LocalPlayer.state.cash or 0,
            bank = LocalPlayer.state.bank or 0,
            family = 'None',
            organization = 'Civilian'
        }
    end

    isMenuOpen = true
    SetNuiFocus(true, true)
    TriggerEvent('cm-hud:client:hideForUi', HUD_REASON)
    TriggerEvent('cm-chat:client:hideForUi', HUD_REASON)
    SendNUIMessage({
        action = 'open',
        data = playerData,
        config = Config
    })
end

local function toggleHub()
    if isMenuOpen then
        closeHub()
    else
        openHub()
    end
end

-- Keymapping and commands
RegisterCommand(Config.Command or 'hub', toggleHub, false)
RegisterKeyMapping(Config.Command or 'hub', 'Open CM Hub Menu', 'keyboard', Config.DefaultKey or 'M')

if Config.CommandAliases then
    for _, alias in ipairs(Config.CommandAliases) do
        RegisterCommand(alias, toggleHub, false)
    end
end

-- NUI callbacks
RegisterNUICallback('close', function(_, cb)
    closeHub()
    cb({ ok = true })
end)

RegisterNUICallback('notify', function(data, cb)
    data = type(data) == 'table' and data or {}
    notify(data.message or 'Information', data.kind or 'info')
    cb({ ok = true })
end)

RegisterNUICallback('get_employed', function(data, cb)
    data = type(data) == 'table' and data or {}
    local jobId = tostring(data.jobId or '')

    local foundJob = nil
    for _, job in ipairs(Config.Jobs or {}) do
        if job.id == jobId then
            foundJob = job
            break
        end
    end

    if not foundJob then
        notify('Selected job not recognized.', 'error')
        cb({ ok = false })
        return
    end

    closeHub()
    Wait(150)

    if foundJob.coords then
        SetNewWaypoint(foundJob.coords.x, foundJob.coords.y)
    end

    notify(('Career Selected: %s! GPS set to %s. Report to %s to begin work.'):format(
        foundJob.title,
        foundJob.locationName or 'job location',
        foundJob.npcName or 'the supervisor'
    ), 'success')

    cb({ ok = true })
end)

RegisterNUICallback('set_waypoint', function(data, cb)
    data = type(data) == 'table' and data or {}
    if data.coords and data.coords.x and data.coords.y then
        closeHub()
        Wait(150)
        SetNewWaypoint(tonumber(data.coords.x) + 0.0, tonumber(data.coords.y) + 0.0)
        notify(('GPS waypoint set: %s'):format(tostring(data.label or 'Selected Property')), 'success')
    else
        notify('Coordinates unavailable for this location.', 'info')
    end
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    data = type(data) == 'table' and data or {}
    local action = data.action

    if action == 'family' then
        closeHub()
        Wait(150)
        ExecuteCommand('family')
        cb({ ok = true })
        return
    end

    if action == 'organization' then
        closeHub()
        Wait(150)
        local state = LocalPlayer.state
        local hasOfficialOrg = false

        if (state.cmPolice and tonumber(state.cmPolice.organizationId) == 1) or
           (state.cmLegalOrg and state.cmLegalOrg.id) or
           (state.cmEms and tonumber(state.cmEms.organizationId) == 1) then
            hasOfficialOrg = true
            ExecuteCommand('cmorgdashboard')
        elseif state.cmGang and type(state.cmGang) == 'table' and state.cmGang.gangId then
            ExecuteCommand('gang')
        else
            notify('You are not a member of any organization or gang.', 'info')
        end
        cb({ ok = true })
        return
    end

    if action == 'inventory' then
        closeHub()
        Wait(150)
        ExecuteCommand('inventory')
        cb({ ok = true })
        return
    end

    if action == 'clothes' then
        closeHub()
        Wait(150)
        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        local bestCoords = vector3(72.25, -1399.1, 29.38)
        local bestDist = #(pCoords - bestCoords)

        local knownStores = {
            vector3(72.25, -1399.1, 29.38),
            vector3(-709.6, -153.1, 37.4),
            vector3(-163.4, -303.3, 39.7),
            vector3(425.6, -806.2, 29.4),
            vector3(-822.4, -1073.5, 11.3),
            vector3(-1193.4, -767.9, 17.3),
            vector3(1693.9, 4822.8, 42.0),
            vector3(125.8, -223.8, 54.5),
            vector3(614.2, 2762.8, 42.0),
            vector3(1196.6, 2710.2, 38.2),
            vector3(-3170.5, 1043.8, 20.8),
            vector3(-1101.4, 2710.6, 19.1)
        }
        for _, store in ipairs(knownStores) do
            local d = #(pCoords - store)
            if d < bestDist then
                bestDist = d
                bestCoords = store
            end
        end

        SetNewWaypoint(bestCoords.x, bestCoords.y)
        notify('GPS set to the nearest Clothing Store & Wardrobe.', 'success')
        cb({ ok = true })
        return
    end

    if action == 'jobcenter' or action == 'job' then
        closeHub()
        Wait(150)
        local empCoords = vector3(718.72, 152.38, 80.74)
        SetNewWaypoint(empCoords.x, empCoords.y)
        notify('GPS set to City Employment Center (Electrician Depot / Switchboard). Speak to Frank Delgado to start civilian work!', 'success')
        cb({ ok = true })
        return
    end

    if action == 'premium_shop' or action == 'shop_hub' then
        closeHub()
        Wait(150)
        SetNewWaypoint(-772.88, -234.92)
        notify('GPS set to Pacific Bluffs Dealership showroom. Premium luxury vehicles and showroom features available.', 'success')
        cb({ ok = true })
        return
    end

    if action == 'events' then
        notify('Unique Events: City street races, car meets, and special tournaments are announced weekly! Check city announcements.', 'info')
        cb({ ok = true })
        return
    end

    if action == 'weekly_offers' then
        notify('Weekly Offers: Special promotional discounts on weaponry, vehicle tuning, and convenience stores are live this week!', 'info')
        cb({ ok = true })
        return
    end

    if action == 'daily_tasks' then
        notify('Daily Tasks: Complete daily jobs, deliveries, and community activities to earn cash bonuses and reputation!', 'info')
        cb({ ok = true })
        return
    end

    if action == 'business' or action == 'realestate' then
        closeHub()
        Wait(150)
        notify('Real Estate & Business: Check your map for property and business icons. Visit Dynasty 8 to browse available listings.', 'info')
        cb({ ok = true })
        return
    end

    if action == 'achievements' then
        notify('Achievements: Progress 11 / 54 completed! Reach city milestones in trading, driving, and career tasks to unlock rewards.', 'info')
        cb({ ok = true })
        return
    end

    if action == 'settings' then
        notify('Settings: Press F7 to toggle/configure HUD, N for Voice Chat, and ESC > Settings > Key Bindings for controls.', 'info')
        cb({ ok = true })
        return
    end

    if action == 'battlepass' then
        notify('Battlepass: Spring Season pass featuring exclusive outfits, vehicle liveries, and bonus crates coming soon!', 'info')
        cb({ ok = true })
        return
    end

    if action == 'contact_admin' then
        closeHub()
        Wait(150)
        local input = lib.inputDialog('Contact Server Staff', {
            { type = 'input', label = 'Subject / Issue', placeholder = 'Brief summary of your question or issue', required = true },
            { type = 'textarea', label = 'Details', placeholder = 'Please provide details so staff can assist you...', required = true, min = 5, max = 300 },
        })
        if input and input[1] and input[2] then
            local formatted = tostring(input[1]) .. ' - ' .. tostring(input[2])
            TriggerServerEvent('cm-hub:server:submitAdminReport', formatted)
        end
        cb({ ok = true })
        return
    end

    if action == 'coming_soon' then
        notify(data.message or 'This feature is coming soon!', 'info')
        cb({ ok = true })
        return
    end

    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isMenuOpen then
        SetNuiFocus(false, false)
    end
end)

