function GetPlayer(source)
    if Framework.IsESX then
        local xPlayer = Core.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer
        end
    elseif Framework.IsQB then
        local Player = Core.Functions.GetPlayer(source)
        if Player then
            return Player
        end
    end
end

function GetIdentifier(source)
    local identifier = nil
    if Framework.IsESX then
        local xPlayer = Core.GetPlayerFromId(source)
        if xPlayer then
            identifier = xPlayer.getIdentifier()
        end
    elseif Framework.IsQB then
        local Player = Core.Functions.GetPlayer(source)
        if Player then
            identifier = Player.PlayerData.citizenid
        end
    end
    return identifier
end

function RemoveMoney(source, type, amount)
    local Player = GetPlayer(source)
    if Framework.IsESX then
        if type == 'cash' then
            return Player.removeMoney(amount, 'Fishing Purchase')
        elseif type == 'bank' then
            return Player.removeAccountMoney('bank', amount)
        end
    elseif Framework.IsQB then
        return Player.Functions.RemoveMoney(type, amount, 'fishing-purchase')
    end
end

function GetPlayerMoney(source, type)
    local Player = GetPlayer(source)
    if Framework.IsESX then
        if type == 'cash' then
            return Player.getAccount('money').money
        elseif type == 'bank' then
            return Player.getAccount('bank').money
        end
    elseif Framework.IsQB then
        return Player.Functions.GetMoney(type)
    end
end

function AddMoney(source, type, amount)
    local Player = GetPlayer(source)
    if Framework.IsESX then
        if type == 'cash' then
            return Player.addMoney(amount)
        elseif type == 'bank' then
            return Player.addAccountMoney('bank', amount)
        end
    elseif Framework.IsQB then
        return Player.Functions.AddMoney(type, amount, 'fishing-sell')
    end
end

function AddItem(source, item, amount)
    local Player = GetPlayer(source)
    if Framework.IsESX then
        return Player.addInventoryItem(item, amount)
    elseif Framework.IsQB then
        return Player.Functions.AddItem(item, amount)
    end
end

function RemoveItem(source, item, amount)
    local Player = GetPlayer(source)
    if Framework.IsESX then
        return Player.removeInventoryItem(item, amount)
    elseif Framework.IsQB then
        return Player.Functions.RemoveItem(item, amount)
    end
end

function GetCountItems(source, itemName)
    local Player = GetPlayer(source)
    if not Player then return 0 end
    if Framework.IsESX then
        local inv = Player.getInventoryItem(itemName)
        return inv and inv.count or 0
    elseif Framework.IsQB then
        local item = Player.Functions.GetItemByName(itemName)
        return item and item.amount or 0
    end
    return 0
end

function CreateUseableItem(item, func)
    if Framework.IsESX then
        Core.RegisterUsableItem(item, func)
    elseif Framework.IsQB then
        Core.Functions.CreateUseableItem(item, func)
    end
end

function CanCarryItem(source, item, count)
    local Player = GetPlayer(source)
    if Framework.IsESX then
        return Player.canCarryItem(item, count)
    elseif Framework.IsQB then
        if GetResourceState('qb-inventory') == 'started' then
            local canAdd, reason = exports['qb-inventory']:CanAddItem(source, item, count)
            return canAdd
        elseif GetResourceState('ox_inventory') == 'started' then
            return exports.ox_inventory:CanCarryItem(source, item, count)
        end
    end
    return false
end
