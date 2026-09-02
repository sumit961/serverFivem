local visuals, carrying, lastRequest, prompt = {}, nil, 0, nil
local armyRoute
local A = Config.ArsenalResupply or {}
local function notify(text, kind) TriggerEvent('cm-hud:client:notify', tostring(text or ''), kind or 'info') end
local function modelFor(name)
    local hash=GetHashKey(name);RequestModel(hash);local deadline=GetGameTimer()+3000
    while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(25) end
    return HasModelLoaded(hash) and hash or nil
end
local function clear(id)
    local row=visuals[tonumber(id)];if row and row.object and DoesEntityExist(row.object) then DeleteEntity(row.object) end
    if tonumber(carrying)==tonumber(id) then ClearPedSecondaryTask(PlayerPedId());carrying=nil end;visuals[tonumber(id)]=nil
end
local function apply(data)
    if type(data)~='table' or not tonumber(data.id) then return end
    if data.state=='removed' or data.state=='extracted' or data.state=='delivered' or data.state=='expired' or data.state=='recovered' then return clear(data.id) end
    local row=visuals[tonumber(data.id)] or {};for k,v in pairs(data)do row[k]=v end;visuals[tonumber(data.id)]=row
    if row.state=='carried' and tonumber(row.carrierSource)==GetPlayerServerId(PlayerId()) then carrying=tonumber(row.id) end
end
RegisterNetEvent('cm-law:client:arsenalCargoSync',function(data)apply(data)end)
RegisterNetEvent('cm-law:client:arsenalRoute',function(data)
    if type(data)~='table'or data.clear==true then armyRoute=nil;return end
    armyRoute={points=data.points or{},index=1};local point=armyRoute.points[1];if point then SetNewWaypoint(point.x+0.0,point.y+0.0)end
end)
RegisterNUICallback('arsenalHistory',function(_,cb)
    local result=lib.callback.await('cm-law:server:arsenalHistory',false)
    cb(result or{ok=false,error='Arsenal history unavailable.'})
end)
local function update(row)
    if not row.object or not DoesEntityExist(row.object) then local hash=modelFor('prop_cs_cardbox_01');if not hash then return end;row.object=CreateObject(hash,row.x or 0,row.y or 0,row.z or 0,false,false,false);SetEntityAsMissionEntity(row.object,true,true);SetModelAsNoLongerNeeded(hash) end
    if row.state=='carried' and row.carrierSource then local p=GetPlayerFromServerId(tonumber(row.carrierSource));local ped=p and p~=-1 and GetPlayerPed(p)or 0;if ped and ped~=0 and DoesEntityExist(ped)then AttachEntityToEntity(row.object,ped,GetPedBoneIndex(ped,57005),.22,.02,-.08,90.0,0.0,80.0,true,true,false,true,1,true);if ped==PlayerPedId()then local dict='anim@heists@box_carry@';RequestAnimDict(dict);if HasAnimDictLoaded(dict)then TaskPlayAnim(ped,dict,'idle',2.0,-2.0,-1,49,0.0,false,false,false)end end;return end end
    if row.x and (row.state=='available' or row.state=='dropped' or row.state=='wrecked') then DetachEntity(row.object,true,true);SetEntityCoordsNoOffset(row.object,row.x,row.y,row.z,false,false,false);PlaceObjectOnGroundProperly(row.object);FreezeEntityPosition(row.object,true) end
end
local function call(action,row)
    local result=lib.callback.await('cm-law:server:arsenalCargo',false,action,row and row.runId,row and row.truckIndex,row and row.id)
    if result and result.ok then notify(result.message or 'Arsenal cargo operation complete.','success') elseif result and result.error then notify(result.error,'error') end;return result
