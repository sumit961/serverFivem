CMPoliceTracking = CMPoliceTracking or {}
local enabled = false
local memberBlips = {}
local meetingBlip

local function clearMembers()
    for serverId, blip in pairs(memberBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        memberBlips[serverId] = nil
    end
end

function CMPoliceTracking.ToggleMemberBlips()
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' or not (state.isLeader or state.permissions and state.permissions['police.view_member_map']) then
        PoliceNotify('Your rank cannot view Police members on the map.', 'error')
        return nil
    end
    enabled = not enabled
    if not enabled then clearMembers() end
    PoliceNotify(enabled and 'Police member map enabled.' or 'Police member map disabled.', 'success')
    return enabled
end

CreateThread(function()
    while true do
        Wait(1500)
        local mine = LocalPlayer.state.cmPolice
        if not enabled or type(mine) ~= 'table' then clearMembers() else
            local seen = {}
            for _, playerIndex in ipairs(GetActivePlayers()) do
                if playerIndex ~= PlayerId() then
                    local serverId = GetPlayerServerId(playerIndex)
                    local other = Player(serverId).state.cmPolice
                    local ped = GetPlayerPed(playerIndex)
                    if type(other) == 'table' and DoesEntityExist(ped) then
                        seen[serverId] = true
                        if not memberBlips[serverId] or not DoesBlipExist(memberBlips[serverId]) then
                            local blip = AddBlipForEntity(ped)
                            memberBlips[serverId] = blip
                            SetBlipSprite(blip, 153); SetBlipColour(blip, 1); SetBlipScale(blip, 0.72)
                            SetBlipAsShortRange(blip, true); ShowHeadingIndicatorOnBlip(blip, true)
                            BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Police member'); EndTextCommandSetBlipName(blip)
                        end
                    end
                end
            end
            for serverId, blip in pairs(memberBlips) do if not seen[serverId] then if DoesBlipExist(blip) then RemoveBlip(blip) end; memberBlips[serverId] = nil end end
        end
    end
end)

RegisterNetEvent('cm-police:client:setMeetingPoint', function(data)
    if type(data) ~= 'table' or not tonumber(data.x) or not tonumber(data.y) then return end
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end
    meetingBlip = AddBlipForCoord(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0, (tonumber(data.z) or 0.0) + 0.0)
    SetBlipSprite(meetingBlip, 280); SetBlipColour(meetingBlip, 1); SetBlipScale(meetingBlip, 0.9); SetBlipRoute(meetingBlip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Police meeting point'); EndTextCommandSetBlipName(meetingBlip)
    SetNewWaypoint(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0)
    PoliceNotify(tostring(data.setterName or 'Police leadership') .. ' set a meeting point.', 'inform', 'Police meeting point')
end)

RegisterNetEvent('cm-police:client:clearMeetingPoint', function()
    if meetingBlip and DoesBlipExist(meetingBlip) then
        -- Only drop the route if it is still ours: the player may have set
        -- their own waypoint since, and clearing that would be rude.
        SetBlipRoute(meetingBlip, false)
        RemoveBlip(meetingBlip)
    end
    meetingBlip = nil
    if lib then lib.notify({ title = 'Police meeting point', description = 'Meeting point cleared.', type = 'inform' }) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearMembers()
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end
end)
