-- ============================================================
-- cm-house | local property photo storage
--
-- screenshot-basic saves the captured frame directly inside this resource:
--   cm-house/html/img/houses/house_<id>.jpg
--
-- New-property photos are held as short-lived pending files until the house
-- row receives its database ID. No webhook, remote host, or client-supplied
-- URL is used.
-- ============================================================

local Pending = {}          -- [token] = { src, houseId|nil, expires }
local Captured = {}         -- [token] = { src, path, filename, expires }
local TOKEN_TTL = 120
local CAPTURE_TIMEOUT_MS = 30000
local PhotoDataCache = {}   -- [houseId] = { version, dataUri, touched }
local PhotoReadRate = {}    -- [src] = { startedMs, count }

local BASE64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function encodeBase64Chunk(data, first, last)
    local out = {}
    local outIndex = 1
    local i = first
    while i <= last do
        local a = data:byte(i) or 0
        local b = data:byte(i + 1)
        local c = data:byte(i + 2)
        local value = a * 65536 + (b or 0) * 256 + (c or 0)

        local c1 = math.floor(value / 262144) % 64
        local c2 = math.floor(value / 4096) % 64
        local c3 = math.floor(value / 64) % 64
        local c4 = value % 64

        out[outIndex] = BASE64_ALPHABET:sub(c1 + 1, c1 + 1)
            .. BASE64_ALPHABET:sub(c2 + 1, c2 + 1)
            .. (b and BASE64_ALPHABET:sub(c3 + 1, c3 + 1) or '=')
            .. (c and BASE64_ALPHABET:sub(c4 + 1, c4 + 1) or '=')
        outIndex = outIndex + 1
        i = i + 3
    end
    return table.concat(out)
end

