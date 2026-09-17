ESX = exports["es_extended"]:getSharedObject()

ESX.RegisterServerCallback('id-electrician:getLevel', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    if xPlayer then
        MySQL.scalar('SELECT electrician_level FROM users WHERE identifier = ?', {xPlayer.identifier}, function(level)
            cb(level)
	    end)
    end
end)

ESX.RegisterServerCallback('id-electrician:checkPanels', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    if xPlayer then
        MySQL.scalar('SELECT electrician_panels FROM users WHERE identifier = ?', {xPlayer.identifier}, function(panels)
            if panels >= Config.LevelUp.Panels then
                MySQL.update('UPDATE users SET electrician_level = 2 WHERE identifier = ?', {xPlayer.identifier})
            end
	    end)
    end
end)

ESX.RegisterServerCallback('id-electrician:getPanels', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    if xPlayer then
        MySQL.scalar('SELECT electrician_panels FROM users WHERE identifier = ?', {xPlayer.identifier}, function(panels)
            cb(panels)
	    end)
    end
end)

ESX.RegisterServerCallback('id-electrician:checkPlates', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    if xPlayer then
        MySQL.scalar('SELECT electrician_plates FROM users WHERE identifier = ?', {xPlayer.identifier}, function(plates)
            if plates >= Config.LevelUp.Plates then
                MySQL.update('UPDATE users SET electrician_level = 3 WHERE identifier = ?', {xPlayer.identifier})
            end
	    end)
    end
end)

ESX.RegisterServerCallback('id-electrician:addPanel', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    if xPlayer then
        MySQL.update('UPDATE users SET electrician_panels = electrician_panels + 1 WHERE identifier = ?', {xPlayer.identifier})
    end
end)

ESX.RegisterServerCallback('id-electrician:addPlate', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    if xPlayer then
        MySQL.update('UPDATE users SET electrician_plates = electrician_plates + 1 WHERE identifier = ?', {xPlayer.identifier})
    end
end)

ESX.RegisterServerCallback('id-electrician:giveMoney', function(source, cb, amount)
    local xPlayer = ESX.GetPlayerFromId(source)

    if xPlayer then
        xPlayer.addMoney(amount)
        xPlayer.showNotification((Translation.Earned):format(amount))
    end
end)

RegisterServerEvent('id-electrician:server:triggerPowerOutageon')
AddEventHandler('id-electrician:server:triggerPowerOutageon', function()
    TriggerClientEvent('id-electrician:triggerPowerOutageon', -1)
    TriggerClientEvent('esx:showNotification', -1, Translation.GlobalPowerOutage)
end)

RegisterServerEvent('id-electrician:server:triggerPowerOutageoff')
AddEventHandler('id-electrician:server:triggerPowerOutageoff', function()
    TriggerClientEvent('id-electrician:triggerPowerOutageoff', -1)
    TriggerClientEvent('esx:showNotification', -1, Translation.GlobalPowerOutageFixed)
end)