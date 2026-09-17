-- ============================================================
--  prism_fishing  |  client-side  |  DEOBFUSCATED
--  Original variables renamed to descriptive identifiers.
--  All logic is preserved 1-to-1; only names and formatting
--  have changed.  Comments explain every non-trivial section.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  MODULE-LEVEL VARIABLES
-- ─────────────────────────────────────────────────────────────

-- Load the shared configuration table (fish list, areas, boats, etc.)
local Config = require("shared/config")

-- Table that holds all active fishing-zone objects (lib.zones spheres)
local fishingZones = {}

-- Holds zone-info for the fishing area the player is currently inside.
-- Set to a table { index, locationIndex } on enter, nil on exit.
local currentZone = nil

-- The fishing-rod prop entity that is attached to the player's hand
local rodEntity = nil

-- The fishing line / rope handle
local ropeHandle = nil

-- The invisible "bobber" ped that the rope is anchored to in the water
local bobberPed = nil


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: InitPlayerFishData
--  Fetches the player's persistent fishing data from the server,
--  stores it in the global PlayerFish table, then builds the UI.
-- ─────────────────────────────────────────────────────────────
function InitPlayerFishData()
    -- Blocking callback: ask the server for this player's fish data
    local fishData = lib.callback.await("prism_fishing:server:GetDataPlayer", false)
    PlayerFish = fishData

    -- Small delay to let everything settle before drawing the HUD
    Wait(1000)
    SetupUi()   -- defined elsewhere (likely a NUI / React message)
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: GetRandomElement(tbl)
--  Returns a uniformly random element from the given table.
-- ─────────────────────────────────────────────────────────────
function GetRandomElement(tbl)
    local randomIndex = math.random(#tbl)
    return tbl[randomIndex]
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: GetWaterHitPoint()
--  Casts a probe from the player's right-hand bone forward/down
--  to find the nearest water-surface point.
--
--  Returns:
--    hitResult  (boolean)  – true if water was found
--    waterCoords (vector3) – world position of the water surface
-- ─────────────────────────────────────────────────────────────
function GetWaterHitPoint()
    -- Origin: player's right-hand bone (bone index 31086 = IK_R_Hand)
    local handCoords = GetPedBoneCoords(cache.ped, 31086, 0.0, 0.0, 0.0)

    -- Destination: a point 50 units in front and 25 units below the ped
    local forwardPoint = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 50.0, -25.0)

    -- Cast a water-detection probe between those two points
    local hitResult, waterCoords = TestProbeAgainstWater(
        handCoords.x, handCoords.y, handCoords.z,
        forwardPoint.x, forwardPoint.y, forwardPoint.z
    )

    return hitResult, waterCoords
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: SpawnFishingRodAndRope(waterCoords, fishData)
--
--  Creates the fishing-rod prop, attaches it to the player's
--  right wrist, then spawns a rope + invisible bobber ped at the
--  calculated water-surface position.
--
--  Parameters:
--    waterCoords (vector3) – where the probe hit the water
--    fishData    (table)   – optional fish config (may contain .ped
--                            to override the default bobber model)
-- ─────────────────────────────────────────────────────────────
function SpawnFishingRodAndRope(waterCoords, fishData)
    local playerPed    = cache.ped
    local playerCoords = GetEntityCoords(playerPed)
    local forwardVec   = GetEntityForwardVector(playerPed)

    -- ── Fishing Rod Prop ──────────────────────────────────────
    local rodModel = -1910604593   -- hash for the fishing-rod object
    lib.requestModel(rodModel)

    -- Delete any previously spawned rod
    if DoesEntityExist(rodEntity) then
        DeleteEntity(rodEntity)
    end

    -- Create the rod at the player's position, then attach it
    rodEntity = CreateObject(rodModel, playerCoords.x, playerCoords.y, playerCoords.z, true, false, false)

    -- Attach rod to the player's right wrist (bone 18905 = SKEL_R_Wrist)
    AttachEntityToEntity(
        rodEntity, playerPed,
        GetPedBoneIndex(playerPed, 18905),  -- right wrist bone index
        0.1, 0.05, 0,                        -- offset x, y, z
        80.0, 120.0, 160.0,                  -- rotation x, y, z
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(rodModel)

    -- ── Bobber / Target Position ──────────────────────────────
    -- Calculate the world position where the line will land:
    -- push the player's XY position forward by their forward vector,
    -- and use the water Z from the probe.
    local bobberCoords = vector3(
        playerCoords.x + forwardVec.x * 30.0,
        playerCoords.y + forwardVec.y * 50.0,
        waterCoords.z
    )

    -- ── Rope Setup ────────────────────────────────────────────
    RopeLoadTextures()

    -- Wait until rope textures are ready
    while true do
        if RopeAreTexturesLoaded() then break end
        Wait(0)
        RopeLoadTextures()
    end

    -- Remove any pre-existing rope
    if DoesRopeExist(ropeHandle) then
        DeleteRope(ropeHandle)
    end

    -- Create the rope at the bobber position
    ropeHandle = AddRope(
        bobberCoords.x, bobberCoords.y, bobberCoords.z,  -- start position
        0.0, 0.0, 0.0,                                    -- rotation
        40.0,                                             -- max length
        5,                                                -- type
        1000.0,                                           -- max extension length
        0.0,                                              -- speed
        1.0,                                              -- break force
        false, false, false,                              -- rigid, unbreakable, ?
        1.0,                                              -- initial length
        true                                              -- wakeup
    )

    -- Wait until the rope handle is valid
    while true do
        if DoesRopeExist(ropeHandle) then break end
        Wait(0)
    end

    Wait(50)
    ActivatePhysics(ropeHandle)  -- enable rope physics simulation
    Wait(50)

    -- ── Bobber Ped ────────────────────────────────────────────
    -- Determine which ped model to use as the invisible bobber anchor.
    -- fishData.ped overrides the default; 802685111 is the fallback hash.
    local bobberModel
    if fishData and fishData.ped then
        bobberModel = fishData.ped
    else
        bobberModel = 802685111
    end

    lib.requestModel(bobberModel)

    -- Delete any pre-existing bobber ped
    if DoesEntityExist(bobberPed) then
        DeleteEntity(bobberPed)
    end

    -- Create the ped at the bobber position (type 28 = unknown / ambient)
    bobberPed = CreatePed(28, bobberModel,
        bobberCoords.x, bobberCoords.y, bobberCoords.z,
        0.0, false, false)

    -- Make the bobber ped invisible, frozen, and non-collidable
    SetEntityVisible(bobberPed, false)
    FreezeEntityPosition(bobberPed, true)
    SetEntityCollision(bobberPed, false, false)

    -- Get the tip of the rod (small offset from the rod object)
    local rodTipCoords = GetOffsetFromEntityInWorldCoords(rodEntity, 0.0, 0.01, 2.5)

    -- Attach both the bobber ped and the rod entity to the rope
    AttachEntitiesToRope(
        ropeHandle,
        bobberPed,        -- entity 1 (water end)
        rodEntity,        -- entity 2 (rod tip end)
        bobberCoords.x, bobberCoords.y, bobberCoords.z,   -- entity 1 attach point
        rodTipCoords.x,   rodTipCoords.y,   rodTipCoords.z, -- entity 2 attach point
        40.0,             -- rope length
        false, false,     -- ?
        nil, nil          -- lock point IDs
    )

    -- Face the player toward the water target
    local heading = GetHeadingFromVector_2d(
        bobberCoords.x - playerCoords.x,
        bobberCoords.y - playerCoords.y
    )
    SetEntityHeading(playerPed, heading)
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: CleanupFishingProps()
--  Destroys the rod entity, bobber ped, and rope, then resets
--  all three handles to nil.
-- ─────────────────────────────────────────────────────────────
function CleanupFishingProps()
    DeleteEntity(rodEntity)
    DeleteEntity(bobberPed)
    DeleteRope(ropeHandle)

    rodEntity   = nil
    bobberPed   = nil
    ropeHandle  = nil
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: PlayCatchAnimation(fishData)
--  Plays the "pick up low" animation on the local player and
--  briefly spawns a visible catch ped (holding the fish) that
--  is attached to the player's left hand before being deleted.
--
--  Parameters:
--    fishData (table) – fish config, optionally containing .ped
--                       (model hash) to use for the catch ped.
-- ─────────────────────────────────────────────────────────────
function PlayCatchAnimation(fishData)
    local playerPed    = cache.ped
    local playerCoords = GetEntityCoords(playerPed)

    -- Clear any current task so the animation plays cleanly
    ClearPedTasks(playerPed)
    Wait(50)

    -- Spawn the catch ped slightly below the player's feet
    local catchSpawnPos = vector3(playerCoords.x, playerCoords.y, playerCoords.z - 1.0)

    -- Choose ped model (fishData.ped or default 802685111)
    local catchModel
    if fishData and fishData.ped then
        catchModel = fishData.ped
    else
        catchModel = 802685111
    end

    lib.requestModel(catchModel)

    -- Delete any lingering catch ped from a previous catch
    if DoesEntityExist(bobberPed) then
        DeleteEntity(bobberPed)
        bobberPed = nil
    end

    -- Create the visible catch ped
    bobberPed = CreatePed(28, catchModel,
        catchSpawnPos.x, catchSpawnPos.y, catchSpawnPos.z,
        0.0, false, false)

    if DoesEntityExist(bobberPed) then
        -- Make the catch ped behave like a passive prop
        SetBlockingOfNonTemporaryEvents(bobberPed, true)
        SetPedCanRagdoll(bobberPed, false)
        SetEntityInvincible(bobberPed, true)
        SetEntityVisible(bobberPed, true)
        SetEntityAlpha(bobberPed, 255, false)
        FreezeEntityPosition(bobberPed, true)
        SetEntityCollision(bobberPed, false, false)

        -- Load and play the "pick up" animation on the local player
        lib.requestAnimDict("random@domestic")
        TaskPlayAnim(playerPed,
            "random@domestic", "pickup_low",
            8.0, -8.0,   -- blend in / blend out speed
            2000,         -- duration ms
            1,            -- flag (repeat = 0, loop = 1)
            0,            -- playback rate
            false, false, false)

        -- Async: after 800 ms attach the catch ped to the player's
        --        left hand, wait another 1.2 s, then clean everything up.
        CreateThread(function()
            Wait(800)

            if DoesEntityExist(bobberPed) then
                -- Bone 28422 = SKEL_L_Hand (left hand)
                AttachEntityToEntity(
                    bobberPed, playerPed,
                    GetPedBoneIndex(playerPed, 28422),
                    0.0, 0.0, 0.0,   -- offset
                    0.0, 0.0, 0.0,   -- rotation
                    true, true, false, true, 1, true
                )

                Wait(1200)

                -- Remove the catch ped and all fishing props
                DeleteEntity(bobberPed)
                bobberPed = nil
                CleanupFishingProps()

                -- Clear the fishing animation
                ClearPedTasks(playerPed)
            end
        end)
    end
end


-- ─────────────────────────────────────────────────────────────
--  CALLBACK: prism_fishing:client:SelectBait
--  Opens an ox_lib context menu listing every bait item the
--  player passed in.  Waits until the menu closes, then returns
--  the selected bait table (or false if the player cancelled).
-- ─────────────────────────────────────────────────────────────
lib.callback.register("prism_fishing:client:SelectBait", function(baitList)
    local selectedBait = nil    -- will hold the chosen bait table
    local menuExited   = false  -- true when the player closed without picking

    -- Build the options array for the context menu
    local menuOptions = {}
    for _, baitItem in ipairs(baitList) do
        local option = {}

        -- Title: "Use <Bait Label>"
        option.title = ("Use %s"):format(baitItem.label)

        -- Localised description
        option.description = locale("context_description_selectBait")

        -- Pass the bait item's internal name as args
        option.args = baitItem.name

        -- Icon from ox_inventory's web image folder
        option.icon = "nui://ox_inventory/web/images/" .. baitItem.name .. Config.ContextImgFormat

        -- When the player clicks this option, store the bait and hide the menu
        option.onSelect = function()
            selectedBait = baitItem
            lib.hideContext()
        end

        menuOptions[#menuOptions + 1] = option
    end

    -- Register the context menu
    lib.registerContext({
        id      = "bait_menu",
        title   = locale("context_title_selectBait"),
        onExit  = function()
            -- Player pressed Escape / closed without selecting
            menuExited = true
        end,
        options = menuOptions,
    })

    lib.showContext("bait_menu")

    -- Busy-wait until the bait menu is no longer the open context
    while lib.getOpenContextMenu() == "bait_menu" do
        Wait(100)
    end

    -- If the player explicitly closed (onExit) without choosing → return false
    if menuExited and not selectedBait then
        return false
    end

    return selectedBait
end)


-- ─────────────────────────────────────────────────────────────
--  CALLBACK: prism_fishing:client:GetCurrentZone
--  Returns the water-probe result and the current zone info so
--  the server can validate where the player is fishing.
-- ─────────────────────────────────────────────────────────────
lib.callback.register("prism_fishing:client:GetCurrentZone", function()
    local hitResult, waterCoords = GetWaterHitPoint()
    return hitResult, currentZone
end)


-- ─────────────────────────────────────────────────────────────
--  CALLBACK: prism_fishing:client:UpdatePlayerFishData
--  Called by the server to patch a single field in PlayerFish.
--  If the field is "level", the HUD is refreshed.
-- ─────────────────────────────────────────────────────────────
lib.callback.register("prism_fishing:client:UpdatePlayerFishData", function(field, value)
    PlayerFish[field] = value

    -- Only refresh the UI when the player's level changes
    if field ~= "level" then return end

    SetupUi()
    return true
end)


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: CancelFishing()
--  Cancels an active fishing session: removes the rod/rope/ped
--  and clears the player's animation tasks.
-- ─────────────────────────────────────────────────────────────
function CancelFishing()
    if rodEntity then
        DeleteEntity(rodEntity)
    end
    if ropeHandle then
        DeleteRope(ropeHandle)
    end
    ClearPedTasks(cache.ped)
end


-- ─────────────────────────────────────────────────────────────
--  NET EVENT: prism_fishing:client:UseFishingRod
--  Triggered by the server to start a fishing attempt.
--
--  Parameters:
--    rodData  (table)  – rod stats (.waitDivisor, etc.)
--    fishName (string) – key into Config.Fish
--    slotId   (any)    – inventory slot, forwarded to ClearFishing
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent("prism_fishing:client:UseFishingRod")
AddEventHandler("prism_fishing:client:UseFishingRod", function(rodData, fishName, slotId)
    -- Look up the fish's full config table
    local fishConfig = Config.Fish[fishName]

    -- Determine the area config: use the current zone's area or fall back
    -- to the generic "outside" config if the player is not in a named zone.
    local areaConfig
    if currentZone then
        areaConfig = Config.FishingArea[currentZone.index]
    end
    if not areaConfig then
        areaConfig = Config.outside
    end

    -- Cast the water probe and spawn the visual fishing props
    local hitResult, waterCoords = GetWaterHitPoint()
    SpawnFishingRodAndRope(waterCoords, fishConfig)

    -- Pre-load the idle fishing animation dictionary
    lib.requestAnimDict("amb@world_human_stand_fishing@idle_a")

    -- ── Cancel key watcher ────────────────────────────────────
    -- Poll every 100 ms; if the player presses E (control 73) cancel fishing.
    local cancelInterval = SetInterval(function()
        if IsControlPressed(0, 73) then   -- 73 = INPUT_ENTER / E key
            CancelFishing()
        end
    end, 100)

    -- ── Main fishing thread ───────────────────────────────────
    CreateThread(function()
        -- Play the standing-fishing idle animation (looped, flag = 1)
        TaskPlayAnim(cache.ped,
            "amb@world_human_stand_fishing@idle_a", "idle_a",
            3.0, 3.0,   -- blend in / blend out
            -1,          -- duration: -1 = until cleared
            1,           -- flag: loop
            0,           -- playback rate
            false, false, false)

        -- ── Wait for a bite ───────────────────────────────────
        -- Random delay between areaConfig.waitTime.min and .max seconds,
        -- divided by the rod's waitDivisor to make better rods faster,
        -- then converted to milliseconds.
        local waitMs = math.random(areaConfig.waitTime.min, areaConfig.waitTime.max)
                       / rodData.waitDivisor
                       * 1000
        Wait(waitMs)

        -- ── Skill check mini-game ─────────────────────────────
        -- Pick a random skill-check config from the fish's skillcheck list
        local skillCheckConfig = GetRandomElement(fishConfig.skillcheck)

        -- StartMinigame returns success (bool) when the player hits the marker
        local success = StartMinigame(skillCheckConfig)

        if success then
            Wait(50)

            -- ── Catch UI ──────────────────────────────────────
            -- Show the "Keep / Release" decision screen
            local catchResult = StartCatchUI({
                name   = fishName,
                label  = fishConfig.label,
                rarity = fishConfig.rarity,
                change = fishConfig.chance,   -- note: original field is "change"
            })

            if catchResult == "keep" then
                -- Play the catch animation and reward the player server-side
                PlayCatchAnimation(fishConfig)
                TriggerServerEvent("prism_fishing:client:FinishFishing")
                CancelFishing()

            elseif catchResult == "release" then
                -- Notify the player and free the slot server-side
                Notify(locale("release_fish", fishConfig.label), "error")
                CancelFishing()
                TriggerServerEvent("prism_fishing:client:ClearFishing", slotId)

            else
                -- Player let the fish escape (timer ran out or dismissed)
                TriggerServerEvent("prism_fishing:client:ClearFishing", slotId)
                CancelFishing()
            end

            -- Stop the cancel-key watcher now that the session is over
            ClearInterval(cancelInterval)
        end
    end)
end)


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: CreateFishingZone(areaKey, locationCoords, areaConfig, locationIndex)
--  Creates a lib.zones sphere around a fishing location.
--  When the player enters the sphere, currentZone is populated;
--  when they leave, it is reset to nil.
-- ─────────────────────────────────────────────────────────────
function CreateFishingZone(areaKey, locationCoords, areaConfig, locationIndex)
    local zone = lib.zones.sphere({
        coords  = locationCoords,
        radius  = areaConfig.radius,
        debug   = areaConfig.debug or false,

        onEnter = function()
            currentZone = {
                index         = areaKey,
                locationIndex = locationIndex,
            }
        end,

        onExit = function()
            currentZone = nil
        end,
    })

    -- Track all zones so they can be cleaned up if needed
    table.insert(fishingZones, zone)
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: OpenBoatShopUI(boatShopKey)
--  Opens the NUI boat-rental shop for the given shop key.
-- ─────────────────────────────────────────────────────────────
function OpenBoatShopUI(boatShopKey)
    local shopConfig = Config.Boats[boatShopKey]
    if not shopConfig then return end

    local boatList = {}   -- (unused here but kept for parity with original)

    -- Show the NUI frame and send the shop data to React
    toggleNuiFrame(true)
    SetNuiFocus(true, true)
    SendReactMessage("ui:openBoatShop", true)
    SendReactMessage("ui:boatShopData", {
        boats = shopConfig.listBoat,
        key   = boatShopKey,
    })
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: GetBoatPrice(boatShopKey, boatName)
--  Returns the price of a specific boat in the given shop,
--  or nil if the shop / boat is not found.
-- ─────────────────────────────────────────────────────────────
function GetBoatPrice(boatShopKey, boatName)
    local shopConfig = Config.Boats[boatShopKey]
    if not shopConfig then return nil end

    for _, boat in pairs(shopConfig.listBoat) do
        if boat.name == boatName then
            return boat.price
        end
    end
    return nil
end


-- ─────────────────────────────────────────────────────────────
--  FUNCTION: FindFreeParkingSpot(coordsList, radius)
--  Iterates through a list of spawn coordinate vectors and
--  returns the first one that has no vehicle within `radius`
--  metres.  Returns nil if every spot is occupied.
-- ─────────────────────────────────────────────────────────────
function FindFreeParkingSpot(coordsList, radius)
    if not radius then radius = 3.5 end

    for i = 1, #coordsList do
        local spot = coordsList[i]
        local occupied = IsAnyVehicleNearPoint(spot.x, spot.y, spot.z, radius)
        if not occupied then
            return spot
        end
    end
    return nil
end


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:rentBoat
--  Fired when the player confirms a boat rental in the UI.
--  Validates money, finds a free spawn point, then spawns
--  the boat vehicle.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:rentBoat", function(data, cb)
    -- Close the NUI shop
    toggleNuiFrame(false)
    SetNuiFocus(false, false)
    SendReactMessage("ui:openBoatShop", false)

    local shopConfig = Config.Boats[data.key]
    if not shopConfig then
        return cb(false)
    end

    -- Get the price for the requested boat model
    local boatPrice = GetBoatPrice(data.key, data.name)

    -- Find a free spawn slot in the configured spawn-point list
    local spawnPoint = FindFreeParkingSpot(shopConfig.spawnCoords, Config.RadiusNearPoint)
    if not spawnPoint then
        Notify(locale("parking_full"), "error")
        return cb(false)
    end

    -- Determine payment method (default: "cash")
    local paymentMethod = shopConfig.payment or "cash"

    -- Ask the server whether the player can afford the boat
    local canAfford = lib.callback.await(
        "prism_fishing:server:CheckPlayerMoney",
        false,
        paymentMethod,
        boatPrice
    )

    if not canAfford then
        -- Tell the player they don't have enough money
        local moneyType = shopConfig.moneyType or "cash"
        Notify(locale("no_money_rentalBoat", boatPrice, moneyType), "error")
        return cb(false)
    end

    -- Spawn the boat at the chosen free parking spot
    createVehicle({
        model       = data.name,
        spawnCoords = spawnPoint,
    })

    cb(true)
end)


-- ─────────────────────────────────────────────────────────────
--  THREAD: Fishing-zone setup
--  Iterates every FishingArea in the config, creates map blips
--  for areas that have them enabled, and registers a lib.zones
--  sphere for each individual location within the area.
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    for areaKey, areaConfig in pairs(Config.FishingArea) do

        -- ── Optional map blips ────────────────────────────────
        if areaConfig.blip.enable then
            for _, locationCoords in ipairs(areaConfig.locations) do
                createBlip({
                    coords   = locationCoords,
                    sprite   = areaConfig.blip.sprite,
                    scale    = areaConfig.blip.scale,
                    color    = areaConfig.blip.color,
                    blipText = areaConfig.blip.name,
                })
            end
        end

        -- ── Zone spheres ──────────────────────────────────────
        for locationIndex, locationCoords in ipairs(areaConfig.locations) do
            CreateFishingZone(areaKey, locationCoords, areaConfig, locationIndex)
        end
    end
end)


