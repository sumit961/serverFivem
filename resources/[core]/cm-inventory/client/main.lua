local Config = CMInventory.Config
local isOpen = false
local Drops = {}
local DropProps = {}
local selectedDropIndex = 1
local lastDropUiKey = nil
local playInventoryAnim

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
    isOpen = true

    -- Inventory NUI focus + hide native and custom HUD while inventory is open.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    hideGameAndCustomHud()

    nui('open', payload or {})
    TriggerServerEvent('cm-inventory:server:requestDrops')
end

local function closeInventory()
    isOpen = false

    -- Restore NUI focus + native/custom HUD when inventory closes.
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    showGameAndCustomHud()

    TriggerServerEvent('cm-inventory:server:closeInventory')
    nui('close', {})
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
    showGameAndCustomHud()
    nui('nearDrops', { visible = false, drops = {} })
    for id in pairs(DropProps or {}) do
        deleteDropProp(id)
    end
end)

RegisterNetEvent('cm-inventory:client:open', function(payload)
    openInventory(payload)
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

        local obj = CreateObject(hash, x, y, z, false, false, false)
        if obj and obj ~= 0 then
            SetEntityAsMissionEntity(obj, true, true)
            PlaceObjectOnGroundProperly(obj)
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
        if drop and drop.id then
            active[tonumber(drop.id)] = true
            ensureDropProp(drop)
        end
    end

    for id in pairs(DropProps) do
        if not active[tonumber(id)] then
            deleteDropProp(id)
        end
    end
end

RegisterNetEvent('cm-inventory:client:updateDrops', function(drops)
    Drops = type(drops) == 'table' and drops or {}
    syncDropProps(Drops)
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
    shirt = { type = 'component', index = 8 },
    outerwear = { type = 'component', index = 11 },
    pants = { type = 'component', index = 4 },
    shoes = { type = 'component', index = 6 },
    accessory = { type = 'component', index = 7 },
    bag = { type = 'component', index = 5 },
    headwear = { type = 'prop', index = 0 },
    glasses = { type = 'prop', index = 1 },
    earrings = { type = 'prop', index = 2 },
    watch = { type = 'prop', index = 6 }
}

local ClothingCategoryBySlot = {
    shirt = 'tshirt', outerwear = 'torso', pants = 'pants', shoes = 'shoes',
    accessory = 'chains', bag = 'bags', headwear = 'hat', glasses = 'glasses',
    earrings = 'earrings', watch = 'watches'
}

local ClothingEmptyDefaults = {
    male = {
        shirt = { type = 'component', index = 8, drawable = 15, texture = 0 },
        outerwear = { type = 'component', index = 11, drawable = 15, texture = 0, arms = 15, armsTexture = 0, undershirt = 15, undershirtTexture = 0 },
        pants = { type = 'component', index = 4, drawable = 21, texture = 0 },
        shoes = { type = 'component', index = 6, drawable = 34, texture = 0 },
        accessory = { type = 'component', index = 7, drawable = 0, texture = 0 },
        bag = { type = 'component', index = 5, drawable = 0, texture = 0 },
        headwear = { type = 'prop', index = 0, drawable = -1, texture = 0 },
        glasses = { type = 'prop', index = 1, drawable = -1, texture = 0 },
        earrings = { type = 'prop', index = 2, drawable = -1, texture = 0 },
        watch = { type = 'prop', index = 6, drawable = -1, texture = 0 }
    },
    female = {
        shirt = { type = 'component', index = 8, drawable = 14, texture = 0 },
        outerwear = { type = 'component', index = 11, drawable = 15, texture = 0, arms = 15, armsTexture = 0, undershirt = 14, undershirtTexture = 0 },
        pants = { type = 'component', index = 4, drawable = 15, texture = 0 },
        shoes = { type = 'component', index = 6, drawable = 35, texture = 0 },
        accessory = { type = 'component', index = 7, drawable = 0, texture = 0 },
        bag = { type = 'component', index = 5, drawable = 0, texture = 0 },
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

local function applyEquipmentSlot(slot, item, silent)
    equipmentState[slot] = item
    local ped = PlayerPedId()

    if ClothingSlotMap[slot] then
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
    -- Any spawn/appearance script can reset freemode components back to the saved base/naked JSON.
    -- Requesting equipment several times lets inventory clothing always win after character creation,
    -- normal spawn, model reloads, or cm-spawn applying appearance slightly late.
    CreateThread(function()
        local waits = { 0, 250, 750, 1500, 3000, 5000 }
        for _, ms in ipairs(waits) do
            if ms > 0 then Wait(ms) end
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

AddEventHandler('playerSpawned', function()
    requestEquipmentRefreshBurst()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        requestEquipmentRefreshBurst()
    end
end)


local function tryOpenVehicleTrunkBeforeInventory()
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, opened = pcall(function()
        return exports['cm-vehicles']:TryOpenNearbyTrunkInventory()
    end)
    return ok and opened == true
end

RegisterCommand('inventory', function()
    if isOpen then closeInventory() return end
    if tryOpenVehicleTrunkBeforeInventory() then return end
    TriggerServerEvent('cm-inventory:server:openInventory')
end, false)

RegisterCommand('inv', function()
    if isOpen then closeInventory() return end
    if tryOpenVehicleTrunkBeforeInventory() then return end
    TriggerServerEvent('cm-inventory:server:openInventory')
end, false)

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

-- Remove GTA V weapon wheel / native weapon slot scrolling.
-- CM weapons are controlled only by inventory gun slot + fast access keys.
CreateThread(function()
    local blocked = {37, 14, 15, 16, 17, 45, 157, 158, 159, 160, 161, 162, 163, 164, 165}
    while true do
        if not isOpen then
            pcall(function() BlockWeaponWheelThisFrame() end)
            HideHudComponentThisFrame(19) -- weapon wheel
            HideHudComponentThisFrame(20) -- weapon stats
            for _, control in ipairs(blocked) do
                DisableControlAction(0, control, true)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Quick access keys 1-5 while inventory is closed.
CreateThread(function()
    local controls = {157, 158, 160, 164, 165}
    while true do
        if not isOpen then
            for index, control in ipairs(controls) do
                if IsDisabledControlJustPressed(0, control) or IsControlJustPressed(0, control) then
                    TriggerServerEvent('cm-inventory:server:quickAccessHotkey', {
                        index = index,
                        weaponInHand = isInventoryWeaponInHand()
                    })
                end
            end
            Wait(0)
        else
            Wait(300)
        end
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

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(2500)
    TriggerServerEvent('cm-inventory:server:requestEquipment')
end)

AddEventHandler('playerSpawned', function()
    Wait(2500)
    TriggerServerEvent('cm-inventory:server:requestEquipment')
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
    if #list == 0 or isOpen then
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
        if not isOpen and Drops and #Drops > 0 then
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
