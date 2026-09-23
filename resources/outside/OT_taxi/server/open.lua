if Config.Framework == 'ESX' then
    ESX = exports['es_extended']:getSharedObject()
elseif Config.Framework == 'QBCORE' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif Config.Framework == 'OX' then
    local file = ('imports/%s.lua'):format(IsDuplicityVersion() and 'server' or 'client')
    local import = LoadResourceFile('ox_core', file)
    local chunk = assert(load(import, ('@@ox_core/%s'):format(file)))
    chunk()
end

function GetPlayerIdentifier(src)
    if Config.Framework == 'OX' then
        local player = Ox.GetPlayer(src)
        return player.charid
    elseif Config.Framework == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer.identifier
    elseif Config.Framework == 'QBCORE' then
        local Player = QBCore.Functions.GetPlayer(src)
        return Player.PlayerData.citizenid
    end
end

function getPlayerName(src)
    if Config.Framework == 'OX' then
        local player = Ox.GetPlayer(src)
        return player.name
    elseif Config.Framework == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer.getName()
    elseif Config.Framework == 'QBCORE' then
        local Player = QBCore.Functions.GetPlayer(src)
        return Player.PlayerData.name
    end
end

function addItem(src, name, count)
    if Config.inventory == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer.canCarryItem(name, count) then
            xPlayer.addInventoryItem(name, count)
            return true
        else
            return false
        end
    elseif Config.inventory == 'OX' then
        local canCarryItem = exports.ox_inventory:CanCarryItem(src, name, count)
        if canCarryItem then
            exports.ox_inventory:AddItem(src, name, count)
            return true
        else
            return false
        end
    elseif Config.inventory == 'QBCORE' then
        local Player = QBCore.Functions.GetPlayer(src)
        Player.Functions.AddItem(name, count)
        return true
    end
end

function addMoney(src, type, count, reason)
    if Config.inventory == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            xPlayer.addAccountMoney(type, count, reason)
            return true
        else
            return false
        end
    elseif Config.inventory == 'OX' then
        exports.ox_inventory:AddItem(src, 'money', count)
        return true
    elseif Config.inventory == 'QBCORE' then
        local Player = QBCore.Functions.GetPlayer(src)
        Player.Functions.AddMoney(type == 'money' and 'cash' or type, count, reason)
        return true
    end
end

function removeMoney(src, type, count, reason)
    if Config.inventory == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            xPlayer.removeAccountMoney(type, count, reason)
            return true
        else
            return false
        end
    elseif Config.inventory == 'OX' then
        exports.ox_inventory:RemoveItem(src, 'money', count)
        return true
    elseif Config.inventory == 'QBCORE' then
        local Player = QBCore.Functions.GetPlayer(src)
        Player.Functions.RemoveMoney(type == 'money' and 'cash' or type, count, reason)
        return true
    end
end

function getMoney(src, type)
    if Config.inventory == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local money = xPlayer.getAccount(type).money
            return money and money or 0
        else
            return 0
        end
    elseif Config.inventory == 'OX' then
        local money = exports.ox_inventory:Search(src, 'count', 'money')
        return money and money or 0
    elseif Config.inventory == 'QBCORE' then
        local Player = QBCore.Functions.GetPlayer(src)
        local money = Player.Functions.GetMoney(type == 'money' and 'cash' or type)
        return money and money or 0
    end
end

function payforRental(src, cost)
    local identifier = GetPlayerIdentifier(src)
    if identifier ~= nil then
        if getMoney(src, 'bank') >= cost then
            removeMoney(src, 'bank', cost, 'Vehicle Rental')
            return true
        elseif getMoney(src, 'money') >= cost then
            removeMoney(src, 'money', cost, 'Vehicle Rental')
            return true
        else
            return false
        end
    end
    return false
end

if Config.useOTSkills then
    exports.OT_skills:registerSkill({
        name = Config.skillName,
        multiplier = Config.skillMultiplier,
        maxlevel = Config.skillMaxlevel,
        maxReward = Config.skillMaxReward,
        maxDeduction = Config.skillMaxReward,
        label = Config.skillLabel,
        description = Config.skillDescription
    })
end