local function base64Encode(data)
    if type(data) ~= 'string' or data == '' then return nil end
    -- Encode in bounded chunks so a large screenshot does not create a giant
    -- temporary bit-string or block the Lua allocator with millions of items.
    local chunks = {}
    local chunkBytes = 24576 -- divisible by 3
    local first = 1
    while first <= #data do
        local last = math.min(#data, first + chunkBytes - 1)
        chunks[#chunks + 1] = encodeBase64Chunk(data, first, last)
        first = last + 1
    end
    return table.concat(chunks)
end

local function invalidatePhotoData(houseId)
    houseId = tonumber(houseId)
    if houseId then PhotoDataCache[houseId] = nil end
end

local function prunePhotoDataCache()
    local maxEntries = math.max(1, tonumber(Config.Photo and Config.Photo.cacheEntries) or 12)
    local count = 0
    local oldestHouse, oldestTouched
    for houseId, item in pairs(PhotoDataCache) do
        count = count + 1
        local touched = tonumber(item.touched) or 0
        if oldestTouched == nil or touched < oldestTouched then
            oldestHouse, oldestTouched = houseId, touched
        end
    end
    while count > maxEntries and oldestHouse do
        PhotoDataCache[oldestHouse] = nil
        count = count - 1
        oldestHouse, oldestTouched = nil, nil
        for houseId, item in pairs(PhotoDataCache) do
            local touched = tonumber(item.touched) or 0
            if oldestTouched == nil or touched < oldestTouched then
                oldestHouse, oldestTouched = houseId, touched
            end
        end
    end
end

local function allowPhotoRead(src)
    local now = GetGameTimer()
    local windowMs = math.max(1000, tonumber(Config.Photo and Config.Photo.requestWindowMs) or 5000)
    local limit = math.max(1, tonumber(Config.Photo and Config.Photo.requestsPerWindow) or 4)
    local rec = PhotoReadRate[src]
    if not rec or now - rec.startedMs >= windowMs then
        PhotoReadRate[src] = { startedMs = now, count = 1 }
        return true
    end
    if rec.count >= limit then return false end
    rec.count = rec.count + 1
    return true
end

local function playerNearPoint(src, point, maxDistance)
    if type(point) ~= 'table' then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
    if not x or not y or not z then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(x, y, z)) <= (tonumber(maxDistance) or 8.0)
end

local function canReadHousePhoto(src, house)
    if not src or src <= 0 or not house then return false end
    if IsRealStaff(src) then return true end
    local insideHouse = WhereIs(src)
    if tonumber(insideHouse) == tonumber(house.id) then return true end
    if GetPlayerRoutingBucket(src) ~= 0 then return false end
    return playerNearPoint(src, house.door_coords, math.max(8.0, (tonumber(Config.Prompt and Config.Prompt.distance) or 2.0) + 5.0))
end

local function photoDirectory()
    local relative = tostring(Config.Photo and Config.Photo.directory or 'html/img/houses')
    relative = relative:gsub('\\', '/'):gsub('^/+', ''):gsub('/+$', '')
    if relative == '' or relative:find('..', 1, true) then
        relative = 'html/img/houses'
    end
    return relative
end

local function resourcePhotoPath(filename)
    return ('%s/%s/%s'):format(GetResourcePath(GetCurrentResourceName()), photoDirectory(), filename)
end

local function localPhotoUrl(filename, version)
    return ('img/houses/%s?v=%s'):format(filename, tostring(version or os.time()))
end

local function fileExists(path)
    local f = io.open(path, 'rb')
    if not f then return false end
    local size = f:seek('end') or 0
    f:close()
    return size > 0
end

local function copyFile(sourcePath, targetPath)
    local source = io.open(sourcePath, 'rb')
    if not source then return false, 'source_open_failed' end
    local data = source:read('*a')
    source:close()
    if not data or #data == 0 then return false, 'source_empty' end

    local target = io.open(targetPath, 'wb')
    if not target then return false, 'target_open_failed' end
    local ok, err = target:write(data)
    target:close()
    if not ok then return false, err or 'target_write_failed' end
    return true
end

-- Installs a newly captured temporary file without destroying the previous
-- property photo until the new file is known to be valid. The returned
-- finalizer commits the replacement when passed true, or restores the old
-- image when passed false.
local function installHousePhoto(tempPath, houseId)
    houseId = tonumber(houseId)
    if not houseId or not fileExists(tempPath) then
        return nil, 'captured_photo_missing'
    end

    local filename = ('house_%d.jpg'):format(houseId)
    local targetPath = resourcePhotoPath(filename)
    local backupPath = targetPath .. '.previous'
    pcall(os.remove, backupPath)

    local hadPrevious = fileExists(targetPath)
    if hadPrevious then
        local backedUp = os.rename(targetPath, backupPath)
        if not backedUp then
            local copied, copyWhy = copyFile(targetPath, backupPath)
            if not copied then return nil, copyWhy or 'photo_backup_failed' end
            pcall(os.remove, targetPath)
        end
    end

    local installed = os.rename(tempPath, targetPath)
    if not installed then
        local copied, copyWhy = copyFile(tempPath, targetPath)
        if copied then pcall(os.remove, tempPath) end
        installed = copied
        if not installed then
            if hadPrevious and fileExists(backupPath) then
                pcall(os.rename, backupPath, targetPath)
            end
            return nil, copyWhy or 'photo_install_failed'
        end
    end

    local finalized = false
    local function finish(commit)
        if finalized then return end
        finalized = true
        if commit == true then
            pcall(os.remove, backupPath)
            return
        end
        pcall(os.remove, targetPath)
        if hadPrevious and fileExists(backupPath) then
            local restored = os.rename(backupPath, targetPath)
            if not restored then
                local copied = copyFile(backupPath, targetPath)
                if copied then pcall(os.remove, backupPath) end
            end
        else
            pcall(os.remove, backupPath)
        end
    end

    invalidatePhotoData(houseId)
    return {
        filename = filename,
        path = targetPath,
        url = localPhotoUrl(filename, os.time()),
        finish = finish,
    }
end

local function newToken(src, houseId)
    local token = ('%d.%d.%d'):format(src, os.time(), math.random(100000, 999999))
    Pending[token] = {
        src = src,
        houseId = tonumber(houseId),
        expires = os.time() + TOKEN_TTL,
    }
    return token
end

local function consume(token, src)
    token = tostring(token or '')
    local rec = Pending[token]
    if not rec then return nil end
    Pending[token] = nil
    if rec.src ~= src or os.time() > rec.expires then return nil end
    return rec
end

local function safeCamera(cam)
    if type(cam) ~= 'table' then return nil end
    local function n(v, min, max)
        v = tonumber(v)
        if not v or v ~= v or v < min or v > max then return nil end
        return v + 0.0
    end

    local x = n(cam.x, -10000.0, 10000.0)
    local y = n(cam.y, -10000.0, 10000.0)
    local z = n(cam.z, -1000.0, 5000.0)
    local rx = n(cam.rx or 0.0, -360.0, 360.0)
    local rz = n(cam.rz or 0.0, -360.0, 360.0)
    local fov = n(cam.fov or 55.0, 10.0, 120.0)
    if not x or not y or not z or not rx or not rz or not fov then return nil end
    return { x = x, y = y, z = z, rx = rx, ry = 0.0, rz = rz, fov = fov }
end

function PhotoReady()
    if GetResourceState('screenshot-basic') ~= 'started' then
        return false, 'screenshot-basic is not running.'
    end
    return true
end

local function requestServerCapture(src, token, houseId)
    local safeToken = tostring(token):gsub('[^%w%-_%.]', '_')
    -- Always capture into a unique temporary file. A permanent house photo is
    -- replaced only after the capture and database update both succeed.
    local filename = ('pending_%s.jpg'):format(safeToken)
    local path = resourcePhotoPath(filename)
    pcall(os.remove, path)

    local promiseResult = promise.new()
    local resolved = false
    local function finish(value)
        if resolved then return end
        resolved = true
        promiseResult:resolve(value)
    end

    local ok, callErr = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(src, {
            fileName = path,
            encoding = 'jpg',
            quality = math.max(0.1, math.min(1.0, tonumber(Config.Photo.quality) or 0.92)),
        }, function(err, savedPath)
            if err then
                pcall(os.remove, path)
                return finish({ ok = false, error = tostring(err) })
            end
            local actualPath = type(savedPath) == 'string' and savedPath ~= '' and savedPath or path
            if not fileExists(actualPath) and actualPath ~= path and fileExists(path) then actualPath = path end
            if not fileExists(actualPath) then
                return finish({ ok = false, error = 'The captured photo file was empty or missing.' })
            end
            finish({ ok = true, path = actualPath, filename = filename })
        end)
    end)

    if not ok then
        pcall(os.remove, path)
        return false, ('Could not request screenshot: %s'):format(tostring(callErr))
    end

    SetTimeout(CAPTURE_TIMEOUT_MS, function()
        pcall(os.remove, path)
        finish({ ok = false, error = 'Screenshot capture timed out.' })
    end)

    local result = Citizen.Await(promiseResult)
    if result.ok ~= true then return false, result.error end
    return true, result
