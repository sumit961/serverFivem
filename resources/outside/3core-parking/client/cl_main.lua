local QBCore = nil
local ESX = nil
local _createdPeds = {}
local _currentGarage = ''
local _closeToSpot = false

if Config['FrameworkSettings']['Framework'] == 'QBCore' then
    local _fileName = Config['FrameworkSettings']['QBCoreFileName']
    QBCore = exports[_fileName]:GetCoreObject()
elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
    TriggerEvent(Config['FrameworkSettings']['ESXEvent'], function(obj) ESX = obj end)
end

local function _drawHelpText(_text)
	BeginTextCommandDisplayHelp('STRING')
	AddTextComponentSubstringPlayerName(_text)
	EndTextCommandDisplayHelp(0, false, true, -1)
end

local function _createBlip(_blipSettings)
    local _blip = AddBlipForCoord(_blipSettings['Coords'])
    SetBlipSprite(_blip, _blipSettings['Sprite'])
    SetBlipScale(_blip, _blipSettings['Scale'])
    SetBlipColour(_blip, _blipSettings['Color'])
    SetBlipAsShortRange(_blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(_blipSettings['Label'])
    EndTextCommandSetBlipName(_blip)
end

local function _findGarageByName(_name)
    for _idx, _garage in pairs(Config['Parking']) do
        if _garage['Name'] == _name then
            return _garage
        end
    end
    return nil
end

local function _openParkingMenu(_parkingSpots)
    if Config['FrameworkSettings']['Framework'] == 'QBCore' then
        QBCore.Functions.TriggerCallback('3core-parking:fetchSpots', function(_locations, _headerData, _ownedVehicles)
            _headerData['ParkingName'] = _currentGarage
            _headerData['PricePerSpot'] = _findGarageByName(_currentGarage)['Price']
            for _idx, _vehicle in pairs(_ownedVehicles) do
                _vehicle['Label'] = GetLabelText(GetDisplayNameFromVehicleModel(_vehicle['Hash']))
            end
            SetNuiFocus(true, true)
            SendNUIMessage({type = 'showMenu', parkingSpots = _locations, headerData = _headerData, ownedVehicles = _ownedVehicles})
        end, _parkingSpots)
    elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
        ESX.TriggerServerCallback('3core-parking:fetchSpots', function(_locations, _headerData, _ownedVehicles)
            _headerData['ParkingName'] = _currentGarage
            _headerData['PricePerSpot'] = _findGarageByName(_currentGarage)['Price']
            for _idx, _vehicle in pairs(_ownedVehicles) do
                _vehicle['Label'] = GetLabelText(GetDisplayNameFromVehicleModel(_vehicle['Hash']))
            end
            SetNuiFocus(true, true)
            SendNUIMessage({type = 'showMenu', parkingSpots = _locations, headerData = _headerData, ownedVehicles = _ownedVehicles})
        end, _parkingSpots)
    end
end

local function _createNpc(_park)
    RequestModel(_park['Npc']['Hash'])
    while not HasModelLoaded(_park['Npc']['Hash']) do Citizen.Wait(0) end
    local _clientPed = CreatePed(4, _park['Npc']['Hash'], _park['Npc']['Coords'], false, false)
    FreezeEntityPosition(_clientPed, true)
    SetEntityInvincible(_clientPed, true)
    SetBlockingOfNonTemporaryEvents(_clientPed, true)
    table.insert(_createdPeds, _clientPed)
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(_clientPed)) < 2.0 then
                _currentGarage = _park['Name']
                _drawHelpText(Config['Text']['OpenMenu'])
                if IsControlJustReleased(0, 38) then
                    _openParkingMenu(_park['ParkSpots'])
                end
            end
        end
    end)
end

