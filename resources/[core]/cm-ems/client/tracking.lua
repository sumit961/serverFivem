CMEMSTracking = CMEMSTracking or {}
local enabled = false
local memberBlips = {}
local meetingBlip

local function clearMembers()
    for serverId, blip in pairs(memberBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        memberBlips[serverId] = nil
    end
end

function CMEMSTracking.ToggleMemberBlips()
    local state = LocalPlayer.state.cmEms
    if type(state) ~= 'table' or not (state.isLeader or state.permissions and state.permissions['ems.view_member_map']) then
        if lib then lib.notify({ title = 'EMS', description = 'Your rank cannot view EMS members on the map.', type = 'error' }) end
        return nil
    end
    enabled = not enabled
    if not enabled then clearMembers() end
    if lib then lib.notify({ title = 'EMS', description = enabled and 'EMS member map enabled.' or 'EMS member map disabled.', type = 'success' }) end
    return enabled
end

CreateThread(function()
    while true do
        Wait(1500)
        local mine = LocalPlayer.state.cmEms
        if not enabled or type(mine) ~= 'table' then clearMembers() else
            local seen = {}
            for _, playerIndex in ipairs(GetActivePlayers()) do
                if playerIndex ~= PlayerId() then
                    local serverId = GetPlayerServerId(playerIndex)
                    local other = Player(serverId).state.cmEms
                    local ped = GetPlayerPed(playerIndex)
                    if type(other) == 'table' and DoesEntityExist(ped) then
                        seen[serverId] = true
                        if not memberBlips[serverId] or not DoesBlipExist(memberBlips[serverId]) then
                            local blip = AddBlipForEntity(ped)
                            memberBlips[serverId] = blip
                            SetBlipSprite(blip, 153); SetBlipColour(blip, 1); SetBlipScale(blip, 0.72)
                            SetBlipAsShortRange(blip, true); ShowHeadingIndicatorOnBlip(blip, true)
                            BeginTextCommandSetBlipName('STRING'); AddTextComponentString('EMS member'); EndTextCommandSetBlipName(blip)
                        end
                    end
                end
            end
            for serverId, blip in pairs(memberBlips) do if not seen[serverId] then if DoesBlipExist(blip) then RemoveBlip(blip) end; memberBlips[serverId] = nil end end
        end
    end
end)

RegisterNetEvent('cm-ems:client:setMeetingPoint', function(data)
    if type(data) ~= 'table' or not tonumber(data.x) or not tonumber(data.y) then return end
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end
    meetingBlip = AddBlipForCoord(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0, (tonumber(data.z) or 0.0) + 0.0)
    SetBlipSprite(meetingBlip, 280); SetBlipColour(meetingBlip, 1); SetBlipScale(meetingBlip, 0.9); SetBlipRoute(meetingBlip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('EMS meeting point'); EndTextCommandSetBlipName(meetingBlip)
    SetNewWaypoint(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0)
    if lib then lib.notify({ title = 'EMS meeting point', description = tostring(data.setterName or 'EMS leadership') .. ' set a meeting point.', type = 'inform' }) end
end)

RegisterNetEvent('cm-ems:client:clearMeetingPoint', function()
    if meetingBlip and DoesBlipExist(meetingBlip) then
        -- Only drop the route if it is still ours: the player may have set
        -- their own waypoint since, and clearing that would be rude.
        SetBlipRoute(meetingBlip, false)
        RemoveBlip(meetingBlip)
    end
    meetingBlip = nil
    if lib then lib.notify({ title = 'EMS meeting point', description = 'Meeting point cleared.', type = 'inform' }) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearMembers()
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end
end)
