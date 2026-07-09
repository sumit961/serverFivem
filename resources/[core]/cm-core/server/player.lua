-- CM-Core player state bridge.
-- cm-playerdata should be the real owner of character data/cash/bank.
-- This cache exists so older CM resources can safely read common state while the framework is being cleaned.

CM = CM or {}
CM.Players = CM.Players or {}

local function shallowCopy(tbl)
    local out = {}
    if type(tbl) ~= 'table' then return out end
    for k, v in pairs(tbl) do out[k] = v end
    return out
end

local function getCharId(data)
    return data and (data.id or data.character_id or data.charId or data.citizenid)
end

local function getAccountId(data)
    return data and (data.account_id or data.accountId or data.account)
end

local function setPlayerState(src, key, value, replicated)
    pcall(function()
        Player(src).state:set(key, value, replicated == true)
    end)
end

local function makePlayer(src, charData, extra)
    charData = shallowCopy(charData or {})
    extra = extra or {}

    local PlayerObject = {}
    PlayerObject.Source = src
    PlayerObject.Character = charData
    PlayerObject.CharacterId = getCharId(charData)
    PlayerObject.AccountId = getAccountId(charData) or extra.accountId
    PlayerObject.CreatedAt = os.time()
    PlayerObject.Metadata = type(charData.metadata) == 'table' and charData.metadata or {}
    PlayerObject.Functions = {}

    function PlayerObject.Functions.GetData()
        return shallowCopy(PlayerObject.Character)
    end

    function PlayerObject.Functions.UpdateData(newData)
        if type(newData) ~= 'table' then return false end
        for k, v in pairs(newData) do PlayerObject.Character[k] = v end
        PlayerObject.CharacterId = getCharId(PlayerObject.Character)
        PlayerObject.AccountId = getAccountId(PlayerObject.Character) or PlayerObject.AccountId
        setPlayerState(src, 'charId', PlayerObject.CharacterId, true)
        setPlayerState(src, 'accountId', PlayerObject.AccountId, true)
        return true
    end

    function PlayerObject.Functions.GetMoney(account)
        return exports['cm-core']:GetMoney(src, account)
    end

    function PlayerObject.Functions.AddMoney(account, amount, reason)
        return exports['cm-core']:AddMoney(src, account, amount, reason)
    end

    function PlayerObject.Functions.RemoveMoney(account, amount, reason)
        return exports['cm-core']:RemoveMoney(src, account, amount, reason)
    end

    function PlayerObject.Functions.SetMoney(account, amount, reason)
        return exports['cm-core']:SetMoney(src, account, amount, reason)
    end

    function PlayerObject.Functions.SetJob(job, grade, onDuty)
        PlayerObject.Character.job = tostring(job or 'unemployed')
        PlayerObject.Character.job_grade = tonumber(grade) or 0
        PlayerObject.Character.onDuty = onDuty == true
        setPlayerState(src, 'job', PlayerObject.Character.job, true)
        setPlayerState(src, 'jobGrade', PlayerObject.Character.job_grade, true)
        setPlayerState(src, 'onDuty', PlayerObject.Character.onDuty, true)
        return true
    end

    function PlayerObject.Functions.Save()
        -- Core no longer owns full character saving. Delegate to cm-playerdata if available.
        if GetResourceState('cm-playerdata') == 'started' then
            local ok, result = pcall(function()
                if exports['cm-playerdata'].SavePlayer then
                    return exports['cm-playerdata']:SavePlayer(src)
                end
            end)
            if ok and result ~= nil then return result end
        end

        -- Legacy fallback: save only common cash/bank/job columns if the old characters table exists.
        if not PlayerObject.CharacterId then return false, 'no_character_id' end
        local ok = pcall(function()
            exports['cm-core']:Update('UPDATE characters SET cash = ?, bank = ?, job = ?, job_grade = ?, last_played = NOW() WHERE id = ?', {
                tonumber(PlayerObject.Character.cash) or 0,
                tonumber(PlayerObject.Character.bank) or 0,
                PlayerObject.Character.job or 'unemployed',
                tonumber(PlayerObject.Character.job_grade) or 0,
                PlayerObject.CharacterId
            })
        end)
        return ok
    end

    return PlayerObject
end

exports('RegisterPlayer', function(src, charData, extra)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil, 'invalid_source' end
    if type(charData) ~= 'table' then return nil, 'invalid_character_data' end

    local player = makePlayer(src, charData, extra)
    CM.Players[src] = player

    setPlayerState(src, 'charId', player.CharacterId, true)
    setPlayerState(src, 'accountId', player.AccountId, true)
    setPlayerState(src, 'cash', tonumber(player.Character.cash) or 0, true)
    setPlayerState(src, 'bank', tonumber(player.Character.bank) or 0, true)
    setPlayerState(src, 'job', player.Character.job or 'unemployed', true)
    setPlayerState(src, 'jobGrade', tonumber(player.Character.job_grade) or 0, true)
    setPlayerState(src, 'isLoggedIn', true, true)

    TriggerEvent('cm-core:server:playerRegistered', src, player)
    return player
end)

exports('GetPlayer', function(src)
    return CM.Players[tonumber(src)]
end)

exports('GetPlayers', function()
    return CM.Players
end)

exports('GetCharacter', function(src)
    local player = CM.Players[tonumber(src)]
    return player and player.Character or nil
end)

exports('GetCharacterId', function(src)
    src = tonumber(src)
    if not src then return nil end

    if GetResourceState('cm-playerdata') == 'started' then
        local ok, charId = pcall(function() return exports['cm-playerdata']:GetCharacterId(src) end)
        if ok and charId then return charId end
    end

    local player = CM.Players[src]
    if player and player.CharacterId then return player.CharacterId end

    local ok, stateChar = pcall(function() return Player(src).state.charId end)
    return ok and stateChar or nil
end)

exports('GetAccountId', function(src)
    src = tonumber(src)
    if not src then return nil end
    local player = CM.Players[src]
    if player and player.AccountId then return player.AccountId end
    local ok, stateAccount = pcall(function() return Player(src).state.accountId end)
    return ok and stateAccount or nil
end)

exports('IsPlayerLoaded', function(src)
    return exports['cm-core']:GetCharacterId(src) ~= nil
end)

exports('UpdatePlayerData', function(src, data)
    local player = CM.Players[tonumber(src)]
    if not player then return false, 'player_not_loaded' end
    return player.Functions.UpdateData(data)
end)

exports('RemovePlayer', function(src, reason)
    src = tonumber(src)
    local player = CM.Players[src]
    if not player then return false end

    pcall(function() player.Functions.Save() end)
    TriggerEvent('cm-core:server:playerRemoved', src, player, reason or 'unknown')
    CM.Players[src] = nil

    setPlayerState(src, 'charId', nil, true)
    setPlayerState(src, 'isLoggedIn', false, true)
    return true
end)


exports('GetOnlinePlayer', function(charId)
    if not charId then return nil end
    for src, player in pairs(CM.Players) do
        if player.CharacterId == charId then
            return { src = src, charId = charId, player = player }
        end
    end
    return nil
end)

exports('GetOnlineCount', function()
    local count = 0
    for _ in pairs(CM.Players) do count = count + 1 end
    return count
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    exports['cm-core']:RemovePlayer(src, reason or 'dropped')
end)
