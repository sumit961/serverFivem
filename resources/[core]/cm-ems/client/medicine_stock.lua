-- Client presentation for the shared medicine stock delivery run.

local medicineRun
local medicineBlip
local medicineBusy = false

local function medicineNotify(message, kind)
    if lib and lib.notify then
        lib.notify({ title = 'EMS Medicine Supply', description = tostring(message), type = kind or 'inform' })
    end
end

local function clearMedicineBlip()
    if medicineBlip and DoesBlipExist(medicineBlip) then RemoveBlip(medicineBlip) end
    medicineBlip = nil
end

local function objectiveCoords(run)
    if not run then return nil end
    if run.stage == 'collect_truck' then return run.truckSpawn end
    if run.stage == 'load' then return run.pickup end
    if run.stage == 'return' then return run.truckSpawn end
end

local function objectiveLabel(run)
    if not run then return 'Medicine supply run' end
    if run.stage == 'collect_truck' then return 'Collect the medicine supply truck' end
    if run.stage == 'load' then return 'Load medicine at Humane Labs' end
    if run.stage == 'return' then return 'Return medicine to Pillbox' end
    return 'Medicine supply run'
end

local function updateMedicineBlip()
    clearMedicineBlip()
    local coords = objectiveCoords(medicineRun)
    if not coords then return end
    medicineBlip = AddBlipForCoord(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    SetBlipSprite(medicineBlip, medicineRun.stage == 'collect_truck' and 477 or 478)
    SetBlipColour(medicineBlip, 3)
    SetBlipScale(medicineBlip, 0.9)
    SetBlipRoute(medicineBlip, true)
    SetBlipRouteColour(medicineBlip, 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(objectiveLabel(medicineRun))
    EndTextCommandSetBlipName(medicineBlip)
end

local function drawMedicinePrompt(label)
    SetTextFont(4)
    SetTextScale(0.36, 0.36)
    SetTextColour(235, 251, 255, 240)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('[E] %s'):format(tostring(label)))
    EndTextCommandDisplayText(0.5, 0.84)
end

local function runVehicle()
    if not medicineRun or not tonumber(medicineRun.netId) then return 0 end
    local netId = tonumber(medicineRun.netId)
    if netId <= 0 or not NetworkDoesEntityExistWithNetworkId(netId) then return 0 end
    local vehicle = NetToVeh(netId)
    return vehicle and DoesEntityExist(vehicle) and vehicle or 0
end

local function drivingAssignedTruck()
    local vehicle = runVehicle()
    local ped = PlayerPedId()
    return vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped, vehicle
end

local function syncMedicineRun(run)
    medicineRun = type(run) == 'table' and run or nil
    medicineBusy = false
    updateMedicineBlip()
    if medicineRun then
        medicineNotify(objectiveLabel(medicineRun), 'inform')
    end
end

RegisterNetEvent('cm-ems:client:medicineRunSync', function(run)
    syncMedicineRun(run)
end)

RegisterNetEvent('cm-ems:client:medicineRunEnded', function(success, message)
    medicineRun = nil
    medicineBusy = false
    clearMedicineBlip()
    medicineNotify(message or (success and 'Medicine supply run complete.' or 'Medicine supply run ended.'),
        success and 'success' or 'error')
end)

CreateThread(function()
    Wait(2500)
    local state = lib.callback.await('cm-ems:server:getMedicineStockState', false)
    if type(state) == 'table' and type(state.myRun) == 'table' then
        syncMedicineRun(state.myRun)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if medicineRun then
            sleep = 0
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local target = objectiveCoords(medicineRun)
            local targetVector = target and vector3(tonumber(target.x) or 0.0, tonumber(target.y) or 0.0, tonumber(target.z) or 0.0)
            local distance = targetVector and #(coords - targetVector) or math.huge
            local driving, vehicle = drivingAssignedTruck()

            if targetVector and distance <= 35.0 then
                DrawMarker(1, targetVector.x, targetVector.y, targetVector.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    medicineRun.stage == 'collect_truck' and 3.0 or 5.0,
                    medicineRun.stage == 'collect_truck' and 3.0 or 5.0,
                    0.35, 77, 225, 255, 115, false, false, 2, false, nil, nil, false)
            end

            if medicineRun.stage == 'collect_truck' then
                if driving and not medicineBusy then
                    medicineBusy = true
                    local ok, message = lib.callback.await('cm-ems:server:medicineRunEnteredTruck', false, medicineRun.runId)
                    medicineBusy = false
                    if not ok then medicineNotify(message or 'The supply truck could not be verified.', 'error') end
                elseif distance <= 8.0 then
                    if vehicle == 0 then
                        drawMedicinePrompt('Wait for the medicine supply truck to load')
                    else
                        drawMedicinePrompt('Enter the medicine supply truck as driver')
                    end
                end
            elseif medicineRun.stage == 'load' then
                if distance <= 6.0 then
                    if not driving then
                        drawMedicinePrompt('Bring the assigned supply truck to this loading point')
                    elseif not medicineBusy then
                        drawMedicinePrompt('Load medicine into the truck')
                        if IsControlJustPressed(0, 38) then
                            medicineBusy = true
                            local completed = true
                            if lib and lib.progressCircle then
                                completed = lib.progressCircle({
                                    duration = math.max(1000, tonumber((Config.MedicineStock or {}).pickupDurationMs) or 10000),
                                    label = 'Loading sealed medicine crates',
                                    position = 'bottom',
                                    canCancel = true,
                                    disable = { move = true, car = true, combat = true },
                                })
                            else
                                Wait(math.max(1000, tonumber((Config.MedicineStock or {}).pickupDurationMs) or 10000))
                            end
                            if completed ~= false then
                                local ok, message = lib.callback.await('cm-ems:server:loadMedicineTruck', false, medicineRun.runId)
                                if not ok then medicineNotify(message or 'Medicine loading failed.', 'error') end
                            end
                            medicineBusy = false
                        end
                    end
                end
            elseif medicineRun.stage == 'return' then
                if distance <= 7.0 then
                    if not driving then
                        drawMedicinePrompt('Return in the assigned medicine supply truck')
                    elseif not medicineBusy then
                        drawMedicinePrompt('Unload medicine and refill hospital stock')
                        if IsControlJustPressed(0, 38) then
                            medicineBusy = true
                            local completed = true
                            if lib and lib.progressCircle then
                                completed = lib.progressCircle({
                                    duration = math.max(1000, tonumber((Config.MedicineStock or {}).returnDurationMs) or 8000),
                                    label = 'Unloading medicine into hospital stock',
                                    position = 'bottom',
                                    canCancel = true,
                                    disable = { move = true, car = true, combat = true },
                                })
                            else
                                Wait(math.max(1000, tonumber((Config.MedicineStock or {}).returnDurationMs) or 8000))
                            end
                            if completed ~= false then
                                local ok, message = lib.callback.await('cm-ems:server:completeMedicineRun', false, medicineRun.runId)
                                if not ok then medicineNotify(message or 'The medicine delivery could not be completed.', 'error') end
                            end
                            medicineBusy = false
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearMedicineBlip()
end)
