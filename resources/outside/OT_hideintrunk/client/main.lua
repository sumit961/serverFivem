trunked = false
currentVehicle = nil
keybind = nil
local ped = cache.ped

RegisterNetEvent('OT_hideintrunk:getouttrunk', function()
    if currentVehicle == nil then return end
    local playerCoords = GetEntityCoords(ped)
    local lockstatus = GetVehicleDoorLockStatus(currentVehicle)
    if Config.GetInLockedVehicles == false then
        if lockstatus == 2 or lockstatus == 7 or lockstatus == 8 then
            notify({type = 'error', description = locales('vehicle_locked')})
        else
            LocalPlayer.state:set('intrunk', false, true)
            trunked = false
            currentVehicle = nil
        end
    else
        LocalPlayer.state:set('intrunk', false, true)
        trunked = false
        currentVehicle = nil
    end
end)

RegisterNetEvent('OT_hideintrunk:getintrunk', function(vehicle, isServer)
    if Config.blacklist[GetEntityModel(vehicle)] then
        return false
    end
    if isServer == true then
        vehicle = NetworkGetEntityFromNetworkId(vehicle)
    end
    local playerCoords = GetEntityCoords(ped)
    local lockstatus = GetVehicleDoorLockStatus(vehicle)
    local trunk = GetEntityBoneIndexByName(vehicle, 'boot')
	local plate = GetVehicleNumberPlateText(vehicle)
	if Config.LimitPeople == false then
        if trunk ~= -1 then
			local coords = GetWorldPositionOfEntityBone(vehicle, trunk)
			if #(playerCoords - coords) <= Config.MaxDistance then
				if not trunked then
					if Config.GetInLockedVehicles == false then
						if lockstatus == 2 or lockstatus == 7 or lockstatus == 8 then
							notify({type = 'error', description = locales('vehicle_locked')})
						else
							getInTrunk(vehicle)
						end
					else
						getInTrunk(vehicle)
					end
				end
			else
				notify({type = 'error', description = locales('vehicle_trunkfar')})
			end
		else
			notify({type = 'error', description = locales('vehicle_notrunk')})
		end
	else
		if GlobalState.hideintrunk[plate] == nil or table.type(GlobalState.hideintrunk[plate]) == 'empty' then
			if trunk ~= -1 then
				local coords = GetWorldPositionOfEntityBone(vehicle, trunk)
				if #(playerCoords - coords) <= Config.MaxDistance then
					if trunked == nil or not trunked then
						if Config.GetInLockedVehicles == false then
							if lockstatus == 2 or lockstatus == 7 or lockstatus == 8 then
								notify({type = 'error', description = locales('vehicle_locked')})
							else
								getInTrunk(vehicle)
							end
						else
							getInTrunk(vehicle)
						end
					end
				else
					notify({type = 'error', description = locales('vehicle_trunkfar')})
				end
			else
				notify({type = 'error', description = locales('vehicle_notrunk')})
			end
		else	    
			notify({type = 'error', description = locales('vehicle_full')})
		end
	end
end)

RegisterCommand("checkvehclass", function(source, args, fullCommand)
    local veh = cache.vehicle
    local model = GetEntityModel(veh)
    local class = GetVehicleClass(veh)
    local classname = GetLabelText('VEH_CLASS_'..class)
    print(class)
    print(classname)
end)

