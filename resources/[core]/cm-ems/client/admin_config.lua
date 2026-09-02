local function apply(npc)
    if type(npc)~='table' then return end
    local location=npc.enabled~=false and npc.location or false
    if npc.id=='wardrobe' then
        Config.Wardrobe.NpcModel,Config.Wardrobe.NpcName,Config.Wardrobe.NpcRole=npc.model,npc.name,npc.role
        TriggerEvent('cm-ems:client:clothingNpcUpdated',location)
    elseif npc.id=='mission' then
        local cfg=Config.EMSMissions.dailyNpcMission; cfg.npcModel,cfg.npcName,cfg.npcRole=npc.model,npc.name,npc.role
        TriggerEvent('cm-ems:client:dailyMissionNpcUpdated',location)
    elseif tostring(npc.id):sub(1,8)=='service_' then
        TriggerEvent('cm-ems:client:appearanceServiceUpdated',tostring(npc.id):sub(9),npc.enabled~=false and {
            enabled=true,model=npc.model,name=npc.name,label=npc.role,location=npc.location
        } or {enabled=false})
    end
end
RegisterNetEvent('cm-ems:client:managedNpcUpdated',apply)
CreateThread(function() Wait(1500); for _,npc in ipairs(lib.callback.await('cm-ems:server:managedNpcs',false) or {}) do apply(npc) end end)
