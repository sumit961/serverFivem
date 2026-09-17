local tags,duis,activeSession,prompt,placement={}, {}, nil, false, nil
local function notify(message,kind) lib.notify({description=message,type=kind or 'inform'}) end
local function sync() local response=lib.callback.await('cm-gang:server:getGraffiti',false); if response and response.ok then tags=response.tags or {} end end
local function ensureDui(gangId)
 local key=gangId
 if duis[key] then return duis[key] end
 local dict='cm_graffiti_'..gangId
 local entry={dict=dict,ready=false,textureReady=false,state='creating_texture'}
 duis[key]=entry
 local txd=CreateRuntimeTxd(dict)
 if not txd then entry.state='txd_failed'; return entry end
 entry.txd=txd
 -- Static local PNG is the primary path: it is sharper, cheaper and avoids a
 -- second DUI lifecycle between placement preview and the saved wall tag.
 local asset=('html/assets/graffiti/%s.png'):format(gangId)
 local ok,texture=pcall(CreateRuntimeTextureFromImage,txd,'art',asset)
 if ok and texture and texture~=0 then
  entry.texture=texture; entry.textureReady=true; entry.ready=true; entry.state='ready_image'
  return entry
 end
 -- DUI fallback keeps the resource adaptable if a client build cannot load the
 -- local file through CreateRuntimeTextureFromImage.
 entry.state='creating_dui_fallback'
 local dui=CreateDui(('https://cfx-nui-%s/html/graffiti.html?v=7&gang=%s'):format(GetCurrentResourceName(),gangId),1024,512)
 entry.dui=dui
 CreateThread(function()
  local deadline=GetGameTimer()+10000
  while duis[key]==entry and not IsDuiAvailable(dui) and GetGameTimer()<deadline do Wait(50) end
  if duis[key]~=entry then return end
  if not IsDuiAvailable(dui) then entry.state='dui_failed'; return end
  local fallback=CreateRuntimeTextureFromDuiHandle(txd,'art',GetDuiHandle(dui))
  if not fallback then entry.state='texture_failed'; return end
  entry.texture=fallback; entry.textureReady=true; entry.ready=true; entry.state='ready_dui'
 end)
 return entry
end
local function cross(a,b) return vector3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function normalized(v) local length=#v; return length>.0001 and v/length or vector3(0,0,0) end
local function wallBasis(tag)
 local normal
 if tag.placementReady and tag.normalX then normal=normalized(vector3(tag.normalX,tag.normalY,tag.normalZ)) else local h=math.rad(tag.heading or 0); normal=vector3(-math.sin(h),math.cos(h),0) end
 local up=tag.placementReady and normalized(vector3(tag.upX,tag.upY,tag.upZ)) or vector3(0,0,1); local right=normalized(cross(up,normal)); up=normalized(cross(normal,right))
 local angle=math.rad(tag.rotation or 0); local rotatedRight=right*math.cos(angle)+up*math.sin(angle); local rotatedUp=up*math.cos(angle)-right*math.sin(angle)
 return normal,rotatedRight,rotatedUp
