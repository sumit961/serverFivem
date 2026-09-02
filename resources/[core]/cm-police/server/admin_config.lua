local NPCS = {
    front_desk = { label='Front Desk', facility='front_desk', key='service_npc', model=Config.ServiceNpc.Model, name=Config.ServiceNpc.Name, role=Config.ServiceNpc.Role },
    armory = { label='Armory', facility='armory', key='armory_npc', model=Config.FacilityNpcs.ArmoryModel, name=Config.FacilityNpcs.ArmoryName, role=Config.FacilityNpcs.ArmoryRole },
    storage = { label='Storage / Evidence', facility='storage', key='storage_npc', model=Config.FacilityNpcs.StorageModel, name=Config.FacilityNpcs.StorageName, role=Config.FacilityNpcs.StorageRole },
    prison_intake = { label='Prison Intake', facility='intake', key='jail_intake', model='s_m_m_prisguard_01', name=Config.JailNpc.Name, role=Config.JailNpc.Role },
    wardrobe = { label='Wardrobe', key='wardrobe_npc', model=Config.Wardrobe.NpcModel, name=Config.Wardrobe.NpcName, role=Config.Wardrobe.NpcRole },
    impound = { label='Impound Operator', key='impound_kiosks', model=Config.Impound.OperatorModel, name=Config.Impound.OperatorName, role=Config.Impound.OperatorRole },
}
local allowed, decode
-- Only expose switches whose direct server actions currently consult this
-- authority. Additional Police subsystems can join this list when their
-- server entry points are wired; an admin toggle must never be UI-only.
local CAPABILITIES = { 'citations','impound','radar','spikes','barricades','clamp','k9','alpr','armory' }
local capabilityCache = {}
function PoliceCapabilityEnabled(id)
    id=tostring(id or ''); if capabilityCache[id]~=nil then return capabilityCache[id] end
    local row=MySQL.single.await('SELECT setting_value FROM cm_police_settings WHERE setting_key = ? LIMIT 1',{'capability:'..id})
    local value=row and decode(row.setting_value); capabilityCache[id]=not value or value.enabled~=false; return capabilityCache[id]
end
exports('IsCapabilityEnabled',PoliceCapabilityEnabled)
lib.callback.register('cm-police:server:capabilities',function(src)
    local characterId=cid(src)
    if not characterId or not memberFor(characterId) then return {} end
    local values={}; for _,id in ipairs(CAPABILITIES) do values[id]=PoliceCapabilityEnabled(id) end
    return values
end)
exports('AdminGetCapabilities',function(src)
    if not allowed(tonumber(src)) then return {ok=false,error='Permission denied.'} end
    local items={}; for _,id in ipairs(CAPABILITIES) do items[#items+1]={id=id,enabled=PoliceCapabilityEnabled(id)} end
    return {ok=true,items=items}
end)
exports('AdminConfigureCapability',function(src,_,id,enabled)
    src,id=tonumber(src),tostring(id or ''); if not allowed(src) then return false,'Permission denied.' end
    local supported=false; for _,candidate in ipairs(CAPABILITIES) do if candidate==id then supported=true break end end
    if not supported then return false,'Unsupported Police capability.' end
    capabilityCache[id]=enabled==true
    MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key,setting_value,updated_by) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),updated_by=VALUES(updated_by)]],
        {'capability:'..id,json.encode({enabled=enabled==true}),tostring(cid(src) or 'admin')})
    TriggerClientEvent('cm-police:client:capabilityUpdated',-1,id,enabled==true)
    return true,('Police %s capability %s.'):format(id,enabled==true and 'enabled' or 'disabled')
end)

allowed = function(src)
    local ok, value = pcall(function() return exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) end)
    return ok and value == true
end
local function cleanText(value, maximum)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    return value:sub(1, maximum)
end
local function validModel(value)
    value = tostring(value or ''):lower()
    return #value > 0 and #value <= 64 and value:match('^[%a_][%w_]*$') and value or nil
end
decode = function(value)
    local ok, data = pcall(json.decode, value or '')
    return ok and type(data) == 'table' and data or nil