local function _createParkingSpots(_spots)
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(1000)
            for _idx, _location in pairs(_spots) do
                if #(GetEntityCoords(PlayerPedId()) - vector3(_location['x'], _location['y'], _location['z'])) < 2.0 then
                    if IsPedInAnyVehicle(PlayerPedId(), false) then
                        if Config['FrameworkSettings']['Framework'] == 'QBCore' then
                            QBCore.Functions.TriggerCallback('3core-parking:checkIfOwned', function(_isOwned)
                                if _isOwned then
                                    _closeToSpot = _location
                                end
                            end, {['x'] = _location['x'], ['y'] = _location['y'], ['z'] = _location['z']})
                        elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
                            ESX.TriggerServerCallback('3core-parking:checkIfOwned', function(_isOwned)
                                if _isOwned then
                                    _closeToSpot = _location
                                end
                            end, {['x'] = _location['x'], ['y'] = _location['y'], ['z'] = _location['z']})
                        end
                    end
                elseif _closeToSpot then
                    _closeToSpot = false
                end
            end
        end
    end)
end

local _entityEnumerator = {
    __gc = function(_enum)
        if _enum.destructor and _enum.handle then
            _enum.destructor(_enum.handle)
        end
        _enum.destructor = nil
        _enum.handle = nil
    end
}

local function _enumerateEntities(_initFunc, _moveFunc, _disposeFunc)
    return coroutine.wrap(function()
        local _iter, _id = _initFunc()
        if not _id or _id == 0 then
            _disposeFunc(_iter)
            return
        end
        local _enum = {_handle = _iter, _destructor = _disposeFunc}
        setmetatable(_enum, _entityEnumerator)
        local _next = true
        repeat
            coroutine.yield(_id)
            _next, _id = _moveFunc(_iter)
        until not _next
        _enum.destructor, _enum.handle = nil, nil
        _disposeFunc(_iter)
    end)
end

local function _enumerateVehicles()
    local _vehicles = _enumerateEntities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
    local _returnVehicles = {}
	for _vehicle in _vehicles do
		table.insert(_returnVehicles, _vehicle)
	end
	return _returnVehicles
end

local function _checkIfClear(_coords)
    local _allVehicles = _enumerateVehicles()
    local _vehicleInArea = {}
    for _idx, _vehicle in pairs(_allVehicles) do
        if #(GetEntityCoords(_vehicle) - _coords) < 2.0 then
            table.insert(_vehicleInArea, _vehicle)
        end
	end
    return #_vehicleInArea == 0
end

local function _notify(_message)
    SetNotificationTextEntry('STRING')
	AddTextComponentSubstringPlayerName(_message)
	DrawNotification(false, true)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if _closeToSpot then
            _drawHelpText(Config['Text']['ParkCar'])
            if IsControlJustPressed(0, 38) then
                if Config['FrameworkSettings']['Framework'] == 'QBCore' then
                    QBCore.Functions.TriggerCallback('3core-parking:checkVehicle', function(_isOwned)
                        if _isOwned then
                            DoScreenFadeOut(1000)
                            Citizen.Wait(1000)
                            local _vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                            TriggerServerEvent('3core-parking:changeState', GetVehicleNumberPlateText(_vehicle), true)
                            SetEntityCoords(_vehicle, _closeToSpot['x'], _closeToSpot['y'], _closeToSpot['z'])
                            SetEntityHeading(_vehicle, _closeToSpot['w'])
                            Citizen.Wait(1000)
                            DoScreenFadeIn(1000)
                            TaskLeaveVehicle(PlayerPedId(), _vehicle, 0)
                            SetVehicleDoorsLocked(_vehicle, 2)
                            while IsPedInAnyVehicle(PlayerPedId(), false) do Citizen.Wait(0) end
                            DeleteEntity(_vehicle)
                            _closeToSpot = false
                        else
                            _notify(Config['Text']['NotOwned'])
                        end
                    end, GetVehicleNumberPlateText(GetVehiclePedIsIn(PlayerPedId(), false)))
                elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
                    ESX.TriggerServerCallback('3core-parking:checkVehicle', function(_isOwned)
                        if _isOwned then
                            DoScreenFadeOut(1000)
                            Citizen.Wait(1000)
                            local _vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                            TriggerServerEvent('3core-parking:changeState', GetVehicleNumberPlateText(_vehicle), true)
                            SetEntityCoords(_vehicle, _closeToSpot['x'], _closeToSpot['y'], _closeToSpot['z'])
                            SetEntityHeading(_vehicle, _closeToSpot['w'])
                            Citizen.Wait(1000)
                            DoScreenFadeIn(1000)
                            TaskLeaveVehicle(PlayerPedId(), _vehicle, 0)
                            SetVehicleDoorsLocked(_vehicle, 2)
                            while IsPedInAnyVehicle(PlayerPedId(), false) do Citizen.Wait(0) end
                            DeleteEntity(_vehicle)
                            _closeToSpot = false
                        else
                            _notify(Config['Text']['NotOwned'])
                        end
                    end, GetVehicleNumberPlateText(GetVehiclePedIsIn(PlayerPedId(), false)))
                end
            end
        end
    end
