local Config = CMInventory.Config
local isOpen = false
local deathBlocked = false
local Drops = {}
local DropProps = {}
local selectedDropIndex = 1
local lastDropUiKey = nil
local playInventoryAnim

local function isDeadOrUnconscious()
    if deathBlocked then return true end
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.isDead == true or false
end

local function isPlayerInsideVehicle()
    local ped = PlayerPedId()
    return ped ~= 0 and IsPedInAnyVehicle(ped, false)
end

local function cdebug(message)
    if not Config.Debug then return end
    print(('[CM-INVENTORY-CLIENT] %s'):format(tostring(message)))
end

local function safeJson(value)
    local ok, encoded = pcall(json.encode, value or {})
    return ok and encoded or tostring(value)
end

local function nui(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function hideGameAndCustomHud()
    -- Hide native GTA/FiveM HUD + radar.
    DisplayHud(false)
    DisplayRadar(false)

    -- Hide your custom cm-hud NUI too. DisplayHud(false) does not affect custom NUI resources.
    TriggerEvent('cm-hud:client:hideForUi')

    if GetResourceState and GetResourceState('cm-hud') == 'started' then
        pcall(function()
            exports['cm-hud']:SetHudVisible(false)
        end)
    end
end

local function showGameAndCustomHud()
    -- Restore native GTA/FiveM HUD + radar.
    DisplayHud(true)
    DisplayRadar(true)

    -- Restore your custom cm-hud NUI after inventory closes.
    TriggerEvent('cm-hud:client:showAfterUi')

    if GetResourceState and GetResourceState('cm-hud') == 'started' then
        pcall(function()
            exports['cm-hud']:SetHudVisible(true)
        end)
    end
end

local function openInventory(payload)
    if isDeadOrUnconscious() then return false end
    isOpen = true

    -- Inventory NUI focus + hide native and custom HUD while inventory is open.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    hideGameAndCustomHud()

    nui('open', payload or {})
    TriggerServerEvent('cm-inventory:server:requestDrops')
    return true
end

local function closeInventory(forDeath)
    isOpen = false

    -- Release this NUI. During unconscious state the death screen owns focus/HUD,
    -- so never re-show the game HUD from the inventory close path.
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    if forDeath == true or isDeadOrUnconscious() then
        hideGameAndCustomHud()
    else
        showGameAndCustomHud()
    end

    TriggerServerEvent('cm-inventory:server:closeInventory')
    nui('close', {})

    -- If a late replicated state update forced this close after the death screen
    -- already opened, let cm-playerdata immediately reclaim its focus.
    if forDeath == true or isDeadOrUnconscious() then
        SetTimeout(0, function()
            TriggerEvent('cm-playerdata:client:restoreDeathFocus')
        end)
    end
end


-- Keep native GTA/FiveM HUD hidden every frame while inventory is open.
-- Some HUD/resources re-enable DisplayHud/DisplayRadar, so a one-time call is not enough.
CreateThread(function()
    while true do
        if isOpen then
            DisplayHud(false)
            DisplayRadar(false)
            HideHudAndRadarThisFrame()
            for component = 0, 22 do
                HideHudComponentThisFrame(component)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

local function drawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(235, 245, 245, 230)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local function getClosestDrop()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, 9999.0
    for _, drop in ipairs(Drops) do
        local c = drop.coords or {}
        local dist = #(coords - vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0))
        if dist < closestDist then
            closest = drop
            closestDist = dist
        end
    end
    return closest, closestDist
end


local deleteDropProp

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    if isDeadOrUnconscious() then hideGameAndCustomHud() else showGameAndCustomHud() end
    nui('nearDrops', { visible = false, drops = {} })
    for id in pairs(DropProps or {}) do
        deleteDropProp(id)
    end
end)

RegisterNetEvent('cm-inventory:client:open', function(payload)
    if isDeadOrUnconscious() then return end
    openInventory(payload)
end)

RegisterNetEvent('cm-inventory:client:forceCloseForDeath', function()
    deathBlocked = true
    selectedDropIndex = 1
    lastDropUiKey = nil
    nui('nearDrops', { visible = false, drops = {} })
    if isOpen then closeInventory(true) end
end)

RegisterNetEvent('cm-playerdata:client:revive', function()
    deathBlocked = false
end)
RegisterNetEvent('cm-playerdata:client:revivePartial', function()
    deathBlocked = false
end)
RegisterNetEvent('cm-playerdata:client:respawn', function()
    deathBlocked = false
end)
RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    deathBlocked = type(data) == 'table' and data.isDead == true or false
    if deathBlocked and isOpen then closeInventory(true) end
end)
RegisterNetEvent('cm-playerdata:client:characterLoaded', function(data)
    deathBlocked = type(data) == 'table' and data.isDead == true or false
    if deathBlocked and isOpen then closeInventory(true) end
end)


RegisterNetEvent('cm-inventory:client:update', function(payload)
    if isOpen then
        nui('update', payload or {})
    end
end)

deleteDropProp = function(dropId)
    dropId = tonumber(dropId)
    local obj = dropId and DropProps[dropId] or nil
    if obj and DoesEntityExist(obj) then
        DeleteEntity(obj)
    end
    if dropId then DropProps[dropId] = nil end
end

