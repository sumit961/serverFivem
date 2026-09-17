Citizen.CreateThread(function()
    ESX.TriggerServerCallback('id-electrician:getLevel', function(level)
        LocalPlayer.state.Level = level
        SendNUIMessage({action = 'professionlevel', value = level})
    end)
end)

showUI = function(bool, bool)
    SendNUIMessage({
        type = "show",
        status = bool,
    })
    SetNuiFocus(bool, bool)

    for k, v in pairs(UI_Components.Requirements) do
        SendNUIMessage({type = 'addrequirements', requirements = #UI_Components.Requirements, data = v})
    end

    ESX.TriggerServerCallback("id-electrician:checkPanels", function() end)
    ESX.TriggerServerCallback("id-electrician:checkPlates", function() end)
    
    ESX.TriggerServerCallback('id-electrician:getLevel', function(level)
        LocalPlayer.state.Level = level
        SendNUIMessage({action = 'professionlevel', value = level})
    end)

    if not LocalPlayer.state.employed then
        SendNUIMessage({action = 'button', value = Translation.Button.GetEmployed})
    else
        SendNUIMessage({action = 'button', value = Translation.Button.Leave})
    end
    
	SendNUIMessage({action = 'priceperpanel', value = Earnings.PerPanel})
	SendNUIMessage({action = 'depositplateprice', value = Earnings.PerDepositPlate})
	SendNUIMessage({action = 'jobdescription', value = UI_Components.JobDescription})
end

RegisterNUICallback("startjob", function(data)
    if not LocalPlayer.state.employed then
        ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin, jobSkin)
            if skin.sex == 0 then
                TriggerEvent('skinchanger:loadClothes', skin, Config.Clothes.male)
            else
                TriggerEvent('skinchanger:loadClothes', skin, Config.Clothes.female)
            end
        end)
        SendNUIMessage({type = "showfixedpanels", status = true})
        ESX.TriggerServerCallback("id-electrician:getPanels", function(panels)
            LocalPlayer.state.panelsrepaired = panels
            SendNUIMessage({action = 'panelsrepaired', value = LocalPlayer.state.panelsrepaired})
        end)
        LocalPlayer.state.employed = true
        LocalPlayer.state.jobStarted = true
    else
        ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)
            TriggerEvent('skinchanger:loadSkin', skin)
        end)
        SendNUIMessage({type = "showfixedpanels", status = false})
        LocalPlayer.state.employed = false
        LocalPlayer.state.jobStarted = false
        LocalPlayer.state.jobStartedPlates = false
        LocalPlayer.state.doneFixed = 0
        LocalPlayer.state.doneFixedPlates = 0
        DeleteVehicle(rentVehicle)
    end
    
    SendNUIMessage({
        type = "show",
        status = false,
    })
    SetNuiFocus(false, false)
    inMenu = false
end)

RegisterNUICallback('close', function(data)
    SetNuiFocus(false, false)
    inMenu = false
end)
