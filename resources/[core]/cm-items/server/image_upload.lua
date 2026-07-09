local function hasOxmysql()
    return GetResourceState('oxmysql') == 'started' and exports.oxmysql
end

local function normalizeGender(gender)
    gender = tostring(gender or 'male'):lower()
    return gender == 'female' and 'female' or 'male'
end

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64lookup = {}
for i = 1, #b64chars do b64lookup[b64chars:sub(i, i)] = i - 1 end

local function base64Decode(data)
    data = tostring(data or ''):gsub('%s', ''):gsub('^data:image/%w+;base64,', '')
    local out, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c ~= '=' then
            local v = b64lookup[c]
            if v ~= nil then
                buffer = buffer * 64 + v
                bits = bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    out[#out + 1] = string.char(math.floor(buffer / (2 ^ bits)) % 256)
                    buffer = buffer % (2 ^ bits)
                end
            end
        end
    end
    return table.concat(out)
end

local function saveBase64Png(relativeName, dataUri)
    if type(dataUri) ~= 'string' or dataUri == '' then return false, 'no_image_data' end
    local b64 = dataUri:match('^data:image/%w+;base64,(.+)$') or dataUri
    if not b64 or b64 == '' then return false, 'bad_image_data' end
    relativeName = tostring(relativeName or ''):gsub('%.%.', ''):gsub('^/', '')
    if relativeName == '' then return false, 'bad_filename' end

    -- PNG files must be binary bytes. Saving raw base64 text corrupts the image.
    local bytes = base64Decode(b64)
    if not bytes or #bytes < 64 then return false, 'bad_image_data' end

    local ok = SaveResourceFile(GetCurrentResourceName(), 'ui/images/clothing/' .. relativeName, bytes, #bytes)
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
