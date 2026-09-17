ESX = exports["es_extended"]:getSharedObject()
LocalPlayer.state.employed = false
LocalPlayer.state.jobStarted = false
LocalPlayer.state.jobStartedPlates = false
LocalPlayer.state.doneFixed = 0
LocalPlayer.state.doneFixedPlates = 0
LocalPlayer.state.Level = 1
LocalPlayer.state.panelsrepaired = 0
inMenu = false
GlobalState.PowerOutage = false

Citizen.CreateThread(function()
    createBlip()
end)

Citizen.CreateThread(function()
	while true do
		local sleep = 1000
		local ped = PlayerPedId()
		local pedCoords = GetEntityCoords(ped)

		if LocalPlayer.state.jobStarted and not LocalPlayer.state.jobStartedPlates then
			sleep = 5
            startJobPanels()
		end

		if LocalPlayer.state.jobStartedPlates then
			sleep = 5
            startJobPlates()
		end

		Citizen.Wait(sleep)
	end
end)

Citizen.CreateThread(function()
    while true do
        local ped = PlayerPedId()
	    local pedCoords = GetEntityCoords(ped)
        local sleep = 1000
        local timer3 = 0
        inDistance = false
        inDistance2 = false
        
        if Vdist(pedCoords.x, pedCoords.y, pedCoords.z, Markers.Coords.GetEmployed.x, Markers.Coords.GetEmployed.y, Markers.Coords.GetEmployed.z) < 10.0 and not inMenu then
            Draw3DText(Markers.Coords.GetEmployed.x, Markers.Coords.GetEmployed.y, Markers.Coords.GetEmployed.z, Translation.ElectricianJob)
            sleep = 5
            DrawMarker(Markers.Types.GetEmployed, Markers.Coords.GetEmployed.x, Markers.Coords.GetEmployed.y, Markers.Coords.GetEmployed.z - 1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, Markers.Colors.GetEmployed.r, Markers.Colors.GetEmployed.g, Markers.Colors.GetEmployed.b, 100, false, true, 2, nil, nil, false)
            if Vdist(pedCoords.x, pedCoords.y, pedCoords.z, Markers.Coords.GetEmployed.x, Markers.Coords.GetEmployed.y, Markers.Coords.GetEmployed.z) < 1.0 then
                inDistance = true
            end
            if not shown and inDistance then
                showUI(true, true)
                inMenu = true
                shown = true
            elseif shown and not inDistance then
                showUI(false)
                inMenu = false
                shown = false
            end
        end

        if LocalPlayer.state.Level >= 2 then
            if Vdist(pedCoords.x, pedCoords.y, pedCoords.z, Markers.Coords.RentVehicle.x, Markers.Coords.RentVehicle.y, Markers.Coords.RentVehicle.z) < 10.0 and LocalPlayer.state.employed and not LocalPlayer.state.jobStartedPlates then
                Draw3DText(Markers.Coords.RentVehicle.x, Markers.Coords.RentVehicle.y, Markers.Coords.RentVehicle.z, Translation.HelpRentVehicle)
                sleep = 5
                DrawMarker(Markers.Types.RentVehicle, Markers.Coords.RentVehicle.x, Markers.Coords.RentVehicle.y, Markers.Coords.RentVehicle.z - 1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, Markers.Colors.RentVehicle.r, Markers.Colors.RentVehicle.g, Markers.Colors.RentVehicle.b, 100, false, true, 2, nil, nil, false)
                if Vdist(pedCoords.x, pedCoords.y, pedCoords.z, Markers.Coords.RentVehicle.x, Markers.Coords.RentVehicle.y, Markers.Coords.RentVehicle.z) < 1.0 then
                    inDistance2 = true
                end
                if not shown2 and inDistance2 then
                    SendNUIMessage({type = "showfixedpanels", status = false})
                    LocalPlayer.state.jobStartedPlates = true
                    createVehicle()
                    createPlatesBlips()
                    shown2 = true
                elseif shown2 and not inDistance2 then
                    shown2 = false
                end
            end
        end

        if LocalPlayer.state.Level >= 3 and (GlobalState.PowerOutage == true) then
            if Vdist(pedCoords.x, pedCoords.y, pedCoords.z, Markers.Coords.Power_Outage.x, Markers.Coords.Power_Outage.y, Markers.Coords.Power_Outage.z) < 10.0 then
                Draw3DText(Markers.Coords.Power_Outage.x, Markers.Coords.Power_Outage.y, Markers.Coords.Power_Outage.z, Translation.FixPowerOutage)
                sleep = 5
                DrawMarker(Markers.Types.Power_Outage, Markers.Coords.Power_Outage.x, Markers.Coords.Power_Outage.y, Markers.Coords.Power_Outage.z - 1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, Markers.Colors.RentVehicle.r, Markers.Colors.RentVehicle.g, Markers.Colors.RentVehicle.b, 100, false, true, 2, nil, nil, false)
                if Vdist(pedCoords.x, pedCoords.y, pedCoords.z, Markers.Coords.Power_Outage.x, Markers.Coords.Power_Outage.y, Markers.Coords.Power_Outage.z) < 1.0 then
                    ESX.ShowHelpNotification(Translation.FixOutage)
                    while IsControlPressed(0, 38) do
                        Citizen.Wait(0)
                        timer3 = timer3 + 1
                        if timer3 >= 2000 then
                            GlobalState.PowerOutage = false
                            TriggerServerEvent("id-electrician:server:triggerPowerOutageoff")
                            ESX.TriggerServerCallback("id-electrician:giveMoney", function() end, Earnings.PerOutageFix)
                            break
                        end
                    end
                end
            end
        end

        Citizen.Wait(sleep)
    end
end)