end
local function loadOverride(id)
    local row = MySQL.single.await('SELECT setting_value FROM cm_police_settings WHERE setting_key = ? LIMIT 1', { 'admin_npc:' .. id })
    return row and decode(row.setting_value) or nil
end
local function loadLocation(def)
    local row = MySQL.single.await('SELECT setting_value FROM cm_police_settings WHERE setting_key = ? LIMIT 1', { def.key })
    local value = row and decode(row.setting_value) or nil
    if def.key == 'impound_kiosks' then value = value and value[1] or nil end
    return value
end
local function payload(id, def)
    local override, location = loadOverride(id), loadLocation(def)
    return { id=id, label=def.label, enabled=not override or override.enabled ~= false,
        model=override and override.model or def.model, name=override and override.name or def.name,
        role=override and override.role or def.role, configured=override ~= nil or location ~= nil, location=location }
end
local function broadcast(id)
    TriggerClientEvent('cm-police:client:managedNpcUpdated', -1, payload(id, NPCS[id]))
end

exports('AdminGetNpcs', function(src)
    if not allowed(tonumber(src)) then return { ok=false, error='Permission denied.' } end
    local items = {}; for id, def in pairs(NPCS) do items[#items+1] = payload(id, def) end
    table.sort(items, function(a,b) return a.label < b.label end)
    return { ok=true, items=items }
end)

exports('AdminConfigureNpc', function(src, _, data)
    src, data = tonumber(src), type(data) == 'table' and data or {}
    if not allowed(src) then return false, 'Permission denied.' end
    local id, operation = tostring(data.npcId or ''), tostring(data.operation or 'save')
    local def = NPCS[id]; if not def then return false, 'Unsupported Police NPC.' end
    if operation == 'reset' then
        MySQL.update.await('DELETE FROM cm_police_settings WHERE setting_key = ?', { 'admin_npc:' .. id })
        if def.facility then exports[GetCurrentResourceName()]:AdminSetFacility(src, 'police', def.facility, true) end
        if id == 'wardrobe' then ResetWardrobeNpcLocation(src,{is_leader=1}) end
        if id == 'impound' then ResetImpoundKioskLocations(src,{is_leader=1}) end
        broadcast(id); return true, 'Police NPC reset to configured defaults.'
    end
    local model, name, role = validModel(data.model), cleanText(data.name, 64), cleanText(data.role, 80)
    if not model or name == '' or role == '' then return false, 'Model, display name or role is invalid.' end
    local override = { enabled=data.enabled == true, model=model, name=name, role=role }
    MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key,setting_value,updated_by) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),updated_by=VALUES(updated_by)]],
        { 'admin_npc:' .. id, json.encode(override), tostring(cid(src) or 'admin') })
    if operation == 'set_location' then
        if def.facility then
            local ok, message = exports[GetCurrentResourceName()]:AdminSetFacility(src, 'police', def.facility, false)
            if ok ~= true then return false, message end
        elseif id == 'wardrobe' then
            local ped=GetPlayerPed(src); if ped==0 then return false,'Character is not loaded.' end
            local c=GetEntityCoords(ped); local ok,message=SetWardrobeNpcLocation(src,{is_leader=1},{x=c.x,y=c.y,z=c.z,heading=GetEntityHeading(ped)})
            if ok~=true then return false,message end
        elseif id == 'impound' then
            local ped=GetPlayerPed(src); if ped==0 then return false,'Character is not loaded.' end
            ResetImpoundKioskLocations(src,{is_leader=1}); local c=GetEntityCoords(ped)
            local ok,message=SetImpoundKioskLocation(src,{is_leader=1},{x=c.x,y=c.y,z=c.z,heading=GetEntityHeading(ped)})
            if ok~=true then return false,message end
        end
    end
    broadcast(id); return true, 'Police NPC configuration saved and refreshed.'
end)

lib.callback.register('cm-police:server:managedNpcs', function()
    local out={}; for id,def in pairs(NPCS) do out[#out+1]=payload(id,def) end; return out
end)