local function loadDropModel(modelName)
    modelName = tostring(modelName or (Config.Drops and Config.Drops.defaultProp) or 'prop_paper_bag_small')
    local hash = GetHashKey(modelName)
    if not IsModelInCdimage(hash) then
        modelName = (Config.Drops and Config.Drops.defaultProp) or 'prop_paper_bag_small'
        hash = GetHashKey(modelName)
    end
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)
    local timeout = GetGameTimer() + 2500
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(10)
    end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function ensureDropProp(drop)
    if not drop or not drop.id then return end
    local id = tonumber(drop.id)
    if not id or DropProps[id] and DoesEntityExist(DropProps[id]) then return end

    local c = drop.coords or {}
    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    if not x or not y or not z then return end

    CreateThread(function()
        if DropProps[id] and DoesEntityExist(DropProps[id]) then return end
        local hash = loadDropModel(drop.propModel)
        if not hash then return end

        local zOffset = tonumber(drop.propZOffset) or 0.0
        local obj = CreateObject(hash, x, y, z + zOffset, false, false, false)
        if obj and obj ~= 0 then
            SetEntityAsMissionEntity(obj, true, true)
            if tonumber(drop.propHeading) then
                SetEntityHeading(obj, tonumber(drop.propHeading))
            end
            -- With no z-offset, sit the prop on the ground; a deliberate offset
            -- (e.g. a floating/raised prop) is respected instead.
            if zOffset == 0.0 then
                PlaceObjectOnGroundProperly(obj)
            end
            FreezeEntityPosition(obj, true)
            SetEntityCollision(obj, true, true)
            SetEntityAlpha(obj, 235, false)
            DropProps[id] = obj
        end
        SetModelAsNoLongerNeeded(hash)
    end)
end

local function syncDropProps(drops)
    local active = {}
    for _, drop in ipairs(drops or {}) do
        if drop and drop.id then active[tonumber(drop.id)] = true end
    end

    -- Props are streamed by distance below. This event only removes deleted or
    -- expired drops immediately, instead of spawning every server drop globally.
    for id in pairs(DropProps) do
        if not active[tonumber(id)] then deleteDropProp(id) end
    end
end

RegisterNetEvent('cm-inventory:client:updateDrops', function(drops)
    Drops = type(drops) == 'table' and drops or {}
    syncDropProps(Drops)
end)

-- Distance-stream ground props to avoid creating up to the full server drop list
-- on every client. A small hysteresis prevents spawn/delete churn at the edge.
CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if ped ~= 0 and Drops and #Drops > 0 then
            local playerCoords = GetEntityCoords(ped)
            local streamDistance = tonumber((Config.Drops or {}).propStreamDistance) or 55.0
            local despawnDistance = math.max(streamDistance + 10.0, tonumber((Config.Drops or {}).propDespawnDistance) or 70.0)
            local active = {}

            for _, drop in ipairs(Drops) do
                local id = tonumber(drop and drop.id)
                if id then
                    active[id] = true
                    local c = drop.coords or {}
                    local coords = vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
                    local distance = #(playerCoords - coords)
                    if distance <= streamDistance then
                        ensureDropProp(drop)
                    elseif distance > despawnDistance and DropProps[id] then
                        deleteDropProp(id)
                    end
                end
            end

            for id in pairs(DropProps) do
                if not active[tonumber(id)] then deleteDropProp(id) end
            end
        elseif next(DropProps) then
            for id in pairs(DropProps) do deleteDropProp(id) end
        end
    end
end)

RegisterNetEvent('cm-inventory:client:notify', function(message, typeName)
    nui('notify', { message = message or '', type = typeName or 'info' })
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message or '')
    EndTextCommandThefeedPostTicker(false, false)
end)

RegisterNetEvent('cm-inventory:client:useProgress', function(label, ms)
    ms = tonumber(ms) or 1000
    nui('progress', { label = label or 'Using item...', ms = ms })
    if playInventoryAnim then playInventoryAnim('use_item', math.min(ms, 1400)) end
end)

RegisterNetEvent('cm-inventory:client:applyHealth', function(amount)
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.min(maxHealth, health + (tonumber(amount) or 25)))
end)

RegisterNetEvent('cm-inventory:client:applyArmor', function(amount)
    local ped = PlayerPedId()
    local armor = GetPedArmour(ped)
    SetPedArmour(ped, math.min(100, armor + (tonumber(amount) or 75)))
end)


local equippedWeaponHash = nil
local equippedWeaponName = nil
local currentWeaponAmmo = 0
local equippedVestComponent = nil
local equipmentState = {}

local WeaponMap = {
    weapon_pistol = `WEAPON_PISTOL`,
    weapon_combatpistol = `WEAPON_COMBATPISTOL`,
    weapon_appistol = `WEAPON_APPISTOL`,
    weapon_pumpshotgun = `WEAPON_PUMPSHOTGUN`,
    weapon_smg = `WEAPON_SMG`,
    weapon_carbinerifle = `WEAPON_CARBINERIFLE`
}

-- Resolve any weapon item to its GTA hash. Items are named after the weapon
-- (weapon_carbinerifle -> WEAPON_CARBINERIFLE), so we derive the hash from the
-- name and fall back to the static map / explicit metadata hash.
local function resolveWeaponHash(itemName, item)
    itemName = tostring(itemName or ''):lower()
    -- explicit hash in metadata wins
    if type(item) == 'table' then
        local md = item.metadata or {}
        local h = md.weaponHash or md.weapon_hash
        if h then
            if type(h) == 'string' then return GetHashKey(h) end
            if type(h) == 'number' then return h end
        end
    end
    if WeaponMap[itemName] then return WeaponMap[itemName] end
    if itemName:find('^weapon_') then
        return GetHashKey(itemName:upper()) -- weapon_carbinerifle -> WEAPON_CARBINERIFLE
    end
    return nil
end


local ClothingSlotMap = {
    mask = { type = 'component', index = 1 },
    arms = { type = 'component', index = 3 },
    shirt = { type = 'component', index = 8 },
    outerwear = { type = 'component', index = 11 },
    pants = { type = 'component', index = 4 },
    shoes = { type = 'component', index = 6 },
    accessory = { type = 'component', index = 7 },
    bag = { type = 'component', index = 5 },
    decals = { type = 'component', index = 10 },
    headwear = { type = 'prop', index = 0 },
    glasses = { type = 'prop', index = 1 },
    earrings = { type = 'prop', index = 2 },
    watch = { type = 'prop', index = 6 }
}