local cam = nil
function doCam(veh, class)
    if not DoesCamExist(cam) then
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        local playerPed = ped
        local coords = GetEntityCoords(playerPed)
        SetCamCoord(cam, coords.x, coords.y, coords.z)
        SetCamRot(cam, 0.0, 0.0, 0.0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        SetCamCoord(cam, coords.x, coords.y, coords.z)
    end
    AttachCamToEntity(cam, veh, Config.CamOffsets[class].x, Config.CamOffsets[class].y, Config.CamOffsets[class].z, true)
    SetCamRot(cam, 0.0, 0.0, GetEntityHeading(veh), 2)
end

function getInTrunk(veh)
    local model = GetEntityModel(veh)
    local class = GetVehicleClass(veh)
    local classname = GetLabelText('VEH_CLASS_'..class)
    if not DoesVehicleHaveDoor(veh, 6) and DoesVehicleHaveDoor(veh, 5) and IsThisModelACar(model) then
        SetVehicleDoorOpen(veh, 5, true, true)
        local playerPed = ped

        local vehdimension1, vehdimension2 = GetModelDimensions(model)

        local trunkDic = 'fin_ext_p1-7'
        local trunkAnim = 'cs_devin_dual-7'
        lib.requestAnimDict(trunkDic)
        SetBlockingOfNonTemporaryEvents(playerPed, true)
        DetachEntity(playerPed)
        ClearPedTasks(playerPed)
        ClearPedSecondaryTask(playerPed)
        ClearPedTasksImmediately(playerPed)
        TaskPlayAnim(playerPed, trunkDic, trunkAnim, 8.0, 8.0, -1, 1, 999.0, 0, 0, 0)
        local plate = GetVehicleNumberPlateText(veh)
        TriggerServerEvent('OT_hideintrunk:getintrunk', plate)
        AttachEntityToEntity(playerPed, veh, 0, -0.1, vehdimension1.y + 0.85, vehdimension2.z - 0.97, 0, 0, 40.0, 1, 1, 1, 1, 1, 1)
        doCam(veh, class)
        trunked = true
        Wait(750)
        SetVehicleDoorShut(veh, 5, true)
        currentVehicle = veh
        LocalPlayer.state:set('intrunk', true, true)
        while trunked do
            doCam(veh, class)
            Wait(0)
            if not IsEntityPlayingAnim(playerPed, trunkDic, trunkAnim, 3) then
                TaskPlayAnim(playerPed, trunkDic, trunkAnim, 8.0, 8.0, -1, 1, 999.0, 0, 0, 0)
            end

            if not DoesEntityExist(veh) or not IsVehicleDriveable(veh, false) or IsEntityInWater(veh) then
                trunked = false
                currentVehicle = nil
                TriggerServerEvent('OT_hideintrunk:getouttrunk', plate)
                LocalPlayer.state:set('intrunk', false, true)
                RemoveAnimDict(trunkDic)
                RenderScriptCams(false, false, 0, 1, 0)
                DestroyCam(cam, false)
                DetachEntity(playerPed)
                ClearPedTasksImmediately(playerPed)
                return
            end
        end
        RemoveAnimDict(trunkDic)
        SetVehicleDoorOpen(veh, 5, 1, 0)
        RenderScriptCams(false, false, 0, 1, 0)
        DestroyCam(cam, false)
        DetachEntity(playerPed)
        Wait(10)
        if DoesEntityExist(veh) and IsVehicleDriveable(veh, false) then
            local dropPosition = GetOffsetFromEntityInWorldCoords(veh, 0.0, vehdimension1.y - 1.0, 0.0)
            SetEntityCoords(playerPed, dropPosition.x, dropPosition.y, dropPosition.z)
            SetVehicleDoorShut(veh, 5, false)
        else
            ClearPedTasks(playerPed)
            local plyCoords = GetEntityCoords(playerPed)
            SetEntityCoords(playerPed, plyCoords.x, plyCoords.y, plyCoords.z + 1)
        end
        TriggerServerEvent('OT_hideintrunk:getouttrunk', plate)
        currentVehicle = nil
    end
end

if Config.textui then
    local uiThreadRunning = false
    uiOpen = false
    local function uiThread()
        if uiThreadRunning then return end
        uiThreadRunning = true
        while uiThreadRunning do
            local sleep = 200
            if trunked then
                sleep = 500
                lib.showTextUI(locales('textui_out', GetControlInstructionalButton(0, joaat('+' .. keybind.name) | 0x80000000, true):sub(3)))
            else
                local coords = GetEntityCoords(ped)
                local vehicle = lib.getClosestVehicle(coords, 5.0, false)
                if not vehicle then
                    if uiOpen then
                        lib.hideTextUI()
                        uiOpen = false
                    end
                else
                    if Config.blacklist[GetEntityModel(vehicle)] then
                        if uiOpen then
                            lib.hideTextUI()
                            uiOpen = false
                        end
                    else
                        local trunk = GetEntityBoneIndexByName(vehicle, 'boot')
                        local trunkPos = GetWorldPositionOfEntityBone(vehicle, trunk)
                        if #(coords - trunkPos) < 1.45 then
                            if not uiOpen then
                                lib.showTextUI(locales('textui_in', GetControlInstructionalButton(0, joaat('+' .. keybind.name) | 0x80000000, true):sub(3)))
                                uiOpen = true
                            end
                        else
                            if uiOpen then
                                lib.hideTextUI()
                                uiOpen = false
                            end
                        end
                    end
                end
            end
            Wait(sleep)
        end
        if uiOpen then
            lib.hideTextUI()
            uiOpen = false
        end
    end
    CreateThread(uiThread)

    lib.onCache('vehicle', function(value)
        if value then
            uiThreadRunning = false
        else
            CreateThread(uiThread)
        end
    end)
end

lib.onCache('ped', function(value)
    ped = value
end)


