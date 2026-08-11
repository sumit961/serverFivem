lib.locale(Bridge?.Config?.Language or 'en')

Editable = {}
Editable.activeUnits = {}

local ESX, QBCore = nil, nil
if GetResourceState('es_extended') == 'started' then
    ESX = exports['es_extended']:getSharedObject()

    AddEventHandler('esx:playerLoaded', function(player, xPlayer)
        if Config.Departments[xPlayer.job.name] then
            if not Editable.activeUnits[xPlayer.job.name] then
                Editable.activeUnits[xPlayer.job.name] = {}
            end

            local identifier = Bridge.Framework.getUniqueId(player)
            Editable.activeUnits[xPlayer.job.name][player] = {
                name = Bridge.Framework.getPlayerName(player),
                grade = xPlayer.job.grade_label,
                callsign = Base.playersData[identifier]?.callsign or locale('no_data'),
                status = Base.playersData[identifier]?.status or locale('no_data'),
                avatarUrl = Base.playersData[identifier]?.avatar or nil,
                coords = GetEntityCoords(GetPlayerPed(player))
            }
        end
    end)

    AddEventHandler('esx:setJob', function(player, job)
        if Config.Departments[job.name] then
            if not Editable.activeUnits[job.name] then
                Editable.activeUnits[job.name] = {}
            end

            local identifier = Bridge.Framework.getUniqueId(player)
            Editable.activeUnits[job.name][player] = {
                name = Bridge.Framework.getPlayerName(player),
                grade = job.grade_label,
                callsign = Base.playersData[identifier]?.callsign or locale('no_data'),
                status = Base.playersData[identifier]?.status or locale('no_data'),
                avatarUrl = Base.playersData[identifier]?.avatar or nil,
                coords = GetEntityCoords(GetPlayerPed(player))
            }
        end
    end)

    AddEventHandler('esx:playerDropped', function(player)
        local player = Bridge.Framework.getPlayerById(player)
        if player?.job?.name then
            if Editable.activeUnits[player.job.name] then
                Editable.activeUnits[player.job.name][player.source] = nil
            end
        end
    end)

    Citizen.CreateThread(function()
        Citizen.Wait(2500)
        local players = ESX.GetExtendedPlayers()
        for _, player in pairs(players) do
            if Config.Departments[player.job.name] then
                if not Editable.activeUnits[player.job.name] then
                    Editable.activeUnits[player.job.name] = {}
                end

                local identifier = Bridge.Framework.getUniqueId(player.source)
                Editable.activeUnits[player.job.name][player.source] = {
                    name = player.getName(),
                    grade = player.job.grade_label,
                    callsign = Base.playersData[identifier]?.callsign or locale('no_data'),
                    status = Base.playersData[identifier]?.status or locale('no_data'),
                    avatarUrl = Base.playersData[identifier]?.avatar or nil,
                    coords = GetEntityCoords(GetPlayerPed(player.source))
                }
            end
        end
    end)
elseif GetResourceState('qb-core') == 'started' then -- compatible with qbx_core
    QBCore = exports['qb-core']:GetCoreObject()

    RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
        local src = source
        Citizen.Wait(1000)
        local player = Bridge.Framework.getPlayerById(src)
        local jobName = player?.PlayerData?.job?.name
        if jobName and Config.Departments[jobName] then
            if not Editable.activeUnits[jobName] then
                Editable.activeUnits[jobName] = {}
            end

            local identifier = Bridge.Framework.getUniqueId(player.PlayerData.source)
            Editable.activeUnits[jobName][player.PlayerData.source] = {
                name = Bridge.Framework.getPlayerName(player.PlayerData.source),
                grade = player.PlayerData.job.grade.name,
                callsign = Base.playersData[identifier]?.callsign or locale('no_data'),
                status = Base.playersData[identifier]?.status or locale('no_data'),
                avatarUrl = Base.playersData[identifier]?.avatar or nil,
                coords = GetEntityCoords(GetPlayerPed(src))
            }
        end
    end)

    RegisterNetEvent('QBCore:Server:SetDuty', function(source, onDuty)
        local src = source
        local player = Bridge.Framework.getPlayerById(src)
        local jobName = player?.PlayerData?.job?.name
        if jobName and Config.Departments[jobName] then
            if onDuty then
                if not Editable.activeUnits[jobName] then
                    Editable.activeUnits[jobName] = {}
                end

                Editable.activeUnits[jobName][player.PlayerData.source] = {
                    name = Bridge.Framework.getPlayerName(player.PlayerData.source),
                    grade = player.PlayerData.job.grade.name,
                    callsign = Base.playersData[identifier]?.callsign or locale('no_data'),
                    status = Base.playersData[identifier]?.status or locale('no_data'),
                    avatarUrl = Base.playersData[identifier]?.avatar or nil,
                    coords = GetEntityCoords(GetPlayerPed(src))
                }
            else
                if Editable.activeUnits[jobName]?[player.PlayerData.source] then
                    Editable.activeUnits[jobName][player.PlayerData.source] = nil
                end
            end
        end
    end)

    AddEventHandler('playerDropped', function()
        local src = source
        local player = Bridge.Framework.getPlayerById(src)
        local jobName = player?.PlayerData?.job?.name
        if jobName and Config.Departments[jobName] then
            if Editable.activeUnits[jobName]?[player.PlayerData.source] then
                Editable.activeUnits[jobName][player.PlayerData.source] = nil
            end
        end
    end)
end

Citizen.CreateThread(function()
    while not Bridge or not Bridge.Framework do
        Citizen.Wait(100)
    end

    Editable.citizenId = Bridge.Framework.frameworkUniqueId() or 'citizenid'
end)


