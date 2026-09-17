local QBCore = nil
local ESX = nil

if Config['FrameworkSettings']['Framework'] == 'QBCore' then
    local _fileName = Config['FrameworkSettings']['QBCoreFileName']
    QBCore = exports[_fileName]:GetCoreObject()
elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
    TriggerEvent(Config['FrameworkSettings']['ESXEvent'], function(obj) ESX = obj end)
end

local function _fetchGarageSpots(_garageName)
    local _parkingDatabase = sqlWrapper('SELECT * FROM 3core_parking', {})
    local _garageSpots = {}
    for _idx, _value in pairs(_parkingDatabase) do
        if _value['garage'] == _garageName then
            table.insert(_garageSpots, _value)
        end
    end
    return _garageSpots
end

local function _checkIfFree(_location)
    local _parkingDatabase = sqlWrapper('SELECT * FROM 3core_parking', {})
    for _idx, _value in pairs(_parkingDatabase) do
        local _vlocation = json.decode(_value['location'])
        if (tostring(_vlocation['x']) == tostring(_location['x'])) and (tostring(_vlocation['y']) == tostring(_location['y'])) and (tostring(_vlocation['z']) == tostring(_location['z'])) then
            return false
        end
    end
    return true
end

local function _checkIfOwner(_source, _location)
    local _parkingDatabase = sqlWrapper('SELECT * FROM 3core_parking', {})
    for _idx, _value in pairs(_parkingDatabase) do
        local _vlocation = json.decode(_value['location'])
        if (tostring(_vlocation['x']) == tostring(_location['x'])) and (tostring(_vlocation['y']) == tostring(_location['y'])) and (tostring(_vlocation['z']) == tostring(_location['z'])) then
            if Config['FrameworkSettings']['Framework'] == 'QBCore' then
                local _player = QBCore.Functions.GetPlayerByCitizenId(_value['identifier'])
                if _player then
                    return _player.PlayerData.source == _source
                else
                    return false
                end
            elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
                local _player = ESX.GetPlayerFromIdentifier(_value['identifier'])
                if _player then
                    return _player.source == _source
                else
                    return false
                end
            end
        end
    end
    return false
end

local function _findGarageByName(_name)
    for _idx, _garage in pairs(Config['Parking']) do
        if _garage['Name'] == _name then
            return _garage
        end
    end
    return nil
end

local function _fetchOwnedVehicles(_source)
    if Config['FrameworkSettings']['Framework'] == 'QBCore' then
        local _player = QBCore.Functions.GetPlayer(_source)
        local _vehicles = sqlWrapper('SELECT * FROM player_vehicles WHERE citizenid = ?', {_player.PlayerData.citizenid})
        local _playerVehicles = {}
        for _idx, _vehicle in pairs(_vehicles) do
            if _vehicle['state'] == 1 then
                table.insert(_playerVehicles, {
                    ['Label'] = _vehicle['vehicle'],
                    ['Hash'] = tonumber(_vehicle['hash']),
                    ['Mods'] = json.decode(_vehicle['mods']),
                    ['Plate'] = _vehicle['plate']
                })
            end
        end
        return _playerVehicles
    elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
        local _player = ESX.GetPlayerFromId(_source)
        local _vehicles = sqlWrapper('SELECT * FROM owned_vehicles WHERE owner = ?', {_player.identifier})
        local _playerVehicles = {}
        for _idx, _vehicle in pairs(_vehicles) do
            if _vehicle['stored'] == 1 then
                local _vehicleData = json.decode(_vehicle['vehicle'])
                table.insert(_playerVehicles, {
                    ['Label'] = _vehicleData['model'],
                    ['Hash'] = _vehicleData['model'],
                    ['Mods'] = _vehicleData,
                    ['Plate'] = _vehicle['plate']
                })
            end
        end
        return _playerVehicles
    end
end