local ClothingCategoryBySlot = {
    mask = 'mask', arms = 'arms', decals = 'decals',
    shirt = 'tshirt', outerwear = 'torso', pants = 'pants', shoes = 'shoes',
    accessory = 'chains', bag = 'bags', headwear = 'hat', glasses = 'glasses',
    earrings = 'earrings', watch = 'watches'
}

local ClothingEmptyDefaults = {
    male = {
        mask = { type = 'component', index = 1, drawable = 0, texture = 0 },
        arms = { type = 'component', index = 3, drawable = 15, texture = 0 },
        shirt = { type = 'component', index = 8, drawable = 15, texture = 0 },
        outerwear = { type = 'component', index = 11, drawable = 15, texture = 0, arms = 15, armsTexture = 0, undershirt = 15, undershirtTexture = 0 },
        pants = { type = 'component', index = 4, drawable = 21, texture = 0 },
        shoes = { type = 'component', index = 6, drawable = 34, texture = 0 },
        accessory = { type = 'component', index = 7, drawable = 0, texture = 0 },
        bag = { type = 'component', index = 5, drawable = 0, texture = 0 },
        decals = { type = 'component', index = 10, drawable = 0, texture = 0 },
        headwear = { type = 'prop', index = 0, drawable = -1, texture = 0 },
        glasses = { type = 'prop', index = 1, drawable = -1, texture = 0 },
        earrings = { type = 'prop', index = 2, drawable = -1, texture = 0 },
        watch = { type = 'prop', index = 6, drawable = -1, texture = 0 }
    },
    female = {
        mask = { type = 'component', index = 1, drawable = 0, texture = 0 },
        arms = { type = 'component', index = 3, drawable = 15, texture = 0 },
        shirt = { type = 'component', index = 8, drawable = 14, texture = 0 },
        outerwear = { type = 'component', index = 11, drawable = 15, texture = 0, arms = 15, armsTexture = 0, undershirt = 14, undershirtTexture = 0 },
        pants = { type = 'component', index = 4, drawable = 15, texture = 0 },
        shoes = { type = 'component', index = 6, drawable = 35, texture = 0 },
        accessory = { type = 'component', index = 7, drawable = 0, texture = 0 },
        bag = { type = 'component', index = 5, drawable = 0, texture = 0 },
        decals = { type = 'component', index = 10, drawable = 0, texture = 0 },
        headwear = { type = 'prop', index = 0, drawable = -1, texture = 0 },
        glasses = { type = 'prop', index = 1, drawable = -1, texture = 0 },
        earrings = { type = 'prop', index = 2, drawable = -1, texture = 0 },
        watch = { type = 'prop', index = 6, drawable = -1, texture = 0 }
    }
}

local function getPedGender(ped)
    local model = GetEntityModel(ped or PlayerPedId())
    return model == `mp_f_freemode_01` and 'female' or 'male'
end


local function normalizeWearGender(value)
    if value == nil or value == '' then return nil end
    local raw = tostring(value):lower()
    if raw == '0' or raw == 'm' or raw == 'male' or raw == 'man' or raw == 'mp_m_freemode_01' then return 'male' end
    if raw == '1' or raw == 'f' or raw == 'female' or raw == 'woman' or raw == 'mp_f_freemode_01' then return 'female' end
    if raw == 'any' or raw == 'all' or raw == 'unisex' or raw == 'both' then return nil end
    return nil
end