function Editable:getCitizensByQuery(sourceId, query, searchType)
    if not searchType then
        searchType = 'default'
    end

    if query then
        query = string.lower(query)
    end

    local cbData = {}
    if ESX then
        local index = 0
        local result = MySQL.query.await([[
            SELECT * FROM users
            WHERE LOWER(CONCAT(firstname, ' ', lastname)) LIKE @query
            OR LOWER(firstname) LIKE @query OR LOWER(lastname) LIKE @query
            OR ]] .. Editable.citizenId .. [[ LIKE @query
        ]], {
            ['@query'] = '%' .. query .. '%'
        })
        for k, v in ipairs(result) do
            index += 1
            if not v[Editable.citizenId] then
                lib.print.error(('Your unique id column doesnt exist in database, please make sure its correct and setup it in p_bridge config. Current unique id column: %s'):format(Editable.citizenId))
            end
            if searchType == 'simple' then
                cbData[index] = {
                    identifier = v.identifier,
                    name = ('%s %s'):format(v.firstname, v.lastname),
                    id = v[Editable.citizenId]
                }
            elseif searchType == 'global' then
                local fields = {
                    ('ID: %s'):format(v[Editable.citizenId]), 
                    ('DOB: %s'):format(v.dateofbirth or locale('no_data'))
                }
                cbData[index] = {
                    id = v.identifier,
                    title = ('%s %s'):format(v.firstname, v.lastname),
                    fields = fields
                }
            elseif searchType == 'default' then
                local profileData = Citizens:getCitizenProfile(v.identifier)
                local activeBolo = Bolo:getTargetBolo(v[Editable.citizenId])


                cbData[index] = {
                    identifier = v.identifier,
                    avatarUrl = profileData?.avatar or nil,
                    firstName = v.firstname,
                    lastName = v.lastname,
                    id = v[Editable.citizenId],
                    job = v.job,
                    metadata = {
                        {
                            label = locale('date_of_birth'),
                            value = v.dateofbirth or locale('no_data'),
                            icon = 'fa-light fa-cake-candles'
                        },
                        {
                            label = locale('gender'),
                            value = v.sex == 'm' and locale('male') or locale('female'),
                            icon = 'fa-light fa-venus-mars',
                        },
                        {
                            label = locale('nationality'),
                            value = v.nationality or v.country or 'USA',
                            icon = 'fa-light fa-globe'
                        },
                        {
                            label = locale('job'),
                            value = Base.jobLabels[v.job] or locale('no_data'),
                            icon = 'fa-light fa-briefcase'
                        },
                        {
                            label = locale('status'),
                            value = activeBolo and locale('status_bolo') or locale('ui_neutral'),
                            icon = activeBolo and 'fa-light fa-exclamation-triangle' or 'fa-light fa-check-circle',
                            color = activeBolo and 'red' or 'green'
                        }
                    }
                }

                if GetResourceState('m-Insurance') == 'started' then
                    local loadedInsurance = false
                    exports['m-Insurance']:HasHealthInsurance(v.identifier, function(hasInsurance)
                        table.insert(cbData[index].metadata, {
                            label = locale('health_insurance'),
                            value = hasInsurance and locale('has_insurance') or locale('no_insurance'),
                            icon = 'fa-light fa-heart-pulse',
                            color = hasInsurance and 'green' or 'red'
                        })
                        loadedInsurance = true
                    end)

                    while not loadedInsurance do Citizen.Wait(10) end
                end
            end
        end

        return cbData
    elseif QBCore then
        local index = 0
        local result = MySQL.query.await([[
            SELECT *, 
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
            FROM players
            WHERE LOWER(CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')))) LIKE @query
            OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname'))) LIKE @query 
            OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE @query
            OR ]] .. Editable.citizenId .. [[ LIKE @query
        ]], {
            ['@query'] = '%' .. query .. '%'
        })
        for k, v in ipairs(result) do
            index += 1
            if not v[Editable.citizenId] then
                lib.print.error(('Your unique id column doesnt exist in database, please make sure its correct and setup it in p_bridge config. Current unique id column: %s'):format(Editable.citizenId))
            end
            if searchType == 'simple' then
                cbData[index] = {
                    identifier = v.citizenid,
                    name = ('%s %s'):format(v.firstname, v.lastname),
                    id = v[Editable.citizenId]
                }
            elseif searchType == 'global' then
                local fields = {
                    ('%s: %s'):format(locale('id'), v[Editable.citizenId]), 
                    ('%s: %s'):format(locale('dob'), v.dateofbirth or locale('no_data'))
                }
                cbData[index] = {
                    id = v.citizenid,
                    title = ('%s %s'):format(v.firstname, v.lastname),
                    fields = fields
                }
            elseif searchType == 'default' then
                local profileData = Citizens:getCitizenProfile(v.citizenid)
                local activeBolo = Bolo:getTargetBolo(v[Editable.citizenId])
                cbData[index] = {
                    identifier =v.citizenid,
                    avatarUrl = profileData?.avatar or nil,
                    firstName = v.firstname,
                    lastName = v.lastname,
                    id = v[Editable.citizenId],
                    job = v.job,
                    metadata = {
                        {
                            label = locale('date_of_birth'),
                            value = json.decode(v.charinfo).birthdate or locale('no_data'),
                            icon = 'fa-light fa-cake-candles'
                        },
                        {
                            label = locale('gender'),
                            value = tonumber(json.decode(v.charinfo).gender) == 0 and locale('male') or locale('female'),
                            icon = 'fa-light fa-venus-mars',
                        },
                        {
                            label = locale('nationality'),
                            value = json.decode(v.charinfo).nationality or 'USA',
                            icon = 'fa-light fa-globe'
                        },
                        {
                            label = locale('job'),
                            value = json.decode(v.job).label or locale('no_data'),
                            icon = 'fa-light fa-briefcase'
                        },
                        {
                            label = locale('status'),
                            value = activeBolo and 'bolo' or 'neutral',
                            icon = activeBolo and 'fa-light fa-exclamation-triangle' or 'fa-light fa-check-circle',
                            color = activeBolo and 'red' or 'green'
                        }
                    }
                }

                if GetResourceState('m-Insurance') == 'started' then
                    local loadedInsurance = false
                    exports['m-Insurance']:HasHealthInsurance(v.citizenid, function(hasInsurance)
                        table.insert(cbData[index].metadata, {
                            label = locale('health_insurance'),
                            value = hasInsurance and locale('has_insurance') or locale('no_insurance'),
                            icon = 'fa-light fa-heart-pulse',
                            color = hasInsurance and 'green' or 'red'
                        })
                        loadedInsurance = true
                    end)

                    while not loadedInsurance do Citizen.Wait(10) end
                end
            end
        end

        return cbData
    end
end

function Editable:getCitizenProfile(identifier)
    if ESX then
        local result = MySQL.single.await([[
            SELECT * FROM users WHERE identifier = @id OR ]] .. Editable.citizenId .. [[ = @id
        ]], {['@id'] = identifier})
        if not result then
            return nil
        end

        if not result[Editable.citizenId] then
            lib.print.error(('Your unique id column doesnt exist in database, please make sure its correct and setup it in p_bridge config. Current unique id column: %s'):format(Editable.citizenId))
        end

        local profileData = Citizens:getCitizenProfile(identifier)
        local citizenProfileData = {
            identifier = identifier,
            uniqueId = result[Editable.citizenId],
            firstName = result.firstname,
            lastName = result.lastname,
            dateOfBirth = result.dateofbirth,
            gender = result.sex == 'm' and locale('male') or locale('female'),
            nationality = result.nationality or result.country or 'USA',
            job = result.job,
            avatarUrl = profileData?.avatar or nil,
            vehicles = Editable:getCitizenVehicles(identifier) or {},
            properties = Editable:getCitizenProperties(identifier) or {},
            licences = Editable:getCitizenLicences(identifier),
            judgments = Judgments:getCitizenJudgments(identifier),
            warrants = Warrants:getCitizenWarrants(result[Editable.citizenId]),
            reports = Reports:getCitizenReports(result[Editable.citizenId]),
            notes = profileData?.notes or {},
            metadata = {
                {
                    label = locale('first_name'),
                    value = result.firstname,
                    icon = 'fa-light fa-user',
                },
                {
                    label = locale('last_name'),
                    value = result.lastname,
                    icon = 'fa-light fa-user',
                },
                {
                    label = locale('date_of_birth'),
                    value = result.dateofbirth or locale('no_data'),
                    icon = 'fa-light fa-cake-candles'
                },
                {
                    label = locale('gender'),
                    value = result.sex == 'm' and locale('male') or locale('female'),
                    icon = 'fa-light fa-venus-mars',
                },
                {
                    label = locale('nationality'),
                    value = result.nationality or result.country or 'USA',
                    icon = 'fa-light fa-globe',
                },
                {
                    label = locale('job'),
                    value = Base.jobLabels[result.job] or locale('no_data'),
                    icon = 'fa-light fa-briefcase',
                },
                {
                    label = locale('citizen_id'),
                    value = result[Editable.citizenId],
                    icon = 'fa-light fa-id-card',
                },
            }
        }
        if GetResourceState('m-Insurance') == 'started' then
            local loadedInsurance = false
            exports['m-Insurance']:HasHealthInsurance(result.identifier, function(hasInsurance)
                table.insert(citizenProfileData.metadata, {
                    label = locale('health_insurance'),
                    value = hasInsurance and locale('has_insurance') or locale('no_insurance'),
                    icon = 'fa-light fa-heart-pulse',
                    color = hasInsurance and 'green' or 'red'
                })
                loadedInsurance = true
            end)

            while not loadedInsurance do Citizen.Wait(10) end
        end

        return citizenProfileData
    elseif QBCore then
        local result = MySQL.single.await([[
            SELECT *, 
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
            FROM players
            WHERE ]] .. Editable.citizenId .. [[ = @id
        ]], {['@id'] = identifier})
        if not result then
            return nil
        end

        local profileData = Citizens:getCitizenProfile(identifier)
        local charInfo = json.decode(result.charinfo)
        local jobData = json.decode(result.job)
        local citizenProfileData = {
            identifier = identifier,
            uniqueId = result[Editable.citizenId],
            firstName = result.firstname,
            lastName = result.lastname,
            dateOfBirth = charInfo.birthdate,
            gender = tonumber(charInfo.gender) == 0 and locale('male') or locale('female'),
            nationality = charInfo.nationality,
            job = jobData.label,
            avatarUrl = profileData?.avatar or nil,
            vehicles = Editable:getCitizenVehicles(identifier) or {},
            properties = Editable:getCitizenProperties(identifier) or {},
            licences = Editable:getCitizenLicences(identifier),
            judgments = Judgments:getCitizenJudgments(identifier),
            warrants = Warrants:getCitizenWarrants(result[Editable.citizenId]),
            reports = Reports:getCitizenReports(result[Editable.citizenId]),
            notes = profileData?.notes or {},
            metadata = {
                {
                    label = locale('first_name'),
                    value = result.firstname,
                    icon = 'fa-light fa-user',
                },
                {
                    label = locale('last_name'),
                    value = result.lastname,
                    icon = 'fa-light fa-user',
                },
                {
                    label = locale('date_of_birth'),
                    value = charInfo.birthdate or locale('no_data'),
                    icon = 'fa-light fa-cake-candles'
                },
                {
                    label = locale('gender'),
                    value = tonumber(charInfo.gender) == 0 and locale('male') or locale('female'),
                    icon = 'fa-light fa-venus-mars',
                },
                {
                    label = locale('nationality'),
                    value = charInfo.nationality or 'USA',
                    icon = 'fa-light fa-globe',
                },
                {
                    label = locale('job'),
                    value = jobData.label or locale('no_data'),
                    icon = 'fa-light fa-briefcase',
                },
                {
                    label = locale('citizen_id'),
                    value = result[Editable.citizenId],
                    icon = 'fa-light fa-id-card',
                },
            }
        }

        if GetResourceState('m-Insurance') == 'started' then
            local loadedInsurance = false
            exports['m-Insurance']:HasHealthInsurance(result.citizenid, function(hasInsurance)
                table.insert(citizenProfileData.metadata, {
                    label = locale('health_insurance'),
                    value = hasInsurance and locale('has_insurance') or locale('no_insurance'),
                    icon = 'fa-light fa-heart-pulse',
                    color = hasInsurance and 'green' or 'red'
                })
                loadedInsurance = true
            end)

            while not loadedInsurance do Citizen.Wait(10) end
        end

        return citizenProfileData
    end
end

function Editable:getVehiclesByQuery(sourceId, query, searchType)
    if not searchType then
        searchType = 'default'
    end

    local cbData = {}
    local index = 0
    if ESX then
        local result = MySQL.query.await([[
            SELECT owned_vehicles.*, users.firstname, users.lastname FROM owned_vehicles
            LEFT JOIN users ON owned_vehicles.owner = users.identifier
            WHERE owned_vehicles.plate LIKE @query
        ]], {
            ['@query'] = '%' .. query .. '%'
        })
        for k, v in ipairs(result) do
            index += 1
            if searchType == 'default' then
                local vehicleData = json.decode(v.vehicle)
                local activeBolo = Bolo:getTargetBolo(v.plate)
                local vehicleProfile = Vehicles:getVehicleProfile(v.plate)

                cbData[index] = {
                    ownerName = ('%s %s'):format(v.firstname, v.lastname),
                    owner = v.owner,
                    plate = v.plate,
                    model = vehicleData.model,
                    mods = vehicleData,
                    avatarUrl = vehicleProfile and vehicleProfile.avatar or nil,
                    status = activeBolo and 'bolo' or 'neutral',
                }
            elseif searchType == 'global' then
                cbData[index] = {
                    id = v.plate,
                    model = json.decode(v.vehicle).model,
                    -- no title because script will convert model to display name
                    fields = {
                        ('Owner: %s %s'):format(v.firstname, v.lastname),
                        -- script will convert model to display name
                        ('Plate: %s'):format(v.plate), 
                    }
                }
            elseif searchType == 'simple' then
                cbData[index] = {
                    id = v.plate,
                    ownerName = ('%s %s'):format(v.firstname, v.lastname),
                    model = json.decode(v.vehicle).model,
                }
            end
        end
    elseif QBCore then
        local result = MySQL.query.await([[
            SELECT player_vehicles.*, 
                JSON_UNQUOTE(JSON_EXTRACT(players.charinfo, '$.firstname')) as firstname,
                JSON_UNQUOTE(JSON_EXTRACT(players.charinfo, '$.lastname')) as lastname
            FROM player_vehicles
            LEFT JOIN players ON player_vehicles.citizenid = players.citizenid
            WHERE player_vehicles.plate LIKE @query
        ]], {
            ['@query'] = '%' .. query .. '%'
        })

        if Bridge?.Config?.Debug then
            lib.print.info('Vehicles by query result:', result)
        end

        for k, v in ipairs(result) do
            index += 1
            if searchType == 'default' then
                local activeBolo = Bolo:getTargetBolo(v.plate)
                local vehicleProfile = Vehicles:getVehicleProfile(v.plate)

                cbData[index] = {
                    ownerName = ('%s %s'):format(v.firstname, v.lastname),
                    owner = v.owner,
                    plate = v.plate,
                    model = v.vehicle,
                    mods = v.mods and json.decode(v.mods) or {},
                    avatarUrl = vehicleProfile and vehicleProfile.avatar or nil,
                    status = activeBolo and 'bolo' or 'neutral',
                    -- tags = {}
                }
            elseif searchType == 'global' then
                cbData[index] = {
                    id = v.plate,
                    model = v.vehicle,
                    -- no title because script will convert model to display name
                    fields = {
                        ('Owner: %s %s'):format(v.firstname, v.lastname),
                        -- script will convert model to display name
                        ('Plate: %s'):format(v.plate), 
                    }
                }
            elseif searchType == 'simple' then
                cbData[index] = {
                    id = v.plate,
                    ownerName = ('%s %s'):format(v.firstname, v.lastname),
                    model = v.vehicle,
                }
            end
        end
    end

    return cbData
end

function Editable:getVehicleColor(vehData)
    local mainColor = locale('no_data')
    if vehData?.color1 then
        mainColor = vehData.color1
    end
    return mainColor
end

function Editable:getVehicleProfile(sourceId, plate)
    local cbData = {}
    if ESX then
        local result = MySQL.single.await([[
            SELECT owned_vehicles.*, users.firstname, users.lastname FROM owned_vehicles
            LEFT JOIN users ON owned_vehicles.owner = users.identifier
            WHERE owned_vehicles.plate = @plate
        ]], {
            ['@plate'] = plate
        })
        if not result then
            return nil
        end

        local vehicleData = json.decode(result.vehicle)
        local activeBolo = Bolo:getTargetBolo(result.plate)
        local vehicleProfile = Vehicles:getVehicleProfile(result.plate)
        cbData = {
            ownerName = ('%s %s'):format(result.firstname, result.lastname),
            owner = result.owner,
            plate = result.plate,
            model = vehicleData.model,
            mods = vehicleData,
            status = activeBolo and 'bolo' or 'neutral',
            notes = vehicleProfile?.notes or {},
            photos = vehicleProfile?.photos or {},
            avatarUrl = vehicleProfile?.avatar or nil,
            bolos = Bolo:getTargetBolos(result.plate),
            reports = Reports:getVehicleReports(result.plate),
            warrants = Warrants:getVehicleWarrants(result.plate),
            incidents = Incidents:getVehicleIncidents(result.plate),
            metadata = {
                {
                    label = locale('model'),
                    value = vehicleData.model,
                    icon = 'fa-light fa-car-side',
                    isModel = true, -- it will get converted to display name in the UI
                },
                {
                    label = locale('owner'),
                    value = ('%s %s'):format(result.firstname, result.lastname),
                    icon = 'fa-light fa-user',
                },
                {
                    label = locale('plate'),
                    value = result.plate,
                    icon = 'fa-light fa-id-card',
                },
                {
                    label = locale('status'),
                    value = activeBolo and 'bolo' or 'neutral',
                    icon = activeBolo and 'fa-light fa-exclamation-triangle' or 'fa-light fa-check-circle',
                    color = activeBolo and 'red' or 'green'
                },
                {
                    label = locale('color'),
                    value = Editable:getVehicleColor(vehicleData),
                    icon = 'fa-light fa-palette',
                }
            }
        }
    elseif QBCore then
        local result = MySQL.single.await([[
            SELECT player_vehicles.*, 
                JSON_UNQUOTE(JSON_EXTRACT(players.charinfo, '$.firstname')) as firstname,
                JSON_UNQUOTE(JSON_EXTRACT(players.charinfo, '$.lastname')) as lastname
            FROM player_vehicles
            LEFT JOIN players ON player_vehicles.citizenid = players.citizenid
            WHERE player_vehicles.plate = @plate
        ]], {
            ['@plate'] = plate
        })
        if not result then
            return nil
        end

        local activeBolo = Bolo:getTargetBolo(result.plate)
        local vehicleProfile = Vehicles:getVehicleProfile(result.plate)
        cbData = {
            ownerName = ('%s %s'):format(result.firstname, result.lastname),
            owner = result.owner,
            plate = result.plate,
            model = result.vehicle,
            mods = json.decode(result.mods),
            status = activeBolo and 'bolo' or 'neutral',
            notes = vehicleProfile?.notes or {},
            photos = vehicleProfile?.photos or {},
            avatarUrl = vehicleProfile?.avatar or nil,
            bolos = Bolo:getTargetBolos(result.plate),
            reports = Reports:getVehicleReports(result.plate),
            warrants = Warrants:getVehicleWarrants(result.plate),
            incidents = Incidents:getVehicleIncidents(result.plate),
            metadata = {
                {
                    label = locale('model'),
                    value = result.vehicle,
                    icon = 'fa-light fa-car-side',
                    isModel = true, -- it will get converted to display name in the UI
                },
                {
                    label = locale('owner'),
                    value = ('%s %s'):format(result.firstname, result.lastname),
                    icon = 'fa-light fa-user',
                },
                {
                    label = locale('plate'),
                    value = result.plate,
                    icon = 'fa-light fa-id-card',
                },
                {
                    label = locale('status'),
                    value = activeBolo and 'bolo' or 'neutral',
                    icon = activeBolo and 'fa-light fa-exclamation-triangle' or 'fa-light fa-check-circle',
                    color = activeBolo and 'red' or 'green'
                },
                {
                    label = locale('color'),
                    value = Editable:getVehicleColor(vehicleData),
                    icon = 'fa-light fa-palette',
                }
            }
        }
    end

    if GetResourceState('m-Insurance') == 'started' then
        local hasInsurance = exports['m-Insurance']:HasCarInsurance(cbData.plate)
        table.insert(cbData.metadata, {
            label = locale('vehicle_insurance'),
            value = hasInsurance and locale('has_insurance') or locale('no_insurance'),
            icon = 'fa-light fa-shield-check',
            color = hasInsurance and 'green' or 'red'
        })
    end
    
    return cbData
end

function Editable:getCitizenVehicles(identifier)
    local cbData = {}
    if ESX then
        local result = MySQL.query.await([[
            SELECT * FROM owned_vehicles WHERE owner = ?
        ]], {identifier})
        for k, v in ipairs(result) do
            local vehicleData = json.decode(v.vehicle)
            local activeBolo = Bolo:getTargetBolo(v.plate)
            cbData[k] = {
                plate = v.plate,
                model = vehicleData.model,
                mods = vehicleData,
                status = activeBolo and 'bolo' or 'neutral'
            }
        end
    elseif QBCore then
        local result = MySQL.query.await([[
            SELECT * FROM player_vehicles WHERE citizenid = ?
        ]], {identifier})
        for k, v in ipairs(result) do
            local vehicleData = json.decode(v.mods)
            local activeBolo = Bolo:getTargetBolo(v.plate)
            cbData[k] = {
                plate = v.plate,
                model = v.vehicle,
                mods = vehicleData,
                status = activeBolo and 'bolo' or 'neutral'
            }
        end
    end

    return cbData
end

function Editable:fetchEmployees(sourceId)
    local playerJob = Bridge.Framework.getPlayerJob(sourceId)
    if not playerJob then
        return {}
    end

    if Base.playersCache[sourceId]?['employees'] then
        local cacheData = Base.playersCache[sourceId]['employees']
        if os.time() - cacheData.timestamp < 5 then
            return cacheData.data
        end
    end

    local jobGradesData = Base.jobsData[playerJob.name]
    local alreadyAdded = {}
    local cbData = {}
    if ESX then
        local result = MySQL.query.await('SELECT * FROM users WHERE job = ?', {playerJob.name})
        for k, v in ipairs(result) do
            local player = Bridge.Framework.getPlayerByUniqueId(v.identifier)
            cbData[k] = {
                source = player?.source or nil,
                name = ('%s %s'):format(v.firstname, v.lastname),
                id = v.identifier,
                uniqueId = v[Editable.citizenId],
                duty = player and Bridge.Framework.CheckJobDuty(player.source) or false,
                rank = jobGradesData[v.job_grade]?.label or locale('no_data'),
                grade = tostring(v.job_grade),
                callsign = Base.playersData[v.identifier]?.callsign or locale('no_data'),
                unit = Base.playersData[v.identifier]?.unit or locale('no_data'),
                status = Base.playersData[v.identifier]?.status or locale('no_data'),
                avatar = Base.playersData[v.identifier]?.avatar or nil,
                licences = Base.playersLicences[v.identifier] or {},
                coords = player and GetEntityCoords(GetPlayerPed(player.source)) or nil
            }
            alreadyAdded[v.identifier] = true
        end

        -- add online players who might not be in the database result (e.g., new hires)
        local players = ESX.GetExtendedPlayers('job', playerJob.name)
        for k, v in ipairs(players) do
            if alreadyAdded[v.identifier] then
                goto continue
            end

            alreadyAdded[v.identifier] = true
            cbData[k] = {
                source = v.source,
                name = ('%s %s'):format(v.get('firstName'), v.get('lastName')),
                uniqueId = v[Editable.citizenId],
                id = v.identifier,
                duty = Bridge.Framework.CheckJobDuty(v.source),
                rank = jobGradesData[tostring(v.job.grade)]?.label or locale('no_data'),
                grade = tostring(v.job.grade),
                callsign = Base.playersData[v.identifier]?.callsign or locale('no_data'),
                unit = Base.playersData[v.identifier]?.unit or locale('no_data'),
                status = Base.playersData[v.identifier]?.status or locale('no_data'),
                avatar = Base.playersData[v.identifier]?.avatar or nil,
                coords = GetEntityCoords(GetPlayerPed(v.source)),
                licences = Base.playersLicences[v.identifier] or {}
            }

            ::continue::
        end
    elseif QBCore then
        local result = MySQL.query.await([[
            SELECT *, 
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
            FROM players
            WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?
        ]], {playerJob.name})
        for k, v in ipairs(result) do
            local player = Bridge.Framework.getPlayerByUniqueId(v.citizenid)
            local charInfo = json.decode(v.charinfo)
            local jobInfo = json.decode(v.job)
            cbData[k] = {
                source = player?.PlayerData?.source or nil,
                name = ('%s %s'):format(v.firstname, v.lastname),
                id = v.citizenid,
                uniqueId = v[Editable.citizenId],
                duty = player and Bridge.Framework.CheckJobDuty(player?.PlayerData?.source) or false,
                rank = player and player.PlayerData.job.grade.name or jobInfo.grade.name,
                grade = player and tostring(player.PlayerData.job.grade.level) or tostring(jobInfo.grade.level),
                callsign = Base.playersData[v.citizenid]?.callsign or locale('no_data'),
                unit = Base.playersData[v.citizenid]?.unit or locale('no_data'),
                status = Base.playersData[v.citizenid]?.status or locale('no_data'),
                avatar = Base.playersData[v.citizenid]?.avatar or nil,
                licences = Base.playersLicences[v.citizenid] or {},
                coords = player and GetEntityCoords(GetPlayerPed(player.PlayerData.source)) or nil
            }
            alreadyAdded[v.citizenid] = true
        end

        -- add online players who might not be in the database result (e.g., new hires)
        for k, v in pairs(QBCore.Functions.GetPlayers()) do
            local player = Bridge.Framework.getPlayerById(v)
            if player?.PlayerData?.job?.name == playerJob.name then
                if alreadyAdded[player.PlayerData.citizenid] then
                    goto continue
                end

                alreadyAdded[player.PlayerData.citizenid] = true
                cbData[k] = {
                    source = player.PlayerData.source,
                    name = Bridge.Framework.getPlayerName(player.PlayerData.source),
                    id = player.PlayerData.citizenid,
                    uniqueId = player.PlayerData[Editable.citizenId],
                    duty = Bridge.Framework.CheckJobDuty(player.PlayerData.source),
                    rank = player.PlayerData.job.grade.name or locale('no_data'),
                    grade = tostring(player.PlayerData.job.grade.level) or '0',
                    callsign = Base.playersData[player.PlayerData.citizenid]?.callsign or locale('no_data'),
                    unit = Base.playersData[player.PlayerData.citizenid]?.unit or locale('no_data'),
                    status = Base.playersData[player.PlayerData.citizenid]?.status or locale('no_data'),
                    avatar = Base.playersData[player.PlayerData.citizenid]?.avatar or nil,
                    coords = GetEntityCoords(GetPlayerPed(player.PlayerData.source)),
                    licences = Base.playersLicences[player.PlayerData.citizenid] or {}
                }
            end

            ::continue::
        end
    end

    if Config.UseCache then
        Base.playersCache[sourceId] = Base.playersCache[sourceId] or {}
        Base.playersCache[sourceId]['employees'] = {data = cbData, timestamp = os.time()} -- save to cache for few seconds to avoid spamming requests
    end

    return cbData
end

function Editable:fetchEmployeesByQuery(sourceId, query)
    local allEmployees = self:fetchEmployees(sourceId)
    local cbData = {}
    local index = 0
    for k, v in pairs(allEmployees) do
        if string.find(string.lower(v.name), string.lower(query), 1, true) then
            index = index + 1
            cbData[index] = v
        end
    end

    return cbData
end

function Editable:hireEmployee(sourceId, data)
    local playerJob = Bridge.Framework.getPlayerJob(sourceId)
    if not playerJob or not Config.Departments[playerJob.name] then
        return false
    end

    local uniqueId = Bridge.Framework.getUniqueId(sourceId)
    local targetId = tonumber(data.id)
    if sourceId == targetId then
        Bridge.Notify.showNotify(sourceId, locale('cannot_hire_yourself'), 'error')
        return false
    end

    local targetPlayer = Bridge.Framework.getPlayerById(targetId)
    if not targetPlayer then
        Bridge.Notify.showNotify(sourceId, locale('player_not_found'), 'error')
        return false
    end

    if not Permissions.hasPerm(sourceId, 'employees.hire') then
        Bridge.Notify.showNotify(sourceId, locale('no_permission'), 'error')
        return false
    end

    if tonumber(data.grade) > tonumber(playerJob.grade) then
        Bridge.Notify.showNotify(sourceId, locale('grade_too_high'), 'error')
        return false
    end

    local result = lib.callback.await('p_mdt/client/employees/hireRequest', targetPlayer.source, {
        jobLabel = Config.Departments[playerJob.name].label,
        gradeLabel = Base.jobsData[playerJob.name][tonumber(data.grade)]?.label or 'N/A',
        playerName = Bridge.Framework.getPlayerName(sourceId)
    })
    if result then
        Bridge.Framework.SetJob(targetPlayer.source, playerJob.name, tonumber(data.grade))
        Bridge.Notify.showNotify(sourceId, locale('employee_hired_success', Bridge.Framework.getPlayerName(targetPlayer.source)), 'success')
        Logs:new(_source, {
            category = 'employees',
            action = 'hire',
            message = ('Hired new employee %s'):format(data.id)
        })
        return {
            source = targetPlayer.source,
            name = Bridge.Framework.getPlayerName(targetPlayer.source),
            id = targetPlayer.identifier,
            duty = Bridge.Framework.CheckJobDuty(targetPlayer.source),
            rank = Base.jobsData[playerJob.name][tonumber(data.grade)]?.label or locale('no_data'),
            grade = tostring(data.grade),
            callsign = Base.playersData[targetPlayer.identifier]?.callsign or locale('no_data'),
            unit = Base.playersData[targetPlayer.identifier]?.unit or locale('no_data'),
            status = Base.playersData[targetPlayer.identifier]?.status or locale('no_data'),
            avatar = Base.playersData[targetPlayer.identifier]?.avatar or nil,
            licences = {}
        }
    else
        Bridge.Notify.showNotify(sourceId, locale('employee_hire_declined'), 'error')
    end

    return false
end

function Editable:fireEmployee(sourceId, data)
    local playerJob = Bridge.Framework.getPlayerJob(sourceId)
    if not playerJob or not Config.Departments[playerJob.name] then
        return false
    end

    if not Permissions.hasPerm(sourceId, 'employees.fire') then
        Bridge.Notify.showNotify(sourceId, locale('no_permission'), 'error')
        return false
    end

    local uniqueId = Bridge.Framework.getUniqueId(sourceId)
    if tostring(uniqueId) == tostring(data.id) then
        Bridge.Notify.showNotify(sourceId, locale('cannot_fire_yourself'), 'error')
        return false
    end

    local targetPlayer = Bridge.Framework.getPlayerByUniqueId(data.id)
    if not targetPlayer then
        local offlinePlayer = Bridge.Framework.getOfflinePlayerByUniqueId(data.id)
        if not offlinePlayer then
            Bridge.Notify.showNotify(sourceId, locale('player_not_found'), 'error')
            return false
        end

        if tonumber(offlinePlayer.job_grade) > tonumber(playerJob.grade) then
            Bridge.Notify.showNotify(sourceId, locale('grade_too_high'), 'error')
            return false
        end

        local result = Bridge.Framework.SetOfflineJob(data.id, 'unemployed', 0)
        if result then
            Bridge.Notify.showNotify(sourceId, locale('employee_fired_success', ('%s %s'):format(offlinePlayer.firstname, offlinePlayer.lastname)), 'success')
            Logs:new(_source, {
                category = 'employees',
                action = 'fire',
                message = ('Fired employee %s'):format(data.id)
            })
            return true
        end
    else
        local targetPlayerJob = Bridge.Framework.getPlayerJob(targetPlayer.source)
        if not targetPlayerJob or targetPlayerJob.name ~= playerJob.name then
            Bridge.Notify.showNotify(sourceId, locale('player_not_in_your_department'), 'error')
            return false
        end

        Bridge.Framework.SetJob(targetPlayer.source, 'unemployed', 0)
        Bridge.Notify.showNotify(sourceId, locale('employee_fired_success', Bridge.Framework.getPlayerName(targetPlayer.source)), 'success')
        Bridge.Notify.showNotify(targetPlayer.source, locale('you_have_been_fired', data.reason), 'success')
        Logs:new(_source, {
            category = 'employees',
            action = 'fire',
            message = ('Fired employee %s'):format(data.id)
        })
        return true
    end


    return false
end

function Editable:updateEmployee(sourceId, data)
    local playerJob = Bridge.Framework.getPlayerJob(sourceId)
    if not playerJob or not Config.Departments[playerJob.name] then
        return false
    end

    if not Permissions.hasPerm(sourceId, 'employees.update_grade') then
        Bridge.Notify.showNotify(sourceId, locale('no_permission'), 'error')
        return false
    end

    local targetPlayer = Bridge.Framework.getPlayerByUniqueId(data.id)
    if not targetPlayer then
        Bridge.Notify.showNotify(sourceId, locale('player_not_found'), 'error')
        return false
    end

    if sourceId == targetPlayer.source then
        Bridge.Notify.showNotify(sourceId, locale('cannot_update_yourself'), 'error')
        return false
    end

    local targetPlayerJob = Bridge.Framework.getPlayerJob(targetPlayer.source)
    if not targetPlayerJob or targetPlayerJob.name ~= playerJob.name then
        Bridge.Notify.showNotify(sourceId, locale('player_not_in_your_department'), 'error')
        return false
    end

    if not data.grade then
        goto skipGrade
    end

    if tonumber(data.grade) > tonumber(playerJob.grade) then
        Bridge.Notify.showNotify(sourceId, locale('grade_too_high'), 'error')
        return false
    end

    Bridge.Framework.SetJob(targetPlayer.source, playerJob.name, tonumber(data.grade))
    Bridge.Notify.showNotify(sourceId, locale('employee_updated_success', Bridge.Framework.getPlayerName(targetPlayer.source)), 'success')
    Bridge.Notify.showNotify(targetPlayer.source, locale('your_job_updated', Base.jobsData[playerJob.name][tonumber(data.grade)]?.label or 'N/A'), 'success')

    ::skipGrade::
    Logs:new(_source, {
        category = 'employees',
        action = 'update',
        message = ('Updated employee grade / licences %s'):format(data.id)
    })
    if data.licences then
        Employees:updateLicences(data.id, data.licences)
    end
    return true
end

function Editable:issueJudgment(sourceId, data)
    local targetIds = {}
    for k, v in pairs(data.citizens) do
        local targetPlayer = Bridge.Framework.getPlayerByUniqueId(v.identifier)
        if not targetPlayer then
            Bridge.Notify.showNotify(sourceId, locale('player_not_online', v.name), 'error')
            return
        end

        targetIds[#targetIds + 1] = targetPlayer.source
    end

    local fullReason = ''
    for k, v in pairs(data.charges) do
        if k == #data.charges then
            fullReason = fullReason..''..v.title
        else
            fullReason = fullReason..''..v.title..', '
        end
    end

    -- if GetResourceState('p_banking') == 'started' then
    --     if data.totalFine > 0 then
    --         local plyName = Bridge.Framework.getPlayerName(sourceId)
    --         local plyJob = Bridge.Framework.getPlayerJob(sourceId)
    --         local policeAccount = MySQL.single.await('SELECT * FROM p_bank_accounts WHERE owner = @owner OR owner = @owner2', {
    --             ['@owner'] = ('society_%s'):format(plyJob.name),
    --             ['@owner2'] = plyJob.name
    --         })
    --         if policeAccount?.iban then
    --             for _, targetId in ipairs(targetIds) do
    --                 print(targetId, 'target id')
    --                 local targetAccount = MySQL.single.await('SELECT * FROM p_bank_accounts WHERE owner = ?', {
    --                     Bridge.Framework.getUniqueId(targetId)
    --                 })
    --                 if targetAccount?.iban then
    --                     exports['p_banking']:createInvoice(targetAccount.iban, policeAccount.iban, plyName, data.totalFine, fullReason)
    --                 end
    --             end
    --         end
    --     end
    -- end

    if GetResourceState('okokBilling') == 'started' then
        if data.totalFine > 0 then
            local playerJob = Bridge.Framework.getPlayerJob(sourceId)
            for _, targetId in pairs(targetIds) do
                TriggerEvent("okokBilling:CreateCustomInvoice", targetId, data.totalFine, fullReason, 'Police', playerJob.name, 'Police')
            end
        end
    end

    if GetResourceState('peleg-billing') == 'started' then
        if data.totalFine > 0 then
            local playerJob = Bridge.Framework.getPlayerJob(sourceId)
            for _, targetId in pairs(targetIds) do
                exports['peleg-billing']:CreateBill(sourceId, targetId, playerJob.name, data.totalFine, fullReason, 'bank')
            end
        end
    end

    if GetResourceState('rcore_prison') == 'started' then
        if data.totalSentence > 0 then
            for _, targetId in ipairs(targetIds) do
                exports['rcore_prison']:Jail(targetId, data.totalSentence, fullReason, sourceId)
            end
        end

        if data.totalFine > 0 then
            for _, targetId in ipairs(targetIds) do
                Bridge.Framework.removeMoney(targetId, 'bank', data.totalFine)
            end
        end
        return true
    elseif GetResourceState('stevo_prison') == 'started' then
        if data.totalSentence > 0 then
            for _, targetId in ipairs(targetIds) do
                exports['stevo_prison']:sentence(sourceId, targetId, data.totalSentence, fullReason)
            end
        end

        if data.totalFine > 0 then
            for _, targetId in ipairs(targetIds) do
                Bridge.Framework.removeMoney(targetId, 'bank', data.totalFine)
            end
        end
        return true
    elseif GetResourceState('DHS-PrisonSim') == 'started' then
        if data.totalSentence > 0 then
            local secLevels = {
                [0] = 'min', 
                [50] = 'med', 
                [100] = 'max'
            }

            local secLevel = 'min'
            for months, level in pairs(secLevels) do
                if data.totalSentence >= months then
                    secLevel = level
                end
            end
            for _, targetId in ipairs(targetIds) do
                exports['DHS-PrisonSim']:SendPlayerToPrison(targetId, secLevel, data.totalSentence * 60)
            end
        end

        if data.totalFine > 0 then
            for _, targetId in ipairs(targetIds) do
                Bridge.Framework.removeMoney(targetId, 'bank', data.totalFine)
            end
        end

        return true
    elseif GetResourceState('pickle_prisons') == 'started' then
        for _, targetId in ipairs(targetIds) do
            exports['pickle_prisons']:JailPlayer(targetId, data.totalSentence)
        end
        return true
    elseif GetResourceState('r_prison') == 'started' then
        for _, targetId in ipairs(targetIds) do
            exports['r_prison']:JailPlayer(targetId, data.totalSentence, data.totalFine)
        end
        return true
    elseif GetResourceState('tk_jail') == 'started' then
        if data.totalSentence > 0 then
            for _, targetId in ipairs(targetIds) do
                exports.tk_jail:jail(targetId, data.totalSentence, 'jail')
            end
        end

        if data.totalFine > 0 then
            for _, targetId in ipairs(targetIds) do
                Bridge.Framework.removeMoney(targetId, 'bank', data.totalFine)
            end
        end
        return true
    elseif GetResourceState('dynyx_prison') == 'started' then
        for _, targetId in ipairs(targetIds) do
            exports['dynyx_prison']:AddPrisonerExternally(targetId, data.totalSentence, fullReason, false, "prison", nil, data.totalFine)
        end
        return true
    elseif GetResourceState('frkn-prison') == 'started' then
        for _, targetId in ipairs(targetIds) do
            exports['frkn-prison']:JailPlayer(sourceId, targetId, data.totalSentence, fullReason)
        end
        if data.totalFine > 0 then
            for _, targetId in ipairs(targetIds) do
                Bridge.Framework.removeMoney(targetId, 'bank', data.totalFine)
            end
        end
    elseif GetResourceState('p_policejob') == 'started' then
        for _, targetId in ipairs(targetIds) do
            exports['p_policejob']:JailPlayer(sourceId, {
                player = targetId,
                jail = data.totalSentence,
                fine = data.totalFine,
                reason = fullReason,
            })
        end
        return true
    else
        lib.print.error('No compatible prison resource found for issuing judgments.')
        return false
    end
end

function Editable:getCitizenLicences(identifier)
    local cbData = {}
    if ESX then
        local result = MySQL.query.await([[
            SELECT user_licenses.*, licenses.label FROM user_licenses
            LEFT JOIN licenses ON user_licenses.type = licenses.type
            WHERE user_licenses.owner = ?
        ]], {identifier})
        for k, v in ipairs(result) do
            cbData[k] = {
                type = v.type,
                label = v.label or ('%s %s'):format(v.type, locale('license')),
            }
        end
    elseif QBCore then
        local targetPlayer = Bridge.Framework.getPlayerByUniqueId(identifier)
        if targetPlayer then
            local licences = targetPlayer.PlayerData.metadata.licences or {}
            local index = 0
            for k, v in pairs(licences) do
                if type(v) == 'boolean' and v == true then
                    index += 1
                    cbData[index] = {
                        type = k,
                        label = ('%s %s'):format(k, locale('license')),
                    }
                end
            end
        else
            local offlinePlayer = Bridge.Framework.getOfflinePlayerByUniqueId(identifier)
            if offlinePlayer then
                local metadata = json.decode(offlinePlayer.metadata)
                local licences = metadata.licences or {}
                local index = 0
                for k, v in pairs(licences) do
                    if type(v) == 'boolean' and v == true then
                        index += 1
                        cbData[index] = {
                            type = k,
                            label = ('%s %s'):format(k, locale('license')),
                        }
                    end
                end
            end
        end
    end

    return cbData
end

function Editable:addCitizenLicense(sourceId, data)
    if ESX then
        MySQL.insert('INSERT INTO user_licenses (owner, type) VALUES (?, ?)', {data.identifier, data.type})
    elseif QBCore then
        local targetPlayer = Bridge.Framework.getPlayerByUniqueId(data.identifier)
        if targetPlayer then
            targetPlayer.PlayerData.metadata.licences[data.type] = true
            targetPlayer.Functions.SetMetaData('licences', targetPlayer.PlayerData.metadata.licences)
        else
            local offlinePlayer = Bridge.Framework.getOfflinePlayerByUniqueId(data.identifier)
            if offlinePlayer then
                local metadata = json.decode(offlinePlayer.metadata)
                if not metadata.licences then
                    metadata.licences = {}
                end

                metadata.licences[data.type] = true
                MySQL.update('UPDATE players SET metadata = ? WHERE citizenid = ?', {json.encode(metadata), data.identifier})
            end
        end
    end
end

function Editable:deleteCitizenLicense(sourceId, data)
    if ESX then
        MySQL.update('DELETE FROM user_licenses WHERE owner = ? AND type = ?', {data.identifier, data.type})
    elseif QBCore then
        local targetPlayer = Bridge.Framework.getPlayerByUniqueId(data.identifier)
        if targetPlayer then
            targetPlayer.PlayerData.metadata.licences[data.type] = nil
            targetPlayer.Functions.SetMetaData('licences', targetPlayer.PlayerData.metadata.licences)
        else
            local offlinePlayer = Bridge.Framework.getOfflinePlayerByUniqueId(data.identifier)
            if offlinePlayer then
                local metadata = json.decode(offlinePlayer.metadata)
                if metadata.licences then
                    metadata.licences[data.type] = nil
                end
                MySQL.update('UPDATE players SET metadata = ? WHERE citizenid = ?', {json.encode(metadata), data.identifier})
            end
        end
    end
end

function Editable:getCitizenProperties(identifier)
    local cbData = {}
    local index = 0
    if GetResourceState('esx_property') == 'started' then
        local propertiesData = LoadResourceFile('esx_property', 'properties.json')
        if propertiesData then
            propertiesData = json.decode(propertiesData)
            for k, v in pairs(propertiesData) do
                if v.Owner and v.Owner == identifier then
                    index += 1
                    cbData[index] = {
                        id = index,
                        name = v.Name,
                        coords = v.Entrance,
                    }
                end
            end
        end
    elseif GetResourceState('tk_housing') == 'started' then
        local propertiesData = exports.tk_housing:getPropertiesByIdentifier(identifier)
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.name or v.address,
                location = v.address,
            }
        end
    elseif GetResourceState('vms_housing') == 'started' then
        local result = exports['vms_housing']:GetPlayerProperties(identifier)
        for k, v in pairs(result) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.name or locale('no_data'),
                location = v.address or locale('no_data'),
            }
        end
    elseif GetResourceState('brutal_housing') == 'started' then
        local propertiesData = MySQL.query.await('SELECT * FROM brutal_housing WHERE owner = ?', {identifier})
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.label,
                location = v.address,
            }
        end
    elseif GetResourceState('qs-housing') == 'started' then
        local playerData = MySQL.single.await('SELECT id FROM player_houses WHERE owner = ?', {identifier})

        if playerData and playerData.id then
            local propertiesData = MySQL.query.await('SELECT * FROM houselocations WHERE owned = ?', {playerData.id})
            
            if propertiesData then
                for k, v in pairs(propertiesData) do
                    index = index + 1
                    local propertyCoords = vec3(0.0, 0.0, 0.0)

                    if v.coords then
                        local rawCoords = json.decode(v.coords)

                        if rawCoords and rawCoords.enter then
                            local targetCoords = {
                                x = rawCoords.enter.x,
                                y = rawCoords.enter.y,
                                z = rawCoords.enter.z
                            }
                            propertyCoords = targetCoords
                        end
                    end

                    cbData[index] = {
                        id = index,
                        name = v.label,
                        coords = propertyCoords
                    }
                end
            end
        end
        if GetResourceState('qs-motels') == 'started' or GetResourceState('qs-motels-creator') == 'started' then
            local motelData = MySQL.query.await('SELECT * FROM motels WHERE owner = ?', {identifier})
            
            if motelData then
                for k, v in pairs(motelData) do
                    index = index + 1
                    local displayName = (v.motel or "Unbekannt") .. " - Raum " .. (v.roomId or "?")

                    cbData[index] = {
                        id = index,
                        name = displayName,
                        location = displayName 
                    }
                end
            end
        end
    elseif GetResourceState('sn_properties') == 'started' then
        local propertiesData = MySQL.query.await('SELECT * FROM properties WHERE owner = ?', {identifier})
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.label,
                coords = json.decode(v.coords),
            }
        end
    elseif GetResourceState('nolag_properties') == 'started' then
        local properties = exports.nolag_properties:GetAllProperties(identifier, 'user', true)
        for k, v in pairs(properties) do
            index += 1
            local name = v.label or locale('no_data')
            local location = v.address or locale('no_data')
            local coords = { x = 0.0, y = 0.0, z = 0.0 }

            local pdata = exports.nolag_properties:GetPropertyData(v.id)
            if pdata and pdata.metadata and pdata.metadata.enterData then
                local ed = pdata.metadata.enterData
                if ed.x and ed.y and ed.z then
                    coords = { x = ed.x, y = ed.y, z = ed.z }
                end
            end

            cbData[index] = {
                id = pdata and pdata.id or p.id,
                name = name,
                coords = coords,
                location = location
            }
        end
    elseif GetResourceState('ak47_housing') == 'started' then
        local propertiesData = MySQL.query.await('SELECT * FROM ak47_housing WHERE owner = ?', {identifier})
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.model or locale('no_data'),
                coords = json.decode(v.enter),
                location = v.model or locale('no_data'),
            }
        end
    elseif GetResourceState('rtx_housing') == 'started' then
        local propertiesData = MySQL.query.await('SELECT * FROM houses WHERE owneridentifier = ?', {identifier})
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.propertyname or locale('no_data'),
                coords = json.decode(v.housedata).enter,
                location = v.adress or locale('no_data'),
            }
        end
    elseif GetResourceState('loaf_housing') == 'started' then
        local propertiesData = MySQL.query.await('SELECT loaf_properties.*, loaf_houses.label, loaf_houses.entrance FROM loaf_properties LEFT JOIN loaf_houses ON loaf_properties.shell = loaf_houses.interior WHERE loaf_properties.owner = ?', {identifier})
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.label or locale('no_data'),
                coords = json.decode(v.entrance),
                location = v.label or locale('no_data'),
            }
        end
    elseif GetResourceState('bcs_housing') == 'started' then
        local owned = exports.bcs_housing:GetOwnedHomeKeys(identifier)
        for k, v in pairs(owned) do
            local entry = v.complex == 'Flat' and v.data.flat.coords or v.entry
            index += 1
            cbData[index] = {
                id = index,
                name = v.name or locale('no_data'),
                coords = entry and json.decode(entry) or nil,
                location = v.name or locale('no_data'),
            }
        end
    end

    return cbData