end
local function drawTag(tag,alpha,isPreview)
 if not tag.gangId then return end
 local texture=ensureDui(tag.gangId)
 if not texture.textureReady then return end
 local normal,right,up=wallBasis(tag)
 local base=vector3(tag.x,tag.y,tag.z)
 local offset=(Config.Graffiti.wallOffset or .025)+(isPreview and .01 or 0.0)
 local center=base+normal*offset
 local hw,hh=tag.width*.5,tag.height*.5
 local a=center-right*hw-up*hh
 local b=center+right*hw-up*hh
 local c=center+right*hw+up*hh
 local d=center-right*hw+up*hh
 alpha=alpha or 255

 -- DrawSpritePoly is the proven GTA/FiveM world-space textured-triangle path.
 -- Pick the winding that faces the current camera instead of stacking two
 -- coplanar windings, which can disappear through depth/back-face behavior.
 local camera=GetGameplayCamCoord()
 local front=dot(normal,camera-center)>=0.0
 local function tri(p1,p2,p3,u1,v1,u2,v2,u3,v3)
  DrawSpritePoly(
   p1.x,p1.y,p1.z,p2.x,p2.y,p2.z,p3.x,p3.y,p3.z,
   255,255,255,alpha,texture.dict,'art',
   u1,v1,1.0,u2,v2,1.0,u3,v3,1.0
  )
 end
 if front then
  tri(a,b,c,0.0,1.0,1.0,1.0,1.0,0.0)
  tri(a,c,d,0.0,1.0,1.0,0.0,0.0,0.0)
 else
  tri(a,c,b,0.0,1.0,1.0,0.0,1.0,1.0)
  tri(a,d,c,0.0,1.0,0.0,0.0,1.0,0.0)
 end

 if isPreview then
  -- Clear placement frame: confirms the exact world quad even if a texture
  -- fails, making wall-placement issues diagnosable in-game.
  DrawLine(a.x,a.y,a.z,b.x,b.y,b.z,67,231,255,220)
  DrawLine(b.x,b.y,b.z,c.x,c.y,c.z,67,231,255,220)
  DrawLine(c.x,c.y,c.z,d.x,d.y,d.z,67,231,255,220)
  DrawLine(d.x,d.y,d.z,a.x,a.y,a.z,67,231,255,220)
  local nend=center+normal*.25
  DrawLine(center.x,center.y,center.z,nend.x,nend.y,nend.z,255,255,255,180)
 end
end
local function cameraDirection(rotation) local rz,rx=math.rad(rotation.z),math.rad(rotation.x); local c=math.abs(math.cos(rx)); return vector3(-math.sin(rz)*c,math.cos(rz)*c,math.sin(rx)) end
local function wallRaycast()
 local origin=GetGameplayCamCoord(); local destination=origin+cameraDirection(GetGameplayCamRot(2))*30.0; local handle=StartExpensiveSynchronousShapeTestLosProbe(origin.x,origin.y,origin.z,destination.x,destination.y,destination.z,511,PlayerPedId(),7)
 local _,hit,coords,normal=GetShapeTestResult(handle); if hit~=1 or #normal<.9 or math.abs(normal.z)>.75 or #(GetEntityCoords(PlayerPedId())-coords)>25.0 then return nil end
 normal=normalized(normal)
 -- GTA/MLO raycasts are not guaranteed to return a normal pointing toward the
 -- viewer. Keep the saved normal on the visible side so wallOffset cannot bury art.
 if dot(normal,origin-coords)<0 then normal=normal*-1.0 end
 local worldUp=vector3(0,0,1); local up=normalized(worldUp-normal*dot(normal,worldUp)); if #up<.9 then return nil end
 return coords,normal,up
end
local function drawHud(p,valid)
 DrawRect(.17,.17,.29,.225,8,18,25,220); local lines={"GRAFFITI PLACEMENT",('%s · Default'):format(p.gangId),valid and 'Aim at wall · ENTER Save' or '~r~Aim at a nearby wall',"Wheel Size · Shift+Wheel Fine","Q / E Rotate · Arrows Fine Move","R Reset · ESC Cancel",('Size %.2f × %.2f m · Rotation %.0f°'):format(p.width,p.height,p.rotation)}
 for i,line in ipairs(lines) do SetTextFont(i==1 and 4 or 0); SetTextScale(0.0,i==1 and .38 or .29); SetTextColour(i==1 and 70 or 225,i==1 and 220 or 235,255,255); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(line); EndTextCommandDisplayText(.035,.07+(i-1)*.029) end
 local texture=duis[p.gangId]; if texture then
  SetTextFont(0); SetTextScale(0.0,.28); SetTextColour(67,231,255,255); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('ART: %s'):format(texture.state)); EndTextCommandDisplayText(.035,.278)
  if texture.textureReady then DrawSprite(texture.dict,'art',.86,.13,.24,.12,0.0,255,255,255,255) end
 end
