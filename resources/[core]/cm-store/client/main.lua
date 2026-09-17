-- cm-store/client/main.lua
-- Convenience store clerk NPCs, cm-ui E-interaction and cinematic NPC dialogue,
-- and gas-station styled interactive NUI bridge.

local RESOURCE = GetCurrentResourceName()
local Config = Config or {}

local uiOpen = false
local dialogueActive = false
local spawnedPeds = {}
local storeBlips = {}
local currentStoreId = 1
local interactShown = false

local function uiAvailable()
    return GetResourceState('cm-ui') == 'started'
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(20)
        tries = tries + 1
    end
    return HasModelLoaded(hash) and hash or nil
end

local function drawText3D(coords, text)
    local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(93, 232, 255, 235)
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(text or ''))
    EndTextCommandDisplayText(screenX, screenY)
end

-- ============================================================
-- Clerk Ped & Blip Spawning
-- ============================================================
local function cleanupStoreEntities()
    for _, p in ipairs(spawnedPeds) do
        if p.entity and DoesEntityExist(p.entity) then
            DeleteEntity(p.entity)
        end
    end
    spawnedPeds = {}

    for _, blip in ipairs(storeBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    storeBlips = {}
end

local function initStoreBlips()
    for _, shop in ipairs(Config.Shops or {}) do
        local b = shop.blip
        if b and b.sprite then
            local c = shop.coords or shop.pedCoords
            if c then
                local blip = AddBlipForCoord(tonumber(c.x or c[1]), tonumber(c.y or c[2]), tonumber(c.z or c[3]))
                SetBlipSprite(blip, b.sprite)
                SetBlipColour(blip, b.color or 2)
                SetBlipScale(blip, b.scale or 0.7)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(shop.name or shop.label or '24/7 Store')
                EndTextCommandSetBlipName(blip)
                storeBlips[#storeBlips + 1] = blip
            end
        end
    end
end

CreateThread(function()
    initStoreBlips()
end)

-- ============================================================
-- Clerk Ambient Sounds & Voice
-- ============================================================
local function playClerkAudio(ped, kind)
    local pedCfg = Config.Ped or {}
    if pedCfg.soundEnabled ~= false then
        if kind == 'door_bell' or kind == 'counter_bell' then
            -- Cash sound disabled per user request: no sound of cash when clerk activates
        elseif kind == 'interact' then
            -- Counter register tone
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        end
    end

    if pedCfg.voiceEnabled ~= false and ped and DoesEntityExist(ped) then
        local speech = 'SHOP_GREET'
        if kind == 'counter_bell' then
            speech = 'GENERIC_HOWS_IT_GOING'
        elseif kind == 'door_bell' or kind == 'door_greet' then
            speech = 'SHOP_GREET'
        elseif kind == 'interact' then
            local greetings = pedCfg.greetings or { 'SHOP_GREET', 'GENERIC_HI', 'GENERIC_HOWS_IT_GOING' }
            speech = greetings[math.random(#greetings)] or 'SHOP_GREET'
        end

        pcall(function()
            StopCurrentPlayingAmbientSpeech(ped)
            PlayPedAmbientSpeechNative(ped, speech, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
        end)
    end
end

-- ============================================================
-- World Cleanup & Prop Sweep
-- ============================================================
local function cleanupDroppedBrooms()
    local broomHash = GetHashKey('prop_tool_broom')
    local handle, obj = FindFirstObject()
    local success = true
    while success do
        if DoesEntityExist(obj) and GetEntityModel(obj) == broomHash then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
        success, obj = FindNextObject(handle)
    end
    EndFindObject(handle)
end

-- ============================================================
-- Clerk Spawning & Proximity Streaming
-- ============================================================
local function getShopShelfStations(shop)
    if shop.shelfStations and #shop.shelfStations > 0 then
        return shop.shelfStations
    end
    if shop.shelfCoords then
        local sc = shop.shelfCoords
        return {
            { coords = vector4(sc.x or sc[1], sc.y or sc[2], sc.z or sc[3], sc.w or sc[4] or 0.0), scenario = 'WORLD_HUMAN_CLIPBOARD' }
        }
    end
    local cp = shop.pedCoords or shop.coords
    return {
        { coords = vector4(cp.x or cp[1], cp.y or cp[2], cp.z or cp[3], cp.w or cp[4] or 0.0), scenario = 'WORLD_HUMAN_CLIPBOARD' }
    }
end

local function getAccurateGroundZ(x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
    local floorZ = z - 1.0
    if found and groundZ > 0.0 and math.abs(groundZ - floorZ) <= 0.6 then
        return groundZ
    end
    return floorZ
end

local function getShopStockCoords(shop)
    if shop.stockCoords then
        local sc = shop.stockCoords
        return vector4(tonumber(sc.x or sc[1]), tonumber(sc.y or sc[2]), tonumber(sc.z or sc[3]), tonumber(sc.w or sc[4] or 0.0))
    end
    if shop.shelfStations and #shop.shelfStations > 0 then
        local sc = shop.shelfStations[1].coords
        return vector4(tonumber(sc.x or sc[1]), tonumber(sc.y or sc[2]), tonumber(sc.z or sc[3]), tonumber(sc.w or sc[4] or 0.0))
    end
    if shop.shelfCoords then
        local sc = shop.shelfCoords
        return vector4(tonumber(sc.x or sc[1]), tonumber(sc.y or sc[2]), tonumber(sc.z or sc[3]), tonumber(sc.w or sc[4] or 0.0))
    end
    local cp = shop.pedCoords
    return vector4(tonumber(cp.x or cp[1]), tonumber(cp.y or cp[2]), tonumber(cp.z or cp[3]), tonumber(cp.w or cp[4] or 0.0))
end

local function spawnClerkForShop(shop, idx)
    local pedCfg = Config.Ped or {}
    if pedCfg.enabled == false then return nil end

    local hash = loadModel(pedCfg.model or 'mp_m_shopkeep_01')
    if not hash then return nil end

    local cp = shop.pedCoords
    if not cp then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    local cx = tonumber(cp.x or cp[1])
    local cy = tonumber(cp.y or cp[2])
    local cz = tonumber(cp.z or cp[3])
    local cw = tonumber(cp.w or cp[4] or 0.0)

    local stations = shop.shelfStations or {
        { coords = vector4(cx, cy, cz, cw), scenario = 'WORLD_HUMAN_CLIPBOARD', behindCounter = true }
    }
    local opening = shop.counterOpening and vector3(tonumber(shop.counterOpening.x or shop.counterOpening[1]), tonumber(shop.counterOpening.y or shop.counterOpening[2]), tonumber(shop.counterOpening.z or shop.counterOpening[3]))
        or vector3(cx, cy, cz)
    local openingAisle = shop.counterOpeningAisle and vector3(tonumber(shop.counterOpeningAisle.x or shop.counterOpeningAisle[1]), tonumber(shop.counterOpeningAisle.y or shop.counterOpeningAisle[2]), tonumber(shop.counterOpeningAisle.z or shop.counterOpeningAisle[3]))
        or opening
    local openingBehind = shop.counterOpeningBehind and vector3(tonumber(shop.counterOpeningBehind.x or shop.counterOpeningBehind[1]), tonumber(shop.counterOpeningBehind.y or shop.counterOpeningBehind[2]), tonumber(shop.counterOpeningBehind.z or shop.counterOpeningBehind[3]))
        or opening

    -- Clean any dropped broom props in the area
    cleanupDroppedBrooms()

    -- Clerk ALWAYS spawns in-store roaming at an aisle shelf station checking shelves or on phone.
    -- Never spawns on the counter or teleports!
    local initialStationIndex = 1
    for sIdx, st in ipairs(stations) do
        if not st.behindCounter then
            initialStationIndex = sIdx
            break
        end
    end
    local initSt = stations[initialStationIndex] or stations[1]
    local spawnX = tonumber(initSt.coords.x or initSt.coords[1])
    local spawnY = tonumber(initSt.coords.y or initSt.coords[2])
    local spawnZ = tonumber(initSt.coords.z or initSt.coords[3])
    local spawnHeading = tonumber(initSt.coords.w or initSt.coords[4] or 0.0)
    local initialScenario = initSt.scenario or 'WORLD_HUMAN_STAND_MOBILE'
    local initialState = 'AT_SHELF'

    local spawnNavZ = getAccurateGroundZ(spawnX, spawnY, spawnZ)
    local ped = CreatePed(4, hash, spawnX, spawnY, spawnNavZ, spawnHeading, false, true)
    if ped and ped ~= 0 then
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityHeading(ped, spawnHeading)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedCanRagdoll(ped, false)
        SetPedFleeAttributes(ped, 0, 0)
        SetPedCombatAttributes(ped, 17, 1)
        FreezeEntityPosition(ped, false)

        TaskStartScenarioInPlace(ped, initialScenario, 0, true)

        local namesList = pedCfg.names or { 'Marcus Reed', 'Eddie Knox', 'Derek Stone', 'Calvin Brooks' }
        local clerkName = namesList[((idx - 1) % #namesList) + 1] or 'Store Clerk'

        SetModelAsNoLongerNeeded(hash)

        return {
            storeId = tonumber(shop.id) or idx,
            shop = shop,
            entity = ped,
            clerkName = clerkName,
            state = initialState,
            stations = stations,
            stationIndex = initialStationIndex,
            counterOpening = opening,
            counterOpeningAisle = openingAisle,
            counterOpeningBehind = openingBehind,
            counterCoords = vector4(cx, cy, cz, cw),
            registerCoords = shop.registerCoords and vector3(shop.registerCoords.x, shop.registerCoords.y, shop.registerCoords.z) or vector3(cx, cy, cz),
            lastPlayerSeenAt = 0,
            lastGreetTime = 0,
            playerWasInside = false,
            outsideSince = GetGameTimer(),
            lastMovedAt = GetGameTimer(),
            walkStartTime = GetGameTimer(),
            nextStationSwitch = GetGameTimer() + math.random(14000, 24000),
            coords = vector3(cx, cy, cz),
        }
    end

    SetModelAsNoLongerNeeded(hash)
    return nil
end

local function despawnClerk(entry)
    if entry and entry.entity and DoesEntityExist(entry.entity) then
        DeleteEntity(entry.entity)
    end
end

-- Streaming thread: Spawns clerks dynamically when player is near, despawns when far
CreateThread(function()
    local SPAWN_DIST = 75.0
    local DESPAWN_DIST = 95.0

    cleanupDroppedBrooms()

    while true do
        Wait(800)
        local pcoords = GetEntityCoords(PlayerPedId())

        for idx, shop in ipairs(Config.Shops or {}) do
            local shopPos = shop.coords or (shop.pedCoords and vector3(shop.pedCoords.x, shop.pedCoords.y, shop.pedCoords.z))
            if shopPos then
                local dist = #(pcoords - vector3(shopPos.x, shopPos.y, shopPos.z))
                local currentEntry = nil
                local entryIdx = nil

                for eIdx, entry in ipairs(spawnedPeds) do
                    if entry.storeId == (tonumber(shop.id) or idx) then
                        currentEntry = entry
                        entryIdx = eIdx
                        break
                    end
                end

                if dist <= SPAWN_DIST and not currentEntry then
                    local entry = spawnClerkForShop(shop, idx)
                    if entry then
                        spawnedPeds[#spawnedPeds + 1] = entry
                    end
                elseif dist > DESPAWN_DIST and currentEntry then
                    despawnClerk(currentEntry)
                    table.remove(spawnedPeds, entryIdx)
                end
            end
        end
    end
end)

-- Helper to check whether a ped is physically on the clerk side behind the counter
local function isPedBehindCounter(ped, entry)
    if not ped or not DoesEntityExist(ped) then return false end
    local pedPos = GetEntityCoords(ped)
    local cx = entry.counterCoords.x
    local cy = entry.counterCoords.y
    local cz = entry.counterCoords.z
    local reg = entry.registerCoords or vector3(cx, cy, cz)
    -- Direction vector from cash register to behind-counter spot
    local vx = cx - reg.x
    local vy = cy - reg.y
    -- Direction vector from cash register to ped
    local dx = pedPos.x - reg.x
    local dy = pedPos.y - reg.y
    -- Dot product: strictly positive means the ped is on the clerk/behind-counter side
    local dot = (dx * vx) + (dy * vy)
    return dot > 0.05 and math.abs(pedPos.z - cz) <= 1.5
end

-- Helper to smoothly pathfind and walk a ped to a target coordinate
-- Uses GTA's collision-aware pathfinder (flag 786603) to steer naturally around counters, props, and walls!
local function walkPedTo(ped, targetX, targetY, targetZ, speed)
    local navZ = getAccurateGroundZ(targetX, targetY, targetZ)
    TaskGoToCoordAnyMeans(ped, targetX, targetY, navZ, speed or 1.0, 0, false, 786603, 0.0)
end

-- ============================================================
-- Clerk Routine — Roaming Stock Visits & Counter Service
-- 1. Visits all store shelves randomly when no customer is inside.
-- 2. Walks smoothly through counter opening waypoints (aisle -> behind -> counter).
-- 3. When a customer enters, immediately heads to cash register,
--    smoothly takes position, and ALWAYS stays behind the counter.
-- ============================================================
CreateThread(function()
    while true do
        Wait(300)
        if #spawnedPeds > 0 and not uiOpen and not dialogueActive then
            local playerPed = PlayerPedId()
            local pcoords   = GetEntityCoords(playerPed)
            local now       = GetGameTimer()

            for _, entry in ipairs(spawnedPeds) do
                local ped = entry.entity
                if ped and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    local isRobbed = entry.robbedUntil and now < entry.robbedUntil
                    if isRobbed then goto continue end

                    local cx  = entry.counterCoords.x
                    local cy  = entry.counterCoords.y
                    local cz  = entry.counterCoords.z
                    local cw  = entry.counterCoords.w or 0.0
                    local counterPos = vector3(cx, cy, cz)

                    local openingAisle  = entry.counterOpeningAisle or entry.counterOpening or counterPos
                    local openingBehind = entry.counterOpeningBehind or entry.counterOpening or counterPos
                    local stations = entry.stations or {}

                    -- ── Detect player inside same store interior ──
                    local isInsideStore = false
                    if not IsPedInAnyVehicle(playerPed, true) then
                        local pedInt   = GetInteriorFromEntity(playerPed)
                        local storeInt = GetInteriorAtCoords(counterPos.x, counterPos.y, counterPos.z)
                        local clerkInt = (ped and DoesEntityExist(ped)) and GetInteriorFromEntity(ped) or 0
                        local _sc      = entry.shop.coords
                        local shopCoords = (_sc and vector3(tonumber(_sc.x or _sc[1]), tonumber(_sc.y or _sc[2]), tonumber(_sc.z or _sc[3])))
                            or counterPos

                        -- Strict interior check: player MUST actually enter the store interior
                        -- Standing outside near the door/glass window has pedInt == 0 and will NOT trigger!
                        local inStoreInterior = (pedInt ~= 0 and (pedInt == storeInt or (clerkInt ~= 0 and pedInt == clerkInt)))
                        if inStoreInterior and #(pcoords - shopCoords) <= 14.0 then
                            isInsideStore = true
                        end
                    end

                    -- ── Stuck detection & recovery (re-issues smooth pathfinding, never teleports) ──
                    local curSpeed = GetEntitySpeed(ped)
                    if curSpeed > 0.08 then
                        entry.lastMovedAt = now
                    end
                    local isWalking = (entry.state == 'GOING_TO_COUNTER' or entry.state == 'GOING_TO_OPENING_AISLE' or entry.state == 'GOING_TO_OPENING_BEHIND' or entry.state == 'GOING_TO_SHELF' or entry.state == 'GOING_TO_SHELF_OPENING_BEHIND' or entry.state == 'GOING_TO_SHELF_OPENING_AISLE')
                    local timeSinceWalkStart = now - (entry.walkStartTime or now)
                    local timeSinceLastMove  = now - (entry.lastMovedAt or now)
                    local isStuck = isWalking and ((curSpeed < 0.12 and timeSinceWalkStart > 900 and timeSinceLastMove > 800) or (timeSinceWalkStart > 2600 and curSpeed < 0.25))

                    if isStuck then
                        entry.lastMovedAt = now
                        entry.walkStartTime = now
                        if entry.state == 'GOING_TO_OPENING_AISLE' then
                            walkPedTo(ped, openingAisle.x, openingAisle.y, openingAisle.z, 1.05)
                        elseif entry.state == 'GOING_TO_OPENING_BEHIND' then
                            walkPedTo(ped, openingBehind.x, openingBehind.y, openingBehind.z, 1.05)
                        elseif entry.state == 'GOING_TO_COUNTER' then
                            walkPedTo(ped, cx, cy, cz, 1.05)
                        elseif entry.state == 'GOING_TO_SHELF_OPENING_BEHIND' then
                            walkPedTo(ped, openingBehind.x, openingBehind.y, openingBehind.z, 1.0)
                        elseif entry.state == 'GOING_TO_SHELF_OPENING_AISLE' then
                            walkPedTo(ped, openingAisle.x, openingAisle.y, openingAisle.z, 1.0)
                        elseif entry.state == 'GOING_TO_SHELF' then
                            local targetStation = stations[entry.stationIndex] or stations[1]
                            local tc = targetStation.coords
                            walkPedTo(ped, tc.x, tc.y, tc.z, 1.0)
                        end
                    end

                    if isInsideStore then
                        -- Player is INSIDE the store: Clerk heads behind counter to serve
                        entry.outsideSince = nil

                        if entry.state == 'AT_COUNTER' then
                            -- Clerk is standing behind register serving customer.
                            local distToPed = #(pcoords - counterPos)
                            if distToPed <= 8.0 then
                                TaskLookAtEntity(ped, playerPed, -1, 2048, 3)
                            end

                            if now - (entry.lastGreetTime or 0) > 8000 then
                                entry.lastGreetTime = now
                                playClerkAudio(ped, 'door_greet')
                            end

                        elseif entry.state == 'GOING_TO_OPENING_AISLE' then
                            -- Step 1: Walking across customer aisle to opening entrance
                            local curDist = #(GetEntityCoords(ped) - openingAisle)
                            if curDist <= 0.65 then
                                -- Step 2: Reached opening entrance, smoothly turn through gap behind counter
                                entry.state = 'GOING_TO_OPENING_BEHIND'
                                entry.walkStartTime = now
                                walkPedTo(ped, openingBehind.x, openingBehind.y, openingBehind.z, 1.05)
                            end

                        elseif entry.state == 'GOING_TO_OPENING_BEHIND' then
                            -- Step 2: Crossing through the counter flap/opening
                            local curDist = #(GetEntityCoords(ped) - openingBehind)
                            if curDist <= 0.55 then
                                -- Step 3: Inside runway behind counter, smoothly walk down to register
                                entry.state = 'GOING_TO_COUNTER'
                                entry.walkStartTime = now
                                walkPedTo(ped, cx, cy, cz, 1.05)
                            end

                        elseif entry.state == 'GOING_TO_COUNTER' then
                            -- Step 3: Walking along runway behind counter to register
                            local curDist = #(GetEntityCoords(ped) - counterPos)
                            if curDist <= 0.45 then
                                -- Arrived behind register on the floor!
                                entry.state = 'AT_COUNTER'
                                local regPos = entry.registerCoords or counterPos
                                -- Turn with legs naturally to face customer / cash register
                                TaskTurnPedToFaceCoord(ped, regPos.x, regPos.y, cz - 1.0, 1200)
                                TaskLookAtEntity(ped, playerPed, -1, 2048, 3)

                                if now - (entry.lastGreetTime or 0) > 8000 then
                                    entry.lastGreetTime = now
                                    playClerkAudio(ped, 'door_greet')
                                end
                            end

                        else
                            -- Customer entered! Clerk was at shelf or roaming
                            if not entry.playerWasInside then
                                entry.playerWasInside = true
                                playClerkAudio(ped, 'door_bell')
                            end

                            if isPedBehindCounter(ped, entry) then
                                -- Already behind counter: walk straight to register
                                entry.state = 'GOING_TO_COUNTER'
                                entry.walkStartTime = now
                                entry.lastMovedAt = now
                                walkPedTo(ped, cx, cy, cz, 1.05)
                            else
                                -- Out in aisle: put away scenario immediately and walk to counter opening
                                ClearPedTasksImmediately(ped)
                                entry.state = 'GOING_TO_OPENING_AISLE'
                                entry.walkStartTime = now
                                entry.lastMovedAt = now
                                walkPedTo(ped, openingAisle.x, openingAisle.y, openingAisle.z, 1.05)
                            end
                        end

                    else
                        -- Player is OUTSIDE the store: Clerk roams shelves and uses phone
                        entry.outsideSince = entry.outsideSince or now

                        if now - entry.outsideSince >= 4500 then
                            entry.playerWasInside = false

                            if entry.state == 'AT_COUNTER' then
                                -- Pick a random shelf in the aisles (outside counter)
                                local available = {}
                                for sIdx, st in ipairs(stations) do
                                    if not st.behindCounter then
                                        available[#available + 1] = sIdx
                                    end
                                end
                                local nextIdx = #available > 0 and available[math.random(1, #available)] or 1
                                entry.stationIndex = nextIdx

                                entry.state = 'GOING_TO_SHELF_OPENING_BEHIND'
                                entry.walkStartTime = now
                                walkPedTo(ped, openingBehind.x, openingBehind.y, openingBehind.z, 1.0)

                            elseif entry.state == 'GOING_TO_SHELF_OPENING_BEHIND' then
                                local curDist = #(GetEntityCoords(ped) - openingBehind)
                                local elapsed = now - (entry.walkStartTime or 0)
                                if curDist <= 0.55 or elapsed >= 4000 then
                                    entry.state = 'GOING_TO_SHELF_OPENING_AISLE'
                                    entry.walkStartTime = now
                                    walkPedTo(ped, openingAisle.x, openingAisle.y, openingAisle.z, 1.0)
                                end

                            elseif entry.state == 'GOING_TO_SHELF_OPENING_AISLE' then
                                local curDist = #(GetEntityCoords(ped) - openingAisle)
                                local elapsed = now - (entry.walkStartTime or 0)
                                if curDist <= 0.65 or elapsed >= 4000 then
                                    local targetStation = stations[entry.stationIndex] or stations[1]
                                    local tc = targetStation.coords
                                    entry.state = 'GOING_TO_SHELF'
                                    entry.walkStartTime = now
                                    walkPedTo(ped, tc.x, tc.y, tc.z, 1.0)
                                end

                            elseif entry.state == 'GOING_TO_SHELF' then
                                local targetStation = stations[entry.stationIndex] or stations[1]
                                local tc = targetStation.coords
                                local targetPos = vector3(tc.x, tc.y, tc.z)
                                local curDist = #(GetEntityCoords(ped) - targetPos)
                                local elapsed = now - (entry.walkStartTime or 0)

                                if curDist <= 0.5 or elapsed >= 7000 then
                                    entry.state = 'AT_SHELF'
                                    -- Turn naturally with legs towards shelf orientation
                                    local hRad = -math.rad(tc.w or 0.0)
                                    local faceX = tc.x + math.sin(hRad) * 2.0
                                    local faceY = tc.y + math.cos(hRad) * 2.0
                                    TaskTurnPedToFaceCoord(ped, faceX, faceY, tc.z - 1.0, 1200)

                                    local shelfScen = targetStation.scenario or 'WORLD_HUMAN_STAND_MOBILE'
                                    TaskStartScenarioInPlace(ped, shelfScen, 0, true)
                                    entry.nextStationSwitch = now + math.random(14000, 24000)
                                end

                            elseif entry.state == 'AT_SHELF' then
                                -- Clerk is at shelf using phone or inspecting stock
                                if #stations > 1 and now >= (entry.nextStationSwitch or 0) then
                                    local available = {}
                                    for sIdx, st in ipairs(stations) do
                                        if not st.behindCounter and sIdx ~= entry.stationIndex then
                                            available[#available + 1] = sIdx
                                        end
                                    end
                                    if #available == 0 then
                                        for sIdx, st in ipairs(stations) do
                                            if not st.behindCounter then
                                                available[#available + 1] = sIdx
                                            end
                                        end
                                    end

                                    local newIdx = #available > 0 and available[math.random(1, #available)] or 1
                                    entry.stationIndex = newIdx
                                    local targetStation = stations[newIdx] or stations[1]
                                    local tc = targetStation.coords

                                    ClearPedTasks(ped)
                                    entry.state = 'GOING_TO_SHELF'
                                    entry.walkStartTime = now
                                    walkPedTo(ped, tc.x, tc.y, tc.z, 1.0)
                                end
                            end
                        end
                    end

                    ::continue::
                end
            end
        end
    end
end)

-- ============================================================
-- Cinematic NPC Dialogue via cm-ui & HUD Integration
-- ============================================================

local function setHudHidden(hidden)
    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetHudVisible(not hidden) end)
        pcall(function() exports['cm-hud']:SetUiVisible(not hidden, 'cm-store') end)
    end
    DisplayRadar(not hidden)
end

local function getStoreEntry(storeId)
    for _, entry in ipairs(spawnedPeds) do
        if entry.storeId == tonumber(storeId) then
            return entry
        end
    end
    return nil
end

local function openStoreDialogue(storeEntry)
    if uiOpen or dialogueActive then return end
    if not storeEntry or not storeEntry.entity or not DoesEntityExist(storeEntry.entity) then return end

    currentStoreId = storeEntry.storeId

    if not uiAvailable() then
        -- Fallback: open store directly if cm-ui dialogue isn't loaded
        TriggerServerEvent('cm-store:server:requestStore', currentStoreId, 'catalog')
        return
    end

    if interactShown then
        exports['cm-ui']:HideInteract()
        interactShown = false
    end

    dialogueActive = true
    setHudHidden(true)

    local pedCfg = Config.Ped or {}
    local dialogCfg = pedCfg.dialog or {}

    local choices = {
        {
            id = 'catalog',
            label = dialogCfg.optionCatalog or 'Browse Store Catalog',
            description = 'Purchase supplies, food, drinks, and fishing gear',
            event = 'cm-store:client:dialogueChoiceCatalog',
        },
        {
            id = 'deliver',
            label = dialogCfg.optionDeliver or "I'm here to deliver the stock",
            description = 'Unload wholesale inventory shipment for this store',
            event = 'cm-store:client:dialogueChoiceDeliver',
        },
        {
            id = 'rob',
            label = dialogCfg.optionRob or 'Give me all your cash right now! [Rob Store]',
            description = 'Demand the register cash at gunpoint',
            event = 'cm-store:client:dialogueChoiceRob',
        },
    }

    if storeEntry.entity and DoesEntityExist(storeEntry.entity) then
        ClearPedTasks(storeEntry.entity)
        TaskTurnPedToFaceEntity(storeEntry.entity, PlayerPedId(), 2000)
        TaskLookAtEntity(storeEntry.entity, PlayerPedId(), -1, 2048, 3)
    end

    exports['cm-ui']:OpenNpcDialogue(storeEntry.entity, {
        name = storeEntry.clerkName or 'Store Clerk',
        role = storeEntry.shop.name or '24/7 STORE',
        quote = dialogCfg.title or 'Welcome to 24/7! How can I help you today?',
        choices = choices,
        closeEvent = 'cm-store:client:dialogueDismissed',
    })
end

RegisterNetEvent('cm-store:client:openDialogue', function(storeId)
    local entry = getStoreEntry(storeId)
    if entry then
        openStoreDialogue(entry)
    end
end)

AddEventHandler('cm-store:client:dialogueChoiceCatalog', function()
    dialogueActive = false
    TriggerServerEvent('cm-store:server:requestStore', currentStoreId, 'catalog')
end)

AddEventHandler('cm-store:client:dialogueChoiceRob', function()
    dialogueActive = false
    setHudHidden(false)
    local entry = getStoreEntry(currentStoreId)
    if entry and entry.entity and DoesEntityExist(entry.entity) then
        local ped = entry.entity
        entry.robbedUntil = GetGameTimer() + 15000
        ClearPedTasksImmediately(ped)
        TaskHandsUp(ped, 15000, PlayerPedId(), -1, true)
        pcall(function()
            PlayPedAmbientSpeechNative(ped, 'GUN_DRAW', 'SPEECH_PARAMS_FORCE_SHOUTED_CLEAR')
        end)
        SetTimeout(15000, function()
            if DoesEntityExist(ped) then
                ClearPedTasks(ped)
                entry.state = 'AT_COUNTER'
                TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1000)
                TaskLookAtEntity(ped, PlayerPedId(), -1, 2048, 3)
            end
        end)
    end
    TriggerServerEvent('cm-store:server:robStore', currentStoreId)
    TriggerEvent('cm-store:client:onStoreRobbery', currentStoreId)
end)

AddEventHandler('cm-store:client:dialogueChoiceDeliver', function()
    dialogueActive = false
    setHudHidden(false)
    TriggerServerEvent('cm-store:server:deliverStock', currentStoreId)
    TriggerEvent('cm-store:client:onStockDelivery', currentStoreId)
end)

AddEventHandler('cm-store:client:dialogueDismissed', function()
    dialogueActive = false
    setHudHidden(false)
    if currentStoreId then
        local entry = getStoreEntry(currentStoreId)
        if entry and entry.entity and DoesEntityExist(entry.entity) then
            local ped = entry.entity
            local playerPed = PlayerPedId()
            if entry.state == 'AT_SHELF' then
                local st = entry.stations and entry.stations[entry.stationIndex]
                local pedCfg = Config.Ped or {}
                TaskStartScenarioInPlace(ped, (st and st.scenario) or pedCfg.shelfScenario or 'WORLD_HUMAN_CLIPBOARD', 0, false)
            else
                TaskTurnPedToFaceEntity(ped, playerPed, 1000)
                TaskLookAtEntity(ped, playerPed, -1, 2048, 3)
            end
        end
    end
end)

-- ============================================================
-- Proximity & Interaction Loop
-- ============================================================
local lastInteractionMode = nil

CreateThread(function()
    local interactDist = (Config.Interact and Config.Interact.distance) or 2.4
    local key = (Config.Interact and Config.Interact.key) or 38
    while true do
        local sleep = 500
        if not uiOpen and not dialogueActive and #spawnedPeds > 0 then
            local pcoords = GetEntityCoords(PlayerPedId())
            local nearEntry = nil
            local interactionMode = nil -- 'talk_clerk', 'ring_bell'
            local nearDist = 999.0

            for _, entry in ipairs(spawnedPeds) do
                local ped = entry.entity
                local clerkCoords = (ped and DoesEntityExist(ped)) and GetEntityCoords(ped) or entry.coords
                local counterPos = vector3(entry.counterCoords.x, entry.counterCoords.y, entry.counterCoords.z)
                local regPos = entry.registerCoords or counterPos

                local distRegister = #(pcoords - regPos)
                local distCounter = #(pcoords - counterPos)
                local distClerk = #(pcoords - clerkCoords)

                -- Issue 6 fix: require same interior as clerk to prevent E-prompt firing through exterior walls
                local playerIntI = GetInteriorFromEntity(PlayerPedId())
                local storeIntI  = GetInteriorAtCoords(counterPos.x, counterPos.y, counterPos.z)
                local clerkIntI  = (ped and DoesEntityExist(ped)) and GetInteriorFromEntity(ped) or 0
                local inSameInt  = (playerIntI ~= 0 and (playerIntI == storeIntI or (clerkIntI ~= 0 and playerIntI == clerkIntI)))

                -- Clerk is always at the counter (no roaming) — always talk_clerk when near register.
                -- ring_bell was for when the clerk was roaming shelves; that mode no longer exists.
                local isNearRegister = inSameInt and ((distRegister <= interactDist) or (distCounter <= (interactDist + 0.6)))
                if isNearRegister and distRegister < nearDist then
                    nearDist = distRegister
                    nearEntry = entry
                    interactionMode = 'talk_clerk'
                -- Also allow direct clerk interaction when standing right next to the ped
                elseif inSameInt and distClerk <= interactDist and distClerk < nearDist then
                    nearDist = distClerk
                    nearEntry = entry
                    interactionMode = 'talk_clerk'
                end
            end

            if nearEntry and interactionMode then
                sleep = 0
                local playerPed = PlayerPedId()
                -- Clerk is always at counter — always refresh look-at when player is nearby
                if nearEntry.entity and DoesEntityExist(nearEntry.entity) then
                    local nowTimer = GetGameTimer()
                    if not nearEntry.lastLookAt or (nowTimer - nearEntry.lastLookAt > 600) then
                        nearEntry.lastLookAt = nowTimer
                        TaskTurnPedToFaceEntity(nearEntry.entity, playerPed, 800)
                        TaskLookAtEntity(nearEntry.entity, playerPed, 2000, 2048, 3)
                    end
                end
                if uiAvailable() then
                    if not interactShown or lastInteractionMode ~= interactionMode then
                        exports['cm-ui']:ShowInteract({
                            key  = Config.Interact.keyLabel or 'E',
                            label = 'STORE INTERACTION',
                            name  = nearEntry.clerkName,
                            role  = nearEntry.shop.name or '24/7 STORE'
                        })
                        interactShown = true
                        lastInteractionMode = interactionMode
                    end
                else
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to talk to Store Clerk')
                    EndTextCommandDisplayHelp(0, false, true, -1)
                end

                if IsControlJustPressed(0, key) then
                    if not dialogueActive and not uiOpen then
                        -- Clerk is always at counter — press E always opens dialogue directly
                        if nearEntry.entity and DoesEntityExist(nearEntry.entity) then
                            TaskTurnPedToFaceEntity(nearEntry.entity, PlayerPedId(), 1200)
                            playClerkAudio(nearEntry.entity, 'interact')
                        end
                        openStoreDialogue(nearEntry)
                    end
                    Wait(350)
                end
            else
                if interactShown then
                    if uiAvailable() then
                        exports['cm-ui']:HideInteract()
                    end
                    interactShown = false
                    lastInteractionMode = nil
                end
            end
        else
            if interactShown then
                if uiAvailable() then
                    exports['cm-ui']:HideInteract()
                end
                interactShown = false
                lastInteractionMode = nil
            end
        end
        Wait(sleep)
    end
end)

-- Name Tags Loop
CreateThread(function()
    local nameDist = tonumber(Config.Ped and Config.Ped.nameDistance or 7.0) or 7.0
    local heightOffset = tonumber(Config.Ped and Config.Ped.nameHeight or 1.32) or 1.32

    while true do
        local sleep = 500
        if not uiOpen and not dialogueActive and (Config.Ped == nil or Config.Ped.showName ~= false) then
            local pcoords = GetEntityCoords(PlayerPedId())
            for _, entry in ipairs(spawnedPeds) do
                local ped = entry.entity
                local pedCoords = (ped and DoesEntityExist(ped)) and GetEntityCoords(ped) or entry.coords
                local dist = #(pcoords - pedCoords)
                if dist <= nameDist then
                    -- Issue 7 fix: only draw name tag when player and clerk share same interior
                    -- (prevents floating name showing through exterior walls from the street)
                    local playerInt2 = GetInteriorFromEntity(PlayerPedId())
                    local storeInt2  = GetInteriorAtCoords(pedCoords.x, pedCoords.y, pedCoords.z)
                    local clerkInt2  = (ped and DoesEntityExist(ped)) and GetInteriorFromEntity(ped) or 0
                    local sameInterior = (playerInt2 ~= 0 and (playerInt2 == storeInt2 or (clerkInt2 ~= 0 and playerInt2 == clerkInt2)))
                    if sameInterior or dist <= 3.5 then
                        sleep = 0
                        drawText3D(vector3(pedCoords.x, pedCoords.y, pedCoords.z + heightOffset), entry.clerkName)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ============================================================
-- NUI Opening & Communication
-- ============================================================
local function closeUi()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    setHudHidden(false)
    if currentStoreId then
        local entry = getStoreEntry(currentStoreId)
        if entry and entry.entity and DoesEntityExist(entry.entity) then
            local pedCfg = Config.Ped or {}
            if entry.state == 'AT_SHELF' then
                TaskStartScenarioInPlace(entry.entity, pedCfg.shelfScenario or 'WORLD_HUMAN_CLIPBOARD', 0, false)
            elseif entry.state == 'AT_COUNTER' then
                TaskTurnPedToFaceEntity(entry.entity, PlayerPedId(), 1000)
                TaskLookAtEntity(entry.entity, PlayerPedId(), -1, 2048, 3)
            end
        end
    end
end

RegisterNetEvent('cm-store:client:openStore', function(ctx)
    if not ctx then return end
    currentStoreId = tonumber(ctx.storeId) or currentStoreId
    uiOpen = true
    setHudHidden(true)
    if interactShown and uiAvailable() then
        exports['cm-ui']:HideInteract()
        interactShown = false
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        ctx = ctx
    })
end)

RegisterNetEvent('cm-store:client:orderResult', function(result)
    SendNUIMessage({
        action = 'orderResult',
        result = result or {}
    })
end)

-- ============================================================
-- NUI Callbacks
-- ============================================================
RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('checkout', function(data, cb)
    data = type(data) == 'table' and data or {}
    data.storeId = currentStoreId
    TriggerServerEvent('cm-store:server:checkoutOrder', data)
    cb({ ok = true })
end)

RegisterNUICallback('buyStore', function(data, cb)
    TriggerServerEvent('cm-store:server:buyStore', currentStoreId)
    cb({ ok = true })
end)

RegisterNUICallback('manageStore', function(data, cb)
    data = type(data) == 'table' and data or {}
    data.storeId = currentStoreId
    TriggerServerEvent('cm-store:server:manageStore', data)
    cb({ ok = true })
end)

RegisterNUICallback('payTax', function(data, cb)
    TriggerServerEvent('cm-store:server:payTax', currentStoreId)
    cb({ ok = true })
end)

RegisterNUICallback('withdrawBusiness', function(data, cb)
    TriggerServerEvent('cm-store:server:withdrawBusiness', currentStoreId)
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    cleanupStoreEntities()
    if uiOpen or dialogueActive then
        SetNuiFocus(false, false)
        setHudHidden(false)
    end
    if uiAvailable() then
        exports['cm-ui']:HideInteract()
        exports['cm-ui']:CancelNpcDialogue()
    end
end)
