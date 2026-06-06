local function LogToFile(level, message)
    local cfg = exports['cm-core']:GetConfig('Logging')
    if not cfg or not cfg.logToFile then return end
    local date = os.date("%Y-%m-%d")
    local time = os.date("%H:%M:%S")
    local filename = (cfg.logPath or "logs/") .. date .. ".log"
    local file = io.open(filename, "a")
    if file then
        file:write(string.format("[%s] [%s] %s\n", time, level:upper(), message))
        file:close()
    end
end

exports('Log', function(resource, level, message, metadata)
    local cfg = exports['cm-core']:GetConfig('Logging')
    if not cfg then return end
    local levels = {debug = 1, info = 2, warn = 3, error = 4}
    local cur = levels[cfg.level] or 2
    local msgLvl = levels[level] or 2
    if msgLvl < cur then return end
    
    local formatted = string.format("[%s] %s: %s", resource or "unknown", level, message)
    print(formatted)
    LogToFile(level, formatted)
    
    if cfg.logToDatabase then
        pcall(function()
            exports['cm-core']:Query(
                'INSERT INTO server_logs (resource, level, category, message, metadata, player_src, player_char_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
                {resource or "unknown", level, metadata and metadata.category or nil, message, metadata and json.encode(metadata) or nil, metadata and metadata.player_src or nil, metadata and metadata.player_char_id or nil}
            )
        end)
    end
end)