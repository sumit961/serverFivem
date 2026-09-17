local data,ped,textVisible=nil,nil,false
local function remove()
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end; ped=nil
    if textVisible then lib.hideTextUI(); textVisible=false end
end
local function refresh()
    CreateThread(function()
        remove(); data=lib.callback.await('cm-gang:server:getProfitFacility',false)
        local f=data and data.facility; if not f then return end
        local model=joaat(f.npcModel); if not IsModelInCdimage(model) or not IsModelValid(model) then return end
        RequestModel(model); local deadline=GetGameTimer()+5000; while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(50) end
        if not HasModelLoaded(model) then return end
        ped=CreatePed(4,model,f.x,f.y,f.z-1.0,f.heading,false,true); SetEntityInvincible(ped,true); FreezeEntityPosition(ped,true); SetBlockingOfNonTemporaryEvents(ped,true); SetModelAsNoLongerNeeded(model)
    end)
end
CreateThread(function()
    while true do
        local wait=1500; local f=data and data.facility
        if f and ped and DoesEntityExist(ped) then
            local distance=#(GetEntityCoords(PlayerPedId())-vector3(f.x,f.y,f.z))
            if distance<12.0 then wait=0; DrawMarker(2,f.x,f.y,f.z+1.05,0,0,0,0,180.0,0,.15,.15,.15,103,232,249,190,false,true,2,false,nil,nil,false)
                if distance<2.0 then
                    if not textVisible then lib.showTextUI(('[E] %s — Collect Gang Profit'):format(f.displayName~='' and f.displayName or data.gangName)); textVisible=true end
                    if IsControlJustReleased(0,38) then local r=lib.callback.await('cm-gang:server:collectProfit',false); lib.notify({description=r and r.ok and ('Collected $%d.'):format(r.amount or 0) or tostring(r and r.reason or 'Collection failed.'):gsub('_',' '),type=r and r.ok and 'success' or 'error'}) end
                elseif textVisible then lib.hideTextUI(); textVisible=false end
            elseif textVisible then lib.hideTextUI(); textVisible=false end
        end
        Wait(wait)
    end
end)
RegisterNetEvent('cm-gang:client:refreshHeadquarters',refresh)
AddStateBagChangeHandler('cmGang',('player:%s'):format(GetPlayerServerId(PlayerId())),function() Wait(250); refresh() end)
AddEventHandler('onClientResourceStart',function(name) if name==GetCurrentResourceName() then Wait(800); refresh() end end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then remove() end end)