end

function Editable:getAllProperties()
    local cbData = {}
    local index = 0
    if GetResourceState('esx_property') == 'started' then
        local propertiesData = LoadResourceFile('esx_property', 'properties.json')
        if propertiesData then
            propertiesData = json.decode(propertiesData)
            for k, v in pairs(propertiesData) do
                index += 1
                cbData[index] = {
                    name = v.Name,
                    coords = v.Entrance,
                    owner = v.Owner and {
                        name = v.OwnerName,
                        id = v.Owner,
                    } or nil
                }
            end
        end
    elseif GetResourceState('tk_housing') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local propertiesData = exports.tk_housing:getProperties()
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                name = v.name or v.address,
                location = v.address,
                owner = v.owner and {
                    name = playersData[v.owner] or locale('no_data'),
                    id = v.owner,
                } or nil
            }
        end
    elseif GetResourceState('vms_housing') == 'started' then
        local result = MySQL.query.await('SELECT * FROM houses')
        for k, v in pairs(result) do
            index += 1
            cbData[index] = {
                name = v.name or locale('no_data'),
                location = v.address or locale('no_data'),
                owner = v.owner and {
                    name = v.owner_name or locale('no_data'),
                    id = v.owner,
                } or nil
            }
        end
    elseif GetResourceState('brutal_housing') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local result = MySQL.query.await('SELECT * FROM brutal_housing')
        for k, v in pairs(result) do
            index += 1
            cbData[index] = {
                name = v.label,
                location = v.address,
                owner = v.owner and {
                    name = playersData[v.owner] or locale('no_data'),
                    id = v.owner,
                } or nil
            }
        end
    elseif GetResourceState('qs-housing') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local housingResult = MySQL.query.await('SELECT * FROM houselocations WHERE owned IS NOT NULL AND owned > 0')

        for k, v in pairs(housingResult) do
            index = index + 1
                
            local propertyCoords = vec3(0.0, 0.0, 0.0)
            if v.coords then
                local rawCoords = json.decode(v.coords)
                if rawCoords and rawCoords.enter then
                    local targetCoords = {
                        x = rawCoords.enter.x,
                        y = rawCoords.enter.y,
                        z = rawCoords.enter.z
                    }
                    propertyCoords = targetCoords
                end
            end

            local ownerName = playersData[v.owner] or locale('no_data')

            cbData[index] = {
                id = index,
                name = v.label,
                coords = propertyCoords,
                owner = {
                    name = ownerName,
                    id = v.owner
                }
            }
        end

        if GetResourceState('qs-motels') == 'started' or GetResourceState('qs-motels-creator') == 'started' then
            local motelResult = MySQL.query.await('SELECT * FROM motels')

            for k, v in pairs(motelResult) do
                if v.owner then
                    index = index + 1
                    
                    local displayName = (v.motel or "Unbekannt") .. " - Raum " .. (v.roomId or "?")
                    local ownerName = playersData[v.owner] or locale('no_data')
                    cbData[index] = {
                        id = index,
                        name = displayName,
                        location = displayName,
                        owner = {
                            name = ownerName,
                            id = v.owner
                        }
                    }
                end
            end
        end
    elseif GetResourceState('sn_properties') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local propertiesData = MySQL.query.await('SELECT * FROM properties', {identifier})
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = index,
                name = v.label,
                coords = json.decode(v.coords),
                owner = {
                    owner = v.owner,
                    ownerName = playersData[v.owner] or locale('no_data'),
                }
            }
        end
    elseif GetResourceState('ak47_housing') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local propertiesData = MySQL.query.await('SELECT * FROM ak47_housing WHERE owner IS NOT NULL')
        for k, v in pairs(propertiesData) do
            index += 1
            
            cbData[index] = {
                id = index,
                name = v.model or locale('no_data'),
                coords = json.decode(v.enter),
                location = v.model or locale('no_data'),
                owner = v.owner and {
                    name = playersData[v.owner] or locale('no_data'),
                    id = v.owner,
                } or nil
            }
        end
    elseif GetResourceState('rtx_housing') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local propertiesData = MySQL.query.await('SELECT * FROM houses')
        for k, v in pairs(propertiesData) do
            index += 1
            
            local houseData = json.decode(v.housedata or '{}')
            local coords = houseData.enter or {x = 0.0, y = 0.0, z = 0.0}
            cbData[index] = {
                id = v.id,
                name = v.propertyname or locale('no_data'),
                coords = coords,
                location = v.adress or locale('no_data'),
                owner = v.owneridentifier and {
                    name = playersData[v.owneridentifier] or locale('no_data'),
                    id = v.owneridentifier,
                } or nil
            }
        end
    elseif GetResourceState('nolag_properties') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local propertiesData = MySQL.query.await('SELECT properties.*, properties_owners.identifier FROM properties LEFT JOIN properties_owners ON properties.id = properties_owners.property_id')
        for k, v in pairs(propertiesData) do
            index += 1
            
            local houseData = json.decode(v.metadata or '{}')
            local coords = houseData.enterData or {x = 0.0, y = 0.0, z = 0.0}
            cbData[index] = {
                id = v.id,
                name = v.label or locale('no_data'),
                coords = coords,
                location = v.address or locale('no_data'),
                owner = v.identifier and {
                    name = playersData[v.identifier] or locale('no_data'),
                    id = v.identifier,
                } or nil
            }
        end
    elseif GetResourceState('loaf_housing') == 'started' then
        local playersData = {}
        if ESX then
            local result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users')
            for k, v in pairs(result) do
                playersData[v.identifier] = ('%s %s'):format(v.firstname, v.lastname)
            end
        elseif QBCore then
            local result = MySQL.query.await([[
                SELECT citizenid, 
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
            ]])
            for k, v in pairs(result) do
                playersData[v.citizenid] = ('%s %s'):format(v.firstname, v.lastname)
            end
        end

        local propertiesData = MySQL.query.await('SELECT loaf_houses.*, loaf_houses.label, loaf_houses.entrance FROM loaf_properties LEFT JOIN loaf_houses ON loaf_properties.shell = loaf_houses.interior WHERE loaf_properties.owner IS NOT NULL')
        for k, v in pairs(propertiesData) do
            index += 1
            cbData[index] = {
                id = v.id,
                name = v.label or locale('no_data'),
                coords = v.entrance and json.decode(v.entrance) or {x = 0.0, y = 0.0, z = 0.0},
                location = v.label or locale('no_data'),
                owner = v.owner and {
                    name = playersData[v.owner] or locale('no_data'),
                    id = v.owner,
                } or nil
            }
        end
    end

    return cbData