end
local function cancelPlacement(reason) if not placement then return end; local sessionId=placement.sessionId; placement=nil; TriggerServerEvent('cm-gang:server:adminGraffitiPlacementCancel',sessionId); ClearAllHelpMessages(); if reason then notify(reason,'inform') end end
RegisterNetEvent('cm-gang:client:adminGraffitiPlacementForceCancel',function() if placement then placement=nil; ClearAllHelpMessages(); notify('Graffiti placement session expired or permission changed.','error') end end)
RegisterNetEvent('cm-gang:client:adminGraffitiPlacement',function(data)
 if placement then cancelPlacement() end; TriggerEvent('cm-admin:client:closeForDevTool'); local seed=type(data.seed)=='table' and data.seed or {}
 placement={sessionId=data.sessionId,gangId=data.gangId,name=data.name,width=tonumber(seed.width) or 2,height=tonumber(seed.height) or 1.2,rotation=tonumber(seed.rotation) or 0,offsetX=0,offsetY=0,seed=seed}; notify('Graffiti placement started. Aim at a wall and press Enter to save.','inform')
 CreateThread(function() while placement do
  Wait(0); local p=placement; local ped=PlayerPedId(); DisablePlayerFiring(PlayerId(),true); for _,control in ipairs({24,25,37,38,44,45,191,200,202,241,242}) do DisableControlAction(0,control,true) end; if IsEntityDead(ped) then cancelPlacement('Graffiti placement cancelled.'); break end
  local coords,normal,up=wallRaycast(); local valid=coords~=nil
  if valid then
   local right=normalized(cross(up,normal)); local fine=IsControlPressed(0,21) and .01 or .05
   if IsDisabledControlJustPressed(0,241) then p.width=math.min(10,p.width+fine); p.height=math.min(6,p.height+fine*.6) end; if IsDisabledControlJustPressed(0,242) then p.width=math.max(.5,p.width-fine); p.height=math.max(.25,p.height-fine*.6) end
   if IsDisabledControlPressed(0,44) then p.rotation=p.rotation-1 end; if IsDisabledControlPressed(0,38) then p.rotation=p.rotation+1 end; if IsControlPressed(0,174) then p.offsetX=p.offsetX-fine end; if IsControlPressed(0,175) then p.offsetX=p.offsetX+fine end; if IsControlPressed(0,172) then p.offsetY=p.offsetY+fine end; if IsControlPressed(0,173) then p.offsetY=p.offsetY-fine end
   if IsDisabledControlJustPressed(0,45) then p.width=tonumber(p.seed.width) or 2; p.height=tonumber(p.seed.height) or 1.2; p.rotation=0; p.offsetX,p.offsetY=0,0 end
   local center=coords+right*p.offsetX+up*p.offsetY; p.preview={x=center.x,y=center.y,z=center.z,normalX=normal.x,normalY=normal.y,normalZ=normal.z,upX=up.x,upY=up.y,upZ=up.z,rotation=p.rotation,width=p.width,height=p.height,placementReady=true,gangId=p.gangId}; drawTag(p.preview,245,true)
   if IsDisabledControlJustPressed(0,191) then local response=lib.callback.await('cm-gang:server:adminGraffitiPlacementSave',false,{sessionId=p.sessionId,x=center.x,y=center.y,z=center.z,normalX=normal.x,normalY=normal.y,normalZ=normal.z,upX=up.x,upY=up.y,upZ=up.z,rotation=p.rotation,width=p.width,height=p.height}); if response and response.ok then if response.tag and response.id then tags[tonumber(response.id)]=response.tag end; placement=nil; notify('Graffiti placement saved.','success') else notify(('Could not save graffiti placement: %s'):format(tostring(response and response.reason or 'unknown_error'):gsub('_',' ')),'error') end end
  end
  drawHud(p,valid); if IsDisabledControlJustPressed(0,200) or IsDisabledControlJustPressed(0,202) then cancelPlacement('Graffiti placement cancelled.'); break end
 end end)
end)
local function repaint(tag)
 if activeSession then return end; local result=lib.callback.await('cm-gang:server:graffitiBegin',false,tag.id); if not result or not result.ok then local messages={already_owned='This graffiti already belongs to your gang.',repaint_in_progress='Someone is already repainting this graffiti.',spray_can_required='You need a Spray Can to repaint graffiti.',inventory_unavailable='Inventory is currently unavailable.'}; return notify(messages[result and result.reason] or tostring(result and result.reason or 'Repaint unavailable.'):gsub('_',' '),'error') end
 activeSession=result.sessionId; local session=activeSession; local animDict='switch@franklin@lamar_tagging_wall'; local anim
 if DoesAnimDictExist(animDict) then lib.requestAnimDict(animDict); anim={dict=animDict,clip='lamar_tagging_wall_loop_lamar'} end
 CreateThread(function() while activeSession==session do Wait(250); local ped=PlayerPedId(); local bucket=tonumber(LocalPlayer.state.routingBucket) or 0; if IsEntityDead(ped) or bucket~=(tag.routingBucket or 0) or #(GetEntityCoords(ped)-vector3(tag.x,tag.y,tag.z))>((Config.Graffiti.interactionDistance or 2.5)+.75) then if lib.progressActive() then lib.cancelProgress() end break end end end)
 local completed=lib.progressCircle({duration=result.duration or 10000,label='Repainting graffiti',position='bottom',canCancel=true,useWhileDead=false,disable={move=true,car=true,combat=true},anim=anim}); if anim then RemoveAnimDict(animDict) end; activeSession=nil; local response=lib.callback.await(completed and 'cm-gang:server:graffitiComplete' or 'cm-gang:server:graffitiCancel',false,session); if completed then if response and response.ok then notify(('Graffiti repainted. Spray can gas: %d%%.'):format(math.max(0,tonumber(response.gasRemaining) or 0)),'success') else notify(tostring(response and response.reason or 'Repaint failed.'):gsub('_',' '),'error') end end
end
RegisterNetEvent('cm-gang:client:graffitiSync',function(value) tags=value or {} end); RegisterNetEvent('cm-gang:client:graffitiRefresh',sync); RegisterNetEvent('cm-gang:client:graffitiUpdated',function(tag) if tag and tag.id then tags[tonumber(tag.id)]=tag end end); RegisterNetEvent('cm-gang:client:graffitiRemoved',function(id) tags[tonumber(id)]=nil end)
CreateThread(function() Wait(1200); sync(); while true do local wait=800; local coords=GetEntityCoords(PlayerPedId()); local nearest,nearDistance
 for _,tag in pairs(tags) do if tag.enabled and tag.placementReady and tag.routingBucket==(tonumber(LocalPlayer.state.routingBucket) or 0) then local distance=#(coords-vector3(tag.x,tag.y,tag.z)); if distance<(Config.Graffiti.streamDistance or 90) then wait=0; drawTag(tag) end if not nearDistance or distance<nearDistance then nearest,nearDistance=tag,distance end end end
 if not placement and LocalPlayer.state.cmGang and nearest and nearDistance<(Config.Graffiti.interactionDistance or 2.5) and not activeSession then if not prompt then lib.showTextUI('[E] Repaint Graffiti'); prompt=true end if IsControlJustReleased(0,38) then lib.hideTextUI(); prompt=false; repaint(nearest) end elseif prompt then lib.hideTextUI(); prompt=false end; Wait(wait)
end end)
AddEventHandler('onResourceStop',function(name) if name~=GetCurrentResourceName() then return end if prompt then lib.hideTextUI() end if placement then TriggerServerEvent('cm-gang:server:adminGraffitiPlacementCancel',placement.sessionId); placement=nil end for _,v in pairs(duis) do if v.dui then DestroyDui(v.dui) end end end)