end

-- Move a pending photo into its permanent house filename after the database
-- creates the property ID. Called only by sv_create.lua.
function FinalizePendingHousePhoto(token, src, houseId)
    token = tostring(token or '')
    houseId = tonumber(houseId)
    local rec = Captured[token]
    if not rec or not houseId then return nil, 'pending_photo_not_found' end
    if rec.src ~= src or os.time() > rec.expires then
        pcall(os.remove, rec.path)
        Captured[token] = nil
        return nil, 'pending_photo_expired'
    end
    if not fileExists(rec.path) then
        Captured[token] = nil
        return nil, 'pending_photo_missing'
    end

    local installed, reason = installHousePhoto(rec.path, houseId)
    if not installed then return nil, reason end

    local affected = MySQL.update.await(
        'UPDATE cm_houses SET image_url = ? WHERE id = ?',
        { installed.url, houseId })
    if not affected or tonumber(affected) <= 0 then
        installed.finish(false)
        return nil, 'property_photo_database_update_failed'
    end

    installed.finish(true)
    Captured[token] = nil
    return installed.url
end

function DiscardPendingHousePhoto(token, src)
    token = tostring(token or '')
    local rec = Captured[token]
    if not rec or (src and rec.src ~= src) then return false end
    pcall(os.remove, rec.path)
    Captured[token] = nil
    return true
