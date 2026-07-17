-- ============================================================
-- cm-house | garage customization
-- Per-property choices rendered through reusable template anchors.
-- ============================================================

local function decode(value, fallback)
    if type(value) == 'table' then return value end
    if value == nil or value == '' then return fallback end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or fallback
end

local function clamp(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return math.floor(value + 0.5)
end

local function normalizeSettings(value)
    value = type(value) == 'table' and value or {}
    local configured = Config.GarageCustomization
        and Config.GarageCustomization.defaults
        and Config.GarageCustomization.defaults.settings or {}
    return {
        floorOpacity = clamp(value.floorOpacity, 0, 150, tonumber(configured.floorOpacity) or 100),
        wallIntensity = clamp(value.wallIntensity, 0, 150, tonumber(configured.wallIntensity) or 100),
        lightIntensity = clamp(value.lightIntensity, 0, 150, tonumber(configured.lightIntensity) or 100),
        decorDensity = clamp(value.decorDensity, 0, 100, tonumber(configured.decorDensity) or 100),
    }
end

local function optionExists(group, key)
    local cfg = Config.GarageCustomization or {}
    return type(cfg[group]) == 'table' and cfg[group][tostring(key or '')] ~= nil
end

local function defaults()
    local d = (Config.GarageCustomization and Config.GarageCustomization.defaults) or {}
    return {
        theme = tostring(d.theme or 'ice_clean'),
        floor = tostring(d.floor or 'ice_pad'),
        wall = tostring(d.wall or 'cyan_wash'),
        light = tostring(d.light or 'bright_white'),
        decor = tostring(d.decor or 'clean'),
        accent = tostring(d.accent or 'cyan'),
        settings = normalizeSettings(d.settings),
    }
end

function GetGarageCustomization(houseId)
    houseId = tonumber(houseId)
    local base = defaults()
    if not houseId then return base end
    local row = MySQL.single.await(
        'SELECT * FROM cm_house_garage_customizations WHERE house_id = ? LIMIT 1', { houseId })
    if not row then return base end
    local stored = {
        theme = tostring(row.theme_key or ''), floor = tostring(row.floor_key or ''),
        wall = tostring(row.wall_key or ''), light = tostring(row.light_key or ''),
        decor = tostring(row.decor_key or ''), accent = tostring(row.accent_key or ''),
    }
    if optionExists('themes', stored.theme) then base.theme = stored.theme end
    if optionExists('floors', stored.floor) then base.floor = stored.floor end
    if optionExists('walls', stored.wall) then base.wall = stored.wall end
    if optionExists('lights', stored.light) then base.light = stored.light end
    if optionExists('decor', stored.decor) then base.decor = stored.decor end
    if optionExists('accents', stored.accent) then base.accent = stored.accent end
    base.settings = normalizeSettings(decode(row.settings, {}))
    base.updatedAt = row.updated_at
    return base
end

local function sanitizedCatalog()
    local source = Config.GarageCustomization or {}
    local out = {}
    for _, group in ipairs({ 'themes', 'floors', 'walls', 'lights', 'decor', 'accents' }) do
        out[group] = {}
        for key, value in pairs(source[group] or {}) do
            local item = {
                key = key,
                label = tostring(value.label or key),
            }
            if group == 'themes' then
                item.floor = value.floor
                item.wall = value.wall
                item.light = value.light
                item.decor = value.decor
                item.accent = value.accent
            elseif group == 'accents' then
                item.rgb = value.rgb
            end
            out[group][key] = item
        end
    end
    return out
end

local function templateForHouse(houseId)
    local house = Houses[tonumber(houseId)]
    if not house or not house.garage_template_id then return nil, nil end
    return house, GarageTemplates[tonumber(house.garage_template_id)]
end

local function nearCustomizationPoint(src, template)
    local point = template and template.customization_point
    if type(point) ~= 'table' then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local maxDistance = tonumber(Config.GarageTemplate and Config.GarageTemplate.customizationUseDistance) or 2.5
    return #(coords - vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0)) <= maxDistance + 0.75
end

lib.callback.register('cm-house:server:getGarageCustomization', function(src, houseId)
    houseId = tonumber(houseId)
    local whereHouse, whereKind = WhereIs(src)
    if tonumber(whereHouse) ~= houseId or whereKind ~= 'garage' then
        return nil, 'You must be inside this garage.'
    end
    local cid = GetCid(src)
    local allowed, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_CUSTOMIZE)
    if not allowed then return nil, why end
    local _, template = templateForHouse(houseId)
    if not template or not template.customization_point then
        return nil, 'This garage template has no customization point.'
    end
    if not nearCustomizationPoint(src, template) then
        return nil, 'Move closer to the garage settings point.'
    end
    return {
        houseId = houseId,
        current = GetGarageCustomization(houseId),
        catalog = sanitizedCatalog(),
    }
end)

