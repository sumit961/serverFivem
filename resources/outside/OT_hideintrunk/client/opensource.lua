if Config.AllowCommandUse then
    RegisterCommand(Config.Outtrunkcmd, function(source, args, rawCommand)
		if not trunked then return end
        TriggerEvent('OT_hideintrunk:getouttrunk')
    end, false)

    RegisterCommand(Config.Intrunkcmd, function(source, args, rawCommand)
		local pCoords = GetEntityCoords(cache.ped)
        local vehicle, vehicleCoords = lib.getClosestVehicle(pCoords, 4.0, false)
        if vehicle == nil or vehicle == 0 then
            notify({type = 'error', description = locales('vehicle_notfound')})
            return
        end
		local plate = GetVehicleNumberPlateText(vehicle)
		if GlobalState.hideintrunk[plate] ~= nil then
            return
        end
        TriggerEvent('OT_hideintrunk:getintrunk', vehicle)
    end, false)

    RegisterCommand(Config.removefromtrunkcmd, function(source, args, rawCommand)
        local pCoords = GetEntityCoords(cache.ped)
        local vehicle, vehicleCoords = lib.getClosestVehicle(pCoords, 4.0, false)
        if vehicle == nil or vehicle == 0 then
            notify({type = 'error', description = locales('vehicle_notfound')})
            return
        end
		local plate = GetVehicleNumberPlateText(vehicle)
		if GlobalState.hideintrunk[plate] == nil then
            return
        end
        TriggerServerEvent('OT_hideintrunk:removefromtrunk', plate)
    end, false)

    RegisterCommand(Config.putintrunkcmd, function(source, args, rawCommand)
        local pCoords = GetEntityCoords(cache.ped)
        local vehicle, vehicleCoords = lib.getClosestVehicle(pCoords, 4.0, false)
        if vehicle == nil or vehicle == 0 then
            notify({type = 'error', description = locales('vehicle_notfound')})
            return
        end
		local targetId, targetPed, targetCoords = lib.getClosestPlayer(pCoords, 3.0, false)
		if targetPed == nil then
			notify({type = 'error', description = locales('player_notfound')})
			return
		end
		TriggerServerEvent('OT_hideintrunk:putintrunk', GetPlayerServerId(targetId), NetworkGetNetworkIdFromEntity(vehicle))
    end, false)
	keybind = lib.addKeybind({
		name = 'trunkaccess',
		description = 'Get In and out of trunk',
		defaultKey = Config.textuikey,
		onPressed = function(self)
			if not uiOpen and not trunked then return end
			if trunked then
				ExecuteCommand(Config.Outtrunkcmd)
			elseif uiOpen then
				ExecuteCommand(Config.Intrunkcmd)
			end
		end,
	})
end

if Config.target then
	local options = {
		{
			name = 'trunk:option1',
			icon = Config.Intrunkicon,
			label = locales('target_intrunk'),
			onSelect = function(data)
				TriggerEvent('OT_hideintrunk:getintrunk', data.entity)
			end,
			action = function(entity)
				TriggerEvent('OT_hideintrunk:getintrunk', entity)
			end,
			canInteract = function(entity)
				if trunked then
					return false
				end
				if Config.blacklist[GetEntityModel(entity)] then
					return false
				end
				return true
			end
		}, 
		{
			name = 'trunk:option2',
			event = 'OT_hideintrunk:getouttrunk',
			icon = Config.Outtrunkicon,
			label = locales('target_outtrunk'),
			canInteract = function(entity)
				if trunked == nil or not trunked then
					return false
				end
				return true
			end
		},
		{
			name = 'trunk:option3',
			icon = Config.removefromtrunkicon,
			label = locales('target_removetrunk'),
			canInteract = function(entity)
				local plate = GetVehicleNumberPlateText(entity)
				if Config.CanRemoveFromTrunk == false then
					return false
				end
				if trunked or GlobalState.hideintrunk[plate] == nil then
					return false
				end
				return true
			end,
			onSelect = function(data)
				local plate = GetVehicleNumberPlateText(data.entity)
				TriggerServerEvent('OT_hideintrunk:removefromtrunk', plate)
			end,
			action = function(entity)
				local plate = GetVehicleNumberPlateText(entity)
				TriggerServerEvent('OT_hideintrunk:removefromtrunk', plate)
			end
		}, 
		{
			name = 'trunk:option4',
			icon = Config.putintrunkicon,
			label = locales('target_putintrunk'),
			canInteract = function(entity)
				if Config.blacklist[GetEntityModel(entity)] then
					return false
				end
				return true
			end,
			onSelect = function(data)
				local targetId, targetPed, targetCoords = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
				if targetPed == nil then
					notify({type = 'error', description = locales('player_notfound')})
					return
				end
				TriggerServerEvent('OT_hideintrunk:putintrunk', GetPlayerServerId(targetId), NetworkGetNetworkIdFromEntity(data.entity))
			end,
			action = function(entity)
				local targetId, targetPed, targetCoords = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
				if targetPed == nil then
					notify({type = 'error', description = locales('player_notfound')})
					return
				end
				TriggerServerEvent('OT_hideintrunk:putintrunk', GetPlayerServerId(targetId), NetworkGetNetworkIdFromEntity(entity))
			end
		}
	}
	local targetSystem = string.lower(Config.targetSystem)
	if targetSystem == 'qtarget' then
		if Config.Usebones then
			exports[targetSystem]:AddTargetBone({'boot'}, {
				options = options,
				distance = Config.MaxDistance
			})
		else
			exports[targetSystem]:Vehicle({
				options = options,
				distance = Config.MaxDistance
			})
		end
	elseif targetSystem == 'ox_target' then
		if Config.Usebones then
			for k, v in pairs(options) do
				options[k].bones = 'boot'
			end
			exports[targetSystem]:addGlobalVehicle(options)
		else
			exports[targetSystem]:addGlobalVehicle(options)
		end
	elseif targetSystem == 'qb-target' then
		if Config.Usebones then
			exports[targetSystem]:AddTargetBone({'boot'}, {
				options = options,
				distance = Config.MaxDistance
			})
		else
			exports[targetSystem]:AddGlobalVehicle({
				options = options,
				distance = Config.MaxDistance
			})
		end
	end
end

function notify(data)
    lib.notify({type = data.type, description = data.description})
end
RegisterNetEvent('OT_hideintrunk:notify', notify)