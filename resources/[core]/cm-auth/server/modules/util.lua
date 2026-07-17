-- cm-auth/server/modules/util.lua
-- Shared server helpers: debug printing, structured logging, player notify,
-- input sanitizing, and safe (pcall-wrapped) oxmysql query wrappers.
-- Exposed on a single module table to keep the global namespace clean.

local Util = {}

function Util.dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    local msg = '[CM-AUTH-DEBUG] '
    for i = 1, #args do msg = msg .. tostring(args[i]) .. ' ' end
    print(msg)
end

local function shouldPrintLevel(level)
    level = tostring(level or 'info'):lower()
    return Config.Debug or level == 'warning' or level == 'error' or level == 'critical'
end

-- Structured logging through cm-core when present, with a console fallback so
-- warnings/errors are never silently swallowed if cm-core is unavailable.
function Util.log(resource, level, message, metadata)
    metadata = metadata or {}
    metadata.category = metadata.category or 'auth'
    local ok = pcall(function()
        if exports['cm-core'] and exports['cm-core'].Log then
            exports['cm-core'].Log(resource or 'cm-auth', level or 'info', message or '', metadata)
        elseif shouldPrintLevel(level) then
            print(('[CM-AUTH] %s: %s'):format(level or 'info', message or ''))
        end
    end)
    if not ok and shouldPrintLevel(level) then
        print(('[CM-AUTH] %s: %s'):format(level or 'info', message or ''))
    end
end

-- Chat notification helper (console echo when src is 0 / server).
function Util.notify(src, message, msgType)
    if src == 0 then
        print(('[CM-AUTH] %s'):format(message or ''))
        return
    end

    local color = { 210, 210, 210 }
    if msgType == 'success' then
        color = { 90, 220, 160 }
    elseif msgType == 'error' then
        color = { 255, 105, 120 }
    end

    TriggerClientEvent('chat:addMessage', src, {
        color = color,
        args = { 'cm-auth', message or '' }
    })
end

-- Trim, strip nulls. Never trust raw client strings.
function Util.sanitize(value)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('%z', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return value
end

-- ---- oxmysql wrappers (all pcall-guarded; return nil on failure) ------------

local function guarded(kind, sql, params)
    if type(sql) ~= 'string' then
        print(('[CM-AUTH] db%s expected SQL string, got %s'):format(kind, type(sql)))
        return nil
    end
    local ok, result = pcall(function()
        return MySQL[kind].await(sql, params or {})
    end)
    if not ok then
        print(('[CM-AUTH] DB %s failed: %s'):format(kind, tostring(result)))
        Util.dprint('SQL:', sql)
        return nil
    end
    return result
end

function Util.query(sql, params)  return guarded('query',  sql, params) end
function Util.single(sql, params) return guarded('single', sql, params) end
function Util.scalar(sql, params) return guarded('scalar', sql, params) end

_G.CMAuthUtil = Util
return Util