lib.callback.register('cm-house:server:saveGarageCustomization', function(src, houseId, payload)
    houseId = tonumber(houseId)
    payload = type(payload) == 'table' and payload or {}
    local whereHouse, whereKind = WhereIs(src)
    if tonumber(whereHouse) ~= houseId or whereKind ~= 'garage' then
        return false, 'You must be inside this garage.'
    end
    local cid = GetCid(src)
    local allowed, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_CUSTOMIZE)
    if not allowed then return false, why end
    local house, template = templateForHouse(houseId)
    if not house or not template or not nearCustomizationPoint(src, template) then
        return false, 'Move closer to the garage settings point.'
    end

    local theme = tostring(payload.theme or '')
    local floor = tostring(payload.floor or '')
    local wall = tostring(payload.wall or '')
    local light = tostring(payload.light or '')
    local decor = tostring(payload.decor or '')
    local accent = tostring(payload.accent or '')
    if not optionExists('themes', theme) then return false, 'Unknown garage theme.' end
    if not optionExists('floors', floor) then return false, 'Unknown floor style.' end
    if not optionExists('walls', wall) then return false, 'Unknown wall style.' end
    if not optionExists('lights', light) then return false, 'Unknown lighting style.' end
    if not optionExists('decor', decor) then return false, 'Unknown decor set.' end
    if not optionExists('accents', accent) then return false, 'Unknown accent colour.' end
    local settings = normalizeSettings(payload.settings)

    local saved, saveError = pcall(function()
        return MySQL.query.await([[
            INSERT INTO cm_house_garage_customizations
                (house_id, theme_key, floor_key, wall_key, light_key, decor_key, accent_key, settings, updated_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                theme_key = VALUES(theme_key), floor_key = VALUES(floor_key),
                wall_key = VALUES(wall_key), light_key = VALUES(light_key),
                decor_key = VALUES(decor_key), accent_key = VALUES(accent_key),
                settings = VALUES(settings), updated_by = VALUES(updated_by)
        ]], { houseId, theme, floor, wall, light, decor, accent, json.encode(settings), tostring(cid) })
    end)
    if not saved then
        print(('[cm-house] garage customization save failed for house %s: %s')
            :format(tostring(houseId), tostring(saveError)))
        return false, 'The garage customization could not be saved.'
    end

    local current = GetGarageCustomization(houseId)
    LogHouse(houseId, house.family_id, cid, 'garage_customize', current)
    for _, playerSrc in ipairs(InsideProperty(houseId, 'garage')) do
        TriggerClientEvent('cm-house:client:garageCustomizationChanged', tonumber(playerSrc), current)
    end
    return true, 'Garage customization saved.', current
end)

exports('GetGarageCustomization', function(houseId)
    return GetGarageCustomization(houseId)
end)

exports('SetGarageCustomization', function(houseId, payload, actorCid)
    if not CMHouseIntegrationAllowed or not CMHouseIntegrationAllowed('garage') then
        return false, 'resource_not_authorized'
    end
    houseId = tonumber(houseId)
    payload = type(payload) == 'table' and payload or {}
    local house, template = templateForHouse(houseId)
    if not house then return false, 'house_not_found' end
    if not template then return false, 'garage_not_found' end
    for group, key in pairs({ themes = payload.theme, floors = payload.floor, walls = payload.wall,
        lights = payload.light, decor = payload.decor, accents = payload.accent }) do
        if not optionExists(group, key) then return false, 'invalid_' .. group end
    end
    local saved = pcall(function()
        return MySQL.query.await([[
            INSERT INTO cm_house_garage_customizations
                (house_id, theme_key, floor_key, wall_key, light_key, decor_key, accent_key, settings, updated_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE theme_key=VALUES(theme_key), floor_key=VALUES(floor_key),
                wall_key=VALUES(wall_key), light_key=VALUES(light_key), decor_key=VALUES(decor_key),
                accent_key=VALUES(accent_key), settings=VALUES(settings), updated_by=VALUES(updated_by)
        ]], { houseId, payload.theme, payload.floor, payload.wall, payload.light, payload.decor,
            payload.accent, json.encode(normalizeSettings(payload.settings)), actorCid and tostring(actorCid) or nil })
    end)
    if not saved then return false, 'customization_save_failed' end
    local current = GetGarageCustomization(houseId)
    LogHouse(houseId, house.family_id, actorCid, 'garage_customize', current)
    for _, playerSrc in ipairs(InsideProperty(houseId, 'garage')) do
        TriggerClientEvent('cm-house:client:garageCustomizationChanged', tonumber(playerSrc), current)
    end
    return true, current
end)
