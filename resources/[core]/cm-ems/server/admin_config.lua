local NPCS = {
    wardrobe = { label='Wardrobe', facility='wardrobe', key='clothing_npc', model=(Config.Wardrobe or {}).NpcModel or 'mp_m_shopkeep_01', name='Nurse Harper', role='EMS Wardrobe Specialist' },
    mission = { label='Daily Mission', facility='mission', key='daily_mission_npc', model=((Config.EMSMissions or {}).dailyNpcMission or {}).npcModel or 's_m_m_paramedic_01', name='Coordinator Lewis', role='EMS Mission Coordinator' },
}
for _, service in ipairs(Config.AppearanceServices or {}) do
    NPCS['service_' .. tostring(service.id)] = { label=service.label or service.name, serviceId=service.id,
        model=service.model, name=service.name, role=service.label or 'Hospital Service',
        defaultLocation={x=service.coords.x,y=service.coords.y,z=service.coords.z,heading=service.coords.w} }
end
local function allowed(src)
    local ok,value=pcall(function() return exports[Config.AdminResource]:HasPermission(src,Config.AdminPermission) end)
    return ok and value==true
end
local function decode(value) local ok,data=pcall(json.decode,value or ''); return ok and type(data)=='table' and data or nil end
local function text(value,max) value=tostring(value or ''):gsub('[%c]',' '):gsub('%s+',' '):match('^%s*(.-)%s*$') or ''; return value:sub(1,max) end
local function model(value) value=tostring(value or ''):lower(); return #value>0 and #value<=64 and value:match('^[%a_][%w_]*$') and value or nil end
local function row(key) local r=MySQL.single.await('SELECT setting_value FROM cm_ems_settings WHERE setting_key = ? LIMIT 1',{key}); return r and decode(r.setting_value) or nil end
local function item(id,def)
    local override=row('admin_npc:'..id)
    local storedLocation=def.key and row(def.key) or nil
    local location=def.key and (storedLocation and (storedLocation.value or storedLocation)) or (override and override.location) or def.defaultLocation
    return {id=id,label=def.label,enabled=not override or override.enabled~=false,model=override and override.model or def.model,
        name=override and override.name or def.name,role=override and override.role or def.role,configured=override~=nil or location~=nil,location=location}
end
local function broadcast(id) TriggerClientEvent('cm-ems:client:managedNpcUpdated',-1,item(id,NPCS[id])) end
exports('AdminGetNpcs',function(src)
    if not allowed(tonumber(src)) then return {ok=false,error='Permission denied.'} end
    local items={}; for id,def in pairs(NPCS) do items[#items+1]=item(id,def) end
    table.sort(items,function(a,b)return a.label<b.label end); return {ok=true,items=items}
end)
exports('AdminConfigureNpc',function(src,_,data)
    src,data=tonumber(src),type(data)=='table' and data or {}; if not allowed(src) then return false,'Permission denied.' end
    local id,operation=tostring(data.npcId or ''),tostring(data.operation or 'save'); local def=NPCS[id]
    if not def then return false,'Unsupported EMS NPC.' end
    if operation=='reset' then
        MySQL.update.await('DELETE FROM cm_ems_settings WHERE setting_key = ?',{ 'admin_npc:'..id })
        if def.facility then
            local ok,message=exports[GetCurrentResourceName()]:AdminSetFacility(src,'ems',def.facility,true)
            broadcast(id); return ok==true,message or 'EMS NPC reset.'
        end
        broadcast(id); return true,'EMS service NPC reset to configured defaults.'
    end
    local m,n,r=model(data.model),text(data.name,64),text(data.role,80); if not m or n=='' or r=='' then return false,'Model, display name or role is invalid.' end
    local location
    if not def.facility then
        local current=row('admin_npc:'..id)
        location=current and current.location or def.defaultLocation
        if operation=='set_location' then
            local ped=GetPlayerPed(src); if not ped or ped==0 then return false,'Character is not loaded.' end
            local c=GetEntityCoords(ped); location={x=c.x,y=c.y,z=c.z,heading=GetEntityHeading(ped)}
        end
    end
    MySQL.insert.await([[INSERT INTO cm_ems_settings (setting_key,setting_value,updated_by) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),updated_by=VALUES(updated_by)]],
        {'admin_npc:'..id,json.encode({enabled=data.enabled==true,model=m,name=n,role=r,location=location}),tostring(cid(src) or 'admin')})
    if operation=='set_location' and def.facility then
        local ok,message=exports[GetCurrentResourceName()]:AdminSetFacility(src,'ems',def.facility,false)
        if ok~=true then return false,message end
    end
    broadcast(id); return true,'EMS NPC configuration saved and refreshed.'
end)
lib.callback.register('cm-ems:server:managedNpcs',function() local out={}; for id,def in pairs(NPCS) do out[#out+1]=item(id,def) end; return out end)