end

---@param playerId number
---@param data {callsign: string, unit: string, status: string, avatar: string}
function Editable:onPlayerDataChange(playerId, data)
    -- optional functionality
    if GetResourceState('es_extended') == 'started' then
        local ESX = exports.es_extended:getSharedObject()
        local player = ESX.GetPlayerFromId(playerId)
        player.set('callsign', data.callsign)
    elseif GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local player = QBCore.Functions.GetPlayer(playerId)
        player.Functions.SetMetaData('callsign', data.callsign)
    end
end
 
-- ## AUTO REGISTER WEAPONS
-- dont touch it if you dont know what you are doing!
Citizen.CreateThread(function()
    Citizen.Wait(2500)
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:registerHook('buyItem', function(payload)
            if payload.itemName and payload.itemName:find('WEAPON_') and payload.metadata and payload.metadata.serial then
                local uniqueId = Bridge.Framework.getUniqueId(payload.source)
                local serialNumber = payload.metadata?.serial
                lib.print.info(payload.metadata)
                if serialNumber then
                    Weapons:register(nil, {
                        ownerId = uniqueId,
                        serial = serialNumber,
                        model = exports['ox_inventory']:Items(payload.itemName)?.label or payload.itemName,
                    })
                end
            end
            return true
        end)
    elseif GetResourceState('origen_inventory') == 'started' then
        exports.origen_inventory:registerHook('buyItem', function(payload)
            if payload.itemName and payload.itemName:find('WEAPON_') and payload.metadata and payload.metadata.serial then
                local uniqueId = Bridge.Framework.getUniqueId(payload.source)
                Weapons:register(nil, {
                    ownerId = uniqueId,
                    serial = payload.metadata?.serial or locale('no_data'),
                    model = exports['origen_inventory']:Items(payload.itemName)?.label or payload.itemName,
                })
            end
            return true
        end)
    elseif GetResourceState('tgiann-inventory') == 'started' then
        exports['tgiann-inventory']:RegisterHook('buyItem', function(payload)
            if payload.itemName and payload.itemName:find('WEAPON_') and payload.metadata and payload.metadata.serial then
                local uniqueId = Bridge.Framework.getUniqueId(payload.source)
                Weapons:register(nil, {
                    ownerId = uniqueId,
                    serial = payload.metadata?.serial or locale('no_data'),
                    model = exports["tgiann-inventory"]:GetItemLabel(payload.itemName) or payload.itemName,
                })
            end
            return true
        end)
    elseif GetResourceState('jaksam_inventory') == 'started' then
        exports.jaksam_inventory:registerHook('onItemAdded', function(payload)
            lib.print.info(payload)
            if payload.itemName and payload.itemName:find('WEAPON_') then
                local uniqueId = Bridge.Framework.getUniqueId(payload.source)
                Weapons:register(nil, {
                    ownerId = uniqueId,
                    serial = payload.metadata?.serial or locale('no_data'),
                    model = exports['jaksam_inventory']:getItemLabel(payload.itemName) or payload.itemName,
                })
            end
            return true
        end, {
            inventoryFromTypeFilter = {shop = true},
            inventoryToTypeFilter = {player = true}
        })
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(2000)
    if not Config.MDT.itemName then return end
    if ESX then
        ESX.RegisterUsableItem(Config.MDT.itemName, function(playerId)
            TriggerClientEvent('p_mdt/openMDT', playerId)
        end)
    elseif QBCore then
        QBCore.Functions.CreateUseableItem(Config.MDT.itemName, function(playerId)
            TriggerClientEvent('p_mdt/openMDT', playerId)
        end)
    end

    lib.checkDependency('p_bridge', '1.2.5')
end)

while not locale do Citizen.Wait(100) end
lib.addCommand('panic', {
    help = locale('activate_panic_button'),
}, function(source, args, raw)
    local _source = source
    local playerJob = Bridge.Framework.getPlayerJob(_source)
    if not playerJob or not Config.Departments[playerJob.name] then
        Bridge.Notify.showNotify(_source, locale('no_permission'), 'error')
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(_source))
    exports['p_mdt']:CreateAlert({
        priority = 'high',
        title = locale('panic_button'),
        description = locale('panic_btn_description'),
        coords = coords,
        fields = {
            {icon = 'fa-solid fa-user', label = locale('officer'), value = Bridge.Framework.getPlayerName(_source)},
        },
        alertTime = 240,
        blip = {
            sprite = 161,
            color = 1,
            scale = 1.2,
            flash = true,
            text = locale('panic_button'),
        }
    })
end)