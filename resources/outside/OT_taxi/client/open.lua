if Config.Framework == 'ESX' then
    ESX = exports['es_extended']:getSharedObject()
elseif Config.Framework == 'QBCORE' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif Config.Framework == 'OX' then
    local file = ('imports/%s.lua'):format(IsDuplicityVersion() and 'server' or 'client')
    local import = LoadResourceFile('ox_core', file)
    local chunk = assert(load(import, ('@@ox_core/%s'):format(file)))
    chunk()
end

function notification(data)
    lib.notify(data)
end
RegisterNetEvent('OT_taxijob:notify', notification)

if Config.givekey then
    RegisterNetEvent('OT_taxijob:givekey', function(plate, networkid)
        local vehicle = NetworkGetEntityFromNetworkId(networkid)
        -- add code here for car keys
    end)
end

if Config.target then
    local targetsystem = string.lower(Config.targetSystem)
    function createTarget(ent, name)
        if Config.targetSystem == 'ox_target' then
            exports[targetsystem]:addLocalEntity(ent, {
                {
                    name = name .. '-1',
                    event = 'OT_taxijob:taxioffice',
                    icon = "far fa-comment",
                    label = _U('target_taxi_office')
                }
            })
        else
            exports[targetsystem]:AddEntityZone(name, ent, {
                name = name,
                debugPoly = false,
                useZ = true
                }, {
                options = {
                    {
                        event = 'OT_taxijob:taxioffice',
                        icon = "far fa-comment",
                        label = _U('target_taxi_office')
                    }
                },
                distance = 2.5
            })
        end
    end

    function removeTarget(ent, name)
        if Config.targetSystem == 'ox_target' then
            exports[targetsystem]:removeLocalEntity(ent)
        else
            exports[targetsystem]:RemoveZone(name)
        end
    end
end

function permCheck(group, grade)
    if Config.Framework == 'ESX' then
        local player = ESX.GetPlayerData()
        if player.job.name == group and player.job.grade >= grade then
            return true
        end
        return false
    elseif Config.Framework == 'QBCORE' then
        local player = QBCore.Functions.GetPlayerData()
        if (player.job.name == group and player.job.grade.level >= grade) or (player.gang.name == group and player.gang.grade.level >= grade) then
            return true
        end
        return false
    elseif Config.Framework == 'OX' then
        local player = Ox.GetPlayerData()
        if player.groups[group] and player.groups[group] >= grade then
            return true
        end
        return false
    end
end