local function itemFitsCurrentGender(metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local required = normalizeWearGender(metadata.gender or metadata.sex or metadata.pedGender or metadata.ped_gender or metadata.model)
    return not required or required == getPedGender(PlayerPedId())
end

local function resolveTorsoFitForItem(ped, metadata, drawable, texture)
    metadata = type(metadata) == 'table' and metadata or {}
    local fallback = {
        arms = metadata.arms,
        armsTexture = metadata.armsTexture or metadata.arms_2,
        undershirt = metadata.undershirt or metadata.tshirt_1,
        undershirtTexture = metadata.undershirtTexture or metadata.tshirt_2,
    }

    if GetResourceState('cm-items') == 'started' then
        local ok, fit = pcall(function()
            return exports['cm-items']:ResolveTorsoFit(metadata.gender or getPedGender(ped), drawable, texture, fallback)
        end)
        if ok and type(fit) == 'table' then return fit end
        ok, fit = pcall(function()
            return exports['cm-items'].ResolveTorsoFit(metadata.gender or getPedGender(ped), drawable, texture, fallback)
        end)
        if ok and type(fit) == 'table' then return fit end
    end

    return fallback
end

local function clearClothingSlot(slot)
    local ped = PlayerPedId()
    local isFemale = IsPedModel(ped, `mp_f_freemode_01`)
    local defaults = isFemale and ClothingEmptyDefaults.female or ClothingEmptyDefaults.male
    local def = defaults[slot]
    if not def then return false end

    if def.type == 'prop' then
        if def.drawable < 0 then ClearPedProp(ped, def.index)
        else SetPedPropIndex(ped, def.index, def.drawable, def.texture or 0, true) end
    else
        -- Removing outerwear must also restore safe arms + undershirt. Otherwise freemode
        -- peds can become invisible when a jacket/t-shirt combination is broken apart.
        if slot == 'outerwear' then
            SetPedComponentVariation(ped, 3, def.arms or 15, def.armsTexture or 0, 0)
            SetPedComponentVariation(ped, 8, def.undershirt or def.drawable or 15, def.undershirtTexture or 0, 0)
        end
        SetPedComponentVariation(ped, def.index, def.drawable, def.texture or 0, 0)
    end

    TriggerEvent('nvCloth:client:equipClothingItem', ClothingCategoryBySlot[slot], def.drawable, def.texture or 0)
    return true
end

local function equipClothingFromInventorySlot(slot, item)
    if not item or not item.metadata then return false end
    local def = ClothingSlotMap[slot]
    if not def then return false end

    local metadata = item.metadata or {}
    if not itemFitsCurrentGender(metadata) then return false end

    local drawable = tonumber(metadata.drawableId or metadata.drawable)
    local texture = tonumber(metadata.textureId or metadata.texture or 0) or 0
    if drawable == nil then return false end

    local ped = PlayerPedId()
    if def.type == 'prop' then
        if drawable < 0 then ClearPedProp(ped, def.index)
        else SetPedPropIndex(ped, def.index, drawable, texture, true) end
    else
        -- Torso items carry matching arms and undershirt to stop clipping through jackets.
        if slot == 'outerwear' then
            local fit = resolveTorsoFitForItem(ped, metadata, drawable, texture)
            local undershirt = tonumber(fit.undershirt)
            local undershirtTexture = tonumber(fit.undershirtTexture) or 0
            local arms = tonumber(fit.arms)
            local armsTexture = tonumber(fit.armsTexture) or 0

            -- Undershirt before torso, arms after torso is the most stable order for freemode tops.
            if undershirt then SetPedComponentVariation(ped, 8, undershirt, undershirtTexture, 0) end
            SetPedComponentVariation(ped, def.index, drawable, texture, 0)
            if arms then SetPedComponentVariation(ped, 3, arms, armsTexture, 0) end
        else
            SetPedComponentVariation(ped, def.index, drawable, texture, 0)
        end
    end

    -- Also notify nvCloth so its clothing state/preview bridge stays in sync.
    local category = metadata.categoryType or metadata.category or ClothingCategoryBySlot[slot]
    TriggerEvent('nvCloth:client:equipClothingItem', category, drawable, texture)
    return true
end

local function notifyLocal(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message or '')
    EndTextCommandThefeedPostTicker(false, false)
end

local function requestAnimDictSafe(dict, timeoutMs)
    dict = tostring(dict or '')
    if dict == '' then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + (tonumber(timeoutMs) or 1200)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(10)
    end
    return HasAnimDictLoaded(dict)
end

playInventoryAnim = function(kind, duration)
    local ped = PlayerPedId()
    if not ped or ped == 0 or IsPedInAnyVehicle(ped, false) then return end

    kind = tostring(kind or 'use_item'):lower()
    duration = tonumber(duration) or 900

    local dict, anim, flag
    if kind == 'pickup' then
        dict, anim, flag, duration = 'pickup_object', 'pickup_low', 48, 850
    elseif kind == 'clothes_on' or kind == 'clothes_off' or kind == 'clothes_change' then
        dict, anim, flag, duration = 'clothingshirt', 'try_shirt_positive_d', 49, math.max(duration, 1200)
    elseif kind == 'weapon_out' or kind == 'weapon_use' then
        dict, anim, flag, duration = 'reaction@intimidation@1h', 'intro', 48, 900
    elseif kind == 'weapon_change' then
        dict, anim, flag, duration = 'reaction@intimidation@1h', 'intro', 48, 750
    elseif kind == 'weapon_in' or kind == 'weapon_keep' then
        dict, anim, flag, duration = 'reaction@intimidation@1h', 'outro', 48, 850
    else
        dict, anim, flag, duration = 'mp_common', 'givetake1_a', 48, math.max(duration, 900)
    end

    CreateThread(function()
        if requestAnimDictSafe(dict, 1400) then
            TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration, flag, 0.0, false, false, false)
            Wait(duration)
            StopAnimTask(ped, dict, anim, 1.0)
            RemoveAnimDict(dict)
        end
    end)
end

RegisterNetEvent('cm-inventory:client:playInventoryAnim', function(kind, duration)
    playInventoryAnim(kind, duration)
end)

local function dutyUniformClothingLocked()
    local police = LocalPlayer and LocalPlayer.state and LocalPlayer.state.cmPolice
    if type(police) == 'table' and police.onDuty == true then return true, 'Police' end
    local legal = LocalPlayer and LocalPlayer.state and LocalPlayer.state.cmLegalOrg
    if type(legal) == 'table' and legal.onDuty == true and legal.uniformActive == true then
        return true, legal.shortLabel or 'organization'
    end
    return false, nil
end

