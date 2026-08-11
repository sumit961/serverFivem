-- cm-house | player G-menu property gift / sale entry points.
local PAGE = 'property'

local function register()
    if GetResourceState('cm-playerdata') ~= 'started' then return end
    pcall(function()
        exports['cm-playerdata']:RegisterInteractionPage({
            id = PAGE, label = 'Property', icon = 'house', order = 36,
            emptyLabel = 'No property actions available',
        })
        exports['cm-playerdata']:RegisterInteractionOption(PAGE, {
            id = 'house_gift', action = 'house_gift', label = 'Gift a House',
            icon = 'gift', type = 'extension', order = 10, close = true,
        })
        exports['cm-playerdata']:RegisterInteractionOption(PAGE, {
            id = 'house_sell_player', action = 'house_sell_player', label = 'Sell a House',
            icon = 'handshake', type = 'extension', order = 20, close = true,
        })
    end)
end

RegisterNetEvent('cm-house:client:choosePropertyTransfer', function(data)
    if type(data) ~= 'table' or type(data.houses) ~= 'table' then return end
    local choices = {}
    for _, house in ipairs(data.houses) do
        choices[#choices + 1] = { value = tostring(house.id), label = ('House #%s'):format(house.number or house.id) }
    end
    local fields = {{ type = 'select', label = 'House', required = true, options = choices }}
    if data.mode == 'sale' then
        fields[#fields + 1] = { type = 'number', label = 'Sale price', required = true, min = 1, max = 100000000 }
    end
    local result = lib.inputDialog(data.mode == 'sale' and 'Sell House' or 'Gift House', fields)
    if not result then return end
    TriggerServerEvent('cm-house:server:createPropertyTransfer', {
        mode = data.mode, targetServerId = data.targetServerId,
        houseId = tonumber(result[1]), price = data.mode == 'sale' and tonumber(result[2]) or 0,
    })
end)

RegisterNetEvent('cm-house:client:confirmPropertyTransfer', function(data)
    CreateThread(function()
        local result = lib.alertDialog({
            header = data.mode == 'sale' and 'Buy House?' or 'Accept House Gift?',
            content = ('Accept **House #%s** from **%s**%s?\n\nStored property contents remain in the house and become accessible to you.'):format(
                tostring(data.houseNumber or data.houseId), tostring(data.sellerName or 'the owner'),
                data.mode == 'sale' and (' for **$' .. tostring(data.price or 0) .. '** from bank') or ''),
            centered = true, cancel = true,
            labels = { confirm = 'Accept', cancel = 'Decline' },
        })
        TriggerServerEvent('cm-house:server:answerPropertyTransfer', data.token, result == 'confirm')
    end)
end)

AddEventHandler('cm-playerdata:client:interactionRegistryReady', register)
AddEventHandler('onClientResourceStart', function(name)
    if name == GetCurrentResourceName() or name == 'cm-playerdata' then Wait(300); register() end
end)
