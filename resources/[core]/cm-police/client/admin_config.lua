local function apply(npc)
    if type(npc) ~= 'table' then return end
    local location = npc.enabled ~= false and npc.location or false
    if npc.id == 'front_desk' then
        Config.ServiceNpc.Model,Config.ServiceNpc.Name,Config.ServiceNpc.Role=npc.model,npc.name,npc.role
        TriggerEvent('cm-police:client:serviceNpcUpdated',location)
    elseif npc.id == 'armory' or npc.id == 'storage' then
        local prefix=npc.id == 'armory' and 'Armory' or 'Storage'
        Config.FacilityNpcs[prefix..'Model'],Config.FacilityNpcs[prefix..'Name'],Config.FacilityNpcs[prefix..'Role']=npc.model,npc.name,npc.role
        TriggerEvent('cm-police:client:facilityNpcUpdated',npc.id..'_npc',location)
    elseif npc.id == 'prison_intake' then
        Config.JailNpc.Model,Config.JailNpc.Name,Config.JailNpc.Role=npc.model,npc.name,npc.role
        TriggerEvent('cm-police:client:jailNpcUpdated',location)
    elseif npc.id == 'wardrobe' then
        Config.Wardrobe.NpcModel,Config.Wardrobe.NpcName,Config.Wardrobe.NpcRole=npc.model,npc.name,npc.role
        TriggerEvent('cm-police:client:wardrobeNpcUpdated',location)
    elseif npc.id == 'impound' then
        Config.Impound.OperatorModel,Config.Impound.OperatorName,Config.Impound.OperatorRole=npc.model,npc.name,npc.role
        TriggerEvent('cm-police:client:impoundKioskUpdated',location and {location} or {})
    end
end
local capabilityCache={}
function PoliceCapabilityClientEnabled(id)
    return capabilityCache[tostring(id or '')]~=false
end
RegisterNetEvent('cm-police:client:capabilityUpdated',function(id,enabled)
    capabilityCache[tostring(id or '')]=enabled==true
end)
RegisterNetEvent('cm-police:client:managedNpcUpdated',apply)
CreateThread(function()
    Wait(1500)
    for _,npc in ipairs(lib.callback.await('cm-police:server:managedNpcs',false) or {}) do apply(npc) end
    capabilityCache=lib.callback.await('cm-police:server:capabilities',false) or {}
end)