end

function DeleteHousePhoto(houseId)
    houseId = tonumber(houseId)
    invalidatePhotoData(houseId)
    if not houseId then return false, 'invalid_house_id' end
    local path = resourcePhotoPath(('house_%d.jpg'):format(houseId))
    if not fileExists(path) then return true, 'no_photo_file' end
    local ok, reason = os.remove(path)
    if ok == nil then return false, tostring(reason or 'photo_delete_failed') end
    return true
end
exports('DeleteHousePhoto', function(houseId)
    local invoker = GetInvokingResource()
    if invoker and invoker ~= GetCurrentResourceName() then
        local grants = Config.Integration and Config.Integration.authorizedResources
            and Config.Integration.authorizedResources[invoker]
        local allowed = grants == true or (type(grants) == 'table'
            and (grants['*'] == true or grants.admin == true))
        if not allowed then return false, 'resource_not_authorized' end
    end
    return DeleteHousePhoto(houseId)
end)

RegisterNetEvent('cm-house:server:discardPendingPhoto', function(token)
    DiscardPendingHousePhoto(token, source)
end)

AddEventHandler('playerDropped', function()
    local src = source
    PhotoReadRate[src] = nil
    for token, rec in pairs(Pending) do
        if rec.src == src then Pending[token] = nil end
    end
    for token, rec in pairs(Captured) do
        if rec.src == src then
            pcall(os.remove, rec.path)
            Captured[token] = nil
        end
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for token, rec in pairs(Pending) do
            if now > rec.expires then Pending[token] = nil end
        end
        for token, rec in pairs(Captured) do
            if now > rec.expires then
                pcall(os.remove, rec.path)
                Captured[token] = nil
            end
        end
    end
end)

lib.callback.register('cm-house:server:requestCapture', function(src, houseId)
    if houseId then
        if not HasHouseStaffPermission(src, 'photos') then return false, 'You cannot retake property photos.' end
    elseif not IsHouseAdmin(src) then
        return false, 'You cannot take property photos.'
    end
    local ok, why = PhotoReady()
    if not ok then return false, why end

    houseId = tonumber(houseId)
    if houseId and not Houses[houseId] then
        return false, 'That property no longer exists.'
    end

    return true, {
        token = newToken(src, houseId),
        quality = Config.Photo.quality,
    }
end)

lib.callback.register('cm-house:server:capturePhoto', function(src, token, cam)
    local rec = consume(token, src)
    if not rec then return false, 'That capture expired. Try again.' end
    if rec.houseId then
        if not HasHouseStaffPermission(src, 'photos') then return false, 'You cannot retake property photos.' end
    elseif not IsHouseAdmin(src) then
        return false, 'You cannot take property photos.'
    end

    local cleanCam = safeCamera(cam)
    if not cleanCam then return false, 'The photo camera data is invalid.' end

    local ok, captured = requestServerCapture(src, token, rec.houseId)
    if not ok then return false, captured end

    if not rec.houseId then
        Captured[tostring(token)] = {
            src = src,
            path = captured.path,
            filename = captured.filename,
            expires = os.time() + math.max(5, tonumber(Config.Photo.pendingMinutes) or 20) * 60,
        }
        return true, localPhotoUrl(captured.filename, os.time())
    end

    local house = Houses[rec.houseId]
    if not house then
        pcall(os.remove, captured.path)
        return false, 'That property no longer exists.'
    end

    local installed, installWhy = installHousePhoto(captured.path, rec.houseId)
    if not installed then return false, installWhy or 'The property photo file could not be installed.' end

    local url = installed.url
    local affected = MySQL.update.await(
        'UPDATE cm_houses SET image_url = ?, photo_cam = ? WHERE id = ?',
        { url, json.encode(cleanCam), rec.houseId })
    if not affected or tonumber(affected) <= 0 then
        installed.finish(false)
        return false, 'The property photo could not be saved.'
    end
    installed.finish(true)

    house.image_url = url
    house.photo_cam = cleanCam
    Audit(src, 'photo_capture_local', { houseId = rec.houseId, file = installed.filename })
    TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(house))
    return true, url
end)

lib.callback.register('cm-house:server:storePhoto', function()
    return false, 'Client-side photo paths are disabled. Use the server capture flow.'
end)

lib.callback.register('cm-house:server:retakePhoto', function(src, houseId)
    if not HasHouseStaffPermission(src, 'photos') then return false, 'Not permitted.' end
    local ok, why = PhotoReady()
    if not ok then return false, why end

    houseId = tonumber(houseId)
    local house = houseId and Houses[houseId] or nil
    if not house then return false, 'That property does not exist.' end

    return true, {
        token = newToken(src, houseId),
        quality = Config.Photo.quality,
        cam = house.photo_cam,
        door = house.door_coords,
    }
end)

local function getHousePhotoDataUri(houseId)
    houseId = tonumber(houseId)
    local house = houseId and Houses[houseId] or nil
    if not house then return nil, 'property_not_found' end

    local filename = ('house_%d.jpg'):format(houseId)
    local path = resourcePhotoPath(filename)
    local file = io.open(path, 'rb')
    if not file then return nil, 'photo_file_missing' end
    local size = file:seek('end') or 0
    file:seek('set', 0)
    local maxBytes = math.max(65536, tonumber(Config.Photo and Config.Photo.maxBytes) or 1572864)
    if size <= 0 or size > maxBytes then
        file:close()
        return nil, size > maxBytes and 'photo_file_too_large' or 'photo_file_empty'
    end

    local version = tostring(house.image_url or filename) .. ':' .. tostring(size)
    local cached = PhotoDataCache[houseId]
    if cached and cached.version == version and type(cached.dataUri) == 'string' then
        cached.touched = os.time()
        file:close()
        return cached.dataUri
    end

    local raw = file:read('*a')
    file:close()
    if not raw or #raw ~= size then return nil, 'photo_file_read_failed' end
    local encoded = base64Encode(raw)
    if not encoded then return nil, 'photo_encode_failed' end

    local dataUri = 'data:image/jpeg;base64,' .. encoded
    PhotoDataCache[houseId] = {
        version = version,
        dataUri = dataUri,
        touched = os.time(),
    }
    prunePhotoDataCache()
    return dataUri
end

lib.callback.register('cm-house:server:getPhotoData', function(src, houseId)
    houseId = tonumber(houseId)
    local house = houseId and Houses[houseId] or nil
    if not house then return false, 'That property does not exist.' end
    if not canReadHousePhoto(src, house) then return false, 'Move closer to the property.' end
    if not allowPhotoRead(src) then return false, 'Property photo requests are temporarily limited.' end

    local dataUri, why = getHousePhotoDataUri(houseId)
    if not dataUri then return false, why or 'The property photo is unavailable.' end
    return true, dataUri
end)

exports('GetPropertyPhotoData', function(houseId)
    return getHousePhotoDataUri(houseId)
end)

exports('GetPropertyPhoto', function(houseId)
    local house = Houses[tonumber(houseId)]
    if not house then return nil end
    return house.image_url, house.photo_cam
end)

exports('GetPropertyPhotoFile', function(houseId)
    houseId = tonumber(houseId)
    if not houseId then return nil end
    local filename = ('house_%d.jpg'):format(houseId)
    local path = resourcePhotoPath(filename)
    if not fileExists(path) then return nil end
    return path, localPhotoUrl(filename, os.time())
end)
