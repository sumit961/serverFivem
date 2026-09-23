trunks = {}
GlobalState.hideintrunk = trunks

RegisterNetEvent('OT_hideintrunk:getintrunk', function(plate)
	local src = source
	trunks[plate] = src
	GlobalState.hideintrunk = trunks
end)

RegisterNetEvent('OT_hideintrunk:getouttrunk', function(plate)
    trunks[plate] = nil
	GlobalState.hideintrunk = trunks
end)

RegisterNetEvent('OT_hideintrunk:removefromtrunk', function(plate)
    if Config.CanRemoveFromTrunk == true then
		if table.type(trunks[plate]) ~= 'empty' then
			TriggerClientEvent('OT_hideintrunk:getouttrunk', trunks[plate])
			trunks[plate] = nil
			GlobalState.hideintrunk = trunks
		end
    end
end)

RegisterNetEvent('OT_hideintrunk:putintrunk', function(target, vehicle)
	TriggerClientEvent('OT_hideintrunk:getintrunk', target, vehicle, true)
end)