end
local function show(text) prompt=text end
CreateThread(function()while true do Wait(500);for _,row in pairs(visuals)do update(row)end end end)
CreateThread(function()while true do if armyRoute and armyRoute.points[armyRoute.index]then local point=armyRoute.points[armyRoute.index];if #(GetEntityCoords(PlayerPedId())-vector3(point.x,point.y,point.z))<35.0 then armyRoute.index=armyRoute.index+1;point=armyRoute.points[armyRoute.index];if point then SetNewWaypoint(point.x+0.0,point.y+0.0)else armyRoute=nil end end;Wait(1000)else Wait(2000)end end end)
CreateThread(function()
    while true do
        local wait=700;prompt=nil;local ped=PlayerPedId();local coords=GetEntityCoords(ped);local nearest,nearestDist
        for _,veh in ipairs(GetGamePool('CVehicle'))do local state=Entity(veh).state.cmArsenalResupply;if type(state)=='table' and state.role=='cargo' then local d= #(coords-GetEntityCoords(veh));if not nearestDist or d<nearestDist then nearest,nearestDist=veh,d end end end
        local army = LocalPlayer.state.cmLegalOrg
        if nearest and nearestDist<100 and not IsPedInAnyVehicle(ped,false) then
            local state=Entity(nearest).state.cmArsenalResupply;local rear=GetOffsetFromEntityInWorldCoords(nearest,0.0,-(tonumber(A.RearDistance)or 3.5),.7)
            if type(army)=='table' and army.id=='army' and army.onDuty==true and nearestDist < (tonumber(A.InteractionDistance)or 2.5)+4.0 then
                show('Press ~INPUT_CONTEXT~ to unload at the Army warehouse')
                if IsControlJustPressed(0,38) then
                    local result=lib.callback.await('cm-law:server:arsenalUnload',false,'start',state.runId,state.truckIndex,NetworkGetNetworkIdFromEntity(nearest))
                    if result and result.ok then
                        local completed=lib.progressCircle({duration=(tonumber(result.duration)or tonumber(A.UnloadSeconds)or 20)*1000,label='Unloading Arsenal cargo',canCancel=true,disable={move=true,car=true,combat=true}})
                        if completed then result=lib.callback.await('cm-law:server:arsenalUnload',false,'complete',state.runId,state.truckIndex,NetworkGetNetworkIdFromEntity(nearest)) end
                    end
                    if result and result.ok then notify(result.message,'success') elseif result and result.error then notify(result.error,'error') end
                end
            end
            if #(coords-rear)<(tonumber(A.InteractionDistance)or 2.5) and GetGameTimer()-lastRequest>1200 then
                lastRequest=GetGameTimer();local near=lib.callback.await('cm-law:server:arsenalCargoNearby',false,state.runId,state.truckIndex,NetworkGetNetworkIdFromEntity(nearest))or{}
                if near.eligible then show('Press ~INPUT_CONTEXT~ to breach the Arsenal cargo') end
                for _,row in ipairs(near.crates or{})do row.x,row.y,row.z=rear.x,rear.y,rear.z;apply(row)end
                if near.eligible and IsControlJustPressed(0,38) then
                    local started=call('breach_start',{runId=state.runId,truckIndex=state.truckIndex})
                    if started and started.ok then
                        local completed=lib.progressCircle({duration=(tonumber(started.duration)or tonumber(A.BreachSeconds)or 20)*1000,label='Breaching Army cargo',canCancel=true,disable={move=false,car=true,combat=true}})
                        local action=completed and'breach_complete'or'breach_cancel'
                        local outcome=call(action,{runId=state.runId,truckIndex=state.truckIndex})
                        if action=='breach_complete'and(not outcome or not outcome.ok)then call('breach_cancel',{runId=state.runId,truckIndex=state.truckIndex})end
                    end
                end
            end
        end
        if carrying then local row=visuals[carrying];if row and row.state=='carried' then wait=0;show('Press ~INPUT_CONTEXT~ to extract · ~INPUT_DETONATE~ drop Arsenal cargo');if IsControlJustPressed(0,38)then call('extract',row)elseif IsControlJustPressed(0,47)then call('drop',row)end;end elseif not(type(army)=='table'and army.id=='army'and army.onDuty==true)then for id,row in pairs(visuals)do if (row.state=='dropped'or row.state=='wrecked')and row.x and #(coords-vector3(row.x,row.y,row.z))<2.5 then wait=0;show('Press ~INPUT_CONTEXT~ to carry Arsenal cargo');if IsControlJustPressed(0,38)then call('claim',row)end;break end end end
        if prompt then BeginTextCommandDisplayHelp('STRING');AddTextComponentSubstringPlayerName(prompt);EndTextCommandDisplayHelp(0,false,true,-1)end;Wait(wait)
    end
end)
CreateThread(function()while true do if carrying and visuals[carrying] and visuals[carrying].state=='carried' then local row=visuals[carrying];call('heartbeat',row);Wait(tonumber(A.HeartbeatIntervalMs)or 2500)else Wait(800)end end end)
CreateThread(function()
    while true do
        local wait=700;local army=LocalPlayer.state.cmLegalOrg
        if type(army)=='table'and army.id=='army'and army.onDuty==true and not carrying then
            local coords=GetEntityCoords(PlayerPedId())
            for id,row in pairs(visuals)do
                if(row.state=='dropped'or row.state=='wrecked')and row.x and #(coords-vector3(row.x,row.y,row.z))<2.5 then
                    wait=0;BeginTextCommandDisplayHelp('STRING');AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to recover military cargo');EndTextCommandDisplayHelp(0,false,true,-1)
                    if IsControlJustPressed(0,38)then local result=lib.callback.await('cm-law:server:arsenalRecover',false,row.runId,row.id);if result and result.ok then clear(id);notify(result.message,'success')elseif result and result.error then notify(result.error,'error')end end
                    break
                end
            end
        end
        Wait(wait)
    end
end)
AddEventHandler('onResourceStop',function(resource)if resource==GetCurrentResourceName()then for id in pairs(visuals)do clear(id)end end end)
