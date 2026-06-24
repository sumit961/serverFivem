local function hasOxmysql()
    return GetResourceState('oxmysql') == 'started' and exports.oxmysql
end

local function normalizeGender(gender)
    gender = tostring(gender or 'male'):lower()
    return gender == 'female' and 'female' or 'male'
end

local function saveBase64Png(relativeName, dataUri)
    if type(dataUri) ~= 'string' or dataUri == '' then return false, 'no_image_data' end
    local b64 = dataUri:match('^data:image/%w+;base64,(.+)$') or dataUri
    if not b64 or b64 == '' then return false, 'bad_image_data' end
    relativeName = tostring(relativeName or ''):gsub('%.%.', ''):gsub('^/', '')
    if relativeName == '' then return false, 'bad_filename' end
    local ok = SaveResourceFile(GetCurrentResourceName(), 'ui/images/clothing/' .. relativeName, b64, -1)
    if not ok then return false, 'save_failed' end
    return true
end

local function upsertCatalogImage(entry, imageName)
    if not hasOxmysql() then return false, 'oxmysql_not_started' end
    local gender = normalizeGender(entry.gender)
    local componentType = tostring(entry.componentType or entry.component_type or 'component'):lower()
    local componentIndex = tonumber(entry.componentIndex or entry.component_index)
    local drawableId = tonumber(entry.drawableId or entry.drawable_id)
    local textureId = tonumber(entry.textureId or entry.texture_id)
    if textureId == nil then textureId = -1 end
    if not componentIndex or not drawableId then return false, 'bad_component' end

    exports.oxmysql:executeSync([[
        INSERT INTO clothing_catalog
          (gender, component_type, component_index, drawable_id, texture_id, image, enabled)
        VALUES (?, ?, ?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE image = VALUES(image), updated_at = CURRENT_TIMESTAMP
    ]], { gender, componentType, componentIndex, drawableId, textureId, imageName })

    if CMItems and CMItems.ReloadClothingCatalog then CMItems.ReloadClothingCatalog() end
    return true
end

exports('SaveClothingImage', function(entry, dataUri)
    entry = type(entry) == 'table' and entry or {}
    local gender = normalizeGender(entry.gender)
    local componentType = tostring(entry.componentType or entry.component_type or 'component'):lower()
    local componentIndex = tonumber(entry.componentIndex or entry.component_index)
    local drawableId = tonumber(entry.drawableId or entry.drawable_id)
    local textureId = tonumber(entry.textureId or entry.texture_id)
    if textureId == nil then textureId = 0 end
    if not componentIndex or not drawableId then return false, 'bad_component' end

    local propPrefix = componentType == 'prop' and 'prop_' or ''
    local fileName = ('custom/%s_%s%s_%s_%s.png'):format(gender, propPrefix, componentIndex, drawableId, textureId)
    local ok, err = saveBase64Png(fileName, dataUri)
    if not ok then return false, err end
    return upsertCatalogImage(entry, fileName)
end)
