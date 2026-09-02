local blips, meetingBlip, enabled = {}, nil, false
local function clear()
    for _,blip in pairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end; blips={}
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end; meetingBlip=nil
end
local function setMeeting(value)
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end; meetingBlip=nil
    if not value or value.active~=true then return end
    meetingBlip=AddBlipForCoord(value.x+0.0,value.y+0.0,value.z+0.0); SetBlipSprite(meetingBlip,280); SetBlipColour(meetingBlip,3); SetBlipRoute(meetingBlip,true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Gang Meeting Point'); EndTextCommandSetBlipName(meetingBlip)
end
RegisterNetEvent('cm-gang:client:meetingChanged',function(gangId,value) local mine=LocalPlayer.state.cmGang; if type(mine)=='table' and mine.gangId==gangId then setMeeting(value) end end)
RegisterNetEvent('cm-gang:client:setTracking',function(value) enabled=value==true; if not enabled then clear() end end)
AddStateBagChangeHandler('cmGang',('player:%s'):format(GetPlayerServerId(PlayerId())),function(_,_,value)
    if type(value)~='table' or not value.gangId then enabled=false; clear() end
end)
CreateThread(function()
    while true do
        if enabled then
            local response=lib.callback.await('cm-gang:server:getTrackingSnapshot',false)
            if not response or response.ok~=true then enabled=false; clear() else
                local seen={}
                for _,row in ipairs(response.members or {}) do
                    local key=tostring(row.characterId); seen[key]=true; local blip=blips[key]
                    if not blip or not DoesBlipExist(blip) then blip=AddBlipForCoord(row.x+0.0,row.y+0.0,row.z+0.0); blips[key]=blip; SetBlipSprite(blip,Config.Tracking.blipSprite or 1); SetBlipColour(blip,Config.Tracking.blipColor or 3); SetBlipScale(blip,Config.Tracking.blipScale or .72); BeginTextCommandSetBlipName('STRING'); AddTextComponentString(row.name or 'Gang member'); EndTextCommandSetBlipName(blip) else SetBlipCoords(blip,row.x+0.0,row.y+0.0,row.z+0.0) end
                end
                for key,blip in pairs(blips) do if not seen[key] then if DoesBlipExist(blip) then RemoveBlip(blip) end; blips[key]=nil end end
                setMeeting(response.meeting)
            end
        end
        Wait(enabled and (Config.Tracking.updateMs or 1500) or 2000)
    end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then clear() end end)
