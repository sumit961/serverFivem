local function safeJson(data)
    if data == nil then return nil end
    local ok, encoded = pcall(json.encode, data)
    return ok and encoded or nil
end

local function ensureLogPath(path)
    if not path or path == '' then return false end
    pcall(function() os.execute(('mkdir -p "%s"'):format(path:gsub('"', ''))) end)
    return true
end

local function LogToFile(level, message)
    local cfg = exports['cm-core']:GetConfig('Logging') or {}
    if not cfg.logToFile then return end

    local logPath = cfg.logPath or 'logs/'
    ensureLogPath(logPath)

    local date = os.date('%Y-%m-%d')
    local time = os.date('%H:%M:%S')
    local filename = logPath .. date .. '.log'
    local file = io.open(filename, 'a')
    if file then
        file:write(string.format('[%s] [%s] %s\n', time, tostring(level):upper(), tostring(message)))
        file:close()
    end
end

exports('Log', function(resource, level, message, metadata)
    local cfg = exports['cm-core']:GetConfig('Logging') or {}
    local levels = { debug = 1, info = 2, warn = 3, warning = 3, error = 4 }
    level = tostring(level or 'info'):lower()
    if level == 'warning' then level = 'warn' end

    local cur = levels[tostring(cfg.level or 'info'):lower()] or 2
    local msgLvl = levels[level] or 2
    if msgLvl < cur then return true end

    resource = tostring(resource or GetInvokingResource() or 'unknown')
    message = tostring(message or ''):sub(1, 1000)
    metadata = type(metadata) == 'table' and metadata or nil

    local formatted = string.format('[%s] %s: %s', resource, level, message)
    print(formatted)
    LogToFile(level, formatted)

    if cfg.logToDatabase then
        pcall(function()
            exports['cm-core']:Query(
                'INSERT INTO server_logs (resource, level, category, message, metadata, player_src, player_char_id, player_account_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                {
                    resource,
                    level,
                    metadata and metadata.category or nil,
                    message,
                    safeJson(metadata),
                    metadata and metadata.player_src or nil,
                    metadata and metadata.player_char_id or nil,
                    metadata and metadata.player_account_id or nil,
                }
            )
        end)
    end

    return true
end)

exports('Audit', function(action, data)
    data = type(data) == 'table' and data or {}
    return exports['cm-core']:Log(data.resource or GetInvokingResource() or 'unknown', 'info', tostring(action or 'audit'), {
        category = data.category or 'audit',
        player_src = data.player_src,
        player_char_id = data.player_char_id,
        player_account_id = data.player_account_id,
        action = action,
        data = data,
    })
end)
