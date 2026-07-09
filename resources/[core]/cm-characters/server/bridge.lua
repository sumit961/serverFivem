-- cm-characters/server/bridge.lua
-- Connects cm-auth/login to character selector. Client can never choose accountId.


-- Production-safe local logger wrapper.
-- When Config.Debug/Config.VerboseLogs is false, normal CM-CHARACTERS debug prints are hidden.
-- Warnings/errors still print so real problems are visible.
local __cmCharactersPrint = print
local function __cmCharactersShouldVerbose()
    return Config and (Config.Debug == true or Config.VerboseLogs == true or Config.ProductionMode == false)
end
local function print(...)
    if __cmCharactersShouldVerbose() then
        return __cmCharactersPrint(...)
    end

    local first = tostring(select(1, ...) or '')
    local isCmCharactersLog = first:find('%[CM%-CHARACTERS') ~= nil
    if not isCmCharactersLog then
        return __cmCharactersPrint(...)
    end

    local upper = first:upper()
    if upper:find('ERROR', 1, true) or upper:find('WARNING', 1, true) or upper:find('FAILED', 1, true) or upper:find('DENIED', 1, true) then
        return __cmCharactersPrint(...)
    end
end

-- v1.5.1: server-side open debounce. cm-auth and spawn fallback may both ask
-- to open the selector during the same login. Client also has a guard, but this
-- reduces duplicated network events and loading messages.
local lastSelectorOpenAt = {}

local function openSelectorOnce(src, accountId, reason, force)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    accountId = tostring(accountId or '')
    if accountId == '' then return false end

    local now = GetGameTimer()
    local last = tonumber(lastSelectorOpenAt[src] or 0) or 0
    if force ~= true and last > 0 and (now - last) < 2500 then
        print(('[CM-CHARACTERS] openSelector skipped duplicate: src=%s account=%s reason=%s'):format(src, accountId, tostring(reason or 'unknown')))
        return true
    end

    lastSelectorOpenAt[src] = now
    TriggerClientEvent('cm-characters:client:openSelector', src, accountId)
    return true
end

AddEventHandler('playerDropped', function()
    lastSelectorOpenAt[source] = nil
end)

exports('OpenCharacterSelector', function(src, accountId)
    src = tonumber(src)
    if not src or src <= 0 then return false end

    -- Server export is meant for cm-auth/cm-core after login. It may set account state,
    -- but normal client events/NUICallbacks are never allowed to override it.
    if accountId ~= nil and tostring(accountId) ~= '' then
        Player(src).state:set('accountId', tostring(accountId), true)
    end

    local stateAccountId = CMCharacters.RequireAccount(src)
    if not stateAccountId then return false end

    Player(src).state:set('isLoggedIn', true, true)
    return openSelectorOnce(src, stateAccountId, 'export_open', false)
end)

RegisterCommand('char', function(source, args)
    local src = source
    local hasPermission = CMCharacters.HasPermission(src, 'command.char')
    if not hasPermission then
        CMCharacters.Notify(src, 'No permission to use /char.', 'error')
        return
    end

    if Config and Config.EnableManualSelectorCommand ~= true and Config.EnableDevCommands ~= true then
        CMCharacters.Notify(src, '/char is disabled in production. Open character selector through cm-auth or cm-admin.', 'error')
        return
    end

    local accountId = CMCharacters.GetAccountId(src)
    if not accountId and args[1] and tostring(args[1]) ~= '' then
        -- Dev/admin only, for local testing when auth state is not present.
        accountId = tostring(args[1])
        Player(src).state:set('accountId', accountId, true)
        Player(src).state:set('isLoggedIn', true, true)
    end

    if not accountId then
        CMCharacters.Notify(src, 'No accountId in state. Login first or use /char [accountId] as admin/dev.', 'error')
        return
    end

    CMCharacters.ClearCharacterState(src)
    CMCharacters.LogAdmin(src, 'manual_open_selector', { account_id = accountId })
    openSelectorOnce(src, accountId, 'command_char', true)
end, false)

-- Auto-open on first spawn fallback if cm-auth does not trigger it.
AddEventHandler('playerSpawned', function(src)
    src = tonumber(src) or source
    SetTimeout(3000, function()
        if not src or src <= 0 then return end
        local accountId = CMCharacters.GetAccountId(src)
        local isLoggedIn = Player(src).state.isLoggedIn
        local charId = Player(src).state.charId

        if accountId and isLoggedIn and not charId then
            openSelectorOnce(src, accountId, 'spawn_fallback', false)
        end
    end)
end)