local function applyEquipmentSlot(slot, item, silent, bypassPoliceDutyLock)
    equipmentState[slot] = item
    local ped = PlayerPedId()

    if ClothingSlotMap[slot] then
        -- Keep the server-owned equipment slot change, but do not let normal
        -- inventory clothing visually overwrite an approved Police uniform.
        -- When duty ends, restoreEquippedClothing below reapplies the latest
        -- slot state, including changes the officer made during the shift.
        local uniformLocked, uniformLabel = dutyUniformClothingLocked()
        if not bypassPoliceDutyLock and uniformLocked then
            if not silent then notifyLocal(('Civilian clothing is saved but cannot replace your on-duty %s uniform.'):format(uniformLabel)) end
            return
        end
        if item and tostring(item.item_name or ''):find('clothing_', 1, true) == 1 then
            if equipClothingFromInventorySlot(slot, item) then
                if not silent then playInventoryAnim('clothes_change') end
                -- If a shirt/undershirt is changed while outerwear is equipped, apply outerwear again
                -- because outerwear metadata contains the clipping-safe arms + undershirt pairing.
                if slot == 'shirt' and equipmentState.outerwear then
                    equipClothingFromInventorySlot('outerwear', equipmentState.outerwear)
                end
                if not silent then notifyLocal(('Equipped %s'):format(item.label or item.item_name)) end
            end
        elseif not item then
            if not silent then playInventoryAnim('clothes_off') end
            clearClothingSlot(slot)

            -- Removing outerwear should reveal the shirt slot if one exists.
            -- Removing shirt should restore the outerwear undershirt instead of leaving an invisible body.
            if slot == 'outerwear' and equipmentState.shirt then
                equipClothingFromInventorySlot('shirt', equipmentState.shirt)
            elseif slot == 'shirt' and equipmentState.outerwear then
                equipClothingFromInventorySlot('outerwear', equipmentState.outerwear)
            end

            if not silent then notifyLocal('Clothing removed.') end
        end
        return
    end

    if slot == 'weapon' then
        local oldHash = equippedWeaponHash
        local oldName = equippedWeaponName
        local newHash = item and item.item_name and resolveWeaponHash(item.item_name, item) or nil
        local newName = item and tostring(item.item_name or ''):lower() or nil

        -- Remove every native GTA weapon first. The player can only carry/use the
        -- inventory weapon that is currently in the gun equipment slot.
        RemoveAllPedWeapons(ped, true)
        equippedWeaponHash = nil
        equippedWeaponName = nil

        if newHash then
            if oldName ~= newName then currentWeaponAmmo = 0 end
            equippedWeaponHash = newHash
            equippedWeaponName = newName
            GiveWeaponToPed(ped, newHash, 0, false, true)
            SetPedAmmo(ped, newHash, math.max(0, tonumber(currentWeaponAmmo) or 0))
            SetCurrentPedWeapon(ped, newHash, true)

            if not silent then
                if oldHash and oldHash ~= newHash then
                    playInventoryAnim('weapon_change')
                else
                    playInventoryAnim('weapon_out')
                end
                notifyLocal(('Equipped %s'):format(item.label or item.item_name))
            end
        else
            SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
            currentWeaponAmmo = 0
            if oldHash and not silent then
                playInventoryAnim('weapon_in')
                notifyLocal('Weapon stored.')
            end
        end
    elseif slot == 'bodyarmor' then
        if item then
            if not silent then playInventoryAnim('clothes_on') end
            local durability = tonumber(item.durability or (item.metadata and item.metadata.durability) or 100) or 100

            -- Wearable vest (cm-gunstore armor): apply GTA component 9 drawable/texture.
            -- Metadata is set by cm-gunstore when the vest was captured/created.
            local md = item.metadata or {}
            if not itemFitsCurrentGender(md) then return end
            local comp = tonumber(md.componentIndex or md.componentId or md.component_id)
            local drawable = tonumber(md.drawableId or md.drawable or md.drawable_id)
            local texture = tonumber(md.textureId or md.texture or md.texture_id) or 0
            if drawable ~= nil and drawable >= 0 then
                comp = comp or 9
                SetPedComponentVariation(ped, comp, drawable, texture, 0)
                equippedVestComponent = comp -- remember so we can clear it on unequip
                -- Persist look so it survives respawn/relog if cm-characters is present.
                if GetResourceState('cm-characters') == 'started' then
                    pcall(function() exports['cm-characters']:SaveAppearance() end)
                end
            end

            -- Armor health: prefer explicit armorValue from the vest, else durability.
            local armorValue = tonumber(md.armorValue or md.armor_value) or durability
            SetPedArmour(ped, math.max(0, math.min(100, math.floor(armorValue))))
            if not silent then notifyLocal(('Equipped %s'):format(item.label or item.item_name)) end
        else
            if not silent then playInventoryAnim('clothes_off') end
            -- Unequip: drop a worn vest component back to the default (no vest).
            if equippedVestComponent then
                SetPedComponentVariation(ped, equippedVestComponent, 0, 0, 0)
                equippedVestComponent = nil
                if GetResourceState('cm-characters') == 'started' then
                    pcall(function() exports['cm-characters']:SaveAppearance() end)
                end
            end
            SetPedArmour(ped, 0)
        end
    elseif slot == 'bag' then
        if item and not silent then
            notifyLocal(('Equipped %s'):format(item.label or item.item_name))
        end
    end
end



RegisterNetEvent('cm-inventory:client:equipClothingFromItem', function(slot, item)
    applyEquipmentSlot(tostring(slot or ''), item)
end)

RegisterNetEvent('cm-inventory:client:addWeaponAmmo', function(weaponName, amount)
    local ped = PlayerPedId()
    weaponName = tostring(weaponName or ''):lower()
    amount = tonumber(amount) or 0
    local hash = resolveWeaponHash(weaponName)
    if not hash or amount <= 0 then return end
    if equippedWeaponHash ~= hash then return end
    currentWeaponAmmo = math.max(0, currentWeaponAmmo + amount)
    SetPedAmmo(ped, hash, currentWeaponAmmo)
    SetCurrentPedWeapon(ped, hash, true)
    notifyLocal(('Reloaded %sx ammo'):format(amount))
end)

RegisterNetEvent('cm-inventory:client:setWeaponAmmo', function(weaponName, amount, ammoItem)
    weaponName = weaponName and tostring(weaponName):lower() or nil
    currentWeaponAmmo = math.max(0, tonumber(amount) or 0)

    local ped = PlayerPedId()
    if not equippedWeaponHash then return end

    local expectedHash = weaponName and resolveWeaponHash(weaponName) or equippedWeaponHash
    if expectedHash and expectedHash == equippedWeaponHash then
        SetPedAmmo(ped, equippedWeaponHash, currentWeaponAmmo)
        if currentWeaponAmmo <= 0 then
            SetAmmoInClip(ped, equippedWeaponHash, 0)
        end
    end
end)


RegisterNetEvent('cm-inventory:client:noInventoryAmmo', function(message)
    local ped = PlayerPedId()
    currentWeaponAmmo = 0
    if equippedWeaponHash then
        SetPedAmmo(ped, equippedWeaponHash, 0)
        SetAmmoInClip(ped, equippedWeaponHash, 0)
    end
    notifyLocal(message or 'No inventory ammo available.')
end)