createBlip = function()
    local blip = AddBlipForCoord(Markers.Coords.GetEmployed.x, Markers.Coords.GetEmployed.y, Markers.Coords.GetEmployed.z)

    SetBlipSprite(blip, Blips.Blip.ID)
    SetBlipScale(blip, Blips.Blip.Scale)
    SetBlipColour(blip, Blips.Blip.Colour)
    SetBlipAsShortRange(blip, true)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Blips.Blip.Label)
    EndTextCommandSetBlipName(blip)
end

createPlatesBlips = function()
    for i, v in ipairs(Job_Locations.Plates) do
        v.blip = AddBlipForCoord(v.x, v.y, v.z)

        SetBlipSprite(v.blip, Blips.PlatesBlips.ID)
        SetBlipColour(v.blip, Blips.PlatesBlips.Colour)
        SetBlipScale(v.blip, Blips.PlatesBlips.Scale)
        SetBlipAsShortRange(v.blip, Blips.PlatesBlips.ShortRange)

        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(Blips.PlatesBlips.Label)
        EndTextCommandSetBlipName(v.blip)
    end
end

createVehicle = function()
    local ped = PlayerPedId()
    ModelHash = Config.RentVehicle.Model
    if not IsModelInCdimage(ModelHash) then return end
        RequestModel(ModelHash)
    while not HasModelLoaded(ModelHash) do
        Citizen.Wait(10)
    end
    rentVehicle = CreateVehicle(ModelHash, Config.RentVehicle.SpawnLocation.x, Config.RentVehicle.SpawnLocation.y, Config.RentVehicle.SpawnLocation.z, Config.RentVehicle.SpawnLocation.heading, true, false)
    SetModelAsNoLongerNeeded(ModelHash)
    SetVehicleOnGroundProperly(rentVehicle)
    SetVehicleFixed(rentVehicle)
    TaskWarpPedIntoVehicle(ped, rentVehicle, -1)
end

startJobPanels = function()
    local ped = PlayerPedId()
	local pedCoords = GetEntityCoords(ped)
    local timer = 0

    for i, v in ipairs(Job_Locations.Panels) do
        if (GetDistanceBetweenCoords(pedCoords.x, pedCoords.y, pedCoords.z, v.x, v.y, v.z, true) < 18) and not v.isFixed then
            DrawMarker(20, v.x, v.y, v.z, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 0.5, 0.5, 0.5, 124, 252, 0, 100, false, true, 2, false, false, false, false)
            if (GetDistanceBetweenCoords(pedCoords.x, pedCoords.y, pedCoords.z, v.x, v.y, v.z, true) < 1) and not v.isFixed then
                ESX.ShowHelpNotification(Translation.FixPanel)
                while IsControlPressed(0, 38) do
                    Citizen.Wait(0)
                    timer = timer + 1
                    if timer >= 500 then
                        v.isFixed = true
                        LocalPlayer.state.panelsrepaired = LocalPlayer.state.panelsrepaired + 1
                        SendNUIMessage({action = 'panelsrepaired', value = LocalPlayer.state.panelsrepaired})
                        Citizen.Wait(10)
                        ESX.TriggerServerCallback("id-electrician:addPanel", function() end)
                        ESX.TriggerServerCallback("id-electrician:giveMoney", function() end, Earnings.PerPanel)
                        RemoveBlip(v.blip)
                        LocalPlayer.state.doneFixed = LocalPlayer.state.doneFixed + 1
                        if LocalPlayer.state.doneFixed == #Job_Locations.Panels then
                            JobDone()
                        else
                            ESX.ShowNotification(Translation.PanelFixed)
                        end
                        break
                    end
                end
            end
        end
    end 
