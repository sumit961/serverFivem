CMGangs = {}
local OWNER='cm-gang'
local function allowed(src,permission)
    local ok,result=pcall(function() return exports['cm-admin']:HasPermission(src,permission) end)
    return ok and result==true
end
local function ready(src,permission)
    if not allowed(src,permission) then return false,'No permission: '..permission end
    if GetResourceState(OWNER)~='started' then return false,'cm-gang is not running.' end
    return true
end
function CMGangs.payload(src)
    local ok=ready(src,'gang.admin.view'); if not ok then return nil end
    local called,result=pcall(function() return exports[OWNER]:AdminGetGangManagement(src) end)
    if not called then print(('[cm-admin] cm-gang management payload failed: %s'):format(tostring(result)));return {ok=false,error='Gang owner failed safely.'} end
    local eventOk,eventData=pcall(function() return exports[OWNER]:AdminGetGangEventManagement(src) end)
    if type(result)=='table' then result.events=eventOk and eventData or nil end
    if type(result)=='table'and GetResourceState('cm-law')=='started'then local arsenalOk,arsenal=pcall(function()return exports['cm-law']:AdminGetArsenalResupply(src)end);result.arsenal=arsenalOk and arsenal or nil end
    return result
end
function CMGangs.invoke(src,action,data)
    local ok,message=ready(src,'gang.admin.manage'); if not ok then return false,message end
    data=type(data)=='table' and data or {}; local gangId=tostring(data.gangId or '')
    local called,result,reason=pcall(function()
        if action=='identity' then return exports[OWNER]:AdminUpdateIdentity(src,gangId,data) end
        if action=='facility' then return exports[OWNER]:AdminSetFacility(src,gangId,data) end
        if action=='assignLeader' then return exports[OWNER]:AdminAssignLeader(src,data.characterId,gangId) end
        if action=='removeLeader' then return exports[OWNER]:AdminRemoveLeader(src,gangId) end
        if action=='recover' then return exports[OWNER]:AdminRecoverGang(src,gangId,data.operation) end
        if action=='legacyMigrate' then return exports[OWNER]:AdminMigrateLegacyGang(src,data.legacyGangId,gangId) end
        if action=='rank' then return exports[OWNER]:AdminSaveRank(src,gangId,data) end
        if action=='armory' then return exports[OWNER]:AdminConfigureArmory(src,gangId,data) end
        if action=='armoryStock' then return exports[OWNER]:AdminAdjustArmoryStock(src,gangId,data.itemId,data.delta) end
        if action=='armoryBundleStock' then return exports[OWNER]:AdminAddArmoryBundleStock(src,gangId,data.itemId) end
        if action=='fleet' then return exports[OWNER]:AdminConfigureFleetVehicle(src,gangId,data) end
        if action=='fleetBegin' then return exports[OWNER]:AdminBeginFleetPlacement(src,gangId,data.model) end
        if action=='fleetReset' then return exports[OWNER]:AdminResetFleetLocation(src,gangId,data.model) end
        if action=='fleetDelete' then return exports[OWNER]:AdminDeleteFleetVehicle(src,gangId,data.model) end
        if action=='graffiti' then return exports[OWNER]:AdminSaveGraffiti(src,data) end
        if action=='graffitiPlacement' then return exports[OWNER]:AdminBeginGraffitiPlacement(src,data) end
        if action=='forceTurfSnapshot' then return exports[OWNER]:AdminForceTurfSnapshot(src) end
        if action=='eventStart' then return exports[OWNER]:AdminStartGangEvent(src) end
        if action=='eventStop' then return exports[OWNER]:AdminStopGangEvent(src,false) end
        if action=='eventCancel' then return exports[OWNER]:AdminStopGangEvent(src,true) end
        if action=='eventConfig' then return exports[OWNER]:AdminConfigureGangEvent(src,data.eventAction,data) end
        if action=='arsenalConfig'then return exports['cm-law']:AdminConfigureArsenalResupply(src,data)end
        if action=='arsenalManifest'then return exports['cm-law']:AdminSaveArsenalManifest(src,data)end
        if action=='arsenalManifestDelete'then return exports['cm-law']:AdminDeleteArsenalManifest(src,data.item)end
        if action=='arsenalRoutePoint'then return exports['cm-law']:AdminCaptureArsenalRoutePoint(src,data.routeId,data.point,data)end
        if action=='arsenalRouteDelete'then return exports['cm-law']:AdminDeleteArsenalRoute(src,data.routeId)end
        if action=='arsenalExtraction'then return exports['cm-law']:AdminCaptureArsenalExtractionPoint(src,data)end
        if action=='arsenalExtractionDelete'then return exports['cm-law']:AdminDeleteArsenalExtractionPoint(src,data.id)end
        if action=='arsenalStart'then return exports['cm-law']:AdminStartArsenalResupply(src)end
        if action=='arsenalCancel'then return exports['cm-law']:AdminCancelArsenalResupply(src)end
        return false,'Unknown gang administration action.'
    end)
    if not called then print(('[cm-admin] cm-gang action %s failed: %s'):format(tostring(action),tostring(result)));return false,'Gang owner failed safely.' end
    if result==true then TriggerEvent('cm-admin:server:addLog',src,'gang_admin_'..action,{category='gangs',gangId=gangId}) end
    return result==true,reason
end
RegisterNetEvent('cm-admin:server:gangEventConfigMode',function(eventAction,data)
    local src=source;local ok,message=ready(src,'gang.admin.manage');if not ok then return end
    local called,result,reason=pcall(function() return exports[OWNER]:AdminConfigureGangEvent(src,tostring(eventAction or ''),type(data)=='table' and data or {}) end)
    if not called then print(('[cm-admin] cm-gang config action %s failed: %s'):format(tostring(eventAction),tostring(result))) end
    TriggerClientEvent('cm-admin:client:gangEventConfigResult',src,called and result==true,called and reason or 'Gang event configuration failed safely.')
    if called and result==true then TriggerEvent('cm-admin:server:addLog',src,'gang_admin_event_config_'..tostring(eventAction),{category='gangs'}) end
end)