CreateThread(function()
    while true do
        if equippedWeaponHash then
            Wait(0)
            DisableControlAction(0, 45, true) -- disable GTA reload; inventory controls ammo.
            local ped = PlayerPedId()

            -- No inventory ammo = no shooting. This stops fake GTA ammo from being used.
            if currentWeaponAmmo <= 0 then
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 257, true)
                DisablePlayerFiring(PlayerId(), true)
            end

            if IsPedShooting(ped) then
                currentWeaponAmmo = math.max(0, (tonumber(currentWeaponAmmo) or 0) - 1)
                TriggerServerEvent('cm-inventory:server:weaponShot')
                Wait(120)
            end
        else
            Wait(400)
        end
    end
end)

RegisterNetEvent('cm-inventory:client:equipmentSlot', function(slot, item)
    applyEquipmentSlot(slot, item)
end)

RegisterNetEvent('cm-inventory:client:setEquipment', function(payload)
    payload = type(payload) == 'table' and payload or {}
    equipmentState = payload

    -- Apply in a fixed order. Shirt first, outerwear last for top-body slots so jacket
    -- metadata can restore the correct arms + undershirt and prevent invisible/clipping body.
    local order = {
        'mask', 'glasses', 'headwear', 'earrings',
        'shirt', 'outerwear', 'bodyarmor', 'bag',
        'accessory', 'weapon', 'ammo', 'watch', 'pants', 'shoes'
    }
    for _, slot in ipairs(order) do
        if payload[slot] ~= nil then
            applyEquipmentSlot(slot, payload[slot], true)
        end
    end

    -- Nil keys are omitted in Lua/NUI payloads, so explicitly clear native GTA
    -- weapons if inventory has no weapon item equipped.
    if payload.weapon == nil then
        applyEquipmentSlot('weapon', nil, true)
    end
end)

local function requestEquipmentRefreshBurst()
    -- Appearance resources may apply components late. Use absolute delays (not
    -- cumulative waits) and fewer refreshes to keep clothing reliable without
    -- unnecessary server/database work for more than ten seconds after spawn.
    CreateThread(function()
        local delays = { 0, 300, 900, 2000, 4500 }
        local startedAt = GetGameTimer()
        for _, delay in ipairs(delays) do
            local remaining = delay - (GetGameTimer() - startedAt)
            if remaining > 0 then Wait(remaining) end
            TriggerServerEvent('cm-inventory:server:requestEquipment')
        end
    end)
end

RegisterNetEvent('cm-inventory:client:requestEquipmentRefresh', function()
    requestEquipmentRefreshBurst()
end)

RegisterNetEvent('cm-inventory:client:forceWearEquippedClothing', function()
    requestEquipmentRefreshBurst()
end)

RegisterNetEvent('cm-inventory:client:restoreEquippedClothing', function()
    local order = { 'mask', 'arms', 'decals', 'glasses', 'headwear', 'earrings', 'shirt', 'outerwear', 'bag', 'accessory', 'watch', 'pants', 'shoes' }
    for _, slot in ipairs(order) do
        applyEquipmentSlot(slot, equipmentState[slot], true, true)
    end
    applyEquipmentSlot('bodyarmor', equipmentState.bodyarmor, true, true)
    if not equipmentState.bodyarmor then
        SetPedComponentVariation(PlayerPedId(), 9, 0, 0, 0)
    end
end)

AddEventHandler('playerSpawned', function()
    requestEquipmentRefreshBurst()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        requestEquipmentRefreshBurst()
    end
end)