end

startJobPlates = function()
    local ped = PlayerPedId()
	local pedCoords = GetEntityCoords(ped)
    local timer2 = 0

    for i, v in ipairs(Job_Locations.Plates) do
        if (GetDistanceBetweenCoords(pedCoords.x, pedCoords.y, pedCoords.z, v.x, v.y, v.z, true) < 18) and not v.isFixedPlate then
            DrawMarker(20, v.x, v.y, v.z, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 0.5, 0.5, 0.5, 255, 255, 0, 100, false, true, 2, false, false, false, false)
            if (GetDistanceBetweenCoords(pedCoords.x, pedCoords.y, pedCoords.z, v.x, v.y, v.z, true) < 1) and not v.isFixedPlate then
                ESX.ShowHelpNotification(Translation.FixPlate)
                while IsControlPressed(0, 38) do
                    Citizen.Wait(0)
                    timer2 = timer2 + 1
                    if timer2 >= 500 then
                        v.isFixedPlate = true
                        Citizen.Wait(10)
                        ESX.TriggerServerCallback("id-electrician:addPlate", function() end)
                        ESX.TriggerServerCallback("id-electrician:giveMoney", function() end, Earnings.PerDepositPlate)
                        RemoveBlip(v.blip)
                        LocalPlayer.state.doneFixedPlates = LocalPlayer.state.doneFixedPlates + 1
                        if LocalPlayer.state.doneFixedPlates == #Job_Locations.Plates then
                            JobDonePlates()
                        else
                            ESX.ShowNotification(Translation.PlateFixed)
                        end
                        break
                    end
                end
            end
        end
    end 
end

JobDone = function()
	LocalPlayer.state.doneFixed = 0
	Citizen.Wait(500)
	for k, v in ipairs(Job_Locations.Panels) do
		v.isFixed = false
		RemoveBlip(v.blip)
	end
    ESX.TriggerServerCallback("id-electrician:checkPanels", function() end)
    startJobPanels()
end

JobDonePlates = function()
    SendNUIMessage({type = "showfixedpanels", status = true})
    LocalPlayer.state.jobStartedPlates = false
	LocalPlayer.state.doneFixedPlates = 0
    ESX.ShowNotification(Translation.JobDone)
	Citizen.Wait(500)
	for k, v in ipairs(Job_Locations.Plates) do
		v.isFixedPlate = false
		RemoveBlip(v.blip)
	end
    ESX.TriggerServerCallback("id-electrician:checkPlates", function() end)
end

function Draw3DText(x, y, z, text)
	local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    local px,py,pz=table.unpack(GetGameplayCamCoords())

	if onScreen then
		SetTextScale(0.35, 0.35)
		SetTextFont(8)
		SetTextProportional(1)
		SetTextColour(255, 255, 255, 215)
		SetTextDropShadow(0, 0, 0, 55)
		SetTextEdge(0, 0, 0, 150)
		SetTextDropShadow()
		SetTextOutline()
		SetTextEntry("STRING")
		SetTextCentre(1)
		AddTextComponentString(text)
		DrawText(_x,_y)
	end
end

function powerOutageOn()
    SetArtificialLightsState(true)
    if Power_Outage.Soundeffect then
        PlaySoundFrontend(-1, "Power_Down", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
    end
    if Power_Outage.ShowVehicleLights then
        SetArtificialLightsStateAffectsVehicles(false)
    end
end

function powerOutageOff()
    SetArtificialLightsState(false)
    if Power_Outage.Soundeffect then
        PlaySoundFrontend(-1, "police_notification", "DLC_AS_VNT_Sounds", 1)
    end
    if Power_Outage.ShowVehicleLights then
        SetArtificialLightsStateAffectsVehicles(true)
    end
end

Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        if not GlobalState.PowerOutage then
            Citizen.Wait(Power_Outage.WaitTime)
            GlobalState.PowerOutage = true
            TriggerServerEvent("id-electrician:server:triggerPowerOutageon")
            if LocalPlayer.state.Level >= 3 then
                ESX.ShowNotification(Translation.PowerPoutage_Electrician)
                SetNewWaypoint(Markers.Coords.Power_Outage.x, Markers.Coords.Power_Outage.y, Markers.Coords.Power_Outage.z)
            end
        end

        Citizen.Wait(sleep)
    end
end)  

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        powerOutageOff()
    end
end)

RegisterNetEvent('id-electrician:triggerPowerOutageon')
AddEventHandler('id-electrician:triggerPowerOutageon', function()
    powerOutageOn()
end)

RegisterNetEvent('id-electrician:triggerPowerOutageoff')
AddEventHandler('id-electrician:triggerPowerOutageoff', function()
    powerOutageOff()
end)