-- ─────────────────────────────────────────────────────────────
--  THREAD: Fishing store NPC + blip
--  Spawns the store-keeper ped and attaches an ox_target to it
--  so the player can open the fishing store page.
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    local storeConfig = Config.OpenMenuStore

    -- Spawn the store NPC using a helper (likely defined in a shared file)
    local storePed = createPed(storeConfig)

    -- Attach an interaction target to the NPC
    addTarget({
        entity  = storePed,
        options = {
            {
                icon     = "fas fa-fish",
                label    = locale("target_open_store"),
                onSelect = function()
                    OpenStorePage()   -- opens the fishing item shop UI
                end,
            },
        },
    })

    -- ── Optional blip ─────────────────────────────────────────
    if storeConfig.blip.enable then
        createBlip({
            coords   = storeConfig.coords,
            sprite   = storeConfig.blip.sprite,
            scale    = storeConfig.blip.scale,
            color    = storeConfig.blip.color,
            blipText = storeConfig.blip.name,
        })
    end
end)


-- ─────────────────────────────────────────────────────────────
--  THREAD: Boat shop NPC(s) + blip(s)
--  For every entry in Config.Boats:
--    • If a "model" is defined, spawns a ped and attaches a
--      target that opens the boat rental UI.
--    • If a blip is enabled, places a map blip at the shop.
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    for boatShopKey, boatShopConfig in pairs(Config.Boats) do

        -- Only spawn a ped if the config includes a model
        if boatShopConfig.model then
            local shopPed = createPed(boatShopConfig)

            addTarget({
                entity  = shopPed,
                options = {
                    {
                        icon     = "fas fa-ship",
                        label    = locale("target_label_rentalBoat"),
                        onSelect = function()
                            OpenBoatShopUI(boatShopKey)
                        end,
                    },
                },
            })
        end

        -- ── Optional blip ─────────────────────────────────────
        if boatShopConfig.blip.enable then
            createBlip({
                coords   = boatShopConfig.coords,
                sprite   = boatShopConfig.blip.sprite,
                scale    = boatShopConfig.blip.scale,
                color    = boatShopConfig.blip.color,
                blipText = boatShopConfig.blip.name,
            })
        end
    end
end)


-- ─────────────────────────────────────────────────────────────
--  THREAD: Framework player-loaded detection
--  Waits until the local player is "loaded" in whichever
--  framework (ESX or QBCore) is active, then calls
--  InitPlayerFishData() to bootstrap the fishing HUD.
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    if Framework.IsESX then
        -- ESX: spin until Core.PlayerLoaded is true
        while true do
            if Core.PlayerLoaded then break end
            Wait(250)
        end
        InitPlayerFishData()

    elseif Framework.IsQB then
        -- QBCore: listen for the player-loaded event
        AddEventHandler("QBCore:Client:OnPlayerLoaded", function()
            InitPlayerFishData()
        end)
    end
end)


-- ─────────────────────────────────────────────────────────────
--  THREAD: Immediate initialisation
--  Calls InitPlayerFishData() on resource start so that players
--  who are already in the session (e.g. after a restart) also
--  get their data loaded.
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    InitPlayerFishData()
end)