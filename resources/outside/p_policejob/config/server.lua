-- server-side configuration

Config.Webhooks = {
    -- Discord webhooks for logging (leave empty to disable)
    band = '',
    bodycam = '',
    breathalyzer = '',
    jail = '',
    cctv = '',
    interactions = '',
    locker = '',
    trash = '',
    mugshot = '',
    trunks = '',
    tickets = '',
    objects = '',
    evidences = '',
    armoury = '',
}


-- Three providers are supported out of the box. Set MediaProvider below to:
-- 'fivemanage' https://fivemanage.com/(default)
-- 'fivemerr' https://fivemerr.com/
-- 'qbox' (https://docs.qbox.re/dashboard/cdn/api/upload-file)

MediaProvider = 'fivemanage'

local function encToMime(encoding)
    if encoding == 'png' then return 'image/png', 'png' end
    if encoding == 'webp' then return 'image/webp', 'webp' end
    return 'image/jpeg', 'jpg'
end

local MEDIA_PROVIDERS = {
    fivemanage = {
        ApiKey = 'KEY_HERE',
        ScreenshotUrl = 'https://api.fivemanage.com/api/v3/file/base64',
        BodycamUrl = 'https://api.fivemanage.com/api/v3/file',
        AuthHeader = function(key) 
            return key 
        end,
        BuildScreenshotRequest = function(base64Data, encoding)
            local mime, ext = encToMime(encoding)
            return json.encode({
                base64 = ('data:%s;base64,%s'):format(mime, base64Data),
                filename = ('screenshot_%s.%s'):format(os.time(), ext),
            }), 'application/json'
        end,
        GetUrl = function(response)
            if type(response) == 'string' then
                local ok, decoded = pcall(json.decode, response)
                if ok then response = decoded end
            end
            if response and response.data and response.data.url then
                return response.data.url
            end
            return nil
        end,
    },
    fivemerr = {
        ApiKey = 'KEY_HERE',
        ScreenshotUrl = 'https://api.fivemerr.com/v1/media/images',
        BodycamUrl = 'https://api.fivemerr.com/v1/media/videos',
        AuthHeader = function(key) return key end,
        BuildScreenshotRequest = function(base64Data, encoding)
            local mime = encToMime(encoding)
            return json.encode({ file = ('data:%s;base64,%s'):format(mime, base64Data) }), 'application/json'
        end,
        GetUrl = function(response)
            if type(response) == 'string' then
                local ok, decoded = pcall(json.decode, response)
                if ok then response = decoded end
            end
            if type(response) == 'table' then
                return response.url or (response.data and response.data.url) or nil
            end
            return nil
        end,
    },
    qbox = {
        ApiKey = 'KEY_HERE',
        ScreenshotUrl = 'https://api.qbox.re/v1/file',
        BodycamUrl = 'https://api.qbox.re/v1/file',
        ClientUpload = true,
        AuthHeader = function(key)
            if key:sub(1, 7):lower() == 'bearer ' then return key end
            return 'Bearer ' .. key
        end,
        BuildScreenshotRequest = function(base64Data, encoding)
            local mime, ext = encToMime(encoding)
            local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
            local lookup = {}
            for i = 1, #alphabet do lookup[alphabet:sub(i, i)] = i - 1 end
            local clean = base64Data:gsub('[^%w%+/=]', '')
            local out, buf, bits = {}, 0, 0
            for i = 1, #clean do
                local c = clean:sub(i, i)
                if c == '=' then break end
                local v = lookup[c]
                if v then
                    buf = (buf << 6) | v
                    bits = bits + 6
                    if bits >= 8 then
                        bits = bits - 8
                        out[#out + 1] = string.char((buf >> bits) & 0xFF)
                        buf = buf & ((1 << bits) - 1)
                    end
                end
            end
            local binary = table.concat(out)
            local boundary = '----p_policejob' .. tostring(math.random(1e9, 9e9))
            local body = table.concat({
                '--' .. boundary,
                ('Content-Disposition: form-data; name="file"; filename="screenshot.%s"'):format(ext),
                'Content-Type: ' .. mime,
                '',
                binary,
                '--' .. boundary .. '--',
                '',
            }, '\r\n')
            return body, 'multipart/form-data; boundary=' .. boundary
        end,
        GetUrl = function(response)
            if type(response) == 'string' then
                local ok, decoded = pcall(json.decode, response)
                if ok then response = decoded end
            end
            if type(response) == 'table' and response.data then
                return response.data.url or response.data.publicUrl or response.data.location or nil
            end
            return nil
        end,
    },
}

local function getProvider()
    return MEDIA_PROVIDERS[MediaProvider] or MEDIA_PROVIDERS.fivemanage
end

-- bodycam video recording configuration (uses the `screencapture` resource)
-- https://github.com/itschip/screencapture
BodycamRecordingConfig = {
    Url = getProvider().BodycamUrl,
    ApiKey = getProvider().AuthHeader(getProvider().ApiKey),
    FormField = 'file',
    GetUrl = function(response) return getProvider().GetUrl(response) end,
}

-- screenshot configuration for photo capture
ScreenshotConfig = {
    Url = getProvider().ScreenshotUrl,
    ApiKey = getProvider().AuthHeader(getProvider().ApiKey),
    Field = 'file',
    Encoding = 'jpg',
    Quality = 0.85,
    ClientUpload = getProvider().ClientUpload or false,
    BuildRequest = function(base64Data, encoding) return getProvider().BuildScreenshotRequest(base64Data, encoding) end,
    GetUrl = function(response) return getProvider().GetUrl(response) end,
}