local function normalizePlate(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper()
end

local function getNearbyOpenTrunkCandidate()
    if GetResourceState('cm-vehicles') ~= 'started' or isPlayerInsideVehicle() then return nil end

    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local best = nil
    local bestDistance = 9999.0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and GetVehicleDoorAngleRatio(vehicle, 5) > 0.05 then
            local trunkCoords = GetEntityCoords(vehicle)
            local bone = GetEntityBoneIndexByName(vehicle, 'boot')
            if bone and bone ~= -1 then
                trunkCoords = GetWorldPositionOfEntityBone(vehicle, bone)
            end

            local distance = #(playerCoords - trunkCoords)
            if distance <= 4.5 and distance < bestDistance then
                local state = Entity(vehicle).state
                local plate = normalizePlate(state and state.cmPlate or GetVehicleNumberPlateText(vehicle))
                if plate ~= '' then
                    best = {
                        plate = plate,
                        netId = NetworkGetNetworkIdFromEntity(vehicle)
                    }
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

local function openNormalInventoryFallback()
    if isDeadOrUnconscious() then return end
    TriggerServerEvent('cm-inventory:server:openInventory')
end

RegisterNetEvent('cm-inventory:client:openConfirmedVehicleTrunk', function()
    if isDeadOrUnconscious() then return end

    local opened = false
    if GetResourceState('cm-vehicles') == 'started' then
        local ok, result = pcall(function()
            return exports['cm-vehicles']:TryOpenNearbyTrunkInventory()
        end)
        opened = ok and result == true
    end

    if not opened then openNormalInventoryFallback() end
end)

local function openInventoryCommand()
    if isDeadOrUnconscious() then return end
    if isOpen then closeInventory() return end

    local candidate = getNearbyOpenTrunkCandidate()
    if candidate then
        -- Server checks owner + distance first. Non-owners silently receive their
        -- normal player inventory, so cm-vehicles never emits an ownership error.
        TriggerServerEvent('cm-inventory:server:resolveVehicleTrunkOpen', candidate.plate, candidate.netId)
        return
    end

    openNormalInventoryFallback()
end

RegisterCommand('inventory', openInventoryCommand, false)
RegisterCommand('inv', openInventoryCommand, false)

RegisterKeyMapping('inventory', 'Open inventory', 'keyboard', Config.OpenKey or 'I')

RegisterCommand('invping', function()
    print('[CM-INVENTORY-CLIENT] invping works - client/main.lua is loaded')
    TriggerServerEvent('cm-inventory:server:debugPing')
    TriggerServerEvent('cm-inventory:server:requestDrops')
end, false)

RegisterCommand('testgive', function(_, args)
    local itemName = tostring(args[1] or 'water'):lower()
    local amount = tonumber(args[2]) or 1
    print(('[CM-INVENTORY-CLIENT] testgive command called: %sx %s'):format(amount, itemName))
    TriggerServerEvent('cm-inventory:server:debugGiveItem', itemName, amount)
end, false)

RegisterCommand('pickupdrop', function()
    if isDeadOrUnconscious() or isPlayerInsideVehicle() then return end
    local drop, dist = getClosestDrop()
    if drop and dist <= ((Config.Drops and Config.Drops.pickupDistance) or 2.0) then
        TriggerServerEvent('cm-inventory:server:pickupDrop', drop.id)
    else
        TriggerEvent('cm-inventory:client:notify', 'No item drop nearby.', 'error')
    end
end, false)


RegisterCommand('givetest', function(_, args)
    local itemName = tostring(args[1] or 'water'):lower()
    local amount = tonumber(args[2]) or 1
    print(('[CM-INVENTORY-CLIENT] givetest command called: %sx %s'):format(amount, itemName))
    TriggerServerEvent('cm-inventory:server:devGiveTest', itemName, amount)
end, false)

RegisterCommand('showtestreceiver', function()
    print('[CM-INVENTORY-CLIENT] showtestreceiver command called')
    TriggerServerEvent('cm-inventory:server:showTestReceiver')
end, false)

RegisterCommand('cleartestreceiver', function()
    print('[CM-INVENTORY-CLIENT] cleartestreceiver command called')
    TriggerServerEvent('cm-inventory:server:clearTestReceiver')
end, false)


RegisterCommand('invdebug', function()
    Config.Debug = not Config.Debug
    print(('[CM-INVENTORY-CLIENT] Debug is now %s'):format(Config.Debug and 'ON' or 'OFF'))
    TriggerServerEvent('cm-inventory:server:setDebug', Config.Debug)
end, false)

RegisterNUICallback('close', function(_, cb)
    closeInventory()
    cb({ ok = true })
end)

RegisterNUICallback('debugMove', function(data, cb)
    if Config.Debug then
        cdebug(('NUI %s'):format(safeJson(data or {})))
        TriggerServerEvent('cm-inventory:server:uiDebug', data or {})
    end
    cb({ ok = true })
end)

RegisterNUICallback('moveItem', function(data, cb)
    if Config.Debug then
        cdebug(('moveItem callback %s'):format(safeJson(data or {})))
    end
    TriggerServerEvent('cm-inventory:server:moveItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('splitItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:splitItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('dropItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:dropItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('useItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:useItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('giveItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:giveItem', data or {})
    cb({ ok = true })
end)

-- Tier 2: give flow with target name/list + confirmation.
-- Step 1: ask the server who is nearby for this slot.
RegisterNUICallback('requestGive', function(data, cb)
    TriggerServerEvent('cm-inventory:server:requestGive', data or {})
    cb({ ok = true })
end)

-- Step 2: player picked/confirmed a target in the NUI.
RegisterNUICallback('confirmGive', function(data, cb)
    TriggerServerEvent('cm-inventory:server:confirmGive', data or {})
    cb({ ok = true })
end)

-- Server tells us who is nearby -> hand the list to the NUI to show a confirm
-- (single) or a picker (multiple).
RegisterNetEvent('cm-inventory:client:giveTargets', function(payload)
    SendNUIMessage({ action = 'giveTargets', data = payload or {} })
end)

RegisterNUICallback('reloadWeapon', function(_, cb)
    TriggerEvent('cm-inventory:client:notify', 'Manual reload is disabled. Ammo is used from inventory when you shoot.', 'info')
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        if isOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            if IsControlJustPressed(0, 322) then closeInventory() end -- ESC
            Wait(0)
        else
            Wait(250)
        end
    end
end)

local function isInventoryWeaponInHand()
    if not equippedWeaponHash then return false end
    local ped = PlayerPedId()
    local selected = GetSelectedPedWeapon(ped)
    return selected == equippedWeaponHash and selected ~= GetHashKey('WEAPON_UNARMED')
end

-- Remove GTA V weapon wheel / native weapon switching and reserve keys 1-5
-- exclusively for CM fast-access slots. These controls must be disabled every
-- frame; polling them at 100-150ms can miss IsControlJustPressed and allows GTA
-- to select a native weapon before CM handles the key.
CreateThread(function()
    local fastControls = {157, 158, 160, 164, 165} -- keyboard 1-5
    local blockedControls = {
        37,       -- weapon wheel / TAB
        14, 15,  -- weapon wheel next/previous
        16, 17,  -- select next/previous weapon
        45,       -- native reload
        157, 158, 159, 160, 161, 162, 163, 164, 165 -- native weapon slots 1-9
    }

    while true do
        if not isOpen then
            for _, control in ipairs(blockedControls) do
                DisableControlAction(0, control, true)
            end
            pcall(function() BlockWeaponWheelThisFrame() end)
            HideHudComponentThisFrame(19)
            HideHudComponentThisFrame(20)

            for index, control in ipairs(fastControls) do
                if IsDisabledControlJustPressed(0, control) then
                    TriggerServerEvent('cm-inventory:server:quickAccessHotkey', {
                        index = index,
                        weaponInHand = isInventoryWeaponInHand()
                    })
                end
            end
            Wait(0)
        else
            Wait(100)
        end
    end
end)

-- Replicated unconscious state fallback. The authoritative drop is called by
-- cm-playerdata on SetDead(true); this only recovers safely if resources restart.
local deathReported = false
CreateThread(function()
    while true do
        local dead = isDeadOrUnconscious()
        if dead then
            deathBlocked = true
            if isOpen then closeInventory(true) end
            if not deathReported then
                deathReported = true
                TriggerServerEvent('cm-inventory:server:playerDied')
            end
        else
            deathBlocked = false
            deathReported = false
        end
        Wait(dead and 250 or 500)
    end
end)


-- Keep equipped armor durability synced to the bodyarmor item metadata.
CreateThread(function()
    local lastArmor = nil
    while true do
        local item = equipmentState and equipmentState.bodyarmor or nil
        if item then
            local armor = GetPedArmour(PlayerPedId())
            if lastArmor == nil then lastArmor = armor end
            if armor ~= lastArmor then
                lastArmor = armor
                TriggerServerEvent('cm-inventory:server:armorChanged', armor)
                Wait(1200)
            end
            Wait(500)
        else
            lastArmor = nil
            Wait(1200)
        end
    end
end)

-- Ground drops: real prop + on-screen pickup card.
local function dropCoords(drop)
    local c = drop and drop.coords or {}
    return vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
end

local function imageForDrop(drop)
    local image = drop and (drop.image or drop.icon) or 'placeholder.png'
    image = tostring(image or 'placeholder.png')
    if image:find('^nui://') then
        local resource, path = image:match('^nui://([^/]+)/(.+)$')
        if resource and path then return ('https://cfx-nui-%s/%s'):format(resource, path) end
    end
    if image:find('^https?://') or image:find('^data:') then return image end
    if image:find('^custom/') then return 'https://cfx-nui-cm-items/ui/images/clothing/' .. image end
    if image:find('^clothing/') then return 'https://cfx-nui-cm-items/ui/images/' .. image end
    return 'images/' .. image
end

local function buildNearbyDrops(playerCoords)
    local uiDistance = tonumber((Config.Drops or {}).uiDistance) or ((tonumber((Config.Drops or {}).pickupDistance) or 2.0) + 0.4)
    local list = {}
    for _, drop in ipairs(Drops or {}) do
        local coords = dropCoords(drop)
        local dist = #(playerCoords - coords)
        if dist <= uiDistance then
            list[#list + 1] = {
                id = tonumber(drop.id),
                label = drop.label or drop.item_name or 'Item',
                quantity = tonumber(drop.quantity) or 1,
                image = imageForDrop(drop),
                distance = dist,
                coords = coords
            }
        end
    end
    table.sort(list, function(a, b) return (a.distance or 999.0) < (b.distance or 999.0) end)
    return list
end

local function sendDropPickupUi(list, selected)
    list = type(list) == 'table' and list or {}
    if #list == 0 or isOpen or isDeadOrUnconscious() or isPlayerInsideVehicle() then
        if lastDropUiKey ~= 'hidden' then
            nui('nearDrops', { visible = false, drops = {} })
            lastDropUiKey = 'hidden'
        end
        return
    end

    local payloadDrops = {}
    for i, drop in ipairs(list) do
        payloadDrops[#payloadDrops + 1] = {
            id = drop.id,
            label = drop.label,
            quantity = drop.quantity,
            image = drop.image,
            selected = i == selected
        }
        if #payloadDrops >= 6 then break end
    end

    local key = tostring(selected) .. ':'
    for _, drop in ipairs(payloadDrops) do
        key = key .. tostring(drop.id) .. ':' .. tostring(drop.quantity) .. '|'
    end

    if key ~= lastDropUiKey then
        nui('nearDrops', { visible = true, drops = payloadDrops, selected = selected, count = #list })
        lastDropUiKey = key
    end
end

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('cm-inventory:server:requestDrops')

    while true do
        local sleep = 1000
        if not isOpen and not isDeadOrUnconscious() and not isPlayerInsideVehicle() and Drops and #Drops > 0 then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local markerDistance = (Config.Drops and Config.Drops.markerDistance) or 18.0
            local pickupDistance = (Config.Drops and Config.Drops.pickupDistance) or 2.0
            local nearby = buildNearbyDrops(coords)

            if #nearby > 0 then
                sleep = 0
                if selectedDropIndex < 1 then selectedDropIndex = 1 end
                if selectedDropIndex > #nearby then selectedDropIndex = #nearby end

                if #nearby > 1 then
                    if IsControlJustPressed(0, 172) or IsControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 15) then -- Arrow up / mouse wheel up
                        selectedDropIndex = selectedDropIndex - 1
                        if selectedDropIndex < 1 then selectedDropIndex = #nearby end
                        lastDropUiKey = nil
                    elseif IsControlJustPressed(0, 173) or IsControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 14) then -- Arrow down / mouse wheel down
                        selectedDropIndex = selectedDropIndex + 1
                        if selectedDropIndex > #nearby then selectedDropIndex = 1 end
                        lastDropUiKey = nil
                    end
                else
                    selectedDropIndex = 1
                end

                sendDropPickupUi(nearby, selectedDropIndex)

                local selected = nearby[selectedDropIndex]
                if selected and selected.distance <= (pickupDistance + 0.5) and IsControlJustPressed(0, 38) then -- E
                    TriggerServerEvent('cm-inventory:server:pickupDrop', selected.id)
                    Wait(450)
                end
            else
                selectedDropIndex = 1
                sendDropPickupUi({}, 1)
            end

            for _, drop in ipairs(Drops) do
                local dCoords = dropCoords(drop)
                local dist = #(coords - dCoords)
                if dist <= markerDistance then
                    sleep = 0
                    DrawMarker((Config.Drops and Config.Drops.markerType) or 2, dCoords.x, dCoords.y, dCoords.z + 0.14,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.18, 0.18, 0.18, 39, 231, 255, 105,
                        false, true, 2, false, nil, nil, false)
                end
            end
        else
            selectedDropIndex = 1
            sendDropPickupUi({}, 1)
        end
        Wait(sleep)
    end
end)

-- Keep drops fresh so one-minute expired props disappear even when nobody picks them up.
CreateThread(function()
    while true do
        Wait(15000)
        TriggerServerEvent('cm-inventory:server:requestDrops')
    end
end)