end)

local function _createParking()
    for _idx, _park in pairs(Config['Parking']) do
        _createBlip(_park['Blip'])
        _createNpc(_park)
        _createParkingSpots(_park['ParkSpots'])
    end
end

Citizen.CreateThread(function()
	while true do
		Citizen.Wait(0)
		if NetworkIsSessionStarted() then
			_createParking()
			return
		end
	end
end)

RegisterNUICallback('close', function(_data, _cb)
    SetNuiFocus(false, false)
end)

RegisterNUICallback('buySpot', function(_data, _cb)
    TriggerServerEvent('3core-parking:buySpot', _currentGarage, tonumber(_data['locationIndex']))
end)

RegisterNUICallback('cancel', function(_data, _cb)
    TriggerServerEvent('3core-parking:cancel', _currentGarage, tonumber(_data['locationIndex']))
end)

RegisterNUICallback('confirmDialog', function(_data, _cb)
    local _garage = _findGarageByName(_currentGarage)
    if _garage then
        local _location = _garage['ParkSpots'][tonumber(_data['locationIndex'])]
        if _checkIfClear(vector3(_location['x'], _location['y'], _location['z'])) then
            if Config['FrameworkSettings']['Framework'] == 'QBCore' then
                QBCore.Functions.SpawnVehicle(_data['selectedVehicle']['Hash'], function(_vehicle)
                    SetVehicleNumberPlateText(_vehicle, _data['selectedVehicle']['Plate'])
                    SetVehicleDoorsLocked(_vehicle, 2)
                    QBCore.Functions.SetVehicleProperties(_vehicle, _data['selectedVehicle']['Mods'])
                    TriggerEvent('vehiclekeys:client:SetOwner', _data['selectedVehicle']['Plate'])
                    TriggerServerEvent('3core-parking:changeState', _data['selectedVehicle']['Plate'], false)
                    _cb({['success'] = true, ['message'] = Config['Text']['SpotSpawn']})
                end, _location)
            elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
                ESX.Game.SpawnVehicle(_data['selectedVehicle']['Hash'], vector3(_location['x'], _location['y'], _location['z']), _location['w'], function(_vehicle)
                    SetVehicleNumberPlateText(_vehicle, _data['selectedVehicle']['Plate'])
                    --SetVehicleDoorsLocked(_vehicle, 2)
                    ESX.Game.SetVehicleProperties(_vehicle, _data['selectedVehicle']['Mods'])
                    TriggerServerEvent('3core-parking:changeState', _data['selectedVehicle']['Plate'], false)
                    _cb({['success'] = true, ['message'] = Config['Text']['SpotSpawn']})
                end)
            end
        else
            _cb({['success'] = false, ['message'] = Config['Text']['SpotTaken']})
        end
    end
end)

RegisterNetEvent('3core-parking:updateSpots', function(_parkingSpots)
    SendNUIMessage({type = 'updateSpots', parkingSpots = _parkingSpots})
end)

RegisterNetEvent('3core-parking:notify', function(_message)
    _notify(_message)
end)

RegisterNetEvent('onResourceStop', function(_name)
    if GetCurrentResourceName() ~= _name then return end
    for _idx, _ped in pairs(_createdPeds) do DeleteEntity(_ped) end
end)