local Inventory = {}

---@param source number
---@param itemName string
---@param count number
---@return boolean
function Inventory.giveItem(source, itemName, count)
    local xPlayer = server.getPlayer(source)
    if shared.getFrameworkName() == "esx" then
        return xPlayer.addInventoryItem(itemName, count)
    elseif shared.getFrameworkName() == "qb" then
        return xPlayer.Functions.AddItem(itemName, count)
    elseif shared.getFrameworkName() == "qbx" then
        return xPlayer.Functions.AddItem(itemName, count)
    end
    return false
end

---@param source number
---@param itemName string
---@param count number
---@return boolean
function Inventory.removeItem(source, itemName, count)
    local xPlayer = server.getPlayer(source)
    if shared.getFrameworkName() == "esx" then
        return xPlayer.removeInventoryItem(itemName, count)
    elseif shared.getFrameworkName() == "qb" then
        return xPlayer.Functions.RemoveItem(itemName, count)
    elseif shared.getFrameworkName() == "qbx" then
        return xPlayer.Functions.RemoveItem(itemName, count)
    end
    return false
end

---@param source number
---@param itemName string
---@param count number
---@return boolean
function Inventory.hasItem(source, itemName, amount)
    amount = amount or 1
    local xPlayer = server.getPlayer(source)

    local count = 0
    local item = nil

    if shared.getFrameworkName() == "esx" then
        item = xPlayer.hasItem(itemName)
    else --[[ QB or QBOX ]]
        item = xPlayer.Functions.GetItemByName(itemName)
    end
    if item then
        count = item.amount or item.count or 0
    end
    return count >= amount
end

---@param source number
---@param itemName string
---@return number
function Inventory.getItemCountByName(source, itemName)
    local xPlayer = server.getPlayer(source)

    local count = 0
    local item = nil

    if shared.getFrameworkName() == "esx" then
        item = xPlayer.hasItem(itemName)
    else --[[ QB or QBOX ]]
        item = xPlayer.Functions.GetItemByName(itemName)
    end
    if item then
        count = item.amount or item.count or 0
    end
    return count
end

---@param source number
---@return any[]
function Inventory.getInventory(source)
    local xPlayer = server.getPlayer(source)
    if shared.getFrameworkName() == "esx" then
        return xPlayer.getInventory()
    elseif shared.getFrameworkName() == "qb" then
        return xPlayer.PlayerData.items
    elseif shared.getFrameworkName() == "qbx" then
        return xPlayer.PlayerData.items
    end
    return {}
end

return Inventory