if Config['FrameworkSettings']['Framework'] == 'QBCore' then
    QBCore.Functions.CreateCallback('3core-parking:fetchSpots', function(_source, _cb, _defaultLocations)
        local _garageLocations = {}
        local _freeSpaces = 0
        for _idx = 1, #_defaultLocations do
            if _checkIfFree(_defaultLocations[_idx]) then _freeSpaces = _freeSpaces + 1 end
            _garageLocations[_idx] = {
                ['Free'] = _checkIfFree(_defaultLocations[_idx]),
                ['CoordsIdx'] = _idx,
                ['IsOwner'] = _checkIfOwner(_source, _defaultLocations[_idx])
            }
        end
        local _headerData = {
            ['FreeSpaces'] = _freeSpaces,
            ['Balance'] = QBCore.Functions.GetPlayer(_source).Functions.GetMoney('bank')
        }
        local _ownedVehicles = _fetchOwnedVehicles(_source)
        _cb(_garageLocations, _headerData, _ownedVehicles)
    end)
    QBCore.Functions.CreateCallback('3core-parking:checkIfOwned', function(_source, _cb, _location)
        _cb(_checkIfOwner(_source, _location))
    end)
    QBCore.Functions.CreateCallback('3core-parking:checkVehicle', function(_source, _cb, _plate)
        local _player = QBCore.Functions.GetPlayer(_source)
        local _vehicleDatabase = sqlWrapper('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {_plate, _player.PlayerData.citizenid})
        _cb(_vehicleDatabase[1])
    end)
elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
    ESX.RegisterServerCallback('3core-parking:fetchSpots', function(_source, _cb, _defaultLocations)
        local _garageLocations = {}
        local _freeSpaces = 0
        for _idx = 1, #_defaultLocations do
            if _checkIfFree(_defaultLocations[_idx]) then _freeSpaces = _freeSpaces + 1 end
            _garageLocations[_idx] = {
                ['Free'] = _checkIfFree(_defaultLocations[_idx]),
                ['CoordsIdx'] = _idx,
                ['IsOwner'] = _checkIfOwner(_source, _defaultLocations[_idx])
            }
        end
        local _headerData = {
            ['FreeSpaces'] = _freeSpaces,
            ['Balance'] = ESX.GetPlayerFromId(_source).getAccount('bank').money
        }
        local _ownedVehicles = _fetchOwnedVehicles(_source)
        _cb(_garageLocations, _headerData, _ownedVehicles)
    end)
    ESX.RegisterServerCallback('3core-parking:checkIfOwned', function(_source, _cb, _location)
        _cb(_checkIfOwner(_source, _location))
    end)
    ESX.RegisterServerCallback('3core-parking:checkVehicle', function(_source, _cb, _plate)
        local _player = ESX.GetPlayerFromId(_source)
        local _vehicleDatabase = sqlWrapper('SELECT * FROM owned_vehicles WHERE plate = ? AND owner = ?', {_plate, _player.identifier})
        _cb(_vehicleDatabase[1])
    end)
end

local function _updateSpots(_source, _name)
    local _garage = _findGarageByName(_name)
    local _garageLocations = {}
    for _idx = 1, #_garage['ParkSpots'] do
        _garageLocations[_idx] = {
            ['Free'] = _checkIfFree(_garage['ParkSpots'][_idx]),
            ['CoordsIdx'] = _idx,
            ['IsOwner'] = _checkIfOwner(_source, _garage['ParkSpots'][_idx])
        }
    end
    TriggerClientEvent('3core-parking:updateSpots', -1, _garageLocations)
end

RegisterServerEvent('3core-parking:buySpot', function(_garage, _index)
    local _src = source
    local _garageConfig = _findGarageByName(_garage)
    if _garageConfig then
        if Config['FrameworkSettings']['Framework'] == 'QBCore' then
            local _player = QBCore.Functions.GetPlayer(_src)
            local _location = {x = _garageConfig['ParkSpots'][_index]['x'], y = _garageConfig['ParkSpots'][_index]['y'], z = _garageConfig['ParkSpots'][_index]['z']}
            if _player.Functions.GetMoney('bank') >= _garageConfig['Price'] then
                _player.Functions.RemoveMoney('bank', _garageConfig['Price'])
                sqlWrapper('INSERT INTO 3core_parking (identifier, garage, location) VALUES (?, ?, ?)', {_player.PlayerData.citizenid, _garage, json.encode(_location)})
                _updateSpots(_src, _garage)
            else
                TriggerClientEvent('3core-parking:notify', _src, Config['Text']['NotEnough'])
            end
        elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
            local _player = ESX.GetPlayerFromId(_src)
            local _location = {x = _garageConfig['ParkSpots'][_index]['x'], y = _garageConfig['ParkSpots'][_index]['y'], z = _garageConfig['ParkSpots'][_index]['z']}
            if _player.getAccount('bank').money >= _garageConfig['Price'] then
                _player.removeAccountMoney('bank', _garageConfig['Price'])
                sqlWrapper('INSERT INTO 3core_parking (identifier, garage, location) VALUES (?, ?, ?)', {_player.identifier, _garage, json.encode(_location)})
                _updateSpots(_src, _garage)
            else
                TriggerClientEvent('3core-parking:notify', _src, Config['Text']['NotEnough'])
            end
        end
    end
end)

RegisterServerEvent('3core-parking:cancel', function(_garage, _index)
    if Config['FrameworkSettings']['Framework'] == 'QBCore' then
        local _src = source
        local _player = QBCore.Functions.GetPlayer(_src)
        local _garageConfig = _findGarageByName(_garage)
        local _playerSpots = sqlWrapper('SELECT * FROM 3core_parking WHERE garage = ? AND identifier = ?', {_garage, _player.PlayerData.citizenid})
        if _garageConfig then
            local _garageLocation = _garageConfig['ParkSpots'][_index]
            for _idx, _spot in pairs(_playerSpots) do
                local _spotCoords = json.decode(_spot['location'])
                if tostring(_spotCoords['x']) == tostring(_garageLocation['x']) and tostring(_spotCoords['y']) == tostring(_garageLocation['y']) and tostring(_spotCoords['z']) == tostring(_garageLocation['z']) then
                    sqlWrapper('DELETE FROM 3core_parking WHERE id = ?', {_spot['id']})
                    _updateSpots(_src, _garage)
                    return
                end
            end
        end
    elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
        local _src = source
        local _player = ESX.GetPlayerFromId(_src)
        local _garageConfig = _findGarageByName(_garage)
        local _playerSpots = sqlWrapper('SELECT * FROM 3core_parking WHERE garage = ? AND identifier = ?', {_garage, _player.identifier})
        if _garageConfig then
            local _garageLocation = _garageConfig['ParkSpots'][_index]
            for _idx, _spot in pairs(_playerSpots) do
                local _spotCoords = json.decode(_spot['location'])
                if tostring(_spotCoords['x']) == tostring(_garageLocation['x']) and tostring(_spotCoords['y']) == tostring(_garageLocation['y']) and tostring(_spotCoords['z']) == tostring(_garageLocation['z']) then
                    sqlWrapper('DELETE FROM 3core_parking WHERE id = ?', {_spot['id']})
                    _updateSpots(_src, _garage)
                    return
                end
            end
        end
    end
end)

RegisterServerEvent('3core-parking:changeState', function(_plate, _state)
    if Config['FrameworkSettings']['Framework'] == 'QBCore' then
        local _src = source
        local _player = QBCore.Functions.GetPlayer(_src)
        sqlWrapper('UPDATE player_vehicles SET state = ? WHERE plate = ? AND citizenid = ?', {_state, _plate, _player.PlayerData.citizenid})
    elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
        local _src = source
        local _player = ESX.GetPlayerFromId(_src)
        sqlWrapper('UPDATE owned_vehicles SET stored = ? WHERE plate = ? AND owner = ?', {_state, _plate, _player.identifier})
    end
end)

RegisterServerEvent('onResourceStart', function(_resourceName)
    if GetCurrentResourceName() ~= _resourceName then return end
    if Config['FrameworkSettings']['Framework'] == 'QBCore' then
        local _database = sqlWrapper('SELECT * FROM player_vehicles', {})
        for _idx, _value in pairs(_database) do
            sqlWrapper('UPDATE player_vehicles SET state = ? WHERE plate = ?', {1, _value['plate']})
        end
        print('[3Core Garages] Vehicle Reset Was Finished')
    elseif Config['FrameworkSettings']['Framework'] == 'ESX' then
        local _database = sqlWrapper('SELECT * FROM owned_vehicles', {})
        for _idx, _value in pairs(_database) do
            sqlWrapper('UPDATE owned_vehicles SET stored = ? WHERE plate = ?', {1, _value['plate']})
        end
        print('[3Core Garages] Vehicle Reset Was Finished')
    end
end)