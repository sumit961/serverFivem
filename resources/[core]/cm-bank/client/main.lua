local Config = CMBank.Config

local isOpen = false
local openPending = false
local promptVisible = false
local atmModelHashes = {}

for _, model in ipairs(Config.AtmModels or {}) do
    atmModelHashes[#atmModelHashes + 1] = joaat(model)
end

local function dbg(...)
    if Config.Debug then print('[CM-BANK]', ...) end
end

local function notify(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', message, kind or 'info')
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

local function nui(action, payload)
    SendNUIMessage({ action = action, data = payload or {} })
end

local function sendInteraction(visible, overrides)
    if promptVisible == visible then return end
    promptVisible = visible
    local interaction = Config.Interaction or {}
    overrides = overrides or {}
    nui('interaction', {
        visible = visible == true,
        key = Config.interactKeyLabel or 'E',
        name = overrides.name or interaction.title or 'ATM',
        role = overrides.role or interaction.hint or 'Deposit, withdraw or send money',
    })
end

local function drawText3D(coords, lines)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    local camCoords = GetGameplayCamCoords()
    local dist = #(camCoords - coords)
    local scale = math.max(0.28, math.min(0.42, 0.5 / math.max(dist * 0.3, 1.0)))
    local lineGap = 0.026
    local startY = y - ((#lines - 1) * lineGap * 0.5)

    for i, line in ipairs(lines) do
        SetTextScale(scale, scale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(line.r or 235, line.g or 245, line.b or 255, line.a or 235)
        SetTextCentre(true)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(line.text or '')
        EndTextCommandDisplayText(x, startY + (i - 1) * lineGap)
    end
end

local function getClosestAtm(coords, maxDistance)
    local closestDist = maxDistance
    local closestObj = nil
    for _, model in ipairs(atmModelHashes) do
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, maxDistance, model, false, false, false)
        if obj and obj ~= 0 then
            local dist = #(coords - GetEntityCoords(obj))
            if dist < closestDist then
                closestDist = dist
                closestObj = obj
            end
        end
    end
    return closestObj ~= nil, closestDist, closestObj
end

-- ATM blips: locations are learned from the scan loop below (as any client
-- walks within detectDistance of a real prop) rather than hardcoded, so the
-- blip set stays accurate across map/prop changes. See CMBank.CoordKey.
local blippedAtmKeys = {}
local reportedAtmKeys = {}

local function createAtmBlip(coords)
    local cfg = Config.AtmBlip or {}
    if cfg.enabled == false then return end
    local key = CMBank.CoordKey(coords.x, coords.y, coords.z)
    if blippedAtmKeys[key] then return end
    blippedAtmKeys[key] = true

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, cfg.sprite or 108)
    SetBlipColour(blip, cfg.color or 2)
    SetBlipScale(blip, cfg.scale or 0.7)
    SetBlipAsShortRange(blip, cfg.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(cfg.label or 'ATM')
    EndTextCommandSetBlipName(blip)
end

RegisterNetEvent('cm-bank:client:syncAtmBlips', function(list)
    for _, coords in ipairs(list or {}) do
        createAtmBlip(coords)
    end
end)

RegisterNetEvent('cm-bank:client:addAtmBlip', function(coords)
    if type(coords) == 'table' then createAtmBlip(coords) end
end)

CreateThread(function()
    TriggerServerEvent('cm-bank:server:requestAtmSync')
end)

local function closeMenu(sendClose)
    if not isOpen and not openPending then return end
    isOpen = false
    openPending = false
    SetNuiFocus(false, false)
    nui('close', {})
    if sendClose then TriggerServerEvent('cm-bank:server:closeSession') end
end

local pendingSource = 'atm'

local function openMenu(source)
    if isOpen or openPending then return end
    openPending = true
    pendingSource = source or 'atm'
    sendInteraction(false)
    TriggerServerEvent('cm-bank:server:requestOpen')
end

RegisterNetEvent('cm-bank:client:openMenu', function(ctx)
    if not openPending then return end
    openPending = false
    isOpen = true
    ctx = type(ctx) == 'table' and ctx or {}
    -- The server now derives the authoritative source from player position.
    -- pendingSource remains only as a compatibility fallback for older payloads.
    ctx.source = ctx.source or pendingSource
    SetNuiFocus(true, true)
    nui('open', ctx)
end)

RegisterNetEvent('cm-bank:client:openDenied', function(message)
    openPending = false
    if message and message ~= '' then notify(message, 'error') end
end)

RegisterNetEvent('cm-bank:client:actionResult', function(action, result)
    result = type(result) == 'table' and result or {}
    nui('actionResult', { action = action, result = result })
    if result.message and result.message ~= '' then
        notify(result.message, result.ok and 'success' or 'error')
    end
end)

RegisterNetEvent('cm-bank:client:ownershipToggled', function(enabled)
    nui('ownershipToggled', { enabled = enabled == true })
end)

RegisterNetEvent('cm-bank:client:recipientLookupResult', function(result)
    nui('recipientLookupResult', type(result) == 'table' and result or {})
end)

RegisterNetEvent('cm-bank:client:statementsResult', function(result)
    nui('statementsResult', type(result) == 'table' and result or {})
end)

RegisterNetEvent('cm-bank:client:atmAnalyticsResult', function(result)
    nui('atmAnalyticsResult', type(result) == 'table' and result or {})
end)

RegisterNetEvent('cm-bank:client:atmHistoryResult', function(result)
    nui('atmHistoryResult', type(result) == 'table' and result or {})
end)

RegisterNetEvent('cm-bank:client:payeesResult', function(result)
    nui('payeesResult', type(result) == 'table' and result or {})
end)

-- v1.6.0: reuses the existing notify() helper (cm-hud if present, else the
-- native thefeed ticker) — no new notification system, just one more caller.
RegisterNetEvent('cm-bank:client:atmNotice', function(message, kind)
    if message and message ~= '' then notify(message, kind or 'error') end
end)

RegisterNUICallback('deposit', function(data, cb)
    TriggerServerEvent('cm-bank:server:deposit', tonumber(data and data.amount))
    cb({ ok = true })
end)

RegisterNUICallback('withdraw', function(data, cb)
    TriggerServerEvent('cm-bank:server:withdraw', tonumber(data and data.amount))
    cb({ ok = true })
end)

RegisterNUICallback('transfer', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-bank:server:transfer', tonumber(data.targetCharId), tonumber(data.amount), data.note)
    cb({ ok = true })
end)

RegisterNUICallback('lookupRecipient', function(data, cb)
    TriggerServerEvent('cm-bank:server:lookupRecipient', tonumber(data and data.targetCharId))
    cb({ ok = true })
end)

RegisterNUICallback('fetchPayees', function(_, cb)
    TriggerServerEvent('cm-bank:server:fetchPayees')
    cb({ ok = true })
end)

RegisterNUICallback('addPayee', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-bank:server:addPayee', tonumber(data.recipientCharId), data.nickname)
    cb({ ok = true })
end)

RegisterNUICallback('renamePayee', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-bank:server:renamePayee', tonumber(data.payeeId), data.nickname)
    cb({ ok = true })
end)

RegisterNUICallback('setPayeeFavourite', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-bank:server:setPayeeFavourite', tonumber(data.payeeId), data.favourite == true)
    cb({ ok = true })
end)

RegisterNUICallback('deletePayee', function(data, cb)
    TriggerServerEvent('cm-bank:server:deletePayee', tonumber(data and data.payeeId))
    cb({ ok = true })
end)

RegisterNUICallback('fetchStatements', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-bank:server:fetchStatements', {
        page = tonumber(data.page),
        filter = data.filter,
        search = data.search,
        dateRange = data.dateRange,
    })
    cb({ ok = true })
end)

RegisterNUICallback('buyAtm', function(_, cb)
    TriggerServerEvent('cm-bank:server:buyAtm')
    cb({ ok = true })
end)

RegisterNUICallback('setAtmFee', function(data, cb)
    TriggerServerEvent('cm-bank:server:setAtmFee', tonumber(data and data.feePercent))
    cb({ ok = true })
end)

RegisterNUICallback('withdrawAtmEarnings', function(_, cb)
    TriggerServerEvent('cm-bank:server:withdrawAtmEarnings')
    cb({ ok = true })
end)

RegisterNUICallback('sellAtm', function(_, cb)
    TriggerServerEvent('cm-bank:server:sellAtm')
    cb({ ok = true })
end)

RegisterNUICallback('setAtmContact', function(data, cb)
    TriggerServerEvent('cm-bank:server:setAtmContact', data and data.contact)
    cb({ ok = true })
end)

RegisterNUICallback('restockAtm', function(data, cb)
    TriggerServerEvent('cm-bank:server:restockAtm', tonumber(data and data.amount))
    cb({ ok = true })
end)

RegisterNUICallback('fetchAtmAnalytics', function(data, cb)
    TriggerServerEvent('cm-bank:server:fetchAtmAnalytics', data and data.range)
    cb({ ok = true })
end)

RegisterNUICallback('fetchAtmHistory', function(data, cb)
    TriggerServerEvent('cm-bank:server:fetchAtmHistory', { page = tonumber(data and data.page) })
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu(true)
    cb({ ok = true })
end)

CreateThread(function()
    local perf = Config.Perf or { farSleep = 1500, nearSleep = 400, activeSleep = 0 }
    local detectDistance = tonumber(Config.detectDistance) or 20.0
    local interactDistance = tonumber(Config.interactDistance) or 1.6

    while true do
        local sleep = perf.farSleep

        if isOpen or openPending then
            sendInteraction(false)
            sleep = 250
        else
            local ped = PlayerPedId()
            if not IsPauseMenuActive() and not IsEntityDead(ped) then
                local coords = GetEntityCoords(ped)
                local nearAny, dist, atmObj = getClosestAtm(coords, detectDistance)
                if nearAny then
                    sleep = perf.nearSleep

                    local atmCoords = GetEntityCoords(atmObj)
                    local key = CMBank.CoordKey(atmCoords.x, atmCoords.y, atmCoords.z)
                    if not reportedAtmKeys[key] then
                        reportedAtmKeys[key] = true
                        if not blippedAtmKeys[key] then
                            TriggerServerEvent('cm-bank:server:reportAtm', { x = atmCoords.x, y = atmCoords.y, z = atmCoords.z })
                        end
                    end

                    if dist <= interactDistance then
                        sleep = perf.activeSleep
                        sendInteraction(true)
                        if IsControlJustPressed(0, Config.interactKey or 38) then
                            openMenu('atm')
                            Wait(350)
                        end
                    else
                        sendInteraction(false)
                    end
                else
                    sendInteraction(false)
                end
            else
                sendInteraction(false)
            end
        end

        Wait(sleep)
    end
end)

-- Bank tellers: admin-placed NPCs (see Config.Tellers). Spawned from sync/add
-- events, never guessed at hardcoded coordinates.
local tellers = {}

-- Universally-valid ambient ped, used if the configured model turns out not
-- to be a normally-streamable one (e.g. some named peds are cutscene-only
-- and silently refuse to load via CreatePed).
local FALLBACK_TELLER_MODEL = 'a_m_m_business_01'

local function tryLoadModel(modelName)
    local hash = joaat(modelName)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local attempts = 0
    while not HasModelLoaded(hash) and attempts < 200 do
        Wait(10)
        attempts = attempts + 1
    end
    return HasModelLoaded(hash) and hash or nil
end

local function requestTellerModel(modelName)
    local hash = tryLoadModel(modelName)
    if hash then return hash end
    if modelName ~= FALLBACK_TELLER_MODEL then
        print(('[CM-BANK] Teller model "%s" failed to load, falling back to %s'):format(tostring(modelName), FALLBACK_TELLER_MODEL))
        return tryLoadModel(FALLBACK_TELLER_MODEL)
    end
    return nil
end

local function createTellerBlip(t, cfg)
    local blipCfg = cfg.Blip or {}
    if blipCfg.enabled == false then return nil end
    local blip = AddBlipForCoord(t.x, t.y, t.z)
    SetBlipSprite(blip, blipCfg.sprite or 108)
    SetBlipColour(blip, blipCfg.color or 3)
    SetBlipScale(blip, blipCfg.scale or 0.85)
    SetBlipAsShortRange(blip, blipCfg.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(t.name or 'Bank')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function spawnTeller(t)
    if not t or not t.id or tellers[t.id] then return end
    local cfg = Config.Tellers or {}
    if cfg.enabled == false then return end

    tellers[t.id] = {
        id = t.id, name = t.name, coords = vector3(t.x, t.y, t.z), heading = t.heading or 0,
        ped = nil, blip = createTellerBlip(t, cfg),
    }

    CreateThread(function()
        local hash = requestTellerModel(t.model or cfg.model or FALLBACK_TELLER_MODEL)
        if not hash then
            print('[CM-BANK] Failed to load any teller ped model for', t.name)
            return
        end
        local ped = CreatePed(4, hash, t.x, t.y, t.z, t.heading or 0, false, false)
        SetEntityAsMissionEntity(ped, true, true)
        SetModelAsNoLongerNeeded(hash)

        -- Let the ped's collision settle for a tick, then snap it to the
        -- actual ground height at this XY before locking it in place —
        -- freezing immediately at the raw stored Z can leave it floating or
        -- embedded if that Z isn't exactly ground level.
        Wait(50)
        PlaceEntityOnGroundProperly(ped)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedCanRagdollFromPlayerImpact(ped, false)
        SetPedCanRagdoll(ped, false)
        SetPedDiesWhenInjured(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        -- Matches the peaceful-ped pattern already proven in cm-gunstore.
        SetPedCombatAttributes(ped, 46, true)
        -- Zero perception means the AI never receives the "I'm being
        -- attacked" stimulus that would trigger a fight/defend reaction in
        -- the first place — this is what invincibility alone doesn't cover.
        SetPedSeeingRange(ped, 0.0)
        SetPedHearingRange(ped, 0.0)
        SetPedAlertness(ped, 0)
        SetPedCanBeTargetted(ped, false)
        local scenario = cfg.scenario or 'WORLD_HUMAN_STAND_IMPATIENT'
        TaskStartScenarioInPlace(ped, scenario, 0, true)

        if tellers[t.id] then
            tellers[t.id].ped = ped
            tellers[t.id].scenario = scenario
        end

        -- Belt-and-suspenders: even with zero perception, a direct melee
        -- hit can still force a brief in-place reaction animation (freezing
        -- position stops it from moving, not from playing that animation).
        -- Re-asserting the idle scenario every second forces it back to
        -- fully idle within at most a second, no matter what triggered it.
        CreateThread(function()
            while tellers[t.id] and tellers[t.id].ped == ped do
                Wait(1000)
                if DoesEntityExist(ped) then
                    if GetEntityHealth(ped) < GetEntityMaxHealth(ped) then
                        SetEntityHealth(ped, GetEntityMaxHealth(ped))
                    end
                    FreezeEntityPosition(ped, true)
                    TaskStartScenarioInPlace(ped, scenario, 0, true)
                else
                    break
                end
            end
        end)
    end)
end

local function despawnTeller(id)
    local entry = tellers[id]
    if not entry then return end
    if entry.ped and DoesEntityExist(entry.ped) then
        DeleteEntity(entry.ped)
    end
    if entry.blip and DoesBlipExist(entry.blip) then
        RemoveBlip(entry.blip)
    end
    tellers[id] = nil
end

RegisterNetEvent('cm-bank:client:syncTellers', function(list)
    for _, t in ipairs(list or {}) do spawnTeller(t) end
end)

RegisterNetEvent('cm-bank:client:addTeller', function(t)
    if type(t) == 'table' then spawnTeller(t) end
end)

RegisterNetEvent('cm-bank:client:removeTeller', function(id)
    despawnTeller(tonumber(id))
end)

CreateThread(function()
    TriggerServerEvent('cm-bank:server:requestTellerSync')
end)

local function findClosestTeller(coords, maxDistance)
    local closestDist = maxDistance
    local closest = nil
    for _, t in pairs(tellers) do
        local dist = #(coords - t.coords)
        if dist < closestDist then
            closestDist = dist
            closest = t
        end
    end
    return closest, closestDist
end

CreateThread(function()
    local cfg = Config.Tellers or {}
    local speakDistance = tonumber(cfg.speakDistance) or 6.0
    local interactDistance = tonumber(cfg.interactDistance) or 1.8
    local greetSound = cfg.greetSound or { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' }
    local nearTellerId = nil

    while true do
        local sleep = 800

        if cfg.enabled ~= false and not isOpen and not openPending then
            local ped = PlayerPedId()
            if not IsPauseMenuActive() and not IsEntityDead(ped) then
                local coords = GetEntityCoords(ped)
                local teller, dist = findClosestTeller(coords, speakDistance)
                if teller then
                    sleep = 0
                    drawText3D(teller.coords + vector3(0.0, 0.0, 1.0), {
                        { text = teller.name, r = 120, g = 220, b = 255, a = 240 },
                    })

                    if teller.id ~= nearTellerId then
                        nearTellerId = teller.id
                        dbg(('Greeting %s with sound %s/%s'):format(teller.name, greetSound.name, greetSound.set))
                        PlaySoundFrontend(-1, greetSound.name, greetSound.set, true)
                    end

                    if dist <= interactDistance then
                        sendInteraction(true, { name = teller.name, role = 'Deposit, withdraw or send money' })
                        if IsControlJustPressed(0, Config.interactKey or 38) then
                            openMenu('teller')
                            Wait(350)
                        end
                    else
                        sendInteraction(false)
                    end
                else
                    nearTellerId = nil
                    sendInteraction(false)
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if isOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 200, true)
            if IsControlJustPressed(0, 200) then closeMenu(true) end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    sendInteraction(false)
    SetNuiFocus(false, false)
    for _, t in pairs(tellers) do
        if t.ped and DoesEntityExist(t.ped) then DeleteEntity(t.ped) end
        if t.blip and DoesBlipExist(t.blip) then RemoveBlip(t.blip) end
    end